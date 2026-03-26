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
LOG_FILE="/var/log/zabbix-agent2-installer.log"
LOG_MAX_SIZE=$((1024 * 1024))
LOG_ROTATE_COUNT=5

OS_ID=""
OS_VERSION_ID=""
OS_MAJOR=""
OS_PRETTY_NAME=""
PKG_MANAGER=""
INSTALL_MODE="interactive"

HOSTNAME_ZBX=""
ZABBIX_SERVER=""
ZABBIX_VERSION="7.0"
ENABLE_REMOTE_COMMANDS="n"
AUTO_YES="n"
REMOVE_CONFIG="n"
REMOVE_REPO="n"

ACTION=""
TMP_REPO_PKG="/tmp/zabbix-release.pkg"

# repo, которые можно отключить, если они ломают dnf
DNF_BROKEN_REPOS_PATTERN="rpmfusion*"

# =========================================================
# Логирование
# =========================================================
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -ge "$LOG_MAX_SIZE" ]; then
            for ((i=LOG_ROTATE_COUNT; i>=1; i--)); do
                if [ -f "${LOG_FILE}.${i}" ]; then
                    if [ "$i" -eq "$LOG_ROTATE_COUNT" ]; then
                        rm -f "${LOG_FILE}.${i}"
                    else
                        mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i+1))"
                    fi
                fi
            done
            mv "$LOG_FILE" "${LOG_FILE}.1"
        fi
    fi
}

log_raw() {
    local level="$1"
    local message="$2"
    local ts
    ts="$(date '+%F %T')"
    rotate_log
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

init_log() {
    touch "$LOG_FILE" 2>/dev/null || {
        echo -e "${RED}[ОШИБКА] Не удалось создать лог-файл: $LOG_FILE${NC}"
        exit 1
    }
    log_info "Запуск Zabbix Agent2 Installer v1.3 Enterprise Fixed"
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
    echo "Контакты: @RasulovDD"
    echo "Версия: 1.3 Enterprise Fixed"
    echo -e "${NC}"
}

# =========================================================
# Базовые функции
# =========================================================
check_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo -e "${RED}[ОШИБКА] Запустите скрипт от root или через sudo${NC}"
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Не найдена команда: $cmd"
        exit 1
    fi
}

confirm() {
    local prompt="$1"
    if [[ "$AUTO_YES" =~ ^[Yy]$ ]]; then
        return 0
    fi
    read -rp "$prompt (y/n): " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# =========================================================
# Определение ОС
# =========================================================
detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Не найден /etc/os-release"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-unknown}"
    OS_MAJOR="${OS_VERSION_ID%%.*}"

    case "$OS_ID" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        rocky|almalinux|rhel)
            PKG_MANAGER="dnf"
            ;;
        *)
            log_warn "ОС не входит в список официально поддерживаемых: $OS_PRETTY_NAME"
            if ! confirm "Продолжить"; then
                exit 0
            fi
            ;;
    esac

    log_info "Определена ОС: $OS_PRETTY_NAME"
    log_info "Пакетный менеджер: $PKG_MANAGER"
}

# =========================================================
# Проверка зависимостей
# =========================================================
check_dependencies() {
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd systemctl
    require_cmd wget
    require_cmd hostname

    case "$PKG_MANAGER" in
        apt)
            require_cmd apt
            require_cmd dpkg
            ;;
        dnf)
            require_cmd dnf
            require_cmd rpm
            ;;
    esac
}

