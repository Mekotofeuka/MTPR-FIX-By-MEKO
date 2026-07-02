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
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ"
    
    if ! command -v cc &> /dev/null; then
        echo ""
        print_info "Для работы необходимо установить:"
        echo ""
        echo -e "  ${BOLD}• build-essential${NC} — компилятор"
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
        apt install -y build-essential curl dnsutils
        print_success "Установлено"
    else
        local missing=()
        for cmd in curl nslookup; do
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

# ── Проверка и установка pqfetch ──────────────────────────
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
    print_info "Для работы нужны:"
    echo ""
    echo -e "  ${BOLD}1. Rust${NC} — язык"
    echo -e "  ${BOLD}2. pqfetch${NC} — утилита для проверки PQ-шифров"
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

# ── Получение IP-адресов ──────────────────────────────────
resolve_ip() {
    local host="$1"
    nslookup "$host" 2>/dev/null | grep -E 'Address: ' | grep -v '#' | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//'
}

# ── Проверка IP через pqfetch ─────────────────────────────
check_ip_pqfetch() {
    local ip="$1"
    local sni="$2"
    local port="${3:-443}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    local result=$(pqfetch "$ip" 2>&1 || true)
    
    # Парсим результат
    local pq_support="no"
    local tls_version=""
    local cipher=""
    local temp_key=""
    local cert=""
    
    if echo "$result" | grep -qi "X25519MLKEM768"; then
        pq_support="yes"
        tls_version=$(echo "$result" | grep -E "tls" | head -1 | awk '{print $2}')
        cipher=$(echo "$result" | grep -E "tls" | head -1 | awk '{print $3}')
    elif echo "$result" | grep -qi "X25519"; then
        pq_support="no"
        temp_key="X25519"
        tls_version=$(echo "$result" | grep -E "tls" | head -1 | awk '{print $2}')
        cipher=$(echo "$result" | grep -E "tls" | head -1 | awk '{print $3}')
    fi
    
    echo "$pq_support|$tls_version|$cipher|$temp_key|$result"
}

# ── Проверка одного IP ─────────────────────────────────────
check_single_ip() {
    local ip="$1"
    local sni="$2"
    local port="${3:-443}"
    
    local result=$(check_ip_pqfetch "$ip" "$sni" "$port")
    local pq_support=$(echo "$result" | cut -d'|' -f1)
    local tls_version=$(echo "$result" | cut -d'|' -f2)
    local cipher=$(echo "$result" | cut -d'|' -f3)
    local temp_key=$(echo "$result" | cut -d'|' -f4)
    
    if [ "$pq_support" = "yes" ]; then
        echo -e "  🟢 $ip — PQ OK"
        [ -n "$tls_version" ] && echo -e "    $tls_version | $cipher"
        return 0
    else
        if echo "$temp_key" | grep -qi "X25519"; then
            echo -e "  🔴 $ip — PQ нет, маркер ДА"
            [ -n "$tls_version" ] && echo -e "    $tls_version | $cipher | $temp_key"
            return 1
        else
            echo -e "  🟡 $ip — PQ нет, но маркер НЕТ"
            [ -n "$tls_version" ] && echo -e "    $tls_version | $cipher"
            return 2
        fi
    fi
}

