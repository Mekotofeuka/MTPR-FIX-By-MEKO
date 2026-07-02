#!/bin/bash

# =============================================
# SNI Checker - проверка TLS и PQ
# По мотивам SNI_cheker бота
# =============================================

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
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ vav"
    
    if ! command -v cc &> /dev/null; then
        echo ""
        print_info "Для работы необходимо установить:"
        echo ""
        echo -e "  ${BOLD}• build-essential${NC} — компилятор"
        echo -e "  ${BOLD}• openssl${NC} — для TLS"
        echo -e "  ${BOLD}• curl${NC} — для HTTP"
        echo -e "  ${BOLD}• dnsutils${NC} — для nslookup"
        echo ""
        echo -en "  ${BOLD}Установить?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
        read -r deps_confirm
        
        if [[ -n "$deps_confirm" && "$deps_confirm" =~ ^[nN]$ ]]; then
            echo ""
            print_info "Возврат..."
            sleep 0.5
            return 1
        fi
        
        apt update -qq 2>/dev/null || true
        apt install -y build-essential openssl curl dnsutils
        print_success "Установлено"
    else
        local missing=()
        for cmd in openssl curl nslookup; do
            if ! command -v $cmd &> /dev/null; then
                missing+=($cmd)
            fi
        done
        if [ ${#missing[@]} -ne 0 ]; then
            echo ""
            print_info "Не хватает: ${missing[*]}"
            echo -en "  ${BOLD}Установить?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
            read -r deps_confirm
            if [[ -n "$deps_confirm" && "$deps_confirm" =~ ^[nN]$ ]]; then
                echo ""
                print_info "Возврат..."
                sleep 0.5
                return 1
            fi
            apt update -qq 2>/dev/null || true
            apt install -y "${missing[@]}"
            print_success "Установлено"
        else
            print_success "Все зависимости уже есть"
        fi
    fi
    return 0
}

# ── Проверка Rust и pqfetch ──────────────────────────────
install_pqfetch() {
    local need_rust=false
    local need_pqfetch=false
    
    if [ ! -f "$HOME/.cargo/bin/rustc" ] && ! command -v rustc &> /dev/null; then
        need_rust=true
    fi
    
    if [ ! -f "$HOME/.cargo/bin/pqfetch" ] && ! command -v pqfetch &> /dev/null; then
        need_pqfetch=true
    fi
    
    [ "$need_rust" = false ] && [ "$need_pqfetch" = false ] && return 0
    
    echo ""
    print_info "Для PQ-проверки нужны:"
    echo ""
    echo -e "  ${BOLD}1. Rust${NC} — язык"
    echo -e "  ${BOLD}2. pqfetch${NC} — PQ-утилита"
    echo ""
    echo -en "  ${BOLD}Установить?${NC} ${GREEN}[Enter/Y - да, N - нет]:${NC} "
    read -r install_confirm
    
    if [[ -n "$install_confirm" && "$install_confirm" =~ ^[nN]$ ]]; then
        echo ""
        print_info "Возврат..."
        sleep 0.5
        return 1
    fi
    
    print_header "УСТАНОВКА RUST И PQFECTH"
    
    if [ "$need_rust" = true ]; then
        print_info "Устанавливаю Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        export PATH="$HOME/.cargo/bin:$PATH"
        print_success "Rust установлен"
    fi
    
    if [ "$need_pqfetch" = true ]; then
        print_info "Устанавливаю pqfetch..."
        export PATH="$HOME/.cargo/bin:$PATH"
        cargo install pqfetch
        print_success "pqfetch установлен"
    fi
    
    export PATH="$HOME/.cargo/bin:$PATH"
    return 0
}

# ── Получение IP ─────────────────────────────────────────
resolve_ip() {
    local host="$1"
    nslookup "$host" 2>/dev/null | grep -E 'Address: ' | grep -v '#' | awk '{print $2}' | tr '\n' ', ' | sed 's/, $//'
}

# ── Парсинг поля из openssl -brief ──────────────────────
parse_field() {
    local text="$1"
    local key="$2"
    echo "$text" | grep -E "^$key:" | head -1 | sed "s/^$key: //"
}

# ── Проверка ─────────────────────────────────────────────
check_site() {
    local domain="$1"
    local port="${2:-443}"
    local connect="${domain}:${port}"
    local is_ip=false
    local sni=""
    
    # Проверяем IP
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_ip=true
        # Пробуем определить SNI
        local cert=$(echo | timeout 5 openssl s_client -connect "$connect" 2>/dev/null 2>&1 | openssl x509 -noout -subject 2>/dev/null)
        if [ -n "$cert" ]; then
            sni=$(echo "$cert" | sed -n 's/.*CN=\([^,]*\).*/\1/p' | head -1)
            [ -n "$sni" ] && sni="${sni#\*.}"
        fi
        if [ -n "$sni" ]; then
            echo -e "\n${CYAN}🔍 SNI определён: ${sni}${NC}"
        fi
    fi
    
    echo -e "\n${BOLD}🔎 ${domain}:${port}${NC}"
    
    if [ "$is_ip" = false ]; then
        local ip_str=$(resolve_ip "$domain")
        [ -n "$ip_str" ] && echo -e "\n${CYAN}🌐 IP: ${NC}$ip_str"
    fi
    echo ""
    
    # ── 1. PQ-проверка ──────────────────────────────────────
    echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
    
    local pq_sni="$domain"
    [ "$is_ip" = true ] && [ -n "$sni" ] && pq_sni="$sni"
    
    local pq_output=""
    
    # Пробуем через openssl с -groups
    if command -v openssl &> /dev/null; then
        pq_output=$(echo | timeout 10 openssl s_client -connect "$connect" -servername "$pq_sni" -groups X25519MLKEM768 -brief 2>/dev/null || true)
    fi
    
    # Если openssl не дал результат или не поддерживает -groups — пробуем pqfetch
    if [ -z "$pq_output" ] || ! echo "$pq_output" | grep -qi "CONNECTION ESTABLISHED"; then
        if command -v pqfetch &> /dev/null; then
            export PATH="$HOME/.cargo/bin:$PATH"
            pq_output=$(pqfetch "$pq_sni" 2>&1 || true)
        fi
    fi
    
    if echo "$pq_output" | grep -qi "X25519MLKEM768"; then
        local proto=$(parse_field "$pq_output" "Protocol version")
        local cipher=$(parse_field "$pq_output" "Ciphersuite")
        local temp=$(parse_field "$pq_output" "Peer Temp Key")
        local cert=$(parse_field "$pq_output" "Peer certificate")
        local sig=$(parse_field "$pq_output" "Signature type")
        local hash=$(parse_field "$pq_output" "Hash used")
        
        echo -e "${GREEN}✅ Статус: поддерживается${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$temp" ] && echo "  Peer Temp Key: $temp"
        [ -n "$cert" ] && echo "  Сертификат: $cert"
        [ -n "$sig" ] && echo "  Подпись: $sig"
        [ -n "$hash" ] && echo "  Хэш: $hash"
        echo ""
        echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${GREEN}🟢 Маркер: НЕТ — сервер принимает X25519MLKEM768${NC}"
        return 0
    fi
    
    # PQ не прошёл
    echo -e "${RED}🔸 Статус: не поддерживается${NC}"
    
    local reason=$(echo "$pq_output" | grep -E "alert|error:|invalid" | head -1)
    [ -n "$reason" ] && echo -e "  Причина: ${GRAY}${reason}${NC}"
    echo ""
    
    # ── 2. Обычный TLS ──────────────────────────────────────
    echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
    
    local tls_sni="$domain"
    [ "$is_ip" = true ] && [ -n "$sni" ] && tls_sni="$sni"
    
    local tls_output=""
    if command -v openssl &> /dev/null; then
        tls_output=$(echo | timeout 10 openssl s_client -connect "$connect" -servername "$tls_sni" -brief 2>/dev/null || true)
    fi
    
    if [ -n "$tls_output" ] && echo "$tls_output" | grep -qi "CONNECTION ESTABLISHED"; then
        local proto=$(parse_field "$tls_output" "Protocol version")
        local cipher=$(parse_field "$tls_output" "Ciphersuite")
        local temp=$(parse_field "$tls_output" "Peer Temp Key")
        local cert=$(parse_field "$tls_output" "Peer certificate")
        local sig=$(parse_field "$tls_output" "Signature type")
        local hash=$(parse_field "$tls_output" "Hash used")
        
        echo -e "${GREEN}🔹 Статус: OK${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$temp" ] && echo "  Peer Temp Key: $temp"
        [ -n "$cert" ] && echo "  Сертификат: $cert"
        [ -n "$sig" ] && echo "  Подпись: $sig"
        [ -n "$hash" ] && echo "  Хэш: $hash"
        echo ""
        
        # ── Вердикт ──────────────────────────────────────────
        if echo "$temp" | grep -qi "X25519"; then
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
        local curl_out=$(timeout 10 curl -vI --tlsv1.3 --connect-timeout 5 "https://$connect" 2>&1 | grep -E "SSL connection|TLS|subject" | head -5 || true)
        
        if [ -n "$curl_out" ]; then
            echo -e "${GREEN}🔹 Статус: OK${NC}"
            echo "$curl_out"
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

