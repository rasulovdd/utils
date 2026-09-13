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
OS_ID_LIKE=""
OS_FAMILY=""          # ubuntu | debian | rhel
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
TMP_REPO_PKG=""

# repo, которые можно отключить, если они ломают dnf
DNF_BROKEN_REPOS_PATTERN="rpmfusion*"

# Не позволяем apt/dpkg задавать интерактивные вопросы
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

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
    echo "[$ts] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
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
    log_info "Запуск Zabbix Agent2 Installer v1.4 Universal"
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
    echo "Версия: 1.4 Universal"
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
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-unknown}"
    OS_MAJOR="${OS_VERSION_ID%%.*}"

    # Определяем "семью" ОС: реальный ID + производные через ID_LIKE.
    # Это позволяет работать не только с Ubuntu/Debian/RHEL напрямую,
    # но и с производными дистрибутивами (Mint, Pop!_OS, Oracle Linux и т.д.)
    case "$OS_ID" in
        ubuntu)
            OS_FAMILY="ubuntu"
            PKG_MANAGER="apt"
            ;;
        debian)
            OS_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        rocky|almalinux|rhel|centos|ol)
            OS_FAMILY="rhel"
            PKG_MANAGER="dnf"
            ;;
        *)
            if echo "$OS_ID_LIKE" | grep -qiw "ubuntu"; then
                OS_FAMILY="ubuntu"
                PKG_MANAGER="apt"
            elif echo "$OS_ID_LIKE" | grep -qiw "debian"; then
                OS_FAMILY="debian"
                PKG_MANAGER="apt"
            elif echo "$OS_ID_LIKE" | grep -Eqiw "rhel|fedora|centos"; then
                OS_FAMILY="rhel"
                PKG_MANAGER="dnf"
            else
                log_warn "ОС не входит в список официально поддерживаемых: $OS_PRETTY_NAME"
                if ! confirm "Продолжить"; then
                    exit 0
                fi
                # Лучшая догадка по наличию пакетного менеджера
                if command -v apt >/dev/null 2>&1; then
                    OS_FAMILY="debian"
                    PKG_MANAGER="apt"
                elif command -v dnf >/dev/null 2>&1; then
                    OS_FAMILY="rhel"
                    PKG_MANAGER="dnf"
                else
                    log_error "Не удалось определить пакетный менеджер (apt/dnf не найдены)"
                    exit 1
                fi
            fi
            ;;
    esac

    log_info "Определена ОС: $OS_PRETTY_NAME (ID=$OS_ID, семья=$OS_FAMILY)"
    log_info "Пакетный менеджер: $PKG_MANAGER"
}

# =========================================================
# Проверка/установка зависимостей
# =========================================================
# В отличие от старой версии, отсутствующие утилиты не считаются
# фатальной ошибкой — скрипт пытается доустановить их сам.
# Это чинит частый случай: минимальные облачные образы Ubuntu/Debian
# без gnupg/wget, из-за чего apt update падает на проверке подписи репо.
ensure_base_packages() {
    local missing=()

    for cmd in wget curl gnupg; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi

    log_warn "Отсутствуют утилиты: ${missing[*]}. Пробую установить..."

    case "$PKG_MANAGER" in
        apt)
            apt_retry apt-get update -o Acquire::Retries=3 -y || true
            apt_retry apt-get install -y -o Acquire::Retries=3 \
                wget curl gnupg ca-certificates apt-transport-https || {
                log_warn "Не удалось установить часть базовых пакетов через apt, продолжаю с тем что есть"
            }
            ;;
        dnf)
            dnf install -y wget curl gnupg2 ca-certificates || {
                log_warn "Не удалось установить часть базовых пакетов через dnf, продолжаю с тем что есть"
            }
            ;;
    esac
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Не найдена команда: $cmd (не удалось установить автоматически)"
        exit 1
    fi
}

check_dependencies() {
    require_cmd awk
    require_cmd grep
    require_cmd sed
    require_cmd systemctl
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

    ensure_base_packages
    require_cmd wget
}

# =========================================================
# Синхронизация времени
# =========================================================
# Частая причина провала проверки GPG-подписи репозитория на свежих
# ВМ — некорректное системное время (ещё не синхронизировано по NTP).
# Проверяем это заранее и по возможности чиним, не считая фатальным.
ensure_time_sync() {
    if ! command -v timedatectl >/dev/null 2>&1; then
        return 0
    fi

    local ntp_active
    ntp_active="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "")"

    if [ "$ntp_active" != "yes" ]; then
        log_warn "Системное время не синхронизировано по NTP, включаю синхронизацию"
        timedatectl set-ntp true >/dev/null 2>&1 || true
        sleep 2
    fi
}

