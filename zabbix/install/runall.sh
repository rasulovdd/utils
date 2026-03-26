#!/bin/bash

set -u
set -o pipefail

# =========================================================
# Цвета
# =========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[1;36m'
NC='\033[0m'

# =========================================================
# Глобальные переменные
# =========================================================
ZABBIX_CONFIG="/etc/zabbix/zabbix_agent2.conf"
TMP_DEB="/tmp/zabbix-release.deb"
LOG_FILE="/var/log/zabbix-agent2-installer.log"

OS_ID=""
OS_VERSION_ID=""
OS_CODENAME=""
OS_PRETTY_NAME=""
PKG_MANAGER="apt"

HOSTNAME_ZBX=""
ZABBIX_SERVER=""
ZABBIX_VERSION="7.0"
ENABLE_REMOTE_COMMANDS="n"

# =========================================================
# Логирование
# =========================================================
log_raw() {
    local level="$1"
    local message="$2"
    local ts
    ts="$(date '+%F %T')"
    echo "[$ts] [$level] $message" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[ИНФО]${NC} $1"
    log_raw "INFO" "$1"
}

log_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
    log_raw "SUCCESS" "$1"
}

log_warn() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"
    log_raw "WARNING" "$1"
}

log_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
    log_raw "ERROR" "$1"
}

# =========================================================
# Шапка
# =========================================================
show_header() {
    echo -e "${CYAN}"
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ ██████╗  █████╗ ███████╗██╗   ██╗██╗      ██████╗ ██╗   ██╗██████╗ ██████╗  │"
    echo "│ ██╔══██╗██╔══██╗██╔════╝██║   ██║██║     ██╔═══██╗██║   ██║██╔══██╗██╔══██╗ │"
    echo "│ ██████╔╝███████║███████╗██║   ██║██║     ██║   ██║██║   ██║██║  ██║██║  ██║ │"
    echo "│ ██╔══██╗██╔══██║╚════██║██║   ██║██║     ██║   ██║╚██╗ ██╔╝██║  ██║██║  ██║ │"
    echo "│ ██║  ██║██║  ██║███████║╚██████╔╝███████╗╚██████╔╝ ╚████╔╝ ██████╔╝██████╔╝ │"
    echo "│ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝   ╚═══╝  ╚═════╝ ╚═════╝  │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo "zabbix-agent2 installer by rasulovdd"
    echo "Проект: https://github.com/rasulovdd/utils/tree/main/zabbix/install/"
    echo "Контакты: @RasulovDD"
    echo "Версия: 1.2 PRO"
    echo -e "${NC}"
}

# =========================================================
# Базовые проверки
# =========================================================
check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[ОШИБКА] Пожалуйста, запустите этот скрипт от root или через sudo${NC}"
        exit 1
    fi
}

init_log() {
    touch "$LOG_FILE" 2>/dev/null || {
        echo -e "${RED}[ОШИБКА] Не удалось создать лог-файл: $LOG_FILE${NC}"
        exit 1
    }
    log_info "Запуск скрипта установки Zabbix Agent2"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Не найдена команда: $cmd"
        exit 1
    fi
}

check_dependencies() {
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd systemctl
    require_cmd wget
    require_cmd dpkg
    require_cmd apt
}

# =========================================================
# Определение ОС
# =========================================================
detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Не найден /etc/os-release. Не могу определить ОС."
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-unknown}"

    log_info "Определена ОС: $OS_PRETTY_NAME"

    case "$OS_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        *)
            log_warn "Скрипт официально поддерживает Ubuntu/Debian."
            read -rp "Продолжить в любом случае? (y/n): " continue_anyway
            if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
                exit 0
            fi
            ;;
    esac
}

# =========================================================
# Проверка репозитория по ОС и версии Zabbix
# =========================================================
get_zabbix_repo_url() {
    case "${OS_ID}:${OS_VERSION_ID}:${ZABBIX_VERSION}" in
        ubuntu:24.04:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb"
            ;;
        ubuntu:22.04:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb"
            ;;
        debian:12:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb"
            ;;
        debian:11:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian11_all.deb"
            ;;
        ubuntu:24.04:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu24.04_all.deb"
            ;;
        ubuntu:22.04:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu22.04_all.deb"
            ;;
        debian:12:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_6.0+debian12_all.deb"
            ;;
        debian:11:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_6.0+debian11_all.deb"
            ;;
        *)
            return 1
            ;;
    esac
}

