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

# ── Функции для работы с TOML ──────────────
_toml_get_value() {
    local _key="$1" _file="$2"
    [ -f "$_file" ] || return 0
    awk -v k="$_key" '
        /^[[:space:]]*#/ { next }
        $1 == k && $2 == "=" { gsub(/[^0-9]/, "", $3); print $3; exit }
    ' "$_file" 2>/dev/null
}

_toml_has_section() {
    local _section="$1" _file="$2"
    grep -qE "^\\[${_section}\\]" "$_file" 2>/dev/null
}

_toml_has_key() {
    local _key="$1" _file="$2"
    grep -qE "^${_key}[[:space:]]*=" "$_file" 2>/dev/null
}

_is_excluded_path() {
    local _path="$1"
    case "$_path" in
        *telemt-panel*|*telemt_panel*) return 0 ;;
    esac
    return 1
}

_looks_like_telemt_config() {
    local _file="$1"
    [ -f "$_file" ] || return 1
    grep -qE '^\[access\.users\]|^\[censorship\]|^\[general\.modes\]|^tls_domain[[:space:]]*=' "$_file" 2>/dev/null
}

# ── Функция проверки установки Telemt (сначала версия) ──────
is_telemt_installed() {
    command -v telemt >/dev/null 2>&1
}

get_telemt_version() {
    if command -v telemt >/dev/null 2>&1; then
        telemt --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# ── Расширенное обнаружение Telemt ──────────
detect_telemt_advanced() {
    local DETECTED_CONFIG_PATH=""
    local DETECTED_PORT=""
    
    # 1. Локальный процесс telemt
    if pgrep -x telemt &>/dev/null || systemctl is-active telemt.service &>/dev/null 2>&1; then
        local _args
        _args=$(ps -eo args 2>/dev/null | grep '[t]elemt' | grep -v 'telemt-panel' | grep -v 'telemt_panel' | head -1 | grep -oE '/[^ ]+\.toml' | head -1)
        if [ -n "$_args" ] && [ -f "$_args" ] && ! _is_excluded_path "$_args" && _looks_like_telemt_config "$_args"; then
            DETECTED_CONFIG_PATH="$_args"
        fi
    fi
    
    # 2. Поиск конфига в стандартных местах
    if [ -z "$DETECTED_CONFIG_PATH" ]; then
        local _cf
        for _cf in /etc/telemt/telemt.toml /etc/telemt/config.toml /etc/telemt.toml /opt/telemt/config.toml /opt/telemt/telemt.toml; do
            if [ -f "$_cf" ] && ! _is_excluded_path "$_cf" && _looks_like_telemt_config "$_cf"; then
                DETECTED_CONFIG_PATH="$_cf"
                break
            fi
        done
    fi
    
    # 3. Проверяем сохранённый путь
    if [ -z "$DETECTED_CONFIG_PATH" ] && [ -f "$CONFIG_PATH_FILE" ] && [ -s "$CONFIG_PATH_FILE" ]; then
        local _saved_path=$(cat "$CONFIG_PATH_FILE")
        if [ "$_saved_path" != "skip" ] && [ -f "$_saved_path" ] && _looks_like_telemt_config "$_saved_path"; then
            DETECTED_CONFIG_PATH="$_saved_path"
        fi
    fi
    
    # 4. Получаем порт из конфига
    if [ -n "$DETECTED_CONFIG_PATH" ] && [ -f "$DETECTED_CONFIG_PATH" ]; then
        DETECTED_PORT=$(_toml_get_value "port" "$DETECTED_CONFIG_PATH")
    fi
    
    echo "$DETECTED_CONFIG_PATH:$DETECTED_PORT"
}

# ── Проверяем, сохранён ли путь к конфигу ──────────────────
if [ -f "$CONFIG_PATH_FILE" ] && [ -s "$CONFIG_PATH_FILE" ]; then
    CONFIG_TELEMT=$(cat "$CONFIG_PATH_FILE")
    if [ "$CONFIG_TELEMT" = "skip" ]; then
        CONFIG_TELEMT=""
    fi
else
    # Определяем, установлен ли Telemt
    TELEMT_VERSION=$(get_telemt_version)
    
    echo ""
    echo -e "  ${NC}${BOLD}Укажите путь к конфигу Telemt${NC}"
    echo -e "  ${NC}${BOLD}По умолчанию: ${GREEN}${BOLD}[/etc/telemt/telemt.toml]${NC}"
    
    if [ -n "$TELEMT_VERSION" ]; then
        # Telemt найден — ищем конфиг
        _detected_info=$(detect_telemt_advanced)
        _detected_path="${_detected_info%:*}"
        _detected_port="${_detected_info#*:}"
        
        if [ -n "$_detected_path" ] && [ -f "$_detected_path" ]; then
            echo -e "  ${NC}${BOLD}Телемт найден по пути: ${GREEN}${BOLD}${_detected_path}${NC}"
            echo -e "  ${NC}${BOLD}Если путь определён верно — нажмите ${GREEN}${BOLD}Enter${NC}"
        else
            echo -e "  ${NC}${BOLD}Телемт найден (версия ${TELEMT_VERSION}), но конфиг не обнаружен.${NC}"
            echo -e "  ${NC}${BOLD}Если путь определён верно — нажмите ${GREEN}${BOLD}Enter${NC}"
        fi
    else
        echo -e "  ${NC}${BOLD}Телемт не найден.${NC}"
        echo -e "  ${NC}${BOLD}Если Telemt не установлен - нажмите ${GREEN}${BOLD}Enter${NC}"
    fi
    
    echo ""
    echo -en "  ${BOLD}Ввод:${NC} "
    read -r CONFIG_TELEMT_INPUT

    if [[ "$CONFIG_TELEMT_INPUT" =~ ^[Nn]$ ]]; then
        mkdir -p /opt/mtpr-simple
        echo "skip" > "$CONFIG_PATH_FILE"
        CONFIG_TELEMT=""
    else
        if [ -z "$CONFIG_TELEMT_INPUT" ]; then
            # Если Enter — пробуем определить автоматически
            _detected_info=$(detect_telemt_advanced)
            _detected_path="${_detected_info%:*}"
            
            if [ -n "$_detected_path" ] && [ -f "$_detected_path" ]; then
                CONFIG_TELEMT_INPUT="$_detected_path"
            else
                # Если Telemt не найден и Enter — делаем skip
                if [ -z "$TELEMT_VERSION" ]; then
                    log_info "Telemt не найден, пропускаем настройку конфига"
                    mkdir -p /opt/mtpr-simple
                    echo "skip" > "$CONFIG_PATH_FILE"
                    CONFIG_TELEMT=""
                else
                    CONFIG_TELEMT_INPUT="/etc/telemt/telemt.toml"
                fi
            fi
        fi

        # Если CONFIG_TELEMT_INPUT не пустой, пробуем сохранить
        if [ -n "$CONFIG_TELEMT_INPUT" ]; then
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

            mkdir -p /opt/mtpr-simple
            echo "$CONFIG_TELEMT_INPUT" > "$CONFIG_PATH_FILE"
            CONFIG_TELEMT="$CONFIG_TELEMT_INPUT"
        fi
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

# ── Функция получения порта Telemt ──────────────────────────
get_telemt_port() {
    local config_path="$1"
    if [ -z "$config_path" ] || [ ! -f "$config_path" ]; then
        echo ""
        return 1
    fi
    _toml_get_value "port" "$config_path"
}

# ── Название кастомной цепочки iptables ─────────────────────
SYNFIX_CHAIN="MTPR_SYNFIX"

# ── ПРОВЕРКА НАЛИЧИЯ ЦЕПОЧКИ IPTABLES SYN FIX ────────────────
is_syn_fix_chain_installed() {
    iptables -L "$SYNFIX_CHAIN" -n >/dev/null 2>&1
}

is_syn_fix_service_running() {
    systemctl is-active --quiet mtpr-synfix.service
}

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

is_our_syn_fix_installed() {
    is_syn_fix_chain_installed
}

# ── ПРОВЕРКА MSS, MSS_BULK И SYN_LIMIT В КОНФИГЕ TELEMT ────
is_mss_enabled() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        return 1
    fi
    if grep -E '^[[:space:]]*client_mss[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        return 0
    fi
    return 1
}

is_mss_bulk_enabled() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        return 1
    fi
    if grep -E '^[[:space:]]*mss_bulk[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        return 0
    fi
    return 1
}

is_synlimit_enabled() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        return 1
    fi
    if grep -E '^[[:space:]]*synlimit[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        return 0
    fi
    return 1
}

are_mss_options_enabled() {
    if is_mss_enabled || is_mss_bulk_enabled; then
        return 0
    else
        return 1
    fi
}

are_bad_options_enabled() {
    if is_mss_enabled || is_mss_bulk_enabled || is_synlimit_enabled; then
        return 0
    else
        return 1
    fi
}

# ── ВКЛЮЧЕНИЕ MSS И MSS_BULK ───────────────────────────────
enable_mss_options() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        log_error "Файл конфига не найден или не указан"
        return 1
    fi

    local changed=0
    local mss_value="92"
    local mss_bulk_value="1200"

    # Проверяем наличие строк (даже закомментированных)
    local has_mss=$(grep -E '^[[:space:]]*#?[[:space:]]*client_mss[[:space:]]*=' "$CONFIG_TELEMT" | head -1)
    local has_mss_bulk=$(grep -E '^[[:space:]]*#?[[:space:]]*mss_bulk[[:space:]]*=' "$CONFIG_TELEMT" | head -1)

    # Раскомментируем и обновляем client_mss
    if [ -n "$has_mss" ]; then
        sed -i 's/^[[:space:]]*#[[:space:]]*client_mss[[:space:]]*=.*/client_mss = '"$mss_value"'/' "$CONFIG_TELEMT"
        changed=1
    else
        # Добавляем в секцию server
        if grep -q '^\[server\]' "$CONFIG_TELEMT"; then
            sed -i '/^\[server\]/a client_mss = '"$mss_value"'' "$CONFIG_TELEMT"
            changed=1
        else
            echo "" >> "$CONFIG_TELEMT"
            echo "[server]" >> "$CONFIG_TELEMT"
            echo "client_mss = $mss_value" >> "$CONFIG_TELEMT"
            changed=1
        fi
    fi

    # Раскомментируем и обновляем mss_bulk
    if [ -n "$has_mss_bulk" ]; then
        sed -i 's/^[[:space:]]*#[[:space:]]*mss_bulk[[:space:]]*=.*/mss_bulk = '"$mss_bulk_value"'/' "$CONFIG_TELEMT"
        changed=1
    else
        # Добавляем в секцию server
        if grep -q '^\[server\]' "$CONFIG_TELEMT"; then
            sed -i '/^\[server\]/a mss_bulk = '"$mss_bulk_value"'' "$CONFIG_TELEMT"
            changed=1
        else
            if ! grep -q '^\[server\]' "$CONFIG_TELEMT"; then
                echo "" >> "$CONFIG_TELEMT"
                echo "[server]" >> "$CONFIG_TELEMT"
            fi
            echo "mss_bulk = $mss_bulk_value" >> "$CONFIG_TELEMT"
            changed=1
        fi
    fi

    if [ "$changed" -eq 1 ]; then
        log_success "MSS (client_mss = $mss_value) и mss_bulk = $mss_bulk_value добавлены в конфиг"
        
        # Спрашиваем о перезапуске
        echo ""
        echo -en "  ${BOLD}${NC}Перезапустить telemt для применения изменений?${NC} ${GREEN}${BOLD}[Enter/Y - да, N - нет]:${NC} "
        local restart_confirm
        read -r restart_confirm
        
        if [[ -z "$restart_confirm" || "$restart_confirm" =~ ^[yY]$ ]]; then
            if systemctl restart telemt 2>/dev/null; then
                log_success "Telemt успешно перезапущен"
            else
                log_warning "Не удалось перезапустить telemt (возможно, он не установлен как служба)"
            fi
        else
            log_info "Перезапуск отменён. Изменения применятся после перезапуска telemt"
        fi
    else
        log_info "Не удалось добавить параметры client_mss и mss_bulk"
    fi
}

# ── ОТКЛЮЧЕНИЕ MSS, MSS_BULK И SYN_LIMIT ───────────────────
disable_bad_options() {
    if [ -z "$CONFIG_TELEMT" ] || [ ! -f "$CONFIG_TELEMT" ]; then
        log_error "Файл конфига не найден или не указан"
        return 1
    fi

    local changed=0

    if grep -E '^[[:space:]]*client_mss[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        sed -i 's/^[[:space:]]*client_mss[[:space:]]*=.*/#client_mss = 0/' "$CONFIG_TELEMT"
        changed=1
    fi

    if grep -E '^[[:space:]]*mss_bulk[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        sed -i 's/^[[:space:]]*mss_bulk[[:space:]]*=.*/#mss_bulk = 0/' "$CONFIG_TELEMT"
        changed=1
    fi

    if grep -E '^[[:space:]]*synlimit[[:space:]]*=' "$CONFIG_TELEMT" | grep -v '^#' | grep -q .; then
        sed -i 's/^[[:space:]]*synlimit[[:space:]]*=.*/#synlimit = 0/' "$CONFIG_TELEMT"
        changed=1
    fi

    if [ "$changed" -eq 1 ]; then
        log_success "MSS, mss_bulk и synlimit отключены (строки закомментированы)"
    else
        log_info "Активные строки client_mss, mss_bulk или synlimit не найдены"
    fi
}

