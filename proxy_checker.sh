#!/bin/bash

# =============================================
# SNI Checker - проверка TLS и PQ
# Полная копия логики SNI_cheker бота
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

# ── Проверка зависимостей vvv ──────────────────────────────────
check_dependencies() {
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ"
    
    local missing=()
    for cmd in openssl curl nslookup; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo ""
        print_info "Не хватает: ${missing[*]}"
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
        apt install -y "${missing[@]}"
        print_success "Установлено"
    else
        print_success "Все зависимости уже есть"
    fi
    
    # Проверяем версию OpenSSL
    local openssl_ver=$(openssl version | head -1)
    print_info "OpenSSL: $openssl_ver"
    
    return 0
}

# ── Получение IP-адресов (как в боте) ──────────────────────
resolve_ip() {
    local host="$1"
    local ips=""
    
    # Используем getent или nslookup как в боте
    if command -v getent &> /dev/null; then
        ips=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ', ' | sed 's/, $//')
    fi
    
    if [ -z "$ips" ]; then
        ips=$(nslookup "$host" 2>/dev/null | grep -E 'Address: ' | grep -v '#' | awk '{print $2}' | tr '\n' ', ' | sed 's/, $//')
    fi
    
    echo "$ips"
}

# ── Парсинг поля из openssl -brief (как в боте) ──────────
parse_field() {
    local text="$1"
    local key="$2"
    echo "$text" | grep -E "^$key:" | head -1 | sed "s/^$key: //"
}

# ── Запуск openssl (как в боте run_openssl) ────────────────
run_openssl() {
    local args=("$@")
    timeout 10 openssl "${args[@]}" 2>/dev/null || true
}

# ── Запуск openssl full (как в боте run_openssl_full) ──────
run_openssl_full() {
    local args=("$@")
    echo | timeout 10 openssl "${args[@]}" 2>/dev/null || true
}

# ── Извлечение деталей сертификата (как в боте) ────────────
extract_cert_details() {
    local full_output="$1"
    local subject=$(echo "$full_output" | grep -E '^subject=' | head -1 | sed 's/^subject=//')
    local issuer=$(echo "$full_output" | grep -E '^issuer=' | head -1 | sed 's/^issuer=//')
    local not_before=$(echo "$full_output" | grep -E '^Not Before' | head -1 | sed 's/^Not Before: //')
    local not_after=$(echo "$full_output" | grep -E '^Not After' | head -1 | sed 's/^Not After: //')
    
    echo "SUBJECT:$subject"
    echo "ISSUER:$issuer"
    echo "NOT_BEFORE:$not_before"
    echo "NOT_AFTER:$not_after"
}

# ── Форматирование цепочки сертификатов ─────────────────────
format_cert_chain() {
    local output="$1"
    echo "$output" | grep -A 20 "Certificate chain" | head -10
}

# ── Проверка прокси (как в боте check_one) ─────────────────
check_site() {
    local domain="$1"
    local port="${2:-443}"
    local connect="${domain}:${port}"
    local is_ip=false
    
    # Проверяем IP
    if [[ "$domain" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        is_ip=true
    fi
    
    echo -e "\n${BOLD}🔎 ${domain}:${port}${NC}"
    
    # DNS (как в боте)
    local ip_str=$(resolve_ip "$domain")
    if [ -n "$ip_str" ]; then
        echo -e "\n${CYAN}🌐 IP: ${NC}$ip_str"
    fi
    echo ""
    
    # ── 1. PQ-проверка (как в боте) ──────────────────────────
    local pq=$(run_openssl s_client -connect "$connect" -servername "$domain" -groups X25519MLKEM768 -brief)
    
    if echo "$pq" | grep -qi "CONNECTION ESTABLISHED"; then
        local proto=$(parse_field "$pq" "Protocol version")
        local cipher=$(parse_field "$pq" "Ciphersuite")
        local temp=$(parse_field "$pq" "Peer Temp Key")
        local verify=$(parse_field "$pq" "Verification")
        local cert_cn=$(parse_field "$pq" "Peer certificate")
        local sig=$(parse_field "$pq" "Signature type")
        local hash_used=$(parse_field "$pq" "Hash used")
        
        echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
        echo -e "${GREEN}✅ Статус: поддерживается${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$temp" ] && echo "  Peer Temp Key: $temp"
        [ -n "$cert_cn" ] && echo "  Сертификат: $cert_cn"
        [ -n "$sig" ] && echo "  Подпись: $sig"
        [ -n "$hash_used" ] && echo "  Хэш: $hash_used"
        [ -n "$verify" ] && echo "  Верификация: $verify"
        
        # Полный вывод для деталей сертификата
        local full=$(run_openssl_full s_client -connect "$connect" -servername "$domain" -groups X25519MLKEM768)
        local cert_info=$(extract_cert_details "$full")
        
        if [ -n "$cert_info" ]; then
            echo ""
            echo -e "${CYAN}━━━ Сертификат ━━━${NC}"
            echo "$cert_info" | while IFS=: read -r key value; do
                [ -n "$value" ] && echo "  $key: ${value:0:120}"
            done
        fi
        
        echo ""
        echo -e "${GREEN}━━━ ВЕРДИКТ ━━━${NC}"
        echo -e "${GREEN}🟢 Маркер: НЕТ — сервер принимает X25519MLKEM768${NC}"
        return 0
    fi
    
    # PQ не прошёл
    echo -e "${CYAN}━━━ PQ-подключение ━━━${NC}"
    echo -e "${RED}🔸 Статус: не поддерживается${NC}"
    
    local reason=$(echo "$pq" | grep -E "alert|error:" | head -1)
    [ -n "$reason" ] && echo -e "  Причина: ${GRAY}${reason}${NC}"
    echo ""
    
    # ── 2. Обычный TLS (как в боте) ──────────────────────────
    local std=$(run_openssl s_client -connect "$connect" -servername "$domain" -brief)
    
    if echo "$std" | grep -qi "CONNECTION ESTABLISHED"; then
        local proto=$(parse_field "$std" "Protocol version")
        local cipher=$(parse_field "$std" "Ciphersuite")
        local cert_cn=$(parse_field "$std" "Peer certificate")
        local sig=$(parse_field "$std" "Signature type")
        local verify=$(parse_field "$std" "Verification")
        local temp=$(parse_field "$std" "Peer Temp Key")
        local hash_used=$(parse_field "$std" "Hash used")
        
        echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
        echo -e "${GREEN}🔹 Статус: OK${NC}"
        [ -n "$proto" ] && echo "  Протокол: $proto"
        [ -n "$cipher" ] && echo "  Шифронабор: $cipher"
        [ -n "$temp" ] && echo "  Peer Temp Key: $temp"
        [ -n "$cert_cn" ] && echo "  Сертификат: $cert_cn"
        [ -n "$sig" ] && echo "  Подпись: $sig"
        [ -n "$hash_used" ] && echo "  Хэш: $hash_used"
        [ -n "$verify" ] && echo "  Верификация: $verify"
        
        # Полный вывод для деталей сертификата
        local full=$(run_openssl_full s_client -connect "$connect" -servername "$domain")
        local cert_info=$(extract_cert_details "$full")
        
        if [ -n "$cert_info" ]; then
            echo ""
            echo -e "${CYAN}━━━ Сертификат ━━━${NC}"
            echo "$cert_info" | while IFS=: read -r key value; do
                [ -n "$value" ] && echo "  $key: ${value:0:120}"
            done
        fi
        
        echo ""
        # ── Вердикт (как в боте) ──────────────────────────────
        if echo "$temp" | grep -qi "^X25519"; then
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
        echo -e "${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
        if echo "$std" | grep -qi "TIMEOUT"; then
            echo -e "${YELLOW}⏱ Таймаут при обычном TLS-подключении${NC}"
        else
            echo -e "${RED}❌ Обычное TLS тоже не удалось${NC}"
            local err=$(echo "$std" | grep -E "error:|alert" | head -1)
            [ -n "$err" ] && echo -e "  ${GRAY}${err}${NC}"
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

# ── Очистка экрана ──────────────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# ── Главная ──────────────────────────────────────────────────
main() {
    if [ $# -gt 0 ]; then
        check_dependencies >/dev/null 2>&1
        parse_and_check "$1"
        exit 0
    fi
    
    clear_screen
    echo ""
    echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА TLS И PQ-БЕЗОПАСНОСТЬ${NC}"
    echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
    echo ""
    
    check_dependencies || return 0
    
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
