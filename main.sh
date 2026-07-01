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
    CONFIG_TELEMT=$(cat "$CONFIG_PATH_FILE")
    if [ "$CONFIG_TELEMT" = "skip" ]; then
        CONFIG_TELEMT=""
    fi
else
    echo ""
    echo -e "  ${NC}${BOLD}Укажите путь к конфигу Telemt${NC}"
    echo -e "  ${NC}${BOLD}По умолчанию: ${GREEN}${BOLD}[/etc/telemt/telemt.toml]${NC}"
    echo -e "  ${NC}${BOLD}Если не меняли путь — нажмите ${GREEN}${BOLD}Enter${NC}"
    echo -e "  ${NC}${BOLD}Если Telemt ещё не установлен — нажмите${GREEN}${BOLD} [N/n]${NC}"
    echo ""
    echo -en "  ${BOLD}Ввод:${NC} "
    read -r CONFIG_TELEMT_INPUT

    if [[ "$CONFIG_TELEMT_INPUT" =~ ^[Nn]$ ]]; then
        # Пользователь выбрал N - пропускаем указание пути
        mkdir -p /opt/mtpr-simple
        echo "skip" > "$CONFIG_PATH_FILE"
        CONFIG_TELEMT=""
    else
        if [ -z "$CONFIG_TELEMT_INPUT" ]; then
            CONFIG_TELEMT_INPUT="/etc/telemt/telemt.toml"
        fi

        # ── Проверяем, что указанный файл конфига действительно существует ──
        if [ ! -f "$CONFIG_TELEMT_INPUT" ]; then
            log_warning "Файл $CONFIG_TELEMT_INPUT не найден."
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
        echo "$CONFIG_TELEMT_INPUT" > "$CONFIG_PATH_FILE"
        CONFIG_TELEMT="$CONFIG_TELEMT_INPUT"
    fi
fi

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

# ── ПРОВЕРКА НАЛИЧИЯ ЦЕПОЧКИ IPTABLES SYN FIX ────────────────
is_syn_fix_chain_installed() {
    iptables -L "$SYNFIX_CHAIN" -n >/dev/null 2>&1
}

# ── ПРОВЕРКА СТАТУСА SYSTEMD СЕРВИСА SYN FIX ─────────────────
is_syn_fix_service_running() {
    systemctl is-active --quiet mtpr-synfix.service
}

# ── ПОЛУЧЕНИЕ СТАТУСА SYN FIX (для show_header) ────────────────
get_synfix_status() {
    if is_syn_fix_chain_installed; then
        if is_syn_fix_service_running; then
            echo "active"
        else
            echo "has_chain_only"
        fi
    else
        echo "inactive"
    fi
}

# ── Для обратной совместимости с остальным кодом меню ──────
is_our_syn_fix_installed() {
    is_syn_fix_chain_installed
}

# ── ПРОВЕРКА НАЛИЧИЯ MSS И SYN_LIMIT В КОНФИГЕ TELEMT ──────
is_mss_enabled() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        return 1
    fi
    if grep -E 'client_mss[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        return 0
    fi
    return 1
}

is_synlimit_enabled() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        return 1
    fi
    if grep -E 'synlimit[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        return 0
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
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        log_error "Файл конфига не найден или не указан"
        return 1
    fi

    local changed=0

    # Отключаем MSS
    if grep -E 'client_mss[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        sed -i '/client_mss[[:space:]]*=/s/^/#/' "$CONFIG_TELEMT"
        changed=1
    fi

    # Отключаем synlimit
    if grep -E 'synlimit[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        sed -i '/synlimit[[:space:]]*=/s/^/#/' "$CONFIG_TELEMT"
        changed=1
    fi

    if [ "$changed" -eq 1 ]; then
        log_success "MSS и synlimit отключены (строки закомментированы)"
    else
        log_info "Активные строки client_mss или synlimit не найдены"
    fi
}

