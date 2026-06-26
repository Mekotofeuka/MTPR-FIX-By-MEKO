#!/bin/bash
set -eo pipefail

# ── Цвета ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Логирование ─────────────────────────────────────────────
log_info() { echo -e "  ${BLUE}[i]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "  ${RED}[✗]${NC} $1" >&2; }
log_warning() { echo -e "  ${YELLOW}[!]${NC} $1"; }

# ── Проверка root ────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Требуются права root"
        exit 1
    fi
}

check_root

# ── Файл для сохранения пути к конфигу ──────────────────────
CONFIG_PATH_FILE="/opt/mtpr-simple/config_path"

# ── Проверяем, сохранён ли путь к конфигу ──────────────────
if [ -f "$CONFIG_PATH_FILE" ] && [ -s "$CONFIG_PATH_FILE" ]; then
    DEFAULT_CONFIG_TELEMT=$(cat "$CONFIG_PATH_FILE")
else
    DEFAULT_CONFIG_TELEMT="/etc/telemt/telemt.toml"
    echo -en "Укажите путь к конфигу Telemt (По умолчанию: [${DEFAULT_CONFIG_TELEMT}] если не меняли - нажмите Enter): "
    read -r CONFIG_TELEMT_INPUT

    if [ -z "$CONFIG_TELEMT_INPUT" ]; then
        CONFIG_TELEMT_INPUT="$DEFAULT_CONFIG_TELEMT"
    fi

    DEFAULT_CONFIG_TELEMT="$CONFIG_TELEMT_INPUT"

    # ── Проверяем, что указанный файл конфига действительно существует ──
    if [ ! -f "$DEFAULT_CONFIG_TELEMT" ]; then
        log_warning "Файл $DEFAULT_CONFIG_TELEMT не найден."
        echo -en "  ${BOLD}Сохранить этот путь всё равно? [y/N]:${NC} "
        confirm_path=""
        read -r confirm_path
        if [[ ! "$confirm_path" =~ ^[yY]$ ]]; then
            log_error "Путь к конфигу не подтверждён, выход."
            exit 1
        fi
    fi

    # ── Сохраняем путь ──────────────────────────────────────
    mkdir -p /opt/mtpr-simple
    echo "$DEFAULT_CONFIG_TELEMT" >"$CONFIG_PATH_FILE"
fi

CONFIG_TELEMT="$DEFAULT_CONFIG_TELEMT"

# ── Файл для хранения порта ─────────────────────────────────
PORT_FILE="/opt/mtpr-simple/port"