# ── УСТАНОВКА SYN FIX ──────────────────────────────────────
install_syn_fix() {
    local ports_input
    local fix_choice
    local auto_install=false
    local forced_ports=""
    local FIX_TYPE="new"

    if [[ "$1" == "-auto_install" ]]; then
        auto_install=true
        forced_ports="$2"
        FIX_TYPE="new"
    fi

    ssh_port=$(get_ssh_port)

    if [ "$auto_install" = true ]; then
        if [[ -n "$forced_ports" ]]; then
            ports_input="$forced_ports"
            log_info "Используем порты, переданные аргументом: $ports_input"
        else
            log_info "Порты не переданы, используем 443"
            ports_input="443"
        fi
    else
        echo ""
        echo -en "  ${BOLD}Введите порты для SYN FIX (через запятую, например: 443,8443,8080):${NC} "
        read -r ports_input
        if [ -z "$ports_input" ]; then
            ports_input="443"
        fi

        echo ""
        echo -e "  ${BOLD}Выберите тип SYN FIX:${NC}"
        echo -e "  ${GREEN}[1]${NC}  ${BOLD}Новый вариант${NC} (u32 + ACCEPT без лимита) — ${GREEN}рекомендуется${NC}"
        echo -e "  ${CYAN}[2]${NC}  ${BOLD}Старый вариант${NC} (TTL+Length + ACCEPT без лимита)"
        echo ""
        echo -en "  ${NC}${BOLD}Ввод (Новый - ${GREEN}${BOLD}1 или enter${NC}${BOLD}, старый - ${RED}${BOLD}2${NC}${BOLD}):${NC} "
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

    # Парсим порты
    IFS=',' read -ra PORTS_ARRAY <<< "$ports_input"
    local valid_ports=()
    for p in "${PORTS_ARRAY[@]}"; do
        p=$(echo "$p" | xargs)
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
            valid_ports+=("$p")
        else
            log_warning "Некорректный порт '$p' пропущен"
        fi
    done

    if [ ${#valid_ports[@]} -eq 0 ]; then
        log_error "Нет корректных портов для установки"
        return 1
    fi

    local ports_str=$(IFS=,; echo "${valid_ports[*]}")
    log_info "Установка SYN FIX на порты: $ports_str"
    save_port "$ports_str"

    if [ "$auto_install" = false ]; then
        echo ""
        log_warning "Будет выполнена установка SYN FIX на порты: $ports_str"
        echo ""
        echo -e "  ${BOLD}Что будет сделано:${NC}"
        echo -e "  • Создана отдельная цепочка iptables ${CYAN}$SYNFIX_CHAIN${NC}"
        echo -e "  • Добавлены правила SYN-фильтрации для портов: ${CYAN}$ports_str${NC}"
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

    generate_apply_script "$FIX_TYPE" "${valid_ports[@]}"
    generate_service_unit
    systemctl daemon-reload
    PORT="$ports_str" /opt/mtpr-simple/apply-mtpr-synfix.sh
    systemctl enable mtpr-synfix.service
    systemctl restart mtpr-synfix.service

    log_success "SYN FIX успешно установлен на порты: $ports_str"
}

# ── Удаление правил из файла iptables ──────────────────────
remove_iptables_rules() {
    local rules_file="/etc/iptables/rules.v4"
    
    if [ ! -f "$rules_file" ]; then
        log_warning "Файл $rules_file не найден"
        return 1
    fi
    
    log_info "Проверка наличия наших правил в $rules_file..."
    
    if ! grep -q "MTPR_SYNFIX" "$rules_file"; then
        log_warning "Наши правила (MTPR_SYNFIX) не найдены в файле"
        return 1
    fi
    
    echo ""
    echo -e "  ${BOLD}Обнаружены наши правила SYN FIX в файле${NC}"
    echo -e "  ${DIM}Что будет сделано:${NC}"
    echo -e "  • Будут удалены только строки с цепочкой $SYNFIX_CHAIN"
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
    
    local temp_file=$(mktemp)
    grep -v "MTPR_SYNFIX" "$rules_file" > "$temp_file"
    mv "$temp_file" "$rules_file"
    chmod 644 "$rules_file"
    
    log_success "Правила $SYNFIX_CHAIN удалены из $rules_file"
}

# ── Удаление SYN FIX ────────────────────────────────────────
remove_syn_fix() {
    log_info "Удаление SYN FIX..."

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
    rm -f /etc/systemd/system/mtpr-synfix.service
    systemctl daemon-reload

    log_success "SYN FIX удалён"
}

restart_syn_fix_service() {
    log_info "Перезапуск сервиса mtpr-synfix.service..."
    systemctl restart mtpr-synfix.service
    log_success "Сервис успешно перезапущен"
}

# ── Генерация скрипта применения правил ──────────────────────────
generate_apply_script() {
    local fix_type="${1:-new}"
    shift
    local ports=("$@")

    if [ "$fix_type" = "old" ]; then
        cat >/opt/mtpr-simple/apply-mtpr-synfix.sh <<'APPLY_SCRIPT_EOF'
#!/bin/bash
set -e

# ── Парсим порты из файла ──────────────────────────────────
if [ -f /opt/mtpr-simple/port ]; then
    PORTS=$(cat /opt/mtpr-simple/port)
else
    echo "SYN FIX: Файл с портами не найден" >&2
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

# ── Проходим по каждому порту ──────────────────────────────
IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
for PORT in "${PORT_ARRAY[@]}"; do
    PORT=$(echo "$PORT" | xargs)
    [ -z "$PORT" ] && continue

    # ── iOS — проверка TTL+Length, ACCEPT БЕЗ ЛИМИТА ────────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
        -m tcp --tcp-flags SYN SYN \
        -m length --length 64 \
        -m ttl --ttl-lt 65 \
        -j ACCEPT

    # ── ВТОРОЙ СЛОЙ — все остальные → hashlimit 54/мин ──────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
        -m hashlimit \
        --hashlimit-name mtproto_"$PORT" \
        --hashlimit-mode srcip \
        --hashlimit-upto 54/minute \
        --hashlimit-burst 1 \
        --hashlimit-htable-expire 60000 \
        --hashlimit-htable-size 32768 \
        -j ACCEPT

    # ── REJECT для всех остальных ────────────────────────────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
        -j REJECT --reject-with tcp-reset
done

# обратно в INPUT
iptables -t filter -A "$CHAIN" -j RETURN

APPLY_SCRIPT_EOF
    else
        # Новый вариант (u32 + ACCEPT без лимита)
        cat >/opt/mtpr-simple/apply-mtpr-synfix.sh <<'APPLY_SCRIPT_EOF'
#!/bin/bash
set -e

# ── Парсим порты из файла ──────────────────────────────────
if [ -f /opt/mtpr-simple/port ]; then
    PORTS=$(cat /opt/mtpr-simple/port)
else
    echo "SYN FIX: Файл с портами не найден" >&2
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

# ── Проходим по каждому порту ──────────────────────────────
IFS=',' read -ra PORT_ARRAY <<< "$PORTS"
for PORT in "${PORT_ARRAY[@]}"; do
    PORT=$(echo "$PORT" | xargs)
    [ -z "$PORT" ] && continue

    # ── ACCEPT для маркированных iOS (БЕЗ ЛИМИТА) ─────────────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn -m mark --mark 0x400 -j ACCEPT

    # ── ВТОРОЙ СЛОЙ — все остальные → hashlimit 54/мин ──────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
        -m hashlimit \
        --hashlimit-name mtproto_"$PORT" \
        --hashlimit-mode srcip \
        --hashlimit-upto 54/minute \
        --hashlimit-burst 1 \
        --hashlimit-htable-expire 60000 \
        --hashlimit-htable-size 32768 \
        -j ACCEPT

    # ── REJECT для всех остальных ────────────────────────────
    iptables -t filter -A "$CHAIN" -p tcp --dport "$PORT" --syn \
        -j REJECT --reject-with tcp-reset
done

# обратно в INPUT
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

# ── Пункт 2: Управление MSS, mss_bulk и synlimit ──────────
apply_optimization() {
    if are_bad_options_enabled; then
        echo ""
        log_info "Обнаружены активные строки с client_mss, mss_bulk или synlimit в $CONFIG_TELEMT"
        echo -en "  ${BOLD}${NC}Отключить mss, mss_bulk и synlimit в cfg telemt? [Y/n]:${NC} "
        local confirm
        read -r confirm
        if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
            disable_bad_options
        else
            log_info "Отмена"
        fi
    else
        echo ""
        log_info "client_mss, mss_bulk и synlimit уже отключены или отсутствуют в конфиге"
        echo -en "  ${BOLD}]:${NC}Включить mss и mss_bulk в конфиге telemt? [Y/n]:${NC} "
        local confirm
        read -r confirm
        if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
            enable_mss_options
        else
            log_info "Отмена"
        fi
    fi
    echo ""
    read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
}

# ── Пункт 3: Базовая оптимизация ───────────────────────────
apply_basic_optimization() {
    echo ""
    log_info "Выполнение базовой оптимизации системы и Telemt..."

    if [ -n "$CONFIG_TELEMT" ] && [ -f "$CONFIG_TELEMT" ]; then
        systemctl stop telemt 2>/dev/null || true

        if grep -q '^max_connections *=.*' "$CONFIG_TELEMT"; then
            if ! grep -q '^max_connections *= *16384' "$CONFIG_TELEMT"; then
                sed -i 's/^max_connections *= *.*/max_connections = 16384/' "$CONFIG_TELEMT"
            fi
        else
            grep -q '\[server\]' "$CONFIG_TELEMT" && sed -i '/\[server\]/a max_connections = 16384' "$CONFIG_TELEMT"
        fi

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

    mkdir -p /etc/systemd/system/telemt.service.d

    if ! grep -q "LimitNOFILE=65535" /etc/systemd/system/telemt.service.d/limits.conf 2>/dev/null; then
        cat >/etc/systemd/system/telemt.service.d/limits.conf <<EOF
[Service]
LimitNOFILE=65535
EOF
    fi

    systemctl daemon-reload

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

    remove_syn_fix

    log_info "Удаление файлов конфигурации..."
    rm -rf /opt/mtpr-simple

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

is_mtprotozig_installed() {
    command -v mtbuddy >/dev/null 2>&1
}

get_telemt_version() {
    if command -v telemt >/dev/null 2>&1; then
        telemt --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

get_telemt_online() {
    if is_telemt_installed; then
        curl -s http://127.0.0.1:9091/v1/stats/users/active-ips 2>/dev/null | grep -o '"active_ips":\[[^]]*\]' | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | wc -l | tr -d ' '
    else
        echo ""
    fi
}

get_mtprotozig_online() {
    if is_mtprotozig_installed; then
        sudo journalctl -u mtproto-proxy -n 50 2>/dev/null | grep -o 'users_total=[0-9]*' | tail -1 | cut -d'=' -f2
    else
        echo ""
    fi
}

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
    echo -e "  ${BOLD}MTProto Fixer by MEKO v1.31${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""

    # ── ОПРЕДЕЛЯЕМ ПОРТ КАЖДЫЙ РАЗ ──────────────────────────
    local current_port=""
    local config_path=""
    
    # Проверяем, есть ли сохранённый путь
    if [ -f "$CONFIG_PATH_FILE" ] && [ -s "$CONFIG_PATH_FILE" ]; then
        config_path=$(cat "$CONFIG_PATH_FILE")
        if [ "$config_path" = "skip" ]; then
            config_path=""
        fi
    fi
    
    # Если сохранённого пути нет, используем тот что в CONFIG_TELEMT
    if [ -z "$config_path" ] && [ -n "$CONFIG_TELEMT" ] && [ "$CONFIG_TELEMT" != "skip" ]; then
        config_path="$CONFIG_TELEMT"
    fi
    
    # Если есть путь и файл существует — берём порт из него
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        current_port=$(grep -E '^port[[:space:]]*=' "$config_path" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        if [[ "$current_port" =~ ^[0-9]+$ ]]; then
            save_port "$current_port"
        fi
    fi
    
    # Если порт не определился через конфиг — пробуем через detect_telemt_advanced
    if [ -z "$current_port" ] || ! [[ "$current_port" =~ ^[0-9]+$ ]]; then
        local detected_info=$(detect_telemt_advanced)
        local detected_path="${detected_info%:*}"
        local detected_port="${detected_info#*:}"
        
        if [ -n "$detected_port" ] && [[ "$detected_port" =~ ^[0-9]+$ ]]; then
            current_port="$detected_port"
            save_port "$current_port"
            # Если нашелся конфиг через detect, обновляем CONFIG_TELEMT
            if [ -n "$detected_path" ] && [ -f "$detected_path" ]; then
                CONFIG_TELEMT="$detected_path"
                mkdir -p /opt/mtpr-simple
                echo "$detected_path" > "$CONFIG_PATH_FILE"
            fi
        fi
    fi
    
    # Если всё ещё нет порта — пробуем через ss
    if [ -z "$current_port" ] || ! [[ "$current_port" =~ ^[0-9]+$ ]]; then
        local detected_port=$(ss -tlnp 2>/dev/null | grep telemt | grep -oP ':\K[0-9]+' | head -1)
        if [[ -n "$detected_port" ]] && [[ "$detected_port" =~ ^[0-9]+$ ]]; then
            current_port="$detected_port"
            save_port "$current_port"
        fi
    fi

    local synfix_status=$(get_synfix_status)
    if [ "$synfix_status" = "active" ]; then
        echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен${NC}"
    elif [ "$synfix_status" = "has_chain_only" ]; then
        echo -e "  ${BOLD}SYN FIX:${NC} ${YELLOW}Цепочка есть, сервис не запущен${NC}"
    else
        echo -e "  ${BOLD}SYN FIX:${NC} ${RED}${BOLD}Не установлен${NC}"
    fi

    local telemt_installed=false
    local mtprotozig_installed=false
    
    if is_telemt_installed; then
        telemt_installed=true
    fi
    if is_mtprotozig_installed; then
        mtprotozig_installed=true
    fi

    # ── ФОРМИРУЕМ СТРОКУ СТАТУСА ─────────────────────────────
    local status_line=""
    
    if [ "$telemt_installed" = true ] && [ "$mtprotozig_installed" = true ]; then
        # Оба установлены
        local telemt_version=$(get_telemt_version)
        local port_display=""
        if [ -n "$current_port" ] && [[ "$current_port" =~ ^[0-9]+$ ]]; then
            port_display=" Port: ${current_port}"
        fi
        status_line="Telemt V: ${GREEN}${telemt_version}${NC}${BOLD}${port_display}  |  Mtproto.zig: ${GREEN}установлен${NC}"
    elif [ "$telemt_installed" = true ]; then
        # Только Telemt
        local telemt_version=$(get_telemt_version)
        local port_display=""
        if [ -n "$current_port" ] && [[ "$current_port" =~ ^[0-9]+$ ]]; then
            port_display=" Port: ${current_port}"
        fi
        status_line="Telemt V: ${GREEN}${telemt_version}${NC}${port_display}"
    elif [ "$mtprotozig_installed" = true ]; then
        # Только MTProtoZig
        status_line="Mtproto.zig: ${GREEN}установлен${NC}"
    else
        # Ничего не установлено
        status_line="${RED}Прокси не установлены${NC}"
    fi
    
    echo -e "  ${BOLD}${status_line}${NC}"

    # ── ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ ДЛЯ TELEMT ────────────────
    if [ "$telemt_installed" = true ]; then
        local online_count=$(get_telemt_online)
        echo -e "  ${BOLD}Подключено к прокси Telemt:${NC} ${CYAN}$online_count${NC}${BOLD} человек"

        local mss_status=""
        local mss_bulk_status=""
        local synlimit_status=""
        
        if is_mss_enabled; then
            mss_status="${RED}включен${NC}"
        else
            mss_status="${GREEN}отключен${NC}"
        fi
        
        if is_mss_bulk_enabled; then
            mss_bulk_status="${RED}включен${NC}"
        else
            mss_bulk_status="${GREEN}отключен${NC}"
        fi
        
        if is_synlimit_enabled; then
            synlimit_status="${RED}включен${NC}"
        else
            synlimit_status="${GREEN}отключен${NC}"
        fi
        
        echo -e "  ${BOLD}Встроенный MSS:${NC} $mss_status  |  ${BOLD}MSS_BULK:${NC} $mss_bulk_status  |  ${BOLD}Synlimit:${NC} $synlimit_status"
    fi

    # ── ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ ДЛЯ MTPROTOZIG ────────────
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


# ── Функция проверки статуса базовой оптимизации ──────────
is_optimization_applied() {
    local applied=0
    local check_count=0
    
    # Проверяем sysctl параметры (3 ключевых)
    if [ -f /etc/sysctl.d/99-custom.conf ]; then
        # Проверяем tcp_congestion_control (BBR)
        local current_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [ "$current_congestion" = "bbr" ]; then
            check_count=$((check_count + 1))
        fi
        
        # Проверяем default_qdisc (fq)
        local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        if [ "$current_qdisc" = "fq" ]; then
            check_count=$((check_count + 1))
        fi
        
        # Проверяем tcp_fastopen
        local current_fastopen=$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)
        if [ "$current_fastopen" = "3" ]; then
            check_count=$((check_count + 1))
        fi
    fi
    
    # Если хотя бы 2 из 3 параметров совпадают — считаем оптимизацию применённой
    if [ "$check_count" -ge 2 ]; then
        applied=1
    fi
    
    return $applied
}

# ── Функция открытия меню прокси ──────────────────────────
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

# ── Функция проверки ограничений сервера ──────────────────
check_censor() {
    echo ""
    log_info "Проверка ограничений на сервере..."
    echo ""
    wget -qO- censorcheck.tlab.pw | bash
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Главное меню ─────────────────────────────────────────────
main_menu() {
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

        if are_bad_options_enabled; then
            local item2="${GREEN}${BOLD}Отключить mss, mss_bulk и synlimit в конфиге telemt${NC}"
        else
            local item2="${NC}${BOLD}Включить mss и mss_bulk в конфиге telemt${RED} (не рекомендуется)"
        fi

        if is_optimization_applied; then
            local item3_text="${GRAY}${BOLD}Выполнить базовую оптимизацию (уже применена)${NC}"
        else
            local item3_text="${GREEN}${BOLD}Выполнить базовую оптимизацию${NC}"
        fi

        echo -e "  ${CYAN}[1]${NC}  $item1"
        echo -e "  ${CYAN}[2]${NC}  $item3_text"
        echo -e "  ${CYAN}[3]${NC}  ${NC}${BOLD}Меню прокси и кфг${NC}"
        echo -e "  ${CYAN}[4]${NC}  ${NC}${BOLD}Обновить скрипт${NC}"
        echo -e "  ${CYAN}[5]${NC}  $item2"
        echo -e "  ${CYAN}[6]${NC}  ${NC}${BOLD}Проверить ограничения на сервере${NC}"
        echo -e "  ${CYAN}[7]${NC}  ${RED}${BOLD}Полное удаление MEKOpr${NC}"
        
        if [ "$show_iptables_rules" = true ]; then
            echo -e "  ${RED}[8]${NC}  Удалить правила iptables-persistent"
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
            apply_basic_optimization
            echo ""
            read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
            ;;
        3)
            open_proxy_menu
            ;;
        4)
            echo ""
            update_script
            ;;
        5)
            echo ""
            apply_optimization
            echo ""
            read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
            ;;
        6)
            check_censor
            ;;
        7)
            remove_mekopr
            ;;
        8)
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

    if [ -f "$PORT_FILE" ] && [ -s "$PORT_FILE" ]; then
        saved_port=$(cat "$PORT_FILE")
    fi
    if ! [[ "$saved_port" =~ ^[0-9]+$ ]]; then
        saved_port="443"
    fi

    echo ""
    echo -e "  ${YELLOW}[!]${NC} Удаляем текущую версию..."
    remove_syn_fix
    rm -f "$0"

    echo ""
    echo -e "  ${GREEN}[✓]${NC} Скачиваем новую версию main.sh..."
    if curl -fsSL "$url" -o "$temp"; then
        chmod +x "$temp"

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