# ── Парсинг ввода ─────────────────────────────────────────
parse_and_check() {
    local input="$1"
    local domain=""
    local port="443"
    local secret=""
    
    if echo "$input" | grep -qi "t.me/proxy\|tg://proxy"; then
        domain=$(echo "$input" | grep -oP 'server=\K[^&]+' 2>/dev/null || echo "")
        port=$(echo "$input" | grep -oP 'port=\K[^&]+' 2>/dev/null || echo "443")
        secret=$(echo "$input" | grep -oP 'secret=\K[^&]+' 2>/dev/null || echo "")
        
        if [ -z "$domain" ]; then
            print_error "Не удалось извлечь server из ссылки"
            return 1
        fi
        
        echo -e "\n${CYAN}━━━ РАСПАРСЕНО ━━━${NC}"
        echo -e "  ${BOLD}Сервер:${NC} $domain"
        echo -e "  ${BOLD}Порт:${NC} $port"
        [ -n "$secret" ] && echo -e "  ${BOLD}Секрет:${NC} ${secret:0:20}..."
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

# ── Очистка ──────────────────────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# ── Главная ──────────────────────────────────────────────────
main() {
    # Если передан аргумент — просто проверяем и выходим
    if [ $# -gt 0 ]; then
        check_dependencies >/dev/null 2>&1
        install_pqfetch >/dev/null 2>&1
        parse_and_check "$1"
        exit 0
    fi
    
    clear_screen
    echo ""
    echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА TLS И PQ-БЕЗОПАСНОСТЬ${NC}"
    echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
    echo ""
    
    check_dependencies || return 0
    install_pqfetch || return 0
    
    while true; do
        echo ""
        echo -e "  ${BOLD}Введите домен или ссылку для проверки:${NC}"
        echo -e "  ${DIM}Примеры:${NC}"
        echo -e "  ${DIM}  • tg://proxy?server=212.8.229.241&port=443&secret=...${NC}"
        echo -e "  ${DIM}  • 212.8.229.241:443${NC}"
        echo -e "  ${DIM}  • rutube.ru${NC}"
        echo -e "  ${DIM}  • 0, n или q — выход${NC}"
        echo ""
        echo -en "  ${BOLD}Ввод:${NC} "
        read -r proxy_input
        
        if [[ "$proxy_input" == "0" || "$proxy_input" =~ ^[nN]$ || "$proxy_input" =~ ^[qQ]$ ]]; then
            echo ""
            print_info "Возврат..."
            sleep 0.5
            return 0
        fi
        
        if [ -z "$proxy_input" ]; then
            print_warning "Введите что-нибудь"
            continue
        fi
        
        parse_and_check "$proxy_input"
        
        echo ""
        echo -e "  ${GRAY}Нажмите Enter или 0 для выхода...${NC}"
        read -r continue_choice
        if [[ "$continue_choice" == "0" || "$continue_choice" =~ ^[nN]$ || "$continue_choice" =~ ^[qQ]$ ]]; then
            echo ""
            print_info "Возврат..."
            sleep 0.5
            return 0
        fi
        
        clear_screen
        echo ""
        echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА TLS И PQ-БЕЗОПАСНОСТЬ${NC}"
        echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
        echo ""
    done
}

main "$@"
