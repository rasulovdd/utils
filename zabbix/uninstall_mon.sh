#!/bin/bash
# uninstall_mon.sh
# Скрипт удаления мониторинга GPU и Docker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

main() {
    check_root
    
    print_info "Удаление конфигурации мониторинга..."
    
    # Удаляем конфигурационный файл
    if [ -f "/etc/zabbix/zabbix_agent2.d/gpu_docker.conf" ]; then
        rm -f /etc/zabbix/zabbix_agent2.d/gpu_docker.conf
        print_info "Конфигурационный файл удален"
    fi
    
    # Удаляем скрипты
    if [ -d "/etc/zabbix/scripts" ]; then
        rm -f /etc/zabbix/scripts/gpu_stats.sh
        rm -f /etc/zabbix/scripts/docker_stats.sh
        print_info "Скрипты удалены"
    fi
    
    # Перезапускаем Zabbix Agent2
    print_info "Перезапуск Zabbix Agent2..."
    systemctl restart zabbix-agent2
    
    print_info "Удаление завершено!"
}

main "$@"