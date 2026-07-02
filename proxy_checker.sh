#!/bin/bash

# =============================================
# PQC Check Script для Ubuntu 24
# Проверка поддержки X25519MLKEM768
# =============================================

set -e

# ── Цвета ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

print_header() {
    echo -e "\n${CYAN}━━━ $1 ━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# ── Проверка зависимостей ──────────────────────────────────
check_dependencies() {
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ v0.8"
    
    if ! command -v cc &> /dev/null; then
        echo ""
        print_info "Для работы необходимо установить следующие компоненты:"
        echo ""
        echo -e "  ${BOLD}• build-essential${NC} — компилятор C/C++"
        echo -e "  ${BOLD}• openssl${NC} — для TLS-подключений"
        echo -e "  ${BOLD}• curl${NC} — для HTTP-запросов"
        echo -e "  ${BOLD}• dnsutils${NC} — для nslookup"
        echo ""
        echo -en "  ${BOLD}Установить зависимости?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
        read -r deps_confirm
        
        if [[ -n "$deps_confirm" && "$deps_confirm" =~ ^[nN]$ ]]; then
            echo ""
            print_info "Возврат в главное меню..."
            sleep 0.5
            return 1
        fi
        
        print_info "Устанавливаю build-essential..."
        apt update -qq 2>/dev/null || true
        apt install -y build-essential openssl curl dnsutils
        print_success "Зависимости установлены"
    else
        local missing=()
        for cmd in openssl curl nslookup; do
            if ! command -v $cmd &> /dev/null; then
                missing+=($cmd)
            fi
        done
        
        if [ ${#missing[@]} -ne 0 ]; then
            echo ""
            print_info "Для работы необходимо установить следующие компоненты:"
            echo ""
            echo -e "  ${BOLD}• ${missing[*]}${NC}"
            echo ""
            echo -en "  ${BOLD}Установить зависимости?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
            read -r deps_confirm
            
            if [[ -n "$deps_confirm" && "$deps_confirm" =~ ^[nN]$ ]]; then
                echo ""
                print_info "Возврат в главное меню..."
                sleep 0.5
                return 1
            fi
            
            print_info "Устанавливаю необходимые пакеты..."
            apt update -qq 2>/dev/null || true
            apt install -y "${missing[@]}"
            print_success "Зависимости установлены"
        else
            print_success "Все зависимости уже установлены"
        fi
    fi
    
    return 0
}

# ── Проверка наличия Rust и pqfetch ────────────────────────
check_rust_pqfetch() {
    if [ -f "$HOME/.cargo/bin/rustc" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        return 0
    fi
    if command -v rustc &> /dev/null; then
        return 0
    fi
    return 1
}

check_pqfetch() {
    if [ -f "$HOME/.cargo/bin/pqfetch" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        return 0
    fi
    if command -v pqfetch &> /dev/null; then
        return 0
    fi
    return 1
}

# ── Установка Rust и pqfetch ──────────────────────────────
install_pqfetch() {
    local need_rust=false
    local need_pqfetch=false
    
    if ! check_rust_pqfetch; then
        need_rust=true
    fi
    
    if ! check_pqfetch; then
        need_pqfetch=true
    fi
    
    if [ "$need_rust" = false ] && [ "$need_pqfetch" = false ]; then
        return 0
    fi
    
    echo ""
    print_info "Для работы необходимо установить следующие компоненты:"
    echo ""
    echo -e "  ${BOLD}1. Rust${NC} — язык программирования"
    echo -e "  ${BOLD}2. pqfetch${NC} — утилита для проверки PQ-шифров"
    echo ""
    echo -en "  ${BOLD}Установить компоненты?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
    read -r install_confirm
    
    if [[ -n "$install_confirm" && "$install_confirm" =~ ^[nN]$ ]]; then
        echo ""
        print_info "Возврат в главное меню..."
        sleep 0.5
        return 1
    fi
    
    print_header "УСТАНОВКА RUST И PQFECTH"
    
    if [ "$need_rust" = true ]; then
        print_info "Устанавливаю Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        export PATH="$HOME/.cargo/bin:$PATH"
        print_success "Rust установлен"
    else
        print_success "Rust уже установлен"
    fi
    
    if [ "$need_pqfetch" = true ]; then
        print_info "Устанавливаю pqfetch..."
        export PATH="$HOME/.cargo/bin:$PATH"
        cargo install pqfetch
        print_success "pqfetch установлен"
    else
        print_success "pqfetch уже установлен"
    fi
    
    export PATH="$HOME/.cargo/bin:$PATH"
    return 0
}

# ── Получение IP-адресов ────────────────────────────────────
resolve_ip() {
    local host="$1"
    nslookup "$host" 2>/dev/null | grep -E 'Address: ' | grep -v '#' | awk '{print $2}' | tr '\n' ', ' | sed 's/, $//'
}

# ── Определение SNI для IP ──────────────────────────────────
get_sni_from_ip() {
    local ip="$1"
    local port="${2:-443}"
    
    # Пробуем подключиться с разными популярными доменами
    # Пробуем сначала просто через openssl без SNI
    local cert_info=$(echo | timeout 5 openssl s_client -connect "$ip:$port" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | sed 's/^.*CN=//' | sed 's/\/.*$//')
    
    if [ -n "$cert_info" ]; then
        echo "$cert_info"
        return 0
    fi
    
    # Если не получилось — пробуем через curl с выводом сертификата
    local curl_cert=$(timeout 5 curl -vI --connect-timeout 3 "https://$ip:$port" 2>&1 | grep -E "subject:" | head -1 | sed 's/.*CN=//' | sed 's/\/.*$//' | tr -d ' ')
    
    if [ -n "$curl_cert" ]; then
        echo "$curl_cert"
        return 0
    fi
    
    return 1
}

# ── Парсинг поля из вывода openssl -brief ──────────────────
parse_field() {
    local text="$1"
    local key="$2"
    echo "$text" | grep -E "^$key:" | head -1 | sed "s/^$key: //"
}

# ── Проверка прокси ────────────────────────────────────────
check_site() {
    local domain="$1"
    local port="${2:-443}"
    local connect="${domain}:${port}"
    local is_ip=false
    local sni=""
    
    # Проверяем, является ли домен IP-адресом
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_ip=true
        sni=$(get_sni_from_ip "$domain" "$port")
        if [ -n "$sni" ]; then
            echo -e "\n${CYAN}🔍 SNI определён: ${sni}${NC}"
        else
            sni="$domain"
        fi
    fi
    
    echo -e "\n${BOLD}🔎 ${domain}:${port}${NC}"
    
    # IP-адреса (для доменов)
    if [ "$is_ip" = false ]; then
        local ip_str=$(resolve_ip "$domain")
        if [ -n "$ip_str" ]; then
            echo -e "\n${CYAN}🌐 IP: ${NC}$ip_str"
        fi
    fi
    echo ""
    
    # ── PQ-проверка через pqfetch ──────────────────────────
    echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Для IP используем SNI (если определён)
    local pq_target="$domain"
    if [ "$is_ip" = true ] && [ -n "$sni" ] && [ "$sni" != "$domain" ]; then
        pq_target="$sni"
    fi
    
    local pq_output=$(pqfetch "$pq_target" 2>&1 || true)
    
    if echo "$pq_output" | grep -qi "X25519MLKEM768"; then
        echo -e "${GREEN}✅ Статус: поддерживается${NC}"
        echo "$pq_output" | head -1 | while read line; do
            if [ -n "$line" ]; then
                echo "  $line"
            fi
        done
        echo ""
        echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${GREEN}🟢 Маркер: НЕТ — сервер принимает X25519MLKEM768${NC}"
        return 0
    fi
    
    # PQ не прошёл
    echo -e "${RED}🔸 Статус: не поддерживается${NC}"
    
    # Показываем причину
    local reason=$(echo "$pq_output" | grep -E "alert|error:|invalid" | head -1)
    if [ -n "$reason" ]; then
        echo -e "  Причина: ${GRAY}${reason}${NC}"
    fi
    echo ""
    
    # ── Обычное TLS через openssl -brief ──────────────────
    echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
    
    local tls_target="$domain"
    local tls_sni="$domain"
    
    # Для IP используем SNI
    if [ "$is_ip" = true ] && [ -n "$sni" ] && [ "$sni" != "$domain" ]; then
        tls_sni="$sni"
    fi
    
    local tls_output=""
    if command -v openssl &> /dev/null; then
        tls_output=$(echo | timeout 5 openssl s_client -connect "$connect" -servername "$tls_sni" -brief 2>/dev/null || true)
    fi
    
    if [ -n "$tls_output" ] && echo "$tls_output" | grep -qi "CONNECTION ESTABLISHED"; then
        local proto=$(parse_field "$tls_output" "Protocol version")
        local cipher=$(parse_field "$tls_output" "Ciphersuite")
        local temp_key=$(parse_field "$tls_output" "Peer Temp Key")
        local cert_cn=$(parse_field "$tls_output" "Peer certificate")
        local sig=$(parse_field "$tls_output" "Signature type")
        local hash_used=$(parse_field "$tls_output" "Hash used")
        
        echo -e "${GREEN}🔹 Статус: OK${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$temp_key" ] && echo "  Peer Temp Key: $temp_key"
        [ -n "$cert_cn" ] && echo "  Сертификат: $cert_cn"
        [ -n "$sig" ] && echo "  Подпись: $sig"
        [ -n "$hash_used" ] && echo "  Хэш: $hash_used"
        echo ""
        
        # ── Вердикт ──────────────────────────────────────────
        if echo "$temp_key" | grep -qi "X25519"; then
            echo -e "${RED}━━━ ВЕРДИКТ ━━━${NC}"
            echo -e "${RED}🔴 МАРКЕР: ДА${NC}"
            echo -e "${RED}PQ не поддерживается + Peer Temp Key = X25519${NC}"
            echo -e "${YELLOW}⚠️ Риск блокировки на ТСПУ для iOS клиентов${NC}"
        else
            echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
            echo -e "${GREEN}🟢 Маркер: НЕТ${NC}"
            echo -e "${GREEN}PQ не поддерживается, но Peer Temp Key не X25519${NC}"
        fi
    else
        # Пробуем через curl
        echo -e "${YELLOW}⚠️ openssl не дал результат, пробую через curl...${NC}"
        local curl_output=$(timeout 5 curl -vI --tlsv1.3 --connect-timeout 3 "https://${connect}" 2>&1 | grep -E "SSL connection|TLS|subject" | head -5 || true)
        
        if [ -n "$curl_output" ]; then
            echo -e "${GREEN}🔹 Статус: OK${NC}"
            echo "$curl_output"
            echo ""
            echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
            echo -e "${GREEN}🟢 Маркер: НЕТ${NC}"
            echo -e "${GREEN}TLS подключение установлено${NC}"
        else
            echo -e "${RED}❌ Не удалось подключиться по TLS${NC}"
            echo ""
            echo -e "${RED}━━━ ВЕРДИКТ ━━━${NC}"
            echo -e "${RED}🔴 Не удалось проверить${NC}"
        fi
    fi
    echo ""
}

# ── Парсинг ввода ───────────────────────────────────────────
parse_and_check() {
    local input="$1"
    local domain=""
    local port="443"
    local secret=""
    
    # Проверяем, является ли входная строка Telegram-ссылкой
    if echo "$input" | grep -qi "t.me/proxy\|tg://proxy"; then
        domain=$(echo "$input" | grep -oP 'server=\K[^&]+' 2>/dev/null || echo "")
        port=$(echo "$input" | grep -oP 'port=\K[^&]+' 2>/dev/null || echo "443")
        secret=$(echo "$input" | grep -oP 'secret=\K[^&]+' 2>/dev/null || echo "")
        
        if [ -z "$domain" ]; then
            print_error "Не удалось извлечь server из ссылки"
            return 1
        fi
        
        echo -e "\n${CYAN}━━━ РАСПАРСЕНО ИЗ ССЫЛКИ ━━━${NC}"
        echo -e "  ${BOLD}Сервер:${NC} $domain"
        echo -e "  ${BOLD}Порт:${NC} $port"
        if [ -n "$secret" ]; then
            echo -e "  ${BOLD}Секрет:${NC} ${secret:0:20}... (обрезано)"
        fi
        echo ""
    else
        domain="$input"
        if echo "$domain" | grep -q ":"; then
            port=$(echo "$domain" | cut -d':' -f2)
            domain=$(echo "$domain" | cut -d':' -f1)
        fi
    fi
    
    check_site "$domain" "$port"
}

# ── Очистка экрана ──────────────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# ── Основная функция ────────────────────────────────────────
main() {
    clear_screen
    echo ""
    echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА ПРОКСИ НА PQ-БЕЗОПАСНОСТЬ${NC}"
    echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! check_dependencies; then
        return 0
    fi
    
    if ! install_pqfetch; then
        return 0
    fi
    
    while true; do
        echo ""
        echo -e "  ${BOLD}Введите ссылку на прокси для проверки:${NC}"
        echo -e "  ${DIM}Примеры:${NC}"
        echo -e "  ${DIM}  • tg://proxy?server=212.8.229.241&port=443&secret=...${NC}"
        echo -e "  ${DIM}  • 212.8.229.241:443${NC}"
        echo -e "  ${DIM}  • rutube.ru${NC}"
        echo -e "  ${DIM}  • 0 (ноль), n или q — выход в главное меню${NC}"
        echo ""
        echo -en "  ${BOLD}Ввод:${NC} "
        read -r proxy_input
        
        if [[ "$proxy_input" == "0" || "$proxy_input" =~ ^[nN]$ || "$proxy_input" =~ ^[qQ]$ ]]; then
            echo ""
            print_info "Возврат в главное меню..."
            sleep 0.5
            return 0
        fi
        
        if [ -z "$proxy_input" ]; then
            print_warning "Вы ничего не ввели. Попробуйте снова или введите 0 для выхода."
            continue
        fi
        
        parse_and_check "$proxy_input"
        
        echo ""
        echo -e "  ${GRAY}Нажмите Enter для продолжения или 0 для выхода...${NC}"
        read -r continue_choice
        if [[ "$continue_choice" == "0" || "$continue_choice" =~ ^[nN]$ || "$continue_choice" =~ ^[qQ]$ ]]; then
            echo ""
            print_info "Возврат в главное меню..."
            sleep 0.5
            return 0
        fi
        
        clear_screen
        echo ""
        echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА ПРОКСИ НА PQ-БЕЗОПАСНОСТЬ${NC}"
        echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
        echo ""
    done
}

# ── Запуск ──────────────────────────────────────────────────
main "$@"