# ── Установка SYN FIX ──────────────────────────────────────
install_syn_fix() {
    local port
    local auto_install=false
    local forced_port=""
    local fix_choice=""

    # Проверяем аргумент -auto_install
    if [[ "$1" == "-auto_install" ]]; then
        auto_install=true
        forced_port="$2"
        # В авто-режиме всегда ставим новый вариант
        FIX_TYPE="new"
    fi

    ssh_port=$(get_ssh_port)

    # В авто-режиме берём порт из аргумента, иначе дефолтный
    if [ "$auto_install" = true ]; then
        if [[ "$forced_port" =~ ^[0-9]+$ ]]; then
            port="$forced_port"
            log_info "Используем порт, переданный аргументом: $port"
        else
            log_info "Файл с портом не найден, используем 443"
            port="443"
        fi
    else
        # Обычный интерактивный режим
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

        # ── ВЫБОР ТИПА ФИКСА ──────────────────────────────────
        echo ""
        echo -e "  ${BOLD}Выберите тип SYN FIX:${NC}"
        echo -e "  ${GREEN}[1]${NC}  ${BOLD}Новый вариант${NC} (u32 + ACCEPT без лимита) — ${GREEN}рекомендуется${NC}"
        echo -e "  ${CYAN}[2]${NC}  ${BOLD}Старый вариант${NC} (TTL+Length + ACCEPT без лимита)"
        echo ""
        echo -en "  ${BOLD}Выбор [1/2, Enter = 1]:${NC} "
        read -r fix_choice

        if [ -z "$fix_choice" ] || [ "$fix_choice" = "1" ]; then
            FIX_TYPE="new"
            log_info "Выбран новый вариант фикса"
        elif [ "$fix_choice" = "2" ]; then
            FIX_TYPE="old"
            log_info "Выбран старый вариант фикса"
        else
            log_warning "Неверный выбор, используем новый вариант"
            FIX_TYPE="new"
        fi
    fi

    # ── ПОДТВЕРЖДЕНИЕ ПЕРЕД УСТАНОВКОЙ ──────────────────────
    if [ "$auto_install" = false ]; then
        echo ""
        log_warning "Будет выполнена установка SYN FIX на порт $port"
        echo ""
        echo -e "  ${BOLD}Что будет сделано:${NC}"
        echo -e "  • Создана отдельная цепочка iptables ${CYAN}$SYNFIX_CHAIN${NC} для порта ${CYAN}$port${NC}"
        echo -e "  • Добавлены правила SYN-фильтрации в эту цепочку"
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
    fi

    log_info "Установка SYN FIX на порт $port..."
    save_port "$port"

    # ── Генерируем и запускаем скрипт применения правил ─────────
    generate_apply_script "$FIX_TYPE"
    generate_service_unit
    systemctl daemon-reload
    PORT="$port" /opt/mtpr-simple/apply-mtpr-synfix.sh
    systemctl enable mtpr-synfix.service
    systemctl restart mtpr-synfix.service

    log_success "SYN FIX успешно Установлен на порт $port"
}

# ── Удаление правил из файла iptables ──────────────────────
remove_iptables_rules() {
    local rules_file="/etc/iptables/rules.v4"
    
    if [ ! -f "$rules_file" ]; then
        log_warning "Файл $rules_file не найден"
        return 1
    fi
    
    log_info "Проверка наличия наших правил в $rules_file..."
    
    # Проверяем, есть ли наша цепочка в файле
    if ! grep -q "MTPR_SYNFIX" "$rules_file"; then
        log_warning "Наши правила (MTPR_SYNFIX) не найдены в файле"
        return 1
    fi
    
    # Наши правила есть - запрашиваем подтверждение
    echo ""
    echo -e "  ${BOLD}Обнаружены наши правила SYN FIX в файле${NC}"
    echo -e "  ${DIM}Что будет сделано:${NC}"
    if grep -q "^COMMIT" "$rules_file" && grep -c "MTPR_SYNFIX" "$rules_file" | grep -q '^1$'; then
        echo -e "  • Будет удалён весь файл (только наши правила)"
    else
        echo -e "  • Будут удалены только строки с цепочкой $SYNFIX_CHAIN"
    fi
    echo ""
    log_warning "Это изменит конфигурацию iptables-persistent!"
    echo ""
    echo -en "  ${BOLD}Подтвердить удаление? [y/N]:${NC} "
    local confirm
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log_info "Удаление отменено"
        return 0
    fi
    
    echo ""
    
    # Удаляем только наши правила (строки с MTPR_SYNFIX)
    local temp_file=$(mktemp)
    grep -v "MTPR_SYNFIX" "$rules_file" > "$temp_file"
    mv "$temp_file" "$rules_file"
    chmod 644 "$rules_file"
    
    log_success "Правила $SYNFIX_CHAIN удалены из $rules_file"
}