# =========================================================
# URL репозитория
# =========================================================
get_repo_url() {
    case "${OS_ID}:${OS_MAJOR}:${ZABBIX_VERSION}" in
        ubuntu:24:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb"
            ;;
        ubuntu:22:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu22.04_all.deb"
            ;;
        debian:12:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian12_all.deb"
            ;;
        debian:11:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_7.0+debian11_all.deb"
            ;;
        rocky:9:7.0|almalinux:9:7.0|rhel:9:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/rhel/9/x86_64/zabbix-release-latest-7.0.el9.noarch.rpm"
            ;;
        rocky:8:7.0|almalinux:8:7.0|rhel:8:7.0)
            echo "https://repo.zabbix.com/zabbix/7.0/rhel/8/x86_64/zabbix-release-latest-7.0.el8.noarch.rpm"
            ;;
        ubuntu:24:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu24.04_all.deb"
            ;;
        ubuntu:22:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu22.04_all.deb"
            ;;
        debian:12:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_6.0+debian12_all.deb"
            ;;
        debian:11:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/debian/pool/main/z/zabbix-release/zabbix-release_latest_6.0+debian11_all.deb"
            ;;
        rocky:9:6.0|almalinux:9:6.0|rhel:9:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/rhel/9/x86_64/zabbix-release-latest-6.0.el9.noarch.rpm"
            ;;
        rocky:8:6.0|almalinux:8:6.0|rhel:8:6.0)
            echo "https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-latest-6.0.el8.noarch.rpm"
            ;;
        *)
            return 1
            ;;
    esac
}

# =========================================================
# dnf safe helpers
# =========================================================
dnf_makecache_safe() {
    if dnf makecache -y; then
        log_success "dnf cache успешно обновлён"
        return 0
    fi

    log_warn "Обычное обновление dnf cache не удалось, пробую без ${DNF_BROKEN_REPOS_PATTERN} ..."

    if dnf makecache -y --disablerepo="${DNF_BROKEN_REPOS_PATTERN}"; then
        log_success "dnf cache обновлён без ${DNF_BROKEN_REPOS_PATTERN}"
        return 0
    fi

    log_error "Не удалось обновить dnf cache даже без ${DNF_BROKEN_REPOS_PATTERN}"
    return 1
}

dnf_install_safe() {
    local package_name="$1"

    if dnf install -y "$package_name"; then
        return 0
    fi

    log_warn "Обычная установка '$package_name' не удалась, пробую без ${DNF_BROKEN_REPOS_PATTERN} ..."

    if dnf install -y "$package_name" --disablerepo="${DNF_BROKEN_REPOS_PATTERN}"; then
        return 0
    fi

    log_error "Не удалось установить '$package_name' даже без ${DNF_BROKEN_REPOS_PATTERN}"
    return 1
}

dnf_remove_safe() {
    local package_name="$1"

    if dnf remove -y "$package_name"; then
        return 0
    fi

    log_warn "Обычное удаление '$package_name' не удалось, пробую без ${DNF_BROKEN_REPOS_PATTERN} ..."

    if dnf remove -y "$package_name" --disablerepo="${DNF_BROKEN_REPOS_PATTERN}"; then
        return 0
    fi

    log_error "Не удалось удалить '$package_name' даже без ${DNF_BROKEN_REPOS_PATTERN}"
    return 1
}

# =========================================================
# Пакетные операции
# =========================================================
install_repo() {
    local repo_url
    repo_url="$(get_repo_url)" || {
        log_error "Не найден URL репозитория для ${OS_ID} ${OS_VERSION_ID} и Zabbix ${ZABBIX_VERSION}"
        return 1
    }

    log_info "Скачивание репозитория: $repo_url"
    wget -qO "$TMP_REPO_PKG" "$repo_url" || {
        log_error "Не удалось скачать репозиторий"
        return 1
    }

    case "$PKG_MANAGER" in
        apt)
            dpkg -i "$TMP_REPO_PKG" || {
                log_error "Не удалось установить пакет репозитория"
                return 1
            }
            apt update || {
                log_error "Не удалось обновить apt cache"
                return 1
            }
            ;;
        dnf)
            rpm -Uvh --force "$TMP_REPO_PKG" || {
                log_error "Не удалось установить rpm репозиторий"
                return 1
            }
            dnf_makecache_safe || return 1
            ;;
    esac

    log_success "Репозиторий Zabbix установлен"
}

install_agent_package() {
    case "$PKG_MANAGER" in
        apt)
            apt install -y zabbix-agent2 || return 1
            ;;
        dnf)
            dnf_install_safe "zabbix-agent2" || return 1
            ;;
    esac
}

remove_agent_package() {
    case "$PKG_MANAGER" in
        apt)
            apt remove -y zabbix-agent2 || return 1
            apt autoremove -y || true
            ;;
        dnf)
            dnf_remove_safe "zabbix-agent2" || return 1
            ;;
    esac
}