# =========================================================
# Проверка состояния агента
# =========================================================
is_agent_installed() {
    dpkg -s zabbix-agent2 >/dev/null 2>&1
}

is_agent_active() {
    systemctl is-active --quiet zabbix-agent2
}

# =========================================================
# Работа с конфигом
# =========================================================
set_config_value() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -Eq "^[#[:space:]]*${key}=" "$file"; then
        sed -i "s|^[#[:space:]]*${key}=.*|${key}=${value}|g" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

ensure_config_line() {
    local line="$1"
    local file="$2"

    if ! grep -Fqx "$line" "$file"; then
        echo "$line" >> "$file"
    fi
}

# =========================================================
# Выбор версии Zabbix
# =========================================================
choose_zabbix_version() {
    echo -e "${YELLOW}[ИНФО] Выберите версию Zabbix:${NC}"
    echo "1. 7.0 LTS"
    echo "2. 6.0 LTS"
    read -rp "Ваш выбор [1-2, по умолчанию 1]: " version_choice

    case "$version_choice" in
        2) ZABBIX_VERSION="6.0" ;;
        *) ZABBIX_VERSION="7.0" ;;
    esac

    log_info "Выбрана версия Zabbix: $ZABBIX_VERSION"
}

# =========================================================
# Получение конфигурации
# =========================================================
get_configuration() {
    echo -e "${YELLOW}[ИНФО] Настройка конфигурации${NC}"

    local current_hostname
    current_hostname="$(hostname)"

    echo -e "${BLUE}Текущее имя хоста: ${current_hostname}${NC}"
    read -rp "Введите имя хоста для Zabbix агента [${current_hostname}]: " hostname_input
    HOSTNAME_ZBX="${hostname_input:-$current_hostname}"

    if [ -z "$HOSTNAME_ZBX" ]; then
        log_error "Имя хоста не может быть пустым"
        return 1
    fi

    read -rp "Введите IP/FQDN сервера Zabbix: " zabbix_server_input
    ZABBIX_SERVER="${zabbix_server_input:-}"

    if [ -z "$ZABBIX_SERVER" ]; then
        log_error "Сервер Zabbix не может быть пустым"
        return 1
    fi

    if ! [[ "$ZABBIX_SERVER" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
        log_warn "Введённое значение не похоже на валидный IP/FQDN"
        read -rp "Продолжить в любом случае? (y/n): " continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    read -rp "Включить удалённые команды через AllowKey=system.run[*]? (y/n) [n]: " remote_choice
    ENABLE_REMOTE_COMMANDS="${remote_choice:-n}"

    echo
    echo -e "${GREEN}Сводка конфигурации:${NC}"
    echo -e "  Имя хоста: ${GREEN}${HOSTNAME_ZBX}${NC}"
    echo -e "  Сервер Zabbix: ${GREEN}${ZABBIX_SERVER}${NC}"
    echo -e "  Версия Zabbix: ${GREEN}${ZABBIX_VERSION}${NC}"
    if [[ "$ENABLE_REMOTE_COMMANDS" =~ ^[Yy]$ ]]; then
        echo -e "  Remote commands: ${GREEN}Включены${NC}"
    else
        echo -e "  Remote commands: ${YELLOW}Выключены${NC}"
    fi
    echo

    read -rp "Применить эту конфигурацию? (y/n): " apply_config
    if [[ ! "$apply_config" =~ ^[Yy]$ ]]; then
        log_info "Конфигурация отменена"
        return 1
    fi

    return 0
}

# =========================================================
# Проверка сети до сервера
# =========================================================
check_server_connectivity() {
    local host="$1"
    local port="10051"

    log_info "Проверка доступности сервера ${host}:${port}..."

    if command -v timeout >/dev/null 2>&1; then
        if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log_success "Сервер ${host}:${port} доступен"
            return 0
        else
            log_warn "Не удалось подключиться к ${host}:${port}"
            return 1
        fi
    else
        log_warn "Команда timeout не найдена, проверка сети пропущена"
        return 2
    fi
}

# =========================================================
# Установка репозитория
# =========================================================
install_repo() {
    local repo_url
    repo_url="$(get_zabbix_repo_url)" || {
        log_error "Для ${OS_ID} ${OS_VERSION_ID} не найден подходящий URL репозитория Zabbix ${ZABBIX_VERSION}"
        return 1
    }

    log_info "Скачивание репозитория Zabbix..."
    wget -qO "$TMP_DEB" "$repo_url" || {
        log_error "Не удалось скачать пакет репозитория: $repo_url"
        return 1
    }

    log_info "Установка репозитория Zabbix..."
    dpkg -i "$TMP_DEB" || {
        log_error "Не удалось установить пакет репозитория"
        return 1
    }

    log_info "Обновление списка пакетов..."
    apt update || {
        log_error "Не удалось обновить список пакетов"
        return 1
    }

    return 0
}

# =========================================================
# Настройка агента
# =========================================================
configure_agent() {
    log_info "Настройка Zabbix Agent 2..."

    if [ ! -f "$ZABBIX_CONFIG" ]; then
        log_error "Файл конфигурации не найден: $ZABBIX_CONFIG"
        return 1
    fi

    local backup_file
    backup_file="${ZABBIX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"

    cp "$ZABBIX_CONFIG" "$backup_file" || {
        log_error "Не удалось создать бэкап конфигурации"
        return 1
    }

    log_info "Бэкап конфигурации сохранён: $backup_file"

    set_config_value "Hostname" "$HOSTNAME_ZBX" "$ZABBIX_CONFIG"
    log_success "Hostname установлен: $HOSTNAME_ZBX"

    set_config_value "Server" "$ZABBIX_SERVER" "$ZABBIX_CONFIG"
    log_success "Server установлен: $ZABBIX_SERVER"

    set_config_value "ServerActive" "$ZABBIX_SERVER" "$ZABBIX_CONFIG"
    log_success "ServerActive установлен: $ZABBIX_SERVER"

    if [[ "$ENABLE_REMOTE_COMMANDS" =~ ^[Yy]$ ]]; then
        ensure_config_line "AllowKey=system.run[*]" "$ZABBIX_CONFIG"
        log_success "Разрешён ключ system.run[*]"
    fi

    return 0
}

# =========================================================
# Перезапуск агента
# =========================================================
restart_agent() {
    log_info "Перезапуск Zabbix Agent 2..."

    systemctl daemon-reload

    if systemctl restart zabbix-agent2; then
        log_success "Zabbix Agent 2 успешно перезапущен"
    else
        log_error "Не удалось перезапустить Zabbix Agent 2"
        systemctl status zabbix-agent2 --no-pager || true
        return 1
    fi

    echo -e "${YELLOW}[ИНФО] Статус службы:${NC}"
    systemctl --no-pager --full status zabbix-agent2 || true

    echo -e "${YELLOW}[ИНФО] Прослушиваемые порты:${NC}"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp | grep 10050 || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp | grep 10050 || true
    else
        log_warn "Ни ss, ни netstat не найдены"
    fi
}

# =========================================================
# Установка агента
# =========================================================
install_agent() {
    log_info "Начало установки Zabbix Agent 2..."

    if is_agent_active; then
        log_warn "Zabbix Agent 2 уже установлен и работает"
        read -rp "Переустановить? (y/n): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    choose_zabbix_version

    if ! get_configuration; then
        return 1
    fi

    check_server_connectivity "$ZABBIX_SERVER" || true

    if ! install_repo; then
        return 1
    fi

    log_info "Установка пакета zabbix-agent2..."
    apt install -y zabbix-agent2 || {
        log_error "Не удалось установить zabbix-agent2"
        return 1
    }

    systemctl enable zabbix-agent2 >/dev/null 2>&1 || true
    log_success "Служба Zabbix Agent 2 включена"

    if configure_agent; then
        restart_agent
    else
        log_error "Не удалось настроить Zabbix Agent 2"
        return 1
    fi

    rm -f "$TMP_DEB"
    log_success "Установка завершена успешно"
    return 0
}

# =========================================================
# Перенастройка агента
# =========================================================
reconfigure_agent() {
    log_info "Перенастройка Zabbix Agent 2..."

    if [ ! -f "$ZABBIX_CONFIG" ]; then
        log_error "Zabbix Agent 2 не установлен или файл конфигурации не найден"
        return 1
    fi

    choose_zabbix_version

    if ! get_configuration; then
        return 1
    fi

    check_server_connectivity "$ZABBIX_SERVER" || true

    if configure_agent; then
        restart_agent
    else
        log_error "Не удалось перенастроить Zabbix Agent 2"
        return 1
    fi
}

# =========================================================
# Удаление агента
# =========================================================
remove_agent() {
    log_info "Проверка установлен ли Zabbix Agent 2..."

    if ! is_agent_installed; then
        log_info "Zabbix Agent 2 не установлен"
        return 0
    fi

    echo -e "${RED}[ПРЕДУПРЕЖДЕНИЕ] Это действие удалит Zabbix Agent 2.${NC}"
    read -rp "Удалить также каталог /etc/zabbix? (y/n) [n]: " remove_config
    read -rp "Удалить также пакет zabbix-release? (y/n) [n]: " remove_repo
    read -rp "Вы уверены, что хотите продолжить? (y/n): " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Удаление отменено"
        return 0
    fi

    systemctl stop zabbix-agent2 2>/dev/null || true
    systemctl disable zabbix-agent2 2>/dev/null || true

    apt remove -y zabbix-agent2 || {
        log_error "Не удалось удалить пакет zabbix-agent2"
        return 1
    }

    if [[ "$remove_repo" =~ ^[Yy]$ ]]; then
        apt remove -y zabbix-release || true
    fi

    apt autoremove -y || true

    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        rm -rf /etc/zabbix
        log_warn "Каталог /etc/zabbix удалён"
    fi

    log_success "Zabbix Agent 2 удалён"
    return 0
}

# =========================================================
# Показ текущей конфигурации
# =========================================================
show_config() {
    if [ -f "$ZABBIX_CONFIG" ]; then
        echo -e "${YELLOW}[ИНФО] Текущая конфигурация Zabbix Agent 2:${NC}"
        echo -e "${BLUE}"
        grep -E "^(Hostname|Server|ServerActive|AllowKey)=" "$ZABBIX_CONFIG" || true
        echo -e "${NC}"

        echo -e "${YELLOW}[ИНФО] Статус службы:${NC}"
        if systemctl is-active zabbix-agent2 >/dev/null 2>&1; then
            systemctl status zabbix-agent2 --no-pager | grep -E "(Active:|Loaded:|Main PID:)" || true
        else
            log_warn "Служба не активна"
        fi

        echo -e "${YELLOW}[ИНФО] Проверка порта 10050:${NC}"
        if command -v ss >/dev/null 2>&1; then
            ss -tlnp | grep 10050 || true
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tlnp | grep 10050 || true
        fi
    else
        log_info "Zabbix Agent 2 не установлен"
    fi
}

# =========================================================
# Показ последних логов установщика
# =========================================================
show_installer_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}[ИНФО] Последние 50 строк лога установщика:${NC}"
        tail -n 50 "$LOG_FILE"
    else
        log_warn "Лог-файл установщика не найден"
    fi
}