# ── Удаление SYN FIX (только нашей цепочки) ────────────────
remove_syn_fix() {
    log_info "Удаление SYN FIX..."

    # ── Останавливаем и отключаем systemd сервис ────────────────
    systemctl stop mtpr-synfix.service 2>/dev/null || true
    systemctl disable mtpr-synfix.service 2>/dev/null || true

    if iptables -C INPUT -j "$SYNFIX_CHAIN" 2>/dev/null; then
        iptables -D INPUT -j "$SYNFIX_CHAIN"
        log_info "Цепочка $SYNFIX_CHAIN отключена от INPUT"
    fi

    if iptables -L "$SYNFIX_CHAIN" -n >/dev/null 2>&1; then
        iptables -F "$SYNFIX_CHAIN"
        iptables -X "$SYNFIX_CHAIN"
        log_info "Цепочка $SYNFIX_CHAIN удалена"
    fi

    rm -f "$PORT_FILE"

    # Удаляем systemd юнит файл
    rm -f /etc/systemd/system/mtpr-synfix.service

    # Перезагружаем менеджер служб
    systemctl daemon-reload

    log_success "SYN FIX удалён"
}

# ── Перезапуск сервиса SYN FIX ─────────
restart_syn_fix_service() {
    log_info "Перезапуск сервиса mtpr-synfix.service..."
    systemctl restart mtpr-synfix.service
    log_success "Сервис успешно перезапущен"
}