remove_repo_package() {
    case "$PKG_MANAGER" in
        apt)
            apt remove -y zabbix-release || true
            apt autoremove -y || true
            ;;
        dnf)
            dnf_remove_safe "zabbix-release" || true
            ;;
    esac
}

is_agent_installed() {
    case "$PKG_MANAGER" in
        apt) dpkg -s zabbix-agent2 >/dev/null 2>&1 ;;
        dnf) rpm -q zabbix-agent2 >/dev/null 2>&1 ;;
    esac
}

# =========================================================
# Конфиг
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

backup_config() {
    if [ -f "$ZABBIX_CONFIG" ]; then
        local backup_file="${ZABBIX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ZABBIX_CONFIG" "$backup_file" || return 1
        log_info "Бэкап конфига: $backup_file"
    fi
}

configure_agent() {
    log_info "Настройка Zabbix Agent2"

    if [ ! -f "$ZABBIX_CONFIG" ]; then
        log_error "Файл конфига не найден: $ZABBIX_CONFIG"
        return 1
    fi

    backup_config || {
        log_error "Не удалось создать бэкап конфига"
        return 1
    }

    set_config_value "Hostname" "$HOSTNAME_ZBX" "$ZABBIX_CONFIG"
    set_config_value "Server" "$ZABBIX_SERVER" "$ZABBIX_CONFIG"
    set_config_value "ServerActive" "$ZABBIX_SERVER" "$ZABBIX_CONFIG"

    if [[ "$ENABLE_REMOTE_COMMANDS" =~ ^[Yy]$ ]]; then
        ensure_config_line "AllowKey=system.run[*]" "$ZABBIX_CONFIG"
        log_success "Remote commands включены через AllowKey=system.run[*]"
    fi

    log_success "Конфигурация обновлена"
}

validate_config() {
    if command -v zabbix_agent2 >/dev/null 2>&1; then
        if zabbix_agent2 -c "$ZABBIX_CONFIG" -t agent.ping >/dev/null 2>&1; then
            log_success "Тест agent.ping выполнен успешно"
        else
            log_warn "Тест agent.ping завершился с ошибкой"
            return 1
        fi
    else
        log_warn "Команда zabbix_agent2 не найдена, тест пропущен"
    fi
    return 0
}

# =========================================================
# Сеть и firewall
# =========================================================
check_server_connectivity() {
    local host="$1"
    local port="10051"

    log_info "Проверка доступности ${host}:${port}"

    if command -v timeout >/dev/null 2>&1; then
        if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log_success "Сервер ${host}:${port} доступен"
            return 0
        else
            log_warn "Сервер ${host}:${port} недоступен"
            return 1
        fi
    fi

    log_warn "timeout не найден, проверка сети пропущена"
    return 2
}

open_firewall_port() {
    log_info "Проверка firewall для порта 10050/tcp"

    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=10050/tcp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log_success "Порт 10050/tcp открыт в firewalld"
        return 0
    fi

    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qi "Status: active"; then
            ufw allow 10050/tcp >/dev/null 2>&1 || true
            log_success "Порт 10050/tcp открыт в UFW"
            return 0
        fi
    fi

    log_warn "Автонастройка firewall не выполнена: firewalld/UFW не активны или не найдены"
    return 0
}

# =========================================================
# Служба
# =========================================================
restart_agent() {
    log_info "Перезапуск zabbix-agent2"
    systemctl daemon-reload

    if systemctl enable zabbix-agent2 >/dev/null 2>&1 && systemctl restart zabbix-agent2; then
        log_success "Служба zabbix-agent2 запущена"
    else
        log_error "Не удалось запустить zabbix-agent2"
        systemctl status zabbix-agent2 --no-pager || true
        return 1
    fi
}

show_service_status() {
    echo -e "${YELLOW}[ИНФО] Статус службы:${NC}"
    systemctl --no-pager --full status zabbix-agent2 || true

    echo -e "${YELLOW}[ИНФО] Прослушиваемые порты:${NC}"
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp | grep 10050 || true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp | grep 10050 || true
    fi
}