# ── Функция определения порта SSH ────────────────────────────
get_ssh_port() {
    local port
    if command -v sshd >/dev/null 2>&1 && sshd -T 2>/dev/null | grep -q 'port '; then
        port=$(sshd -T | grep 'port ' | awk '{print $2}' | head -1)
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "$port"
            return 0
        fi
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        port=$(grep -E '^Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config | head -1 | awk '{print $2}')
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "$port"
            return 0
        fi
    fi

    if [ -d /etc/ssh/sshd_config.d ]; then
        for cfg in /etc/ssh/sshd_config.d/*.conf; do
            if [ -f "$cfg" ]; then
                port=$(grep -E '^Port[[:space:]]+[0-9]+' "$cfg" | head -1 | awk '{print $2}')
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    echo "$port"
                    return 0
                fi
            fi
        done
    fi

    # Дефолтное значение
    echo "22"
    return 0
}

get_saved_port() {
    if [ -f "$PORT_FILE" ]; then
        cat "$PORT_FILE"
    else
        echo ""
    fi
}

save_port() {
    echo "$1" >"$PORT_FILE"
}

# ── Название кастомной цепочки iptables ─────────────────────
SYNFIX_CHAIN="MTPR_SYNFIX"

# ── ПРОВЕРКА НАЛИЧИЯ НАШЕЙ ЦЕПОЧКИ SYN FIX ──────────────────
is_syn_fix_installed() {
    iptables -L "$SYNFIX_CHAIN" -n >/dev/null 2>&1
}

# ── Для обратной совместимости с остальным кодом меню ──────
is_our_syn_fix_installed() {
    is_syn_fix_installed
}

# ── ПРОВЕРКА НАЛИЧИЯ MSS И SYN_LIMIT В КОНФИГЕ TELEMT ──────
is_mss_enabled() {
    local config="$CONFIG_TELEMT"
    if [ -f "$config" ]; then
        if grep -E 'client_mss[[:space:]]*=' "$config" | grep -v '^#' | grep -q .; then
            return 0
        fi
    fi
    return 1
}

is_synlimit_enabled() {
    local config="$CONFIG_TELEMT"
    if [ -f "$config" ]; then
        if grep -E 'synlimit[[:space:]]*=' "$config" | grep -v '^#' | grep -q .; then
            return 0
        fi
    fi
    return 1
}

are_bad_options_enabled() {
    if is_mss_enabled || is_synlimit_enabled; then
        return 0
    else
        return 1
    fi
}

# ── ОТКЛЮЧЕНИЕ MSS И SYN_LIMIT (закомментирование строк) ──
disable_bad_options() {
    local config="$CONFIG_TELEMT"
    if [ ! -f "$config" ]; then
        log_error "Файл $config не найден"
        return 1
    fi

    local changed=0

    # Отключаем MSS
    if grep -E 'client_mss[[:space:]]*=' "$config" | grep -v '^#' | grep -q .; then
        sed -i '/client_mss[[:space:]]*=/s/^/#/' "$config"
        changed=1
    fi

    # Отключаем synlimit
    if grep -E 'synlimit[[:space:]]*=' "$config" | grep -v '^#' | grep -q .; then
        sed -i '/synlimit[[:space:]]*=/s/^/#/' "$config"
        changed=1
    fi

    if [ "$changed" -eq 1 ]; then
        log_success "MSS и synlimit отключены (строки закомментированы)"
    else
        log_info "Активные строки client_mss или synlimit не найдены"
    fi
}

# ── Установка iptables-persistent (если отсутствует) ────────
ensure_iptables_persistence() {
    if dpkg -s iptables-persistent >/dev/null 2>&1; then
        return 0
    fi
    log_info "Установка iptables-persistent для сохранения правил между перезагрузками..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
}

# ── Сохранение текущих правил iptables на диск ──────────────
persist_iptables_rules() {
    mkdir -p /etc/iptables
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    elif command -v iptables-save >/dev/null 2>&1; then
        iptables-save >/etc/iptables/rules.v4
    fi
}

# ── Установка SYN FIX ──────────────────────────────────────
install_syn_fix() {
    local port
    ssh_port=$(get_ssh_port)
    echo ""
    echo -en "  ${BOLD}Введите порт для SYN FIX (по умолчанию 443):${NC} "
    read -r port
    if [ -z "$port" ]; then
        port="443"
    fi
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Некорректный порт, используем 443"
        port="443"
    fi

    # ── ПОДТВЕРЖДЕНИЕ ПЕРЕД УСТАНОВКОЙ ──────────────────────
    echo ""
    log_warning "Будет выполнена установка SYN FIX на порт $port"
    echo ""
    echo -e "  ${BOLD}Что будет сделано:${NC}"
    echo -e "  • Создана отдельная цепочка iptables ${CYAN}$SYNFIX_CHAIN${NC} для порта ${CYAN}$port${NC}"
    echo -e "  • Добавлены ${CYAN}4 правила${NC} SYN-фильтрации в эту цепочку"
    echo -e "  • Правила будут сохранены через ${CYAN}iptables-persistent${NC} (для применения после перезагрузки)"
    echo -e "  • Вы сможете удалить данную настройку через меню скрипта."
    echo ""
    log_warning "${BOLD}ВНИМАНИЕ:${NC} Данная настройка изменит файрвол системы."
    echo ""
    echo -en "  ${BOLD}Продолжить установку? [y/N]:${NC} "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_info "Установка отменена"
        sleep 0.5
        return 1
    fi

    log_info "Установка SYN FIX на порт $port..."

    ensure_iptables_persistence

    # ── Гарантируем доступ по SSH, прежде чем менять политику фильтрации ──
    if ! iptables -C INPUT -p tcp --dport "$ssh_port" -j ACCEPT 2>/dev/null; then
        iptables -I INPUT 1 -p tcp --dport "$ssh_port" -j ACCEPT
    fi

    # ── Создаём (или очищаем) собственную цепочку ──────────
    iptables -N "$SYNFIX_CHAIN" 2>/dev/null
    iptables -F "$SYNFIX_CHAIN"

    # ── Подключаем цепочку к INPUT, если ещё не подключена ──
    if ! iptables -C INPUT -j "$SYNFIX_CHAIN" 2>/dev/null; then
        iptables -I INPUT 2 -j "$SYNFIX_CHAIN"
    fi

    iptables -A "$SYNFIX_CHAIN" \
        -p tcp --dport "$port" --syn \
        -m tcp --tcp-flags SYN SYN \
        -m length --length 64 \
        -m ttl --ttl-lt 65 \
        -m hashlimit \
        --hashlimit-name ios_"$port" \
        --hashlimit-mode srcip \
        --hashlimit-upto 15/second \
        --hashlimit-burst 30 \
        --hashlimit-htable-expire 60000 \
        --hashlimit-htable-size 32768 \
        -j ACCEPT

    iptables -A "$SYNFIX_CHAIN" \
        -p tcp --dport "$port" --syn \
        -m tcp --tcp-flags SYN SYN \
        -m length --length 64 \
        -m ttl --ttl-lt 65 \
        -j REJECT --reject-with tcp-reset

    iptables -A "$SYNFIX_CHAIN" \
        -p tcp --dport "$port" --syn \
        -m hashlimit \
        --hashlimit-name mtproto_"$port" \
        --hashlimit-mode srcip \
        --hashlimit-upto 54/minute \
        --hashlimit-burst 1 \
        --hashlimit-htable-expire 60000 \
        --hashlimit-htable-size 32768 \
        -j ACCEPT

    iptables -A "$SYNFIX_CHAIN" \
        -p tcp --dport "$port" --syn \
        -j REJECT --reject-with tcp-reset

    save_port "$port"
    persist_iptables_rules

    log_success "SYN FIX успешно Установлен на порт $port"
}

# ── Удаление SYN FIX (только нашей цепочки) ────────────────
remove_syn_fix() {
    log_info "Удаление SYN FIX..."

    if iptables -C INPUT -j "$SYNFIX_CHAIN" 2>/dev/null; then
        iptables -D INPUT -j "$SYNFIX_CHAIN"
        log_info "Цепочка $SYNFIX_CHAIN отключена от INPUT"
    fi

    if iptables -L "$SYNFIX_CHAIN" -n >/dev/null 2>&1; then
        iptables -F "$SYNFIX_CHAIN"
        iptables -X "$SYNFIX_CHAIN"
        log_info "Цепочка $SYNFIX_CHAIN удалена"
    fi

    persist_iptables_rules
    rm -f "$PORT_FILE"

    log_success "SYN FIX удалён"
}

# ── Пункт 2: Отключение MSS и synlimit ─────────────────────
apply_optimization() {
    if are_bad_options_enabled; then
        echo ""
        log_info "Обнаружены активные строки с client_mss или synlimit в $CONFIG_TELEMT"
        echo -en "  ${BOLD}Отключить их? [Y/n]:${NC} "
        local confirm
        read -r confirm
        if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
            disable_bad_options
        else
            log_info "Отмена"
        fi
    else
        echo ""
        log_info "client_mss и synlimit уже отключены или отсутствуют в конфиге"
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
    fi
}

# ── Пункт 3: Базовая оптимизация ───────────────────────────
apply_basic_optimization() {
    echo ""
    log_info "Выполнение базовой оптимизации системы и Telemt..."

    if [ ! -f "$CONFIG_TELEMT" ]; then
        log_error "Файл конфига $CONFIG_TELEMT не найден, базовая оптимизация Telemt-параметров пропущена"
        return 1
    fi

    if [ ! -f /etc/sysctl.conf ]; then
        touch /etc/sysctl.conf
        chmod 644 /etc/sysctl.conf
        log_info "Создан /etc/sysctl.conf"
    fi

    # Создаем директорию для лимитов
    mkdir -p /etc/systemd/system/telemt.service.d

    # Настраиваем лимиты для telemt
    if ! grep -q "LimitNOFILE=65535" /etc/systemd/system/telemt.service.d/limits.conf 2>/dev/null; then
        cat >/etc/systemd/system/telemt.service.d/limits.conf <<EOF
[Service]
LimitNOFILE=65535
EOF
    fi

    systemctl daemon-reload

    # Функция применения sysctl
    apply_sysctl() {
        cat >/etc/sysctl.d/99-custom.conf <<EOF
net.ipv4.tcp_fastopen=3
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.core.netdev_max_backlog=65535
fs.file-max=2097152
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time=45
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_keepalive_probes=3
EOF

        sysctl --system 2>/dev/null || log_info "sysctl --system выполнен без изменений"
    }

    # ★★★★★ ВЫЗЫВАЕМ ФУНКЦИЮ ★★★★★
    apply_sysctl

    systemctl stop telemt

    # Настройка max_connections
    if grep -q '^max_connections *=.*' "$CONFIG_TELEMT"; then
        if ! grep -q '^max_connections *= *16384' "$CONFIG_TELEMT"; then
            sed -i 's/^max_connections *= *.*/max_connections = 16384/' "$CONFIG_TELEMT"
        fi
    else
        grep -q '\[server\]' "$CONFIG_TELEMT" && sed -i '/\[server\]/a max_connections = 16384' "$CONFIG_TELEMT"
    fi

    # Настройка client_handshake
    if grep -q '^client_handshake *=.*' "$CONFIG_TELEMT"; then
        if ! grep -q '^client_handshake *= *15' "$CONFIG_TELEMT"; then
            sed -i 's/^client_handshake *= *.*/client_handshake = 15/' "$CONFIG_TELEMT"
        fi
    fi

    systemctl restart telemt

    log_success "Базовая оптимизация выполнена"
}

# ── Пункт 4: Полное удаление MEKOpr ─────────────────────────
remove_mekopr() {
    echo ""
    log_warning "${BOLD}ВНИМАНИЕ:${NC} Будет выполнено полное удаление MEKOpr со всеми его конфигами и правилами!"
    echo ""
    echo -e "  ${BOLD}Что будет удалено:${NC}"
    echo -e "  • Все iptables правила и цепочка ${CYAN}$SYNFIX_CHAIN${NC}"
    echo -e "  • Все файлы конфигурации в ${CYAN}/opt/mtpr-simple${NC}"
    echo -e "  • Сам скрипт ${CYAN}$0${NC}"
    echo ""
    log_warning "Это действие нельзя отменить!"
    echo -en "  ${BOLD}Продолжить удаление? [y/N]:${NC} "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_info "Удаление отменено"
        return
    fi

    log_info "Начинаем полное удаление MEKOpr..."

    # ── Удаляем SYN FIX (правила iptables) ──────────────────
    remove_syn_fix

    # ── Удаляем файлы MEKOpr ────────────────────────────────
    log_info "Удаление файлов конфигурации..."
    rm -rf /opt/mtpr-simple

    # ── Удаляем сам скрипт ──────────────────────────────────
    log_info "Удаление скрипта..."
    rm -f "$0"

    log_success "MEKOpr полностью удалён с сервера!"
    echo ""
    log_info "Для завершения работы скрипта нажмите Enter..."
    read -r
    exit 0
}

# ── Очистка экрана и шапка ──────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# ── Функция получения версии Telemt ─────────────────────────
get_telemt_version() {
    if command -v telemt >/dev/null 2>&1; then
        telemt --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# ── Функция получения количества уникальных IP ─────────────
get_online_count() {
    local port="443"
    if [ -f "$CONFIG_TELEMT" ]; then
        local config_port=$(grep -E '^port[[:space:]]*=' "$CONFIG_TELEMT" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        if [[ "$config_port" =~ ^[0-9]+$ ]]; then
            port="$config_port"
        fi
    fi
    ss -tnp 2>/dev/null | grep ":${port}" | grep -v '0.0.0.0' | awk '{print $5}' | cut -d: -f1 | sort -u | wc -l | tr -d ' '
}

show_header() {
    clear_screen
    echo ""
    echo -e "  ${BOLD}MTProto Fixer by MEKO v0.79${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""

    # Обновляем порт из конфига при каждом показе меню
    if pgrep -x telemt >/dev/null 2>&1 && [ -f "$CONFIG_TELEMT" ]; then
        local current_port=$(grep -E '^port[[:space:]]*=' "$CONFIG_TELEMT" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        if [[ "$current_port" =~ ^[0-9]+$ ]] && [ "$current_port" != "$(get_saved_port)" ]; then
            save_port "$current_port"
        fi
    fi

    # Определяем статус SYN FIX
    if is_syn_fix_installed; then
        if is_our_syn_fix_installed; then
            local port_info=$(get_saved_port)
            if [ -n "$port_info" ]; then
                echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен${NC} (порт $port_info)"
            else
                echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен${NC}"
            fi
        else
            # Любой другой SYN фикс (не наш)
            echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен${NC}"
        fi
    else
        echo -e "  ${BOLD}SYN FIX:${NC} ${RED}Не установлен${NC}"
    fi

    # Telemt
    if pgrep -x telemt >/dev/null 2>&1; then
        local port_display=""
        if [ -f "$CONFIG_TELEMT" ]; then
            local port=$(grep -E '^port[[:space:]]*=' "$CONFIG_TELEMT" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                port_display=" (порт $port)"
            else
                port_display=" (порт не определён)"
            fi
        else
            port_display=" (порт не определён)"
        fi

        # Получаем версию Telemt
        local telemt_version=$(get_telemt_version)
        local version_color=""
        if [ -n "$telemt_version" ]; then
            if [ "$telemt_version" = "3.4.18" ]; then
                version_color="${GREEN}"
            elif [[ "$(printf '%s\n' "3.4.18" "$telemt_version" | sort -V | head -n1)" != "3.4.18" ]]; then
                version_color="${RED}"
            else
                version_color="${YELLOW}"
            fi
            version_display="${version_color}${telemt_version}${NC}"
        else
            version_display="${RED}не определена${NC}"
        fi

        # Получаем количество уникальных IP
        local online_count=$(get_online_count)

        echo -e "  ${BOLD}Telemt:${NC} ${GREEN}Установлен${NC}${port_display}"
        echo -e "  ${BOLD}Версия Telemt:${NC} $version_display"
        echo -e "  ${BOLD}Подключено к прокси:${NC} ${CYAN}$online_count${NC} человек"

        # Статус MSS и synlimit
        local mss_status=""
        local synlimit_status=""
        if is_mss_enabled; then
            mss_status="${RED}включен${NC}"
        else
            mss_status="${GREEN}отключен${NC}"
        fi
        if is_synlimit_enabled; then
            synlimit_status="${RED}включен${NC}"
        else
            synlimit_status="${GREEN}отключен${NC}"
        fi
        echo -e "  ${BOLD}MSS:${NC} $mss_status  |  ${BOLD}synlimit:${NC} $synlimit_status"
    else
        echo -e "  ${BOLD}Telemt:${NC} ${RED}не обнаружен${NC}"
    fi

    echo ""
}

# ── Главное меню ─────────────────────────────────────────────
main_menu() {
    while true; do
        show_header

        if is_syn_fix_installed; then
            local item1="${RED}Удалить SYN FIX${NC}"
        else
            local item1="${GREEN}Установить SYN FIX${NC}"
        fi

        # Проверяем статус для пункта 2
        if are_bad_options_enabled; then
            local item2="${CYAN}Отключить MSS и synlimit${NC}"
        else
            local item2="${GRAY}Отключить MSS и synlimit (уже отключены)${NC}"
        fi

        echo -e "  ${CYAN}[1]${NC}  $item1"
        echo -e "  ${CYAN}[2]${NC}  $item2"
        echo -e "  ${CYAN}[3]${NC}  ${GREEN}Выполнить базовую оптимизацию${NC}"
        echo -e "  ${CYAN}[4]${NC}  ${RED}Полное удаление MEKOpr${NC}"
        echo -e "  ${CYAN}[0]${NC}  Выход"
        echo ""
        echo -en "  ${BOLD}Выбор:${NC} "
        local choice
        read -r choice

        case "$choice" in
        1)
            echo ""
            if is_syn_fix_installed; then
                log_info "Обнаружена установленная цепочка SYN FIX ($SYNFIX_CHAIN). Удалить её?"
                echo -en "  ${BOLD}Удалить? [Y/n]:${NC} "
                local confirm
                read -r confirm
                if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
                    remove_syn_fix
                else
                    log_info "Отмена удаления"
                fi
            else
                if ! install_syn_fix; then
                    continue
                fi
            fi
            echo ""
            read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
            ;;
        2)
            echo ""
            if are_bad_options_enabled; then
                apply_optimization
            else
                log_info "MSS и synlimit уже отключены"
                echo ""
                read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
            fi
            ;;
        3)
            echo ""
            apply_basic_optimization
            echo ""
            read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
            ;;
        4)
            remove_mekopr
            ;;
        0 | q | Q)
            echo ""
            log_info "Выход"
            exit 0
            ;;
        *)
            log_error "Неверный выбор"
            sleep 1
            ;;
        esac
    done
}

# ── Запуск ────────────────────────────────────────────────────
main_menu