# ── Генерация скрипта применения правил ──────────────────────────
generate_apply_script() {
    local fix_type="${1:-new}"

    if [ "$fix_type" = "old" ]; then
        cat >/opt/mtpr-simple/apply-mtpr-synfix.sh <<'APPLY_SCRIPT_EOF'
#!/bin/bash
set -e

PORT="${PORT:-$(cat /opt/mtpr-simple/port 2>/dev/null)}"

if [ -z "$PORT" ]; then
    echo "SYN FIX: Порт не указан, выход" >&2
    exit 1
fi

CHAIN="MTPR_SYNFIX"

SSH_PORT=$(sshd -T 2>/dev/null | grep '^port ' | awk '{print $2}' || echo 22)

if ! iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport "$SSH_PORT" -j ACCEPT
    echo "SSH-доступ (${SSH_PORT}) разрешён"
fi

iptables -t filter -N "$CHAIN" 2>/dev/null || true
iptables -t filter -F "$CHAIN"

if ! iptables -t filter -C INPUT -j "$CHAIN" 2>/dev/null; then
    iptables -t filter -I INPUT 2 -j "$CHAIN"
    echo "Цепочка $CHAIN подключена к INPUT"
fi

# ── 1. iOS — проверка TTL+Length, ACCEPT БЕЗ ЛИМИТА ────────
iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
    -m tcp --tcp-flags SYN SYN \
    -m length --length 64 \
    -m ttl --ttl-lt 65 \
    -j ACCEPT

# ── 2. ВТОРОЙ СЛОЙ — все остальные (Android/Desktop) → hashlimit 54/мин ──
iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
    -m hashlimit \
    --hashlimit-name mtproto_"$PORT" \
    --hashlimit-mode srcip \
    --hashlimit-upto 54/minute \
    --hashlimit-burst 1 \
    --hashlimit-htable-expire 60000 \
    --hashlimit-htable-size 32768 \
    -j ACCEPT

# ── 3. REJECT ────────────────────────
iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
    -j REJECT --reject-with tcp-reset

#обратно в INPUT
iptables -t filter -A "$CHAIN" -j RETURN

APPLY_SCRIPT_EOF
    else
        # Новый вариант (по умолчанию) — iOS ACCEPT без лимита
        cat >/opt/mtpr-simple/apply-mtpr-synfix.sh <<'APPLY_SCRIPT_EOF'
#!/bin/bash
set -e

PORT="${PORT:-$(cat /opt/mtpr-simple/port 2>/dev/null)}"

if [ -z "$PORT" ]; then
    echo "SYN FIX: Порт не указан, выход" >&2
    exit 1
fi

CHAIN="MTPR_SYNFIX"

SSH_PORT=$(sshd -T 2>/dev/null | grep '^port ' | awk '{print $2}' || echo 22)

if ! iptables -C INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT 1 -p tcp --dport "$SSH_PORT" -j ACCEPT
    echo "SSH-доступ (${SSH_PORT}) разрешён"
fi

iptables -t filter -N "$CHAIN" 2>/dev/null || true
iptables -t filter -F "$CHAIN"

if ! iptables -t filter -C INPUT -j "$CHAIN" 2>/dev/null; then
    iptables -t filter -I INPUT 2 -j "$CHAIN"
    echo "Цепочка $CHAIN подключена к INPUT"
fi

# ── 1. Маркировка iOS в mangle ──────────────────────────────
iptables -t mangle -A PREROUTING -m u32 --u32 "32 & 0x00FFFFFF = 0x0002FFFF && 40 & 0xFF000000 = 0x02000000 && 44 & 0xFFFF0000 = 0x01030000 && 48 & 0xFFFFFF00 = 0x01010800 && 60 & 0xFFFFFFFF = 0x04020000" -j MARK --set-mark 0x400

# ── 2. ACCEPT для маркированных iOS (БЕЗ ЛИМИТА) ─────────────
iptables -t filter -A "$CHAIN" -m mark --mark 0x400 -j ACCEPT

# ── 3. ВТОРОЙ СЛОЙ — все остальные (Android/Desktop) → hashlimit 54/мин ──
iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
    -m hashlimit \
    --hashlimit-name mtproto_"$PORT" \
    --hashlimit-mode srcip \
    --hashlimit-upto 54/minute \
    --hashlimit-burst 1 \
    --hashlimit-htable-expire 60000 \
    --hashlimit-htable-size 32768 \
    -j ACCEPT

# ── 4. REJECT ────────────────────────
iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
    -j REJECT --reject-with tcp-reset

#обратно в INPUT
iptables -t filter -A "$CHAIN" -j RETURN

APPLY_SCRIPT_EOF
    fi

    chmod +x /opt/mtpr-simple/apply-mtpr-synfix.sh
}

