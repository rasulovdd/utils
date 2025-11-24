#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Без цвета


# Вывод шапки с информацией о проекте
show_header() {
    echo -e "\033[1;36m"
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ ██████╗  █████╗ ███████╗██╗   ██╗██╗      ██████╗ ██╗   ██╗██████╗ ██████╗  │"
    echo "│ ██╔══██╗██╔══██╗██╔════╝██║   ██║██║     ██╔═══██╗██║   ██║██╔══██╗██╔══██╗ │"
    echo "│ ██████╔╝███████║███████╗██║   ██║██║     ██║   ██║██║   ██║██║  ██║██║  ██║ │"
    echo "│ ██╔══██╗██╔══██║╚════██║██║   ██║██║     ██║   ██║╚██╗ ██╔╝██║  ██║██║  ██║ │"
    echo "│ ██║  ██║██║  ██║███████║╚██████╔╝███████╗╚██████╔╝ ╚████╔╝ ██████╔╝██████╔╝ │"
    echo "│ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝   ╚═══╝  ╚═════╝ ╚═════╝  │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo "zabbix-agent2 insteller by rasulovdd"
    echo "Проект: https://github.com/rasulovdd/utils/zabbix/install/"
    echo "Контакты: @RasulovDD"
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║           Zabbix Agent2 Installer              ║"
    echo "║               Version 1.0                      ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Путь к файлу конфигурации
ZABBIX_CONFIG="/etc/zabbix/zabbix_agent2.conf"

# Функция для получения данных от пользователя
get_configuration() {
    echo -e "${YELLOW}[ИНФО] Настройка конфигурации${NC}"
    
    # Получение имени хоста
    current_hostname=$(hostname)
    echo -e "${BLUE}Текущее имя хоста: ${current_hostname}${NC}"
    read -p "Введите имя хоста для Zabbix агента [$current_hostname]: " hostname_input
    HOSTNAME=${hostname_input:-$current_hostname}
    
    # Проверка имени хоста
    if [ -z "$HOSTNAME" ]; then
        echo -e "${RED}[ОШИБКА] Имя хоста не может быть пустым${NC}"
        return 1
    fi
    
    # Получение IP сервера Zabbix
    read -p "Введите IP адрес сервера Zabbix: " zabbix_server
    if [ -z "$zabbix_server" ]; then
        echo -e "${RED}[ОШИБКА] IP сервера Zabbix не может быть пустым${NC}"
        return 1
    fi
    
    # Базовая проверка формата IP
    if ! [[ $zabbix_server =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && ! [[ $zabbix_server =~ ^[a-zA-Z0-9.-]+$ ]]; then
        echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ] Введенное значение не похоже на валидный IP или имя хоста${NC}"
        read -p "Продолжить в любом случае? (y/n): " continue_anyway
        if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Показать сводку конфигурации
    echo
    echo -e "${GREEN}Сводка конфигурации:${NC}"
    echo -e "  Имя хоста: ${GREEN}$HOSTNAME${NC}"
    echo -e "  Сервер Zabbix: ${GREEN}$zabbix_server${NC}"
    echo
    
    read -p "Применить эту конфигурацию? (y/n): " apply_config
    if [[ ! $apply_config =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[ИНФО] Конфигурация отменена${NC}"
        return 1
    fi
    
    return 0
}

# Функция для настройки Zabbix агента
configure_agent() {
    echo -e "${YELLOW}[ИНФО] Настройка Zabbix Agent 2...${NC}"
    
    # Проверить существование файла конфигурации
    if [ ! -f "$ZABBIX_CONFIG" ]; then
        echo -e "${RED}[ОШИБКА] Файл конфигурации не найден: $ZABBIX_CONFIG${NC}"
        return 1
    fi
    
    # Создать бэкап оригинального конфига
    backup_file="${ZABBIX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$ZABBIX_CONFIG" "$backup_file"
    echo -e "${YELLOW}[ИНФО] Конфигурация сохранена в бэкап: $backup_file${NC}"
    
    # Обновить имя хоста
    if grep -q "^Hostname=" "$ZABBIX_CONFIG"; then
        sed -i "s/^Hostname=.*/Hostname=$HOSTNAME/" "$ZABBIX_CONFIG"
    else
        echo "Hostname=$HOSTNAME" >> "$ZABBIX_CONFIG"
    fi
    echo -e "${GREEN}[УСПЕХ] Имя хоста установлено: $HOSTNAME${NC}"
    
    # Обновить сервер Zabbix
    if grep -q "^Server=" "$ZABBIX_CONFIG"; then
        sed -i "s/^Server=.*/Server=$zabbix_server/" "$ZABBIX_CONFIG"
    else
        echo "Server=$zabbix_server" >> "$ZABBIX_CONFIG"
    fi
    echo -e "${GREEN}[УСПЕХ] Сервер Zabbix установлен: $zabbix_server${NC}"
    
    # Обновить активный сервер Zabbix (для активных проверок)
    if grep -q "^ServerActive=" "$ZABBIX_CONFIG"; then
        sed -i "s/^ServerActive=.*/ServerActive=$zabbix_server/" "$ZABBIX_CONFIG"
    else
        echo "ServerActive=$zabbix_server" >> "$ZABBIX_CONFIG"
    fi
    echo -e "${GREEN}[УСПЕХ] Активный сервер установлен: $zabbix_server${NC}"
    
    # Включить удаленные команды (опционально)
    read -p "Включить удаленные команды? (y/n) [n]: " enable_remote
    if [[ $enable_remote =~ ^[Yy]$ ]]; then
        sed -i "s/^# EnableRemoteCommands=.*/EnableRemoteCommands=1/" "$ZABBIX_CONFIG"
        echo -e "${GREEN}[УСПЕХ] Удаленные команды включены${NC}"
    fi
    
    return 0
}

# Функция для перезапуска агента
restart_agent() {
    echo -e "${YELLOW}[ИНФО] Перезапуск Zabbix Agent 2...${NC}"
    
    if systemctl is-active --quiet zabbix-agent2; then
        systemctl restart zabbix-agent2
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[УСПЕХ] Zabbix Agent 2 успешно перезапущен${NC}"
            
            # Показать статус
            echo -e "${YELLOW}[ИНФО] Статус службы:${NC}"
            systemctl status zabbix-agent2 --no-pager
            
            # Показать прослушиваемые порты
            echo -e "${YELLOW}[ИНФО] Прослушиваемые порты:${NC}"
            netstat -tlnp | grep zabbix || ss -tlnp | grep zabbix
            
        else
            echo -e "${RED}[ОШИБКА] Не удалось перезапустить Zabbix Agent 2${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}[ИНФО] Запуск Zabbix Agent 2...${NC}"
        systemctl start zabbix-agent2
        systemctl status zabbix-agent2 --no-pager
    fi
}

# Функция для установки Zabbix Agent 2
install_agent() {
    echo -e "${YELLOW}[ИНФО] Начало установки Zabbix Agent 2...${NC}"
    
    # Проверить, не установлен ли уже агент
    if systemctl is-active --quiet zabbix-agent2; then
        echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ] Zabbix Agent 2 уже установлен и работает${NC}"
        read -p "Переустановить? (y/n): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    # Сначала получить конфигурацию
    if ! get_configuration; then
        return 1
    fi
    
    # Скачать и установить репозиторий
    echo -e "${YELLOW}[ИНФО] Скачивание репозитория Zabbix...${NC}"
    wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ОШИБКА] Не удалось скачать репозиторий Zabbix${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}[ИНФО] Установка репозитория Zabbix...${NC}"
    dpkg -i zabbix-release_latest_7.0+ubuntu24.04_all.deb
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}[ОШИБКА] Не удалось установить репозиторий Zabbix${NC}"
        return 1
    fi
    
    # Обновить список пакетов
    echo -e "${YELLOW}[ИНФО] Обновление списка пакетов...${NC}"
    apt update
    
    # Установить Zabbix Agent 2
    echo -e "${YELLOW}[ИНФО] Установка Zabbix Agent 2...${NC}"
    apt install -y zabbix-agent2
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[УСПЕХ] Zabbix Agent 2 успешно установлен${NC}"
        
        # Включить службу
        systemctl enable zabbix-agent2
        echo -e "${GREEN}[УСПЕХ] Служба Zabbix Agent 2 включена${NC}"
        
        # Настроить агент
        if configure_agent; then
            # Перезапустить агент
            restart_agent
        else
            echo -e "${RED}[ОШИБКА] Не удалось настроить Zabbix Agent 2${NC}"
            return 1
        fi
        
    else
        echo -e "${RED}[ОШИБКА] Не удалось установить Zabbix Agent 2${NC}"
        return 1
    fi
    
    # Очистка
    rm -f zabbix-release_latest_7.0+ubuntu24.04_all.deb
}

# Функция для перенастройки существующего агента
reconfigure_agent() {
    echo -e "${YELLOW}[ИНФО] Перенастройка Zabbix Agent 2...${NC}"
    
    if [ ! -f "$ZABBIX_CONFIG" ]; then
        echo -e "${RED}[ОШИБКА] Zabbix Agent 2 не установлен или файл конфигурации не найден${NC}"
        return 1
    fi
    
    if ! get_configuration; then
        return 1
    fi
    
    if configure_agent; then
        restart_agent
    else
        echo -e "${RED}[ОШИБКА] Не удалось перенастроить Zabbix Agent 2${NC}"
        return 1
    fi
}

# Функция для удаления Zabbix Agent 2
remove_agent() {
    echo -e "${YELLOW}[ИНФО] Проверка установлен ли Zabbix Agent 2...${NC}"
    
    if ! dpkg -l | grep -q zabbix-agent2; then
        echo -e "${YELLOW}[ИНФО] Zabbix Agent 2 не установлен${NC}"
        return
    fi
    
    echo -e "${RED}[ПРЕДУПРЕЖДЕНИЕ] Это действие полностью удалит Zabbix Agent 2 и его конфигурацию${NC}"
    read -p "Вы уверены что хотите продолжить? (y/n): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # Остановить и отключить службу
        systemctl stop zabbix-agent2 2>/dev/null
        systemctl disable zabbix-agent2 2>/dev/null
        
        # Удалить пакет
        apt remove -y zabbix-agent2
        apt autoremove -y
        
        # Удалить конфигурационные файлы
        rm -rf /etc/zabbix
        
        echo -e "${GREEN}[УСПЕХ] Zabbix Agent 2 полностью удален${NC}"
    else
        echo -e "${YELLOW}[ИНФО] Удаление отменено${NC}"
    fi
}

# Функция для показа текущей конфигурации
show_config() {
    if [ -f "$ZABBIX_CONFIG" ]; then
        echo -e "${YELLOW}[ИНФО] Текущая конфигурация Zabbix Agent 2:${NC}"
        echo -e "${BLUE}"
        grep -E "^(Hostname|Server|ServerActive)=" "$ZABBIX_CONFIG" | while read line; do
            echo "  $line"
        done
        echo -e "${NC}"
        
        echo -e "${YELLOW}[ИНФО] Статус службы:${NC}"
        systemctl is-active zabbix-agent2 && systemctl status zabbix-agent2 --no-pager | grep -E "(Active|Loaded|Main PID)"
    else
        echo -e "${YELLOW}[ИНФО] Zabbix Agent 2 не установлен${NC}"
    fi
}

# Функция для показа меню
show_menu() {
    echo -e "${NC}Пожалуйста, выберите опцию:${NC}"
    echo -e "  ${GREEN}1${NC}. Установить Zabbix Agent 2"
    echo -e "  ${GREEN}2${NC}. Удалить Zabbix Agent 2"
    echo -e "  ${GREEN}3${NC}. Перенастроить Zabbix Agent 2"
    echo -e "  ${GREEN}4${NC}. Показать текущую конфигурацию"
    echo -e "  ${GREEN}0${NC}. Выход"
    echo
}

# Функция для проверки запуска от root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ОШИБКА] Пожалуйста, запустите этот скрипт от root или используя sudo${NC}"
        exit 1
    fi
}

# Функция для проверки совместимости системы
check_system() {
    if ! grep -q "Ubuntu 24.04" /etc/os-release 2>/dev/null; then
        echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ] Этот скрипт предназначен для Ubuntu 24.04${NC}"
        echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ] Для других систем может потребоваться изменить URL репозитория${NC}"
        read -p "Продолжить в любом случае? (y/n): " continue_anyway
        if [[ ! $continue_anyway =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
}

# Главная функция
main() {
    check_root
    check_system
    
    while true; do
        show_header
        show_menu
        
        read -p "Введите ваш выбор [0-4]: " choice
        
        case $choice in
            1)
                install_agent
                ;;
            2)
                remove_agent
                ;;
            3)
                reconfigure_agent
                ;;
            4)
                show_config
                ;;
            0)
                echo -e "${GREEN}[ИНФО] До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[ОШИБКА] Неверная опция. Пожалуйста, выберите 1-5${NC}"
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
        clear
    done
}

# Очистить экран и запустить главную функцию
clear
main