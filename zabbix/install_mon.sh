#!/bin/bash
# install_mon.sh - Мониторинг GPU и Docker для Zabbix Agent2
# Оптимизирован для: bash <(curl -fsSL https://raw.githubusercontent.com/.../install_mon.sh)

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для вывода
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root"
        print_info "Попытка перезапуска с sudo..."
        exec sudo "$0" "$@"
        exit 1
    fi
}

# Проверка установки Zabbix Agent2
check_zabbix_agent() {
    if ! systemctl is-active --quiet zabbix-agent2; then
        print_error "Zabbix Agent2 не установлен или не запущен"
        print_info "Установите Zabbix Agent2 перед запуском этого скрипта"
        exit 1
    fi
}

# Установка NVIDIA утилит
install_nvidia_utils() {
    print_info "Установка NVIDIA утилит..."
    
    # Проверка наличия NVIDIA GPU
    if ! lspci | grep -i nvidia > /dev/null; then
        print_warning "NVIDIA GPU не обнаружена. Продолжение установки..."
        return 0
    fi
    
    # Проверка установленных драйверов
    if ! command -v nvidia-smi &> /dev/null; then
        print_warning "nvidia-smi не найден. Установка nvidia-utils-580-server..."
        apt update
        apt install -y nvidia-utils-580-server
    else
        print_info "NVIDIA утилиты уже установлены"
    fi
    
    # Проверка работы nvidia-smi
    if nvidia-smi &> /dev/null; then
        print_info "NVIDIA утилиты успешно установлены и работают"
    else
        print_warning "NVIDIA утилиты установлены, но nvidia-smi не работает корректно"
    fi
}

# Создание директорий
create_directories() {
    print_info "Создание директорий для скриптов..."
    mkdir -p /etc/zabbix/scripts
}

# Создание скрипта мониторинга GPU
create_gpu_script() {
    print_info "Создание скрипта мониторинга GPU..."
    
    cat > /etc/zabbix/scripts/gpu_stats.sh << 'EOF'
#!/bin/bash
# Мониторинг GPU через nvidia-smi

# Проверка наличия nvidia-smi
if ! command -v nvidia-smi &> /dev/null; then
    echo "gpu_load:0"
    echo "vram_util:0"
    echo "gpu_temp:0"
    exit 0
fi

# Получаем данные GPU
GPU_LOAD=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1 2>/dev/null || echo "0")
VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1 2>/dev/null || echo "0")
VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 2>/dev/null || echo "1")
GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1 2>/dev/null || echo "0")

# Проверка на пустые значения
if [ -z "$GPU_LOAD" ]; then GPU_LOAD=0; fi
if [ -z "$VRAM_USED" ]; then VRAM_USED=0; fi
if [ -z "$VRAM_TOTAL" ]; then VRAM_TOTAL=1; fi
if [ -z "$GPU_TEMP" ]; then GPU_TEMP=0; fi

# Расчет использования VRAM
VRAM_UTIL=$((VRAM_USED * 100 / VRAM_TOTAL))

echo "gpu_load:$GPU_LOAD"
echo "vram_util:$VRAM_UTIL"
echo "gpu_temp:$GPU_TEMP"
EOF

    chmod +x /etc/zabbix/scripts/gpu_stats.sh
}

# Создание скрипта мониторинга Docker
create_docker_script() {
    print_info "Создание скрипта мониторинга Docker..."
    
    cat > /etc/zabbix/scripts/docker_stats.sh << 'EOF'
#!/bin/bash
# Мониторинг Docker контейнеров

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
    echo "docker_running:0"
    echo "docker_stopped:0"
    echo "docker_total:0"
    exit 0
fi

# Получаем статистику контейнеров
RUNNING_CONTAINERS=$(docker ps --filter "status=running" --quiet 2>/dev/null | wc -l || echo "0")
STOPPED_CONTAINERS=$(docker ps --filter "status=exited" --quiet 2>/dev/null | wc -l || echo "0")
TOTAL_CONTAINERS=$(docker ps -a --quiet 2>/dev/null | wc -l || echo "0")

echo "docker_running:$RUNNING_CONTAINERS"
echo "docker_stopped:$STOPPED_CONTAINERS"
echo "docker_total:$TOTAL_CONTAINERS"
EOF

    chmod +x /etc/zabbix/scripts/docker_stats.sh
}

# Настройка пользовательских параметров Zabbix
configure_zabbix_parameters() {
    print_info "Настройка пользовательских параметров Zabbix..."
    
    # Создаем конфигурационный файл
    cat > /etc/zabbix/zabbix_agent2.d/gpu_docker.conf << 'EOF'
# User parameters for GPU monitoring
UserParameter=gpu.load[*],/etc/zabbix/scripts/gpu_stats.sh | grep gpu_load | cut -d':' -f2
UserParameter=gpu.vram[*],/etc/zabbix/scripts/gpu_stats.sh | grep vram_util | cut -d':' -f2
UserParameter=gpu.temp[*],/etc/zabbix/scripts/gpu_stats.sh | grep gpu_temp | cut -d':' -f2

# User parameters for Docker monitoring
UserParameter=docker.running[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_running | cut -d':' -f2
UserParameter=docker.stopped[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_stopped | cut -d':' -f2
UserParameter=docker.total[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_total | cut -d':' -f2

# Include directory for additional configurations
Include=/etc/zabbix/zabbix_agent2.d/*.conf
EOF

    print_info "Конфигурационный файл создан: /etc/zabbix/zabbix_agent2.d/gpu_docker.conf"
}

# Перезапуск Zabbix Agent2
restart_zabbix_agent() {
    print_info "Перезапуск Zabbix Agent2..."
    systemctl restart zabbix-agent2
    
    # Проверка статуса
    if systemctl is-active --quiet zabbix-agent2; then
        print_info "Zabbix Agent2 успешно перезапущен"
    else
        print_error "Ошибка при перезапуске Zabbix Agent2"
        systemctl status zabbix-agent2
    fi
}

# Тестирование скриптов
test_scripts() {
    print_info "Тестирование скриптов..."
    
    echo "=== Тест GPU скрипта ==="
    /etc/zabbix/scripts/gpu_stats.sh
    
    echo "=== Тест Docker скрипта ==="
    /etc/zabbix/scripts/docker_stats.sh
    
    echo "=== Тест Zabbix параметров ==="
    zabbix_agent2 -t "gpu.load[]" | head -1
    zabbix_agent2 -t "gpu.vram[]" | head -1
    zabbix_agent2 -t "docker.running[]" | head -1
}

# Вывод информации для пользователя
show_final_info() {
    print_info "=== Установка завершена ==="
    echo "Доступные метрики:"
    echo "  - gpu.load[] - Загрузка GPU (%)"
    echo "  - gpu.vram[] - Использование VRAM (%)"
    echo "  - gpu.temp[] - Температура GPU (°C)"
    echo "  - docker.running[] - Запущенные контейнеры"
    echo "  - docker.stopped[] - Остановленные контейнеры"
    echo "  - docker.total[] - Всего контейнеров"
    echo ""
    print_warning "Не забудьте настроить элементы данных в Zabbix сервере!"
}

# Основная функция
main() {
    print_info "Начало установки мониторинга GPU и Docker для Zabbix"
    
    check_root
    check_zabbix_agent
    install_nvidia_utils
    create_directories
    create_gpu_script
    create_docker_script
    configure_zabbix_parameters
    restart_zabbix_agent
    test_scripts
    show_final_info
    
    print_info "Установка успешно завершена!"
}

# Запуск основной функции
main "$@"