# ── Генерация systemd юнита ────────────────────────────────────
generate_service_unit() {
    cat >/etc/systemd/system/mtpr-synfix.service <<'SERVICE_UNIT_EOF'
[Unit]
Description=MTProto SYN FIX rules for Telemt
After=docker.service ufw.service network.target
Wants=docker.service ufw.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/mtpr-simple/apply-mtpr-synfix.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE_UNIT_EOF
    if systemctl daemon-reload 2>/dev/null; then
        log_info "Системный менеджер служб перезапущен"
    fi
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

    if [ -n "$CONFIG_TELEMT" ] && [ -f "$CONFIG_TELEMT" ]; then
        systemctl stop telemt 2>/dev/null || true

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

        systemctl restart telemt 2>/dev/null || true
    else
        log_warning "Файл конфига Telemt не найден или не указан, пропускаем оптимизацию параметров Telemt"
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

# ── Функция проверки установки Telemt ──────────────────────
is_telemt_installed() {
    command -v telemt >/dev/null 2>&1
}

# ── Функция проверки установки MTProtoZig ──────────────────
is_mtprotozig_installed() {
    command -v mtbuddy >/dev/null 2>&1
}

# ── Функция получения версии Telemt ─────────────────────────
get_telemt_version() {
    if command -v telemt >/dev/null 2>&1; then
        telemt --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# ── Функция получения онлайна Telemt ────────────────────────
get_telemt_online() {
    if is_telemt_installed; then
        curl -s http://127.0.0.1:9091/v1/stats/users/active-ips 2>/dev/null | grep -o '"active_ips":\[[^]]*\]' | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | wc -l | tr -d ' '
    else
        echo ""
    fi
}

# ── Функция получения онлайна MTProtoZig ────────────────────
get_mtprotozig_online() {
    if is_mtprotozig_installed; then
        sudo journalctl -u mtproto-proxy -n 50 2>/dev/null | grep -o 'users_total=[0-9]*' | tail -1 | cut -d'=' -f2
    else
        echo ""
    fi
}

# ── Функция получения количества уникальных IP ─────────────
get_online_count() {
    local port="443"
    if [ -n "$CONFIG_TELEMT" ] && [ -f "$CONFIG_TELEMT" ]; then
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
    echo -e "  ${BOLD}MTProto Fixer by MEKO v1.06${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""

    # Обновляем порт из конфига при каждом показе меню
    if [ -n "$CONFIG_TELEMT" ] && [ -f "$CONFIG_TELEMT" ] && pgrep -x telemt >/dev/null 2>&1; then
        local current_port=$(grep -E '^port[[:space:]]*=' "$CONFIG_TELEMT" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        if [[ "$current_port" =~ ^[0-9]+$ ]]; then
            save_port "$current_port"
        else
            # Если порт не определён, но Telemt работает — пробуем определить через ss
            local detected_port=$(ss -tlnp 2>/dev/null | grep telemt | grep -oP ':\K[0-9]+' | head -1)
            if [[ -n "$detected_port" ]]; then
                save_port "$detected_port"
            fi
        fi
    fi

    # Определяем статус SYN FIX (проверка статуса сервиса)
    local synfix_status=$(get_synfix_status)
    if [ "$synfix_status" = "active" ]; then
        echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен${NC}"
    elif [ "$synfix_status" = "has_chain_only" ]; then
        echo -e "  ${BOLD}SYN FIX:${NC} ${YELLOW}Цепочка есть, сервис не запущен${NC}"
    else
        echo -e "  ${BOLD}SYN FIX:${NC} ${RED}${BOLD}Не установлен${NC}"
    fi

    # Проверяем установку Telemt и MTProtoZig
    local telemt_installed=false
    local mtprotozig_installed=false
    
    if is_telemt_installed; then
        telemt_installed=true
    fi
    if is_mtprotozig_installed; then
        mtprotozig_installed=true
    fi

    # Формируем статусную строку
    local status_line=""
    if [ "$telemt_installed" = true ] && [ "$mtprotozig_installed" = true ]; then
        status_line="Telemt: ${GREEN}установлен${NC}${BOLD} | Mtproto.zig: ${GREEN}установлен${NC}"
    elif [ "$telemt_installed" = true ]; then
        status_line="Telemt: ${GREEN}установлен${NC}${BOLD} | Mtproto.zig: ${GRAY}не обнаружен${NC}"
    elif [ "$mtprotozig_installed" = true ]; then
        status_line="Telemt: ${GRAY}не обнаружен${NC}${BOLD} | Mtproto.zig: ${GREEN}установлен${NC}"
    else
        status_line="Telemt: ${RED}не обнаружен${NC}${BOLD} | Mtproto.zig: ${RED}не обнаружен${NC}"
    fi
    echo -e "  ${BOLD}${status_line}${NC}"

    # Если установлен Telemt - показываем детали
    if [ "$telemt_installed" = true ]; then
        local port_display=""
        local saved_port=$(get_saved_port)
        
        # Сначала пытаемся получить порт из сохранённого файла
        if [ -n "$saved_port" ] && [[ "$saved_port" =~ ^[0-9]+$ ]]; then
            port_display=" (порт $saved_port)"
        # Если нет — пытаемся получить из конфига
        elif [ -n "$CONFIG_TELEMT" ] && [ -f "$CONFIG_TELEMT" ]; then
            local port=$(grep -E '^port[[:space:]]*=' "$CONFIG_TELEMT" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                port_display=" (порт $port)"
                save_port "$port"
            else
                port_display="${NC}${BOLD} (порт не определён)"
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
        local online_count=$(get_telemt_online)

        echo -e "  ${BOLD}Telemt:${NC} ${GREEN}Установлен${NC}${port_display}"
        echo -e "  ${BOLD}Версия Telemt:${NC} $version_display"
        echo -e "  ${BOLD}Подключено к прокси Telemt:${NC} ${CYAN}$online_count${NC} человек"

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
        echo -e "  ${BOLD}Встроенный MSS:${NC} $mss_status  |  ${BOLD}Встроенный synlimit:${NC} $synlimit_status"
    fi

    # Если установлен MTProtoZig - показываем онлайн
    if [ "$mtprotozig_installed" = true ]; then
        local online_count=$(get_mtprotozig_online)
        if [ -n "$online_count" ] && [ "$online_count" -ge 0 ] 2>/dev/null; then
            echo -e "  ${BOLD}Подключено к прокси Mtproto.zig:${NC} ${CYAN}$online_count${NC} человек"
        else
            echo -e "  ${BOLD}Подключено к прокси Mtproto.zig:${NC} ${CYAN}0${NC} человек"
        fi
    fi

    echo ""
}

# ── Функция для открытия подменю прокси ─────────────────────
open_proxy_menu() {
    local PROXY_MENU_SCRIPT="/opt/mtpr-simple/proxys/proxymenu.sh"
    if [ -f "$PROXY_MENU_SCRIPT" ]; then
        exec "$PROXY_MENU_SCRIPT"
    else
        log_error "Файл $PROXY_MENU_SCRIPT не найден"
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
    fi
}

# ── Главное меню ─────────────────────────────────────────────
main_menu() {
    # Проверяем аргумент -auto_install
    local auto_install=false
    if [[ "$1" == "-auto_install" ]]; then
        auto_install=true
        local forced_port="$2"
        echo -e "  ${BLUE}[i]${NC} Запуск в режиме авто-установки SYN FIX..."
        install_syn_fix -auto_install "$forced_port"
        echo ""
        read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
    fi

    while true; do
        # Проверка наличия файла iptables с нашими правилами
        local show_iptables_rules=false
        if [ -f /etc/iptables/rules.v4 ]; then
            if grep -q "MTPR_SYNFIX" /etc/iptables/rules.v4 2>/dev/null; then
                show_iptables_rules=true
            fi
        fi
        
        show_header
        echo ""

        local synfix_status=$(get_synfix_status)
        if [ "$synfix_status" = "inactive" ]; then
            local item1="${GREEN}${BOLD}Установить SYN FIX${NC}"
        elif [ "$synfix_status" = "has_chain_only" ]; then
            local item1="${CYAN}Перезапустить сервис${NC}"
        else
            local item1="${RED}${BOLD}Удалить SYN FIX${NC}"
        fi

        # Проверяем статус для пункта 2
        if are_bad_options_enabled; then
            local item2="${CYAN}Отключить встроенные MSS и synlimit${NC}"
        else
            local item2="${GRAY}Отключить встроенные MSS и synlimit (уже отключены)${NC}"
        fi

        echo -e "  ${CYAN}[1]${NC}  $item1"
        echo -e "  ${CYAN}[2]${NC}  $item2"
        echo -e "  ${CYAN}[3]${NC}  ${GREEN}${BOLD}Выполнить базовую оптимизацию${NC}"
        echo -e "  ${CYAN}[4]${NC}  ${RED}${BOLD}Полное удаление MEKOpr${NC}"
        echo -e "  ${CYAN}[5]${NC}  ${NC}${BOLD}Проверить наличие обновлений и обновить скрипт${NC}"
        echo -e "  ${CYAN}[6]${NC}  ${NC}${BOLD}Меню прокси и конфигов - установка, обновление, настройка, удаление${NC}"
        
        if [ "$show_iptables_rules" = true ]; then
            echo -e "  ${RED}[7]${NC}  Удалить правила iptables-persistent"
        fi
        
        echo -e "  ${CYAN}[0]${NC}  Выход"
        echo ""
        echo -en "  ${BOLD}Выбор:${NC} "
        local choice
        read -r choice

        case "$choice" in
        1)
            echo ""
            local synfix_status=$(get_synfix_status)

            if [ "$synfix_status" = "inactive" ]; then
                if ! install_syn_fix; then
                    continue
                fi
            elif [ "$synfix_status" = "has_chain_only" ]; then
                log_info "Цепочка SYN FIX найдена, но сервис не запущен. Перезапустить сервис?"
                echo -en "  ${BOLD}Перезапустить? [Y/n]:${NC} "
                local confirm
                read -r confirm
                if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
                    restart_syn_fix_service
                else
                    log_info "Отмена перезапуска"
                fi
            else
                log_info "Обнаружена установленная цепочка SYN FIX ($SYNFIX_CHAIN). Удалить её?"
                echo -en "  ${BOLD}Удалить? [Y/n]:${NC} "
                local confirm
                read -r confirm
                if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
                    remove_syn_fix
                else
                    log_info "Отмена удаления"
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
        5)
            echo ""
            update_script
            ;;
        6)
            open_proxy_menu
            ;;
        7)
            echo ""
            remove_iptables_rules
            echo ""
            read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
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

# ── Обновление скрипта ──────────────────────────────────────────
update_script() {
    local url="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/main.sh"
    local temp="/tmp/$(basename "$0").new.$$"
    local saved_port=""

    # ── Запоминаем текущий порт
    if [ -f "$PORT_FILE" ] && [ -s "$PORT_FILE" ]; then
        saved_port=$(cat "$PORT_FILE")
    fi
    if ! [[ "$saved_port" =~ ^[0-9]+$ ]]; then
        saved_port="443"
    fi

    echo ""
    echo -e "  ${YELLOW}[!]${NC} Удаляем текущую версию..."

    # ── Удаляем старые файлы, но сохраняем порт ──────────────
    remove_syn_fix
    rm -f "$0"

    echo ""
    echo -e "  ${GREEN}[✓]${NC} Скачиваем новую версию main.sh..."
    if curl -fsSL "$url" -o "$temp"; then
        chmod +x "$temp"

        # ── Скачиваем также все файлы из папки proxys ──────────
        echo -e "  ${GREEN}[✓]${NC} Скачиваем файлы прокси-меню..."
        local proxy_files=("proxys/proxymenu.sh" "proxys/telemt1.sh" "proxys/mtprotozig1.sh")
        mkdir -p /opt/mtpr-simple/proxys
        for pfile in "${proxy_files[@]}"; do
            if curl -fsSL "https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main/$pfile" -o "/opt/mtpr-simple/$pfile"; then
                echo -e "    ${GREEN}✓${NC} $(basename "$pfile")"
            else
                echo -e "    ${RED}✗${NC} $(basename "$pfile") — ошибка"
            fi
        done
        chmod +x /opt/mtpr-simple/proxys/*.sh

        if mv "$temp" "$0"; then
            echo -e "  ${GREEN}[✓]${NC} Обновление успешно. Перезапускаемся..."
            sleep 2
            exec "$0" "$@" -auto_install "$saved_port"
        else
            echo -e "  ${RED}[✗]${NC} Не удалось перезаписать файл"
            rm -f "$temp"
            exit 1
        fi
    else
        echo -e "  ${RED}[✗]${NC} Ошибка скачивания main.sh"
        rm -f "$temp"
        echo -e "  ${YELLOW}Продолжить запуск из исходного файла? [Y/n]:${NC} "
        read -r confirm
        if [[ "$confirm" =~ ^[nN]$ ]]; then
            exit 1
        fi
    fi
}

# ── Запуск ────────────────────────────────────────────────────
main_menu "$@"