# ── Проверка домена ────────────────────────────────────────
check_domain() {
    local domain="$1"
    local port="${2:-443}"
    local ip_list=$(resolve_ip "$domain")
    
    echo -e "\n${BOLD}🔎 ${domain}:${port}${NC}"
    
    if [ -n "$ip_list" ]; then
        echo -e "\n${CYAN}🌐 IP: ${NC}$ip_list"
    fi
    
    # Проверяем каждый IP
    echo -e "\n${CYAN}━━━ Короткая проверка по IP ━━━${NC}"
    echo "  SNI: $domain"
    
    local has_marker=false
    local any_ok=false
    local ip_array=($ip_list)
    
    for ip in "${ip_array[@]}"; do
        if [ -n "$ip" ]; then
            check_single_ip "$ip" "$domain" "$port"
            local ret=$?
            if [ $ret -eq 1 ]; then
                has_marker=true
            fi
            if [ $ret -eq 0 ]; then
                any_ok=true
            fi
        fi
    done
    
    if [ "$has_marker" = true ]; then
        echo ""
        echo -e "${YELLOW}⚠️ Один из IP-адресов домена имеет маркер!${NC}"
        echo -e "${YELLOW}Риск блокировки на ТСПУ для iOS клиентов${NC}"
    fi
    
    # ── Основная проверка через pqfetch ─────────────────────
    echo ""
    echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    local pq_result=$(pqfetch "$domain" 2>&1 || true)
    
    if echo "$pq_result" | grep -qi "X25519MLKEM768"; then
        local proto=$(echo "$pq_result" | grep -E "tls" | head -1 | awk '{print $2}')
        local cipher=$(echo "$pq_result" | grep -E "tls" | head -1 | awk '{print $3}')
        local cert=$(echo "$pq_result" | grep -E "cert" | head -1 | sed 's/^.*CN=//' | cut -d' ' -f1)
        
        echo -e "${GREEN}✅ Статус: поддерживается${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$cert" ] && echo "  Сертификат: $cert"
        echo ""
        echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${GREEN}🟢 Маркер: НЕТ — сервер принимает X25519MLKEM768${NC}"
    else
        echo -e "${RED}🔸 Статус: не поддерживается${NC}"
        echo ""
        echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
        
        local curl_out=$(timeout 10 curl -vI --tlsv1.3 --connect-timeout 5 "https://$domain:$port" 2>&1 | grep -E "SSL connection|TLS|subject|Server Temp Key" | head -5 || true)
        
        if [ -n "$curl_out" ]; then
            echo -e "${GREEN}🔹 Статус: OK${NC}"
            echo "$curl_out"
            echo ""
            
            if echo "$curl_out" | grep -qi "X25519"; then
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
            echo -e "${RED}❌ Не удалось подключиться по TLS${NC}"
            echo ""
            echo -e "${RED}━━━ ВЕРДИКТ ━━━${NC}"
            echo -e "${RED}🔴 Не удалось проверить${NC}"
        fi
    fi
    echo ""
}

# ── Проверка IP напрямую ──────────────────────────────────
check_ip_direct() {
    local ip="$1"
    local port="${2:-443}"
    
    echo -e "\n${BOLD}🔎 ${ip}:${port}${NC}"
    echo ""
    
    # ── PQ-проверка через pqfetch ──────────────────────────
    echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
    
    export PATH="$HOME/.cargo/bin:$PATH"
    local pq_result=$(pqfetch "$ip" 2>&1 || true)
    
    if echo "$pq_result" | grep -qi "X25519MLKEM768"; then
        local proto=$(echo "$pq_result" | grep -E "tls" | head -1 | awk '{print $2}')
        local cipher=$(echo "$pq_result" | grep -E "tls" | head -1 | awk '{print $3}')
        local cert=$(echo "$pq_result" | grep -E "cert" | head -1 | sed 's/^.*CN=//' | cut -d' ' -f1)
        
        echo -e "${GREEN}✅ Статус: поддерживается${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$cert" ] && echo "  Сертификат: $cert"
        echo ""
        echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${GREEN}🟢 Маркер: НЕТ — сервер принимает X25519MLKEM768${NC}"
        return 0
    fi
    
    # PQ не прошёл
    echo -e "${RED}🔸 Статус: не поддерживается${NC}"
    echo ""
    
    # ── Обычный TLS через curl ──────────────────────────────
    echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
    
    local curl_out=$(timeout 10 curl -vI --tlsv1.3 --connect-timeout 5 "https://$ip:$port" 2>&1 | grep -E "SSL connection|TLS|subject|Server Temp Key" | head -5 || true)
    
    if [ -n "$curl_out" ]; then
        echo -e "${GREEN}🔹 Статус: OK${NC}"
        echo "$curl_out"
        echo ""
        
        if echo "$curl_out" | grep -qi "X25519"; then
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
        echo -e "${RED}❌ Не удалось подключиться по TLS${NC}"
        echo ""
        echo -e "${RED}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${RED}🔴 Не удалось проверить${NC}"
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
    
    # Определяем, IP это или домен
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        check_ip_direct "$domain" "$port"
    else
        check_domain "$domain" "$port"
    fi
}

# ── Очистка ──────────────────────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# ── Главная ──────────────────────────────────────────────────
main() {
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
