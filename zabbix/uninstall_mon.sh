#!/bin/bash
# uninstall_mon.sh
# Скрипт удаления мониторинга GPU и Docker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root"
        exit 1
    fi
}

# Проверка существования Zabbix Agent2
check_zabbix_agent() {
    if ! systemctl is-active --quiet zabbix-agent2 2>/dev/null; then
        print_warning "Zabbix Agent2 не запущен или не установлен"
        return 1
    fi
    return 0
}

# Подтверждение удаления
confirm_uninstall() {
    echo "=== Подтверждение удаления ==="
    echo "Будут удалены:"
    echo "  - Конфигурационный файл: /etc/zabbix/zabbix_agent2.d/gpu_docker.conf"
    echo "  - Скрипты мониторинга GPU и Docker"
    echo "  - Zabbix Agent2 будет перезапущен"
    echo ""
    read -p "Вы уверены, что хотите продолжить удаление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Удаление отменено"
        exit 0
    fi
}

# Проверка существования файлов перед удалением
check_files_exist() {
    local files_exist=0
    
    if [ -f "/etc/zabbix/zabbix_agent2.d/gpu_docker.conf" ]; then
        print_info "Найден конфигурационный файл"
        files_exist=1
    fi
    
    if [ -f "/etc/zabbix/scripts/gpu_stats.sh" ]; then
        print_info "Найден скрипт мониторинга GPU"
        files_exist=1
    fi
    
    if [ -f "/etc/zabbix/scripts/docker_stats.sh" ]; then
        print_info "Найден скрипт мониторинга Docker"
        files_exist=1
    fi
    
    if [ $files_exist -eq 0 ]; then
        print_warning "Файлы мониторинга не найдены. Возможно, они уже удалены."
        return 1
    fi
    
    return 0
}

main() {
    check_root
    confirm_uninstall
    
    print_info "Начало удаления мониторинга GPU и Docker..."
    
    # Проверяем существование файлов
    if ! check_files_exist; then
        print_warning "Продолжение удаления несмотря на отсутствие файлов..."
    fi
    
    # Удаляем конфигурационный файл
    if [ -f "/etc/zabbix/zabbix_agent2.d/gpu_docker.conf" ]; then
        rm -f /etc/zabbix/zabbix_agent2.d/gpu_docker.conf
        print_info "Конфигурационный файл удален: /etc/zabbix/zabbix_agent2.d/gpu_docker.conf"
    else
        print_warning "Конфигурационный файл не найден"
    fi
    
    # Удаляем скрипты
    if [ -f "/etc/zabbix/scripts/gpu_stats.sh" ]; then
        rm -f /etc/zabbix/scripts/gpu_stats.sh
        print_info "Скрипт мониторинга GPU удален"
    fi
    
    if [ -f "/etc/zabbix/scripts/docker_stats.sh" ]; then
        rm -f /etc/zabbix/scripts/docker_stats.sh
        print_info "Скрипт мониторинга Docker удален"
    fi
    
    # Проверяем, пуста ли директория scripts и удаляем ее если пуста
    if [ -d "/etc/zabbix/scripts" ]; then
        if [ -z "$(ls -A /etc/zabbix/scripts)" ]; then
            rmdir /etc/zabbix/scripts
            print_info "Директория /etc/zabbix/scripts удалена (пустая)"
        else
            print_info "Директория /etc/zabbix/scripts содержит другие файлы, оставлена"
        fi
    fi
    
    # Перезапускаем Zabbix Agent2 если он установлен
    if check_zabbix_agent; then
        print_info "Перезапуск Zabbix Agent2..."
        if systemctl restart zabbix-agent2; then
            print_info "Zabbix Agent2 успешно перезапущен"
        else
            print_error "Ошибка при перезапуске Zabbix Agent2"
            systemctl status zabbix-agent2 --no-pager
        fi
    else
        print_warning "Zabbix Agent2 не перезапущен (не установлен или не запущен)"
    fi
    
    # Финальная проверка
    echo ""
    print_info "=== Проверка удаления ==="
    if [ ! -f "/etc/zabbix/zabbix_agent2.d/gpu_docker.conf" ] && \
       [ ! -f "/etc/zabbix/scripts/gpu_stats.sh" ] && \
       [ ! -f "/etc/zabbix/scripts/docker_stats.sh" ]; then
        print_info "✓ Все файлы мониторинга успешно удалены"
    else
        print_warning "Некоторые файлы могли остаться. Проверьте вручную."
    fi
    
    print_info "Удаление завершено!"
}

main "$@"