# =========================================================
# Ввод данных
# =========================================================
choose_zabbix_version() {
    if [ "$INSTALL_MODE" = "cli" ]; then
        return 0
    fi

    echo -e "${YELLOW}[ИНФО] Выберите версию Zabbix:${NC}"
    echo "1. 7.0 LTS"
    echo "2. 6.0 LTS"
    read -rp "Ваш выбор [1-2, по умолчанию 1]: " version_choice

    case "$version_choice" in
        2) ZABBIX_VERSION="6.0" ;;
        *) ZABBIX_VERSION="7.0" ;;
    esac
}

get_configuration() {
    if [ "$INSTALL_MODE" = "cli" ]; then
        if [ -z "$HOSTNAME_ZBX" ]; then
            HOSTNAME_ZBX="$(hostname)"
        fi
        if [ -z "$ZABBIX_SERVER" ]; then
            log_error "Для CLI-режима нужно указать --server"
            return 1
        fi
        return 0
    fi

    local current_hostname
    current_hostname="$(hostname)"

    echo -e "${BLUE}Текущее имя хоста: ${current_hostname}${NC}"
    read -rp "Введите имя хоста для Zabbix агента [${current_hostname}]: " hostname_input
    HOSTNAME_ZBX="${hostname_input:-$current_hostname}"

    read -rp "Введите IP/FQDN сервера Zabbix: " server_input
    ZABBIX_SERVER="${server_input:-}"

    if [ -z "$ZABBIX_SERVER" ]; then
        log_error "Сервер Zabbix не может быть пустым"
        return 1
    fi

    read -rp "Включить удалённые команды через AllowKey=system.run[*]? (y/n) [n]: " remote_choice
    ENABLE_REMOTE_COMMANDS="${remote_choice:-n}"

    echo
    echo -e "${GREEN}Сводка:${NC}"
    echo "  Hostname: $HOSTNAME_ZBX"
    echo "  Server: $ZABBIX_SERVER"
    echo "  Version: $ZABBIX_VERSION"
    echo "  Remote commands: $ENABLE_REMOTE_COMMANDS"
    echo

    confirm "Применить эту конфигурацию" || return 1
}

# =========================================================
# Основные действия
# =========================================================
install_agent() {
    log_info "Начало установки Zabbix Agent2"

    if is_agent_installed; then
        log_warn "zabbix-agent2 уже установлен"
        confirm "Переустановить/перенастроить" || return 0
    fi

    choose_zabbix_version
    get_configuration || return 1
    check_server_connectivity "$ZABBIX_SERVER" || true
    install_repo || return 1

    log_info "Установка пакета zabbix-agent2"
    install_agent_package || {
        log_error "Не удалось установить zabbix-agent2"
        return 1
    }

    configure_agent || return 1
    open_firewall_port || true
    restart_agent || return 1
    validate_config || true
    show_service_status
    rm -f "$TMP_REPO_PKG"
    log_success "Установка завершена"
}

reconfigure_agent() {
    log_info "Перенастройка Zabbix Agent2"

    if [ ! -f "$ZABBIX_CONFIG" ]; then
        log_error "Конфиг не найден. Агент не установлен?"
        return 1
    fi

    choose_zabbix_version
    get_configuration || return 1
    check_server_connectivity "$ZABBIX_SERVER" || true
    configure_agent || return 1
    open_firewall_port || true
    restart_agent || return 1
    validate_config || true
    show_service_status
    log_success "Перенастройка завершена"
}

remove_agent() {
    log_info "Удаление Zabbix Agent2"

    if ! is_agent_installed; then
        log_info "zabbix-agent2 не установлен"
        return 0
    fi

    if [ "$INSTALL_MODE" != "cli" ]; then
        read -rp "Удалить также /etc/zabbix? (y/n) [n]: " REMOVE_CONFIG
        read -rp "Удалить также zabbix-release? (y/n) [n]: " REMOVE_REPO
        confirm "Продолжить удаление" || return 0
    fi

    systemctl stop zabbix-agent2 2>/dev/null || true
    systemctl disable zabbix-agent2 2>/dev/null || true

    remove_agent_package || {
        log_error "Не удалось удалить пакет zabbix-agent2"
        return 1
    }

    if [[ "$REMOVE_REPO" =~ ^[Yy]$ ]]; then
        remove_repo_package || true
    fi

    if [[ "$REMOVE_CONFIG" =~ ^[Yy]$ ]]; then
        rm -rf /etc/zabbix
        log_warn "Каталог /etc/zabbix удалён"
    fi

    log_success "Удаление завершено"
}