# =========================================================
# Запуск apt/dnf с логированием реального вывода и ожиданием
# освобождения dpkg/apt lock
# =========================================================
# На свежих Ubuntu/Debian серверах в первые минуты после старта часто
# работает unattended-upgrades/apt-daily и держит dpkg lock — apt
# в этот момент падает почти мгновенно с "Could not get lock ...".
# Раньше скрипт эту причину не показывал (терялся сам текст ошибки),
# из-за чего "apt install zabbix-agent2" падал без объяснений.
apt_retry() {
    local max_wait=180
    local waited=0
    local output
    local rc

    while true; do
        output="$("$@" 2>&1)"
        rc=$?

        if [ "$rc" -eq 0 ]; then
            [ -n "$output" ] && log_raw "OUT" "$output"
            return 0
        fi

        if echo "$output" | grep -qiE "could not get lock|dpkg frontend lock|resource temporarily unavailable|is another process using it"; then
            if [ "$waited" -ge "$max_wait" ]; then
                log_raw "OUT" "$output"
                log_error "apt/dpkg lock удерживается другим процессом дольше ${max_wait}с (unattended-upgrades / apt-daily?), прерываю"
                return 1
            fi
            log_warn "apt/dpkg занят другим процессом (unattended-upgrades / apt-daily), жду 10с... (${waited}/${max_wait}с)"
            sleep 10
            waited=$((waited + 10))
            continue
        fi

        log_raw "OUT" "$output"
        return "$rc"
    done
}

# =========================================================
# Скачивание с ретраями + проверка, что файл — настоящий пакет
# =========================================================
# repo.zabbix.com у части провайдеров (например РФ-хостеров) отдаёт
# транзитные сетевые ошибки (TLS/socket сбои вроде "Could not wait for
# server fd - select"), которые пропадают при повторной попытке.
# Поэтому вместо отдельного лёгкого HEAD-запроса (который сам может
# словить такую ошибку и ложно забраковать рабочий URL) сразу пробуем
# скачать файл несколько раз и проверяем, что это не пустышка/страница
# ошибки, а настоящий .deb/.rpm.
is_valid_package_file() {
    local file="$1"

    [ -s "$file" ] || return 1
    local size
    size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
    [ "$size" -ge 1000 ] || return 1

    case "$file" in
        *.deb)
            [ "$(head -c 7 "$file" 2>/dev/null)" = "!<arch>" ]
            ;;
        *.rpm)
            local magic
            magic="$(head -c 4 "$file" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
            [ "$magic" = "edabeedb" ]
            ;;
        *)
            return 0
            ;;
    esac
}

download_with_retry() {
    local url="$1"
    local dest="$2"
    local attempts=3
    local i

    for ((i = 1; i <= attempts; i++)); do
        rm -f "$dest"

        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --retry 2 --connect-timeout 15 --max-time 60 -o "$dest" "$url" 2>>"$LOG_FILE"
        elif command -v wget >/dev/null 2>&1; then
            wget -q --timeout=30 --tries=2 -O "$dest" "$url" 2>>"$LOG_FILE"
        else
            return 1
        fi

        if is_valid_package_file "$dest"; then
            return 0
        fi

        if [ "$i" -lt "$attempts" ]; then
            log_warn "Попытка ${i}/${attempts} скачать ${url} не удалась (похоже на временный сетевой сбой), повтор через 5с..."
            sleep 5
        fi
    done

    rm -f "$dest"
    return 1
}

# =========================================================
# Динамическое построение URL репозитория Zabbix + скачивание
# =========================================================
# Вместо жёсткой таблицы "ОС:версия -> URL" (которая ломается на
# каждой новой версии ОС/Zabbix) строим кандидатов по известным
# шаблонам имён пакетов в repo.zabbix.com и пробуем скачать каждый,
# пока один не окажется рабочим пакетом.
fetch_repo_package() {
    local dest="$1"
    local base="https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}"
    local candidates=()

    case "$OS_FAMILY" in
        ubuntu|debian)
            local distro_dir="$OS_FAMILY"
            local suffix="${OS_ID}${OS_VERSION_ID}"
            candidates+=(
                "${base}/${distro_dir}/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+${suffix}_all.deb"
                "${base}/${distro_dir}/pool/main/z/zabbix-release/zabbix-release_latest+${suffix}_all.deb"
                "${base}/release/${distro_dir}/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_VERSION}+${suffix}_all.deb"
            )
            ;;
        rhel)
            candidates+=(
                "${base}/rhel/${OS_MAJOR}/x86_64/zabbix-release-latest-${ZABBIX_VERSION}.el${OS_MAJOR}.noarch.rpm"
                "${base}/rhel/${OS_MAJOR}/x86_64/zabbix-release-${ZABBIX_VERSION}-1.el${OS_MAJOR}.noarch.rpm"
            )
            ;;
        *)
            log_error "Неизвестная семья ОС для построения URL репозитория: $OS_FAMILY"
            return 1
            ;;
    esac

    local url
    for url in "${candidates[@]}"; do
        log_info "Пробую скачать репозиторий: $url"
        if download_with_retry "$url" "$dest"; then
            log_success "Скачано: $url"
            RESOLVED_REPO_URL="$url"
            return 0
        fi
        log_warn "Не удалось скачать (или это не валидный пакет): $url"
    done

    return 1
}

# =========================================================
# Очистка старых/битых записей репозитория Zabbix
# =========================================================
# Если раньше на этой машине уже пытались ставить Zabbix (вручную или
# другим скриптом) под неверную версию ОС, в apt/dnf остаются файлы
# с неверным кодовым именем (например "noble" на Ubuntu 22.04 "jammy"),
# из-за которых apt update стабильно шлёт ошибки/предупреждения по
# repo.zabbix.com. Убираем их перед установкой свежего репозитория.
clean_stale_zabbix_repo() {
    case "$PKG_MANAGER" in
        apt)
            rm -f /etc/apt/sources.list.d/zabbix*.list /etc/apt/sources.list.d/zabbix*.sources 2>/dev/null
            ;;
        dnf)
            rm -f /etc/yum.repos.d/zabbix*.repo 2>/dev/null
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

apt_update_safe() {
    if apt_retry apt-get update -o Acquire::Retries=3; then
        return 0
    fi

    log_warn "apt update не удался, пробую с --allow-releaseinfo-change ..."
    if apt_retry apt-get update -o Acquire::Retries=3 --allow-releaseinfo-change; then
        return 0
    fi

    log_error "apt update не удался"
    return 1
}

# =========================================================
# Пакетные операции
# =========================================================
install_repo() {
    clean_stale_zabbix_repo

    local pkg_ext="deb"
    [ "$OS_FAMILY" = "rhel" ] && pkg_ext="rpm"
    TMP_REPO_PKG="/tmp/zabbix-release.${pkg_ext}"
    RESOLVED_REPO_URL=""

    fetch_repo_package "$TMP_REPO_PKG" || {
        log_error "Не удалось скачать рабочий пакет репозитория для ${OS_PRETTY_NAME} и Zabbix ${ZABBIX_VERSION} (все варианты URL проверены). Похоже на сетевую проблему до repo.zabbix.com — проверьте связь с этим хостом с сервера (например: curl -v https://repo.zabbix.com/) либо повторите попытку позже. Также проверьте поддержку вашей ОС/версии: https://repo.zabbix.com/zabbix/${ZABBIX_VERSION}/"
        return 1
    }

    case "$PKG_MANAGER" in
        apt)
            # --allow-downgrades: на сервере может уже стоять более новая
            # zabbix-release с прошлых попыток/версий — не считаем это
            # ошибкой, нам нужен репозиторий именно для ${ZABBIX_VERSION}.
            apt_retry apt-get install -y --allow-downgrades "$TMP_REPO_PKG" || {
                log_warn "Установка репо-пакета провалилась, пробую доустановить зависимости"
                apt_retry apt-get install -f -y || true
                apt_retry apt-get install -y --allow-downgrades "$TMP_REPO_PKG" || {
                    log_error "Не удалось установить пакет репозитория"
                    return 1
                }
            }
            apt_update_safe || return 1
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
            apt_retry apt-get install -y zabbix-agent2 || return 1
            ;;
        dnf)
            dnf_install_safe "zabbix-agent2" || return 1
            ;;
    esac
}

remove_agent_package() {
    case "$PKG_MANAGER" in
        apt)
            apt_retry apt-get remove -y zabbix-agent2 || return 1
            apt_retry apt-get autoremove -y || true
            ;;
        dnf)
            dnf_remove_safe "zabbix-agent2" || return 1
            ;;
    esac
}

remove_repo_package() {
    case "$PKG_MANAGER" in
        apt)
            apt_retry apt-get remove -y zabbix-release || true
            apt_retry apt-get autoremove -y || true
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
        journalctl -u zabbix-agent2 --no-pager -n 50 2>/dev/null || true
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
    echo "3. Своя версия (например 7.2, 7.4)"
    read -rp "Ваш выбор [1-3, по умолчанию 1]: " version_choice

    case "$version_choice" in
        2) ZABBIX_VERSION="6.0" ;;
        3)
            read -rp "Введите версию Zabbix: " custom_version
            ZABBIX_VERSION="${custom_version:-7.0}"
            ;;
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
    ensure_time_sync
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
    [ -n "$TMP_REPO_PKG" ] && rm -f "$TMP_REPO_PKG"
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
  --reconfigure               Перенастроить агент
  --show-config               Показать текущую конфигурацию
  --show-log                  Показать лог установщика

Параметры:
  --server HOST               Сервер Zabbix
  --hostname NAME              Имя хоста агента
  --version X.Y                Версия Zabbix (например 7.0, 6.0, 7.4)
  --enable-remote-commands     Включить AllowKey=system.run[*]
  --remove-config              При удалении удалить /etc/zabbix
  --remove-repo                При удалении удалить zabbix-release
  --yes                        Автоподтверждение
  --help                       Показать помощь

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
