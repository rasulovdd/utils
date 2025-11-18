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

# Проверка NVIDIA утилит
check_nvidia_utils() {
    print_info "Проверка наличия NVIDIA утилит..."
    
    # Проверка наличия NVIDIA GPU
    if ! lspci | grep -i nvidia > /dev/null; then
        print_warning "NVIDIA GPU не обнаружена. Продолжение установки..."
        return 0
    fi
    
    # Проверка наличия nvidia-smi
    if ! command -v nvidia-smi &> /dev/null; then
        print_error "nvidia-smi не найден. Установите NVIDIA утилиты вручную:"
        print_info "Ubuntu/Debian: sudo apt install nvidia-utils-*"
        print_info "CentOS/RHEL: sudo yum install nvidia-utils"
        exit 1
    fi
    
    # Проверка работоспособности nvidia-smi
    if ! timeout 10s nvidia-smi &> /dev/null; then
        print_warning "nvidia-smi обнаружен, но не работает корректно"
        print_info "Возможно, требуется перезагрузка или проверка драйверов"
    else
        print_info "NVIDIA утилиты работают корректно"
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

# Функция для безопасного получения числового значения
safe_number() {
    local value="$1"
    local default="$2"
    
    # Удаляем все нечисловые символы кроме минуса и точек
    value=$(echo "$value" | sed 's/[^0-9.-]*//g')
    
    # Проверяем, что это число
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Проверка наличия nvidia-smi и его работоспособности
if ! command -v nvidia-smi &> /dev/null; then
    echo "gpu_load:0"
    echo "vram_util:0"
    echo "gpu_temp:0"
    exit 0
fi

# Пытаемся получить данные с таймаутом
GPU_DATA=$(timeout 10s nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)

# Если команда не удалась или вернула ошибку
if [ $? -ne 0 ] || [ -z "$GPU_DATA" ] || echo "$GPU_DATA" | grep -q "Failed"; then
    echo "gpu_load:0"
    echo "vram_util:0"
    echo "gpu_temp:0"
    exit 0
fi

# Извлекаем данные из первой строки
GPU_LOAD=$(echo "$GPU_DATA" | head -1 | cut -d',' -f1 | tr -d ' ' | tr -d '%')
VRAM_USED=$(echo "$GPU_DATA" | head -1 | cut -d',' -f2 | tr -d ' ' | tr -d 'MiB')
VRAM_TOTAL=$(echo "$GPU_DATA" | head -1 | cut -d',' -f3 | tr -d ' ' | tr -d 'MiB')
GPU_TEMP=$(echo "$GPU_DATA" | head -1 | cut -d',' -f4 | tr -d ' ' | tr -d 'C')

# Безопасное преобразование в числа
GPU_LOAD=$(safe_number "$GPU_LOAD" "0")
VRAM_USED=$(safe_number "$VRAM_USED" "0")
VRAM_TOTAL=$(safe_number "$VRAM_TOTAL" "1")
GPU_TEMP=$(safe_number "$GPU_TEMP" "0")

# Расчет использования VRAM
if [ "$VRAM_TOTAL" -gt 0 ] 2>/dev/null; then
    VRAM_UTIL=$((VRAM_USED * 100 / VRAM_TOTAL))
else
    VRAM_UTIL=0
fi

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
    
    # Создаем конфигурационный файл (убрана рекурсивная директива Include)
    cat > /etc/zabbix/zabbix_agent2.d/gpu_docker.conf << 'EOF'
# User parameters for GPU monitoring
UserParameter=gpu.load[*],/etc/zabbix/scripts/gpu_stats.sh | grep gpu_load | cut -d':' -f2
UserParameter=gpu.vram[*],/etc/zabbix/scripts/gpu_stats.sh | grep vram_util | cut -d':' -f2
UserParameter=gpu.temp[*],/etc/zabbix/scripts/gpu_stats.sh | grep gpu_temp | cut -d':' -f2

# User parameters for Docker monitoring
UserParameter=docker.running[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_running | cut -d':' -f2
UserParameter=docker.stopped[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_stopped | cut -d':' -f2
UserParameter=docker.total[*],/etc/zabbix/scripts/docker_stats.sh | grep docker_total | cut -d':' -f2
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
    # Даем время агенту перезапуститься
    sleep 2
    
    # Тестируем с правильным пользователем
    sudo -u zabbix zabbix_agent2 -t "gpu.load[]" 2>/dev/null | head -1 || echo "GPU load test skipped"
    sudo -u zabbix zabbix_agent2 -t "gpu.vram[]" 2>/dev/null | head -1 || echo "GPU vram test skipped"
    sudo -u zabbix zabbix_agent2 -t "docker.running[]" 2>/dev/null | head -1 || echo "Docker running test skipped"
}

# Проверка работоспособности NVIDIA
check_nvidia_status() {
    print_info "Проверка статуса NVIDIA..."
    
    if lspci | grep -i nvidia > /dev/null; then
        echo "=== Информация об установленных драйверах NVIDIA ==="
        if command -v nvidia-smi &> /dev/null; then
            nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
        else
            print_warning "nvidia-smi не найден"
        fi
        
        echo "=== Попытка запуска nvidia-smi ==="
        if timeout 5s nvidia-smi &>/dev/null; then
            print_info "NVIDIA работает корректно"
        else
            print_warning "NVIDIA драйверы обнаружены, но nvidia-smi не работает"
            print_info "Возможно, требуется перезагрузка системы"
        fi
    fi
}

# Добавление пользователя zabbix в группу docker
add_zabbix_to_docker() {
    print_info "Проверка и настройка доступа Zabbix к Docker..."

    local USER="zabbix"
    local GROUP="docker"

    # Проверка существования пользователя
    if ! id "$USER" &>/dev/null; then
        print_error "Пользователь $USER не существует. Невозможно настроить доступ к Docker."
        return 1
    fi

    # Проверка существования группы docker
    if ! getent group "$GROUP" &>/dev/null; then
        print_warning "Группа $GROUP не существует. Docker не установлен или установлен нестандартно."
        return 0
    fi

    # Проверка, состоит ли пользователь уже в группе
    if groups "$USER" | grep -q "\b$GROUP\b"; then
        print_info "Пользователь $USER уже имеет доступ к Docker (входит в группу $GROUP)"
        return 0
    fi

    # Добавление в группу
    print_info "Добавляем пользователя $USER в группу $GROUP..."
    sudo usermod -aG "$GROUP" "$USER"

    # Повторная проверка
    if groups "$USER" | grep -q "\b$GROUP\b"; then
        print_info "Успешно: пользователь $USER добавлен в группу $GROUP"
        return 0
    else
        print_error "Не удалось добавить $USER в группу $GROUP. Проверьте права sudo."
        return 1
    fi
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
    
    if lspci | grep -i nvidia > /dev/null; then
        if ! timeout 5s nvidia-smi &>/dev/null; then
            print_warning "Для работы мониторинга GPU требуется перезагрузка системы!"
            print_info "Выполните: reboot"
        fi
    fi
    
    print_warning "Не забудьте настроить элементы данных в Zabbix сервере!"
}

# Основная функция
main() {
    print_info "Начало установки мониторинга GPU и Docker для Zabbix"
    
    check_root
    check_zabbix_agent
    check_nvidia_utils
    create_directories
    create_gpu_script
    create_docker_script
    configure_zabbix_parameters
    add_zabbix_to_docker
    restart_zabbix_agent
    test_scripts
    check_nvidia_status
    show_final_info
    
    print_info "Установка успешно завершена!"
}

# Запуск основной функции
main "$@"