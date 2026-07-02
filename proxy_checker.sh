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
    print_header "ПРОВЕРКА ЗАВИСИМОСТЕЙ v2"
    
    apt update -qq 2>/dev/null || true
    
    # Устанавливаем build-essential если нет
    if ! command -v cc &> /dev/null; then
        print_info "Устанавливаю build-essential..."
        apt install -y build-essential
        print_success "build-essential установлен"
    else
        print_success "build-essential уже установлен"
    fi
    
    local missing=()
    for cmd in openssl curl nslookup; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        print_warning "Отсутствуют: ${missing[*]}"
        print_info "Устанавливаю необходимые пакеты..."
        apt install -y openssl curl dnsutils
        print_success "Зависимости установлены"
    else
        print_success "Все зависимости установлены"
    fi
}

# ── Проверка наличия Rust и pqfetch ────────────────────────
check_rust_pqfetch() {
    # Проверяем Rust через ~/.cargo/bin/rustc
    if [ -f "$HOME/.cargo/bin/rustc" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        return 0
    fi
    
    # Проверяем через which
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
    print_header "УСТАНОВКА RUST И PQFECTH"
    
    local need_rust=false
    local need_pqfetch=false
    
    if ! check_rust_pqfetch; then
        need_rust=true
    fi
    
    if ! check_pqfetch; then
        need_pqfetch=true
    fi
    
    if [ "$need_rust" = false ] && [ "$need_pqfetch" = false ]; then
        print_success "Rust уже установлен"
        print_success "pqfetch уже установлен"
        return 0
    fi
    
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
}

# ── Проверка прокси ────────────────────────────────────────
check_site() {
    local domain="$1"
    local port="${2:-443}"
    
    echo -e "\n${BOLD}🔎 ${domain}:${port}${NC}"
    
    # IP-адреса
    echo -e "\n${CYAN}🌐 IP-адреса:${NC}"
    nslookup $domain 2>/dev/null | grep -E 'Address: ' | grep -v '#' | awk '{print $2}' | head -3 | while read ip; do
        echo "  $ip"
    done
    
    # PQ-проверка
    echo -e "\n${CYAN}━━━ PQ-подключение (X25519MLKEM768) ━━━${NC}"
    export PATH="$HOME/.cargo/bin:$PATH"
    PQFECTH_OUTPUT=$(pqfetch $domain 2>&1 || true)
    
    if echo "$PQFECTH_OUTPUT" | grep -qi "X25519MLKEM768"; then
        echo -e "${GREEN}✅ ПОДДЕРЖИВАЕТ X25519MLKEM768${NC}"
        echo "$PQFECTH_OUTPUT" | head -1
    elif echo "$PQFECTH_OUTPUT" | grep -qi "X25519"; then
        echo -e "${YELLOW}⚠️ Использует X25519 (классический)${NC}"
        echo "$PQFECTH_OUTPUT" | head -1
    else
        echo -e "${RED}❌ Не поддерживается или ошибка${NC}"
        echo "$PQFECTH_OUTPUT" | head -3
    fi
    
    # Обычное TLS
    echo -e "\n${CYAN}━━━ Обычное TLS-подключение ━━━${NC}"
    TLS_INFO=$(echo | openssl s_client -connect $domain:$port -servername $domain 2>/dev/null | grep -E "Protocol|Cipher|Server Temp Key" | head -4)
    
    if [ -n "$TLS_INFO" ]; then
        echo "$TLS_INFO"
    else
        echo -e "${RED}❌ Не удалось подключиться по TLS${NC}"
    fi
    
    # Вердикт
    echo -e "\n${CYAN}━━━ ВЕРДИКТ ━━━${NC}"
    if echo "$PQFECTH_OUTPUT" | grep -qi "X25519MLKEM768"; then
        echo -e "${GREEN}🟢 PQ-безопасен (X25519MLKEM768)${NC}"
    elif echo "$PQFECTH_OUTPUT" | grep -qi "X25519"; then
        echo -e "${YELLOW}🟡 Использует X25519 (не PQ)${NC}"
        echo -e "${YELLOW}⚠️ Риск блокировки на ТСПУ для iOS клиентов${NC}"
    else
        echo -e "${RED}🔴 Не поддерживает PQ или ошибка${NC}"
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
        # Извлекаем server=... и port=...
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
    else
        # Обычный домен или IP:порт
        domain="$input"
        if echo "$domain" | grep -q ":"; then
            port=$(echo "$domain" | cut -d':' -f2)
            domain=$(echo "$domain" | cut -d':' -f1)
        fi
    fi
    
    check_site "$domain" "$port"
}

# ── Основная функция ────────────────────────────────────────
main() {
    clear
    echo ""
    echo -e "  ${BOLD}${CYAN}🔍 ПРОВЕРКА ПРОКСИ НА PQ-БЕЗОПАСНОСТЬ${NC}"
    echo -e "  ${DIM}═════════════════════════════════════════════════${NC}"
    echo ""
    
    # Проверяем зависимости один раз
    check_dependencies
    install_pqfetch
    
    # Цикл проверки
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
        
        # Проверка на выход
        if [[ "$proxy_input" == "0" || "$proxy_input" =~ ^[nN]$ || "$proxy_input" =~ ^[qQ]$ ]]; then
            echo ""
            print_info "Возврат в главное меню..."
            sleep 0.5
            return 0
        fi
        
        # Проверка на пустой ввод
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
    done
}

# ── Запуск ──────────────────────────────────────────────────
main "$@"