show_config() {
    if [ -f "$ZABBIX_CONFIG" ]; then
        echo -e "${YELLOW}[ИНФО] Текущая конфигурация:${NC}"
        grep -E "^(Hostname|Server|ServerActive|AllowKey)=" "$ZABBIX_CONFIG" || true
        echo
        show_service_status
    else
        log_info "Конфиг Zabbix Agent2 не найден"
    fi
}

show_installer_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}[ИНФО] Последние 100 строк лога:${NC}"
        tail -n 100 "$LOG_FILE"
    else
        log_warn "Лог не найден"
    fi
}

# =========================================================
# CLI
# =========================================================
show_help() {
    cat <<EOF
Использование:
  $0 [опции]

Действия:
  --install                  Установить агент
  --remove                   Удалить агент
  --reconfigure              Перенастроить агент
  --show-config              Показать текущую конфигурацию
  --show-log                 Показать лог установщика

Параметры:
  --server HOST              Сервер Zabbix
  --hostname NAME            Имя хоста агента
  --version 6.0|7.0          Версия Zabbix
  --enable-remote-commands   Включить AllowKey=system.run[*]
  --remove-config            При удалении удалить /etc/zabbix
  --remove-repo              При удалении удалить zabbix-release
  --yes                      Автоподтверждение
  --help                     Показать помощь

Примеры:
  $0 --install --server 10.10.10.10 --hostname srv-01 --version 7.0 --yes
  $0 --reconfigure --server zabbix.local --hostname web-01 --enable-remote-commands
  $0 --remove --remove-config --remove-repo --yes
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --install)
                ACTION="install"
                INSTALL_MODE="cli"
                ;;
            --remove)
                ACTION="remove"
                INSTALL_MODE="cli"
                ;;
            --reconfigure)
                ACTION="reconfigure"
                INSTALL_MODE="cli"
                ;;
            --show-config)
                ACTION="show-config"
                INSTALL_MODE="cli"
                ;;
            --show-log)
                ACTION="show-log"
                INSTALL_MODE="cli"
                ;;
            --server)
                ZABBIX_SERVER="${2:-}"
                shift
                ;;
            --hostname)
                HOSTNAME_ZBX="${2:-}"
                shift
                ;;
            --version)
                ZABBIX_VERSION="${2:-}"
                shift
                ;;
            --enable-remote-commands)
                ENABLE_REMOTE_COMMANDS="y"
                ;;
            --remove-config)
                REMOVE_CONFIG="y"
                ;;
            --remove-repo)
                REMOVE_REPO="y"
                ;;
            --yes|-y)
                AUTO_YES="y"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Неизвестный параметр: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

# =========================================================
# Меню
# =========================================================
show_menu() {
    echo "1. Установить Zabbix Agent2"
    echo "2. Удалить Zabbix Agent2"
    echo "3. Перенастроить Zabbix Agent2"
    echo "4. Показать текущую конфигурацию"
    echo "5. Показать лог установщика"
    echo "0. Выход"
    echo
}

interactive_main() {
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
                echo -e "${RED}[ОШИБКА] Неверный выбор${NC}"
                ;;
        esac

        echo
        read -rp "Нажмите Enter для продолжения..."
    done
}

cli_main() {
    case "$ACTION" in
        install) install_agent ;;
        remove) remove_agent ;;
        reconfigure) reconfigure_agent ;;
        show-config) show_config ;;
        show-log) show_installer_log ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# =========================================================
# Точка входа
# =========================================================
main() {
    check_root
    init_log
    detect_os
    check_dependencies
    parse_args "$@"

    if [ "$INSTALL_MODE" = "cli" ]; then
        cli_main
    else
        interactive_main
    fi
}

main "$@"