# =========================================================
# Меню
# =========================================================
show_menu() {
    echo -e "${NC}Пожалуйста, выберите опцию:${NC}"
    echo -e "  ${GREEN}1${NC}. Установить Zabbix Agent 2"
    echo -e "  ${GREEN}2${NC}. Удалить Zabbix Agent 2"
    echo -e "  ${GREEN}3${NC}. Перенастроить Zabbix Agent 2"
    echo -e "  ${GREEN}4${NC}. Показать текущую конфигурацию"
    echo -e "  ${GREEN}5${NC}. Показать лог установщика"
    echo -e "  ${GREEN}0${NC}. Выход"
    echo
}

# =========================================================
# Главная функция
# =========================================================
main() {
    check_root
    init_log
    detect_os
    check_dependencies

    while true; do
        clear
        show_header
        show_menu

        read -rp "Введите ваш выбор [0-5]: " choice

        case "$choice" in
            1) install_agent ;;
            2) remove_agent ;;
            3) reconfigure_agent ;;
            4) show_config ;;
            5) show_installer_log ;;
            0)
                echo -e "${GREEN}[ИНФО] До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[ОШИБКА] Неверная опция. Пожалуйста, выберите 0-5${NC}"
                ;;
        esac

        echo
        read -rp "Нажмите Enter для продолжения..."
    done
}

main