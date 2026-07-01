#!/bin/bash
# telemt1.sh

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

# ── Файл для сохранения пути к конфигу (используем общий с main.sh) ──
CONFIG_PATH_FILE="/opt/mtpr-simple/config_path"

# ── Функция получения текущего пути к конфигу ──────────────
get_config_path() {
    if [ -f "$CONFIG_PATH_FILE" ] && [ -s "$CONFIG_PATH_FILE" ]; then
        path=$(cat "$CONFIG_PATH_FILE")
        if [ "$path" != "skip" ]; then
            echo "$path"
            return 0
        fi
    fi
    echo "/etc/telemt/telemt.toml"
    return 0
}

# ── Функции для работы с TOML ──────────────────────────────
_toml_get_value() {
    local _key="$1" _file="$2"
    [ -f "$_file" ] || return 0
    awk -v k="$_key" '
        /^[[:space:]]*#/ { next }
        $1 == k && $2 == "=" { gsub(/[^0-9]/, "", $3); print $3; exit }
    ' "$_file" 2>/dev/null
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

# ── Расширенное обнаружение Telemt ──────────
detect_telemt_advanced() {
    local DETECTED_CONFIG_PATH=""
    local DETECTED_PORT=""
    local DETECTED_IP=""
    local DETECTED_PUBLIC_HOST=""
    local DETECTED_CLASSIC=""
    local DETECTED_SECURE=""
    local DETECTED_TLS=""
    local DETECTED_TLS_DOMAIN=""
    local DETECTED_SECRET=""
    
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
    
    # 4. Получаем параметры из конфига
    if [ -n "$DETECTED_CONFIG_PATH" ] && [ -f "$DETECTED_CONFIG_PATH" ]; then
        DETECTED_PORT=$(_toml_get_value "port" "$DETECTED_CONFIG_PATH")
        DETECTED_IP=$(grep -E '^ip[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        DETECTED_PUBLIC_HOST=$(grep -E '^public_host[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        DETECTED_TLS_DOMAIN=$(grep -E '^tls_domain[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        DETECTED_SECRET=$(grep -E '^[[:space:]]*[^#]*[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | grep -v '^#' | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        
        # Проверяем режимы
        DETECTED_CLASSIC=$(grep -E '^classic[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | grep -v '^#' | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        DETECTED_SECURE=$(grep -E '^secure[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | grep -v '^#' | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        DETECTED_TLS=$(grep -E '^tls[[:space:]]*=' "$DETECTED_CONFIG_PATH" 2>/dev/null | grep -v '^#' | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    fi
    
    echo "$DETECTED_CONFIG_PATH:$DETECTED_PORT:$DETECTED_IP:$DETECTED_PUBLIC_HOST:$DETECTED_CLASSIC:$DETECTED_SECURE:$DETECTED_TLS:$DETECTED_TLS_DOMAIN:$DETECTED_SECRET"
}

# ── Функция получения публичного IP ──────────────────────────
get_public_ip() {
    local _ip=""
    _ip=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null) ||
    _ip=$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null) ||
    _ip=$(curl -4 -fsS --max-time 5 https://icanhazip.com 2>/dev/null) ||
    _ip=""
    echo "$_ip"
}

# ── Функция формирования ссылок для подключения ─────────────
generate_proxy_links() {
    local config_path=$(get_config_path)
    if [ ! -f "$config_path" ]; then
        return 1
    fi
    
    # Получаем данные из конфига через расширенное обнаружение
    local detected_info=$(detect_telemt_advanced)
    local IFS=':'
    local parts=($detected_info)
    unset IFS
    
    local detected_path="${parts[0]}"
    local detected_port="${parts[1]}"
    local detected_ip="${parts[2]}"
    local detected_public_host="${parts[3]}"
    local detected_classic="${parts[4]}"
    local detected_secure="${parts[5]}"
    local detected_tls="${parts[6]}"
    local detected_tls_domain="${parts[7]}"
    local detected_secret="${parts[8]}"
    
    # Определяем порт
    local port=""
    if [ -n "$detected_port" ]; then
        port="$detected_port"
    else
        port=$(grep -E '^port[[:space:]]*=' "$config_path" 2>/dev/null | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
    fi
    if [ -z "$port" ]; then
        port="443"
    fi
    
    # Определяем сервер (IP или public_host)
    local server=""
    if [ -n "$detected_public_host" ]; then
        server="$detected_public_host"
    elif [ -n "$detected_ip" ]; then
        server="$detected_ip"
    else
        server=$(get_public_ip)
    fi
    if [ -z "$server" ]; then
        server=$(curl -4 -fsS --max-time 3 https://api.ipify.org 2>/dev/null)
    fi
    if [ -z "$server" ]; then
        server="SERVER_IP"
    fi
    
    # Если нет секрета — выходим
    if [ -z "$detected_secret" ]; then
        return 1
    fi
    
    # Определяем какие режимы включены
    local classic_enabled=false
    local secure_enabled=false
    local tls_enabled=false
    
    if [ "$detected_classic" = "true" ]; then
        classic_enabled=true
    fi
    if [ "$detected_secure" = "true" ]; then
        secure_enabled=true
    fi
    if [ "$detected_tls" = "true" ]; then
        tls_enabled=true
    fi
    
    # Если ни один режим не включен явно, но есть tls_domain — считаем что tls включен
    if [ "$classic_enabled" = false ] && [ "$secure_enabled" = false ] && [ "$tls_enabled" = false ]; then
        if [ -n "$detected_tls_domain" ]; then
            tls_enabled=true
        else
            classic_enabled=true
        fi
    fi
    
    local links=""
    
    # TLS режим (ee + secret + hex(tls_domain))
    if [ "$tls_enabled" = true ]; then
        local hex_domain=""
        if [ -n "$detected_tls_domain" ]; then
            hex_domain=$(echo -n "$detected_tls_domain" | xxd -p -c 256 2>/dev/null)
        fi
        local tls_secret="ee${detected_secret}${hex_domain}"
        links="${links}  TLS:\n"
        links="${links}  tg://proxy?server=${server}&port=${port}&secret=${tls_secret}\n"
    fi
    
    # Secure режим (dd + secret)
    if [ "$secure_enabled" = true ]; then
        local secure_secret="dd${detected_secret}"
        links="${links}  Secure (DD):\n"
        links="${links}  tg://proxy?server=${server}&port=${port}&secret=${secure_secret}\n"
    fi
    
    # Classic режим (просто secret)
    if [ "$classic_enabled" = true ]; then
        links="${links}  Classic:\n"
        links="${links}  tg://proxy?server=${server}&port=${port}&secret=${detected_secret}\n"
    fi
    
    echo -e "$links"
}

# ── Функция проверки, установлен ли Telemt ──────────────────
is_telemt_installed() {
    if command -v telemt >/dev/null 2>&1; then
        return 0
    fi
    if systemctl is-active --quiet telemt 2>/dev/null; then
        return 0
    fi
    if pgrep -x telemt >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ── Функция получения версии Telemt ─────────────────────────
get_telemt_version() {
    if command -v telemt >/dev/null 2>&1; then
        telemt --version 2>/dev/null | head -1 | awk '{print $2}'
    else
        echo ""
    fi
}

# ── Функция получения порта(ов) из конфига ──────────────────
get_telemt_ports() {
    local config_path=$(get_config_path)
    if [ ! -f "$config_path" ]; then
        echo ""
        return 1
    fi
    grep -E '^port[[:space:]]*=' "$config_path" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' "'
}

# ── Функция получения онлайна Telemt ────────────────────────
get_telemt_online() {
    if is_telemt_installed; then
        curl -s http://127.0.0.1:9091/v1/stats/users/active-ips 2>/dev/null | grep -o '"active_ips":\[[^]]*\]' | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | wc -l | tr -d ' '
    else
        echo ""
    fi
}

# ── Функция обновления пути к конфигу ──────────────────────
update_config_path() {
    echo ""
    default_path="/etc/telemt/telemt.toml"
    echo -en "Укажите путь к конфигу Telemt (По умолчанию: [${default_path}] если не меняли - нажмите Enter, или [N/n] для возврата в меню): "
    read -r CONFIG_TELEMT_INPUT

    if [[ "$CONFIG_TELEMT_INPUT" =~ ^[Nn]$ ]]; then
        echo ""
        echo -e "  ${GRAY}Возврат в меню...${NC}"
        sleep 0.1
        return 1
    fi

    if [ -z "$CONFIG_TELEMT_INPUT" ]; then
        CONFIG_TELEMT_INPUT="$default_path"
    fi

    if [ ! -f "$CONFIG_TELEMT_INPUT" ]; then
        echo -e "  ${YELLOW}[!]${NC} Файл $CONFIG_TELEMT_INPUT не найден."
        echo -en "  ${BOLD}Сохранить этот путь всё равно? [y/N]:${NC} "
        confirm_path=""
        read -r confirm_path
        if [[ ! "$confirm_path" =~ ^[yY]$ ]]; then
            echo -e "  ${GRAY}Возврат в меню...${NC}"
            sleep 0.1
            return 1
        fi
    fi

    mkdir -p /opt/mtpr-simple
    echo "$CONFIG_TELEMT_INPUT" > "$CONFIG_PATH_FILE"
    echo -e "  ${GREEN}[✓]${NC} Путь сохранён: $CONFIG_TELEMT_INPUT"
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
    return 0
}

# ── Функция просмотра логов ──────────────────────────────────
view_logs() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Просмотр логов Telemt (Ctrl+C для выхода)..."
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
    read -rsn1
    journalctl -u telemt -f
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция установки Telemt ────────────────────────────────
install_telemt() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Установка Telemt"
    echo ""
    echo -e "  ${NC}${BOLD}Выберите какую версию TELEMT вы хотите установить:${NC}"
    echo -e "  ${GREEN}[Enter]${NC}${BOLD} — установить самую последнюю версию"
    echo -e "  ${NC}${BOLD}Либо введите любую версию в формате: ${GREEN}3.4.18"
    echo -e "  ${RED}[N/n]${NC}${BOLD} — назад"
    echo ""
    echo -en "  ${NC}${BOLD}Ввод:${NC} "
    read -r version_input

    if [[ "$version_input" =~ ^[Nn]$ ]]; then
        echo ""
        echo -e "  ${GRAY}Установка отменена${NC}"
        echo ""
        echo -e "  ${GRAY}${BOLD}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
        return 0
    fi

    local install_version="latest"
    local display_version="последнюю"
    
    if [ -n "$version_input" ]; then
        if [[ "$version_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            install_version="$version_input"
            display_version="$version_input"
        else
            echo ""
            echo -e "  ${YELLOW}[!]${NC} Некорректный формат версии. Используйте формат X.Y.Z"
            echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
            read -rsn1
            return 1
        fi
    fi

    echo ""
    echo -e "  ${BLUE}[i]${NC} Установка Telemt версии ${display_version}..."
    echo ""
    
    if [ "$install_version" = "latest" ]; then
        if curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh; then
            echo ""
            echo -e "  ${GREEN}[✓]${NC} Telemt успешно установлен (последняя версия)"
        else
            echo ""
            echo -e "  ${RED}[✗]${NC} Ошибка установки Telemt"
        fi
    else
        if curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh -s -- "$install_version"; then
            echo ""
            echo -e "  ${GREEN}[✓]${NC} Telemt версии ${install_version} успешно установлен"
        else
            echo ""
            echo -e "  ${RED}[✗]${NC} Ошибка установки Telemt версии ${install_version}"
        fi
    fi
    
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция удаления Telemt ──────────────────────────────────
purge_telemt() {
    echo ""
    echo -e "  ${RED}${BOLD}ВНИМАНИЕ:${NC} Будет выполнено полное удаление Telemt!"
    echo ""
    echo -e "  ${BOLD}Будут удалены:${NC}"
    echo -e "  • Все файлы Telemt"
    echo -e "  • Конфигурационные файлы"
    echo -e "  • Systemd служба"
    echo ""
    echo -e "  ${YELLOW}[!]${NC} Это действие нельзя отменить!"
    echo -en "  ${BOLD}Продолжить удаление? [y/N]:${NC} "
    local confirm
    read -r confirm

    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo -e "  ${GRAY}Удаление отменено${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
        return 1
    fi

    echo ""
    echo -e "  ${BLUE}[i]${NC} Удаление Telemt..."
    echo ""
    if curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh -s -- purge; then
        echo ""
        echo -e "  ${GREEN}[✓]${NC} Telemt успешно удалён"
    else
        echo ""
        echo -e "  ${RED}[✗]${NC} Ошибка удаления Telemt"
    fi
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция открытия конфига ────────────────────────────────
edit_config() {
    config_path=$(get_config_path)
    
    if [ ! -f "$config_path" ]; then
        echo ""
        echo -e "  ${YELLOW}[!]${NC} Файл конфига не найден по пути: $config_path"
        echo -e "  ${GRAY}Используйте пункт 4 для обновления пути к конфигу${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
        return 1
    fi
    
    echo ""
    echo -e "  ${BLUE}[i]${NC} Открытие конфига: $config_path"
    
    if command -v nano >/dev/null 2>&1; then
        echo -e "  ${GRAY}После редактирования сохраните файл (Ctrl+O) и закройте (Ctrl+X)${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
        read -rsn1
        nano "$config_path"
    elif command -v vim >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[!]${NC} nano не установлен. Используем vim для открытия файла."
        echo -e "  ${GRAY}Для сохранения: нажмите ESC, затем введите :wq и Enter${NC}"
        echo -e "  ${GRAY}Для выхода без сохранения: ESC, затем :q! и Enter${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
        read -rsn1
        vim "$config_path"
    elif command -v vi >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[!]${NC} Использую vi."
        echo -e "  ${GRAY}Для сохранения: нажмите ESC, затем введите :wq и Enter${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
        read -rsn1
        vi "$config_path"
    else
        echo -e "  ${RED}[✗]${NC} Ни один редактор не найден (nano, vim, vi)"
        echo -e "  ${GRAY}Установите один из редакторов: apt install nano или vim${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
        return 1
    fi
    
    echo ""
    echo -e "  ${GREEN}[✓]${NC} Редактирование завершено"
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция перезапуска Telemt ──────────────────────────────
restart_telemt() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Перезапуск Telemt..."
    echo ""
    if systemctl restart telemt 2>/dev/null; then
        echo -e "  ${GREEN}[✓]${NC} Telemt успешно перезапущен"
    else
        echo -e "  ${YELLOW}[!]${NC} Не удалось перезапустить Telemt (возможно, он не установлен как служба)"
        echo -e "  ${GRAY}Попробуйте сначала установить Telemt (пункт 1)${NC}"
    fi
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Главное меню ─────────────────────────────────────────────
while true; do
    clear
    echo ""
    echo -e "  ${BOLD}Telemt меню v0.51${NC}"
    echo -e "  ${DIM}===========================${NC}"
    
    # Показываем информацию о Telemt, если установлен
    if is_telemt_installed; then
        echo ""
        echo -e "  ${NC}${BOLD}Telemt:${NC}${GREEN} установлен${NC}"
        
        # Версия
        version=$(get_telemt_version)
        if [ -n "$version" ]; then
            echo -e "  ${NC}${BOLD}Версия:${NC} ${GREEN}${version}${NC}"
        fi
        
        # Порт(ы)
        ports=$(get_telemt_ports)
        if [ -n "$ports" ]; then
            port_count=$(echo "$ports" | wc -l)
            if [ "$port_count" -eq 1 ]; then
                echo -e "  ${BOLD}Порт:${NC} ${CYAN}${ports}${NC}"
            else
                echo -e "  ${BOLD}Порты:${NC} ${CYAN}${ports//$'\n'/, }${NC}"
            fi
        fi
        
        # ── ГЕНЕРИРУЕМ ССЫЛКИ ──────────────────────────────────
        links=$(generate_proxy_links)
        if [ -n "$links" ]; then
            echo ""
            echo -e "  ${BOLD}Ссылки для подключения:${NC}"
            echo -e "$links"
        fi
        
        # Онлайн
        online=$(get_telemt_online)
        if [ -n "$online" ] && [ "$online" -ge 0 ] 2>/dev/null; then
            echo -e "  ${NC}${BOLD}Подключено к прокси:${NC} ${CYAN}${BOLD}${online}${NC}${BOLD} человек"
        else
            echo -e "  ${NC}${BOLD}Подключено к прокси:${NC} ${CYAN}${BOLD}0${NC}${BOLD} человек"
        fi
        
        echo ""
    fi
    
    echo -e "  ${CYAN}[1]${NC}  ${BOLD}Установить/обновить/откатить Telemt${NC}"
    echo -e "  ${CYAN}[2]${NC}  ${BOLD}Открыть конфиг Telemt${NC}"
    echo -e "  ${CYAN}[3]${NC}  ${BOLD}Перезапустить Telemt${NC}"
    echo -e "  ${CYAN}[4]${NC}  ${BOLD}Обновить путь к конфигу Telemt${NC}"
    echo -e "  ${CYAN}[5]${NC}  ${BOLD}Посмотреть логи Telemt${NC}"
    echo -e "  ${RED}[6]${NC}  ${BOLD}Удалить Telemt${NC}"
    echo -e "  ${CYAN}[0]${NC}  ${BOLD}Назад в прокси меню${NC}"
    echo ""
    
    if ! is_telemt_installed; then
        echo -e "  ${YELLOW}Telemt не установлен${NC}"
        echo ""
    else
        current_path=$(get_config_path)
        echo -e "  ${DIM}Текущий путь к конфигу: ${current_path}${NC}"
        echo ""
    fi
    
    echo -en "  ${BOLD}Выбор:${NC} "
    read -r choice

    case "$choice" in
        1)
            install_telemt
            ;;
        2)
            edit_config
            ;;
        3)
            restart_telemt
            ;;
        4)
            update_config_path
            ;;
        5)
            view_logs
            ;;
        6)
            purge_telemt
            ;;
        0)
            exec /opt/mtpr-simple/proxys/proxymenu.sh
            ;;
        *)
            echo "  Неверный выбор"
            sleep 0.1
            ;;
    esac
done
