#!/bin/bash
# Простой менеджер SYN FIX
# Меню: 1) Install/Remove SYN FIX, 2) Optimization, 0) Exit
# Запуск: сохраните как /usr/local/bin/mekopr и дайте права на выполнение (chmod +x)

set -eo pipefail

# ── Цвета ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Логирование ─────────────────────────────────────────────
log_info()    { echo -e "  ${BLUE}[i]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1" >&2; }

# ── Проверка root ────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Требуются права root"
        exit 1
    fi
}

# ── Файл для хранения порта ─────────────────────────────────
PORT_FILE="/opt/mtpr-simple/port"

get_saved_port() {
    if [ -f "$PORT_FILE" ]; then
        cat "$PORT_FILE"
    else
        echo ""
    fi
}

save_port() {
    echo "$1" > "$PORT_FILE"
}

# ── ПРОВЕРКА НАЛИЧИЯ ЛЮБОГО ПРАВИЛА С tcp И syn ────────────
is_syn_fix_installed() {
    if iptables-save 2>/dev/null | grep -iE 'tcp.*syn|syn.*tcp' | grep -q .; then
        return 0
    fi
    if grep -rE 'tcp.*syn|syn.*tcp' /etc/ufw/ --include='*.rules' 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# ── ПРОВЕРКА, ЧТО СТОИТ ИМЕННО НАШ SYN FIX (mtpr_syn_fix) ──
is_our_syn_fix_installed() {
    if iptables-save 2>/dev/null | grep -q 'mtpr_syn_fix'; then
        return 0
    fi
    if grep -r 'mtpr_syn_fix' /etc/ufw/ --include='*.rules' 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# ── Определение Telemt ──────────────────────────────────────
detect_telemt() {
    if pgrep -x telemt >/dev/null 2>&1; then
        local configs=(
            "/etc/telemt/telemt.toml"
            "/etc/telemt/config.toml"
            "/etc/telemt.toml"
            "/opt/telemt/config.toml"
            "/opt/telemt/telemt.toml"
        )
        for cfg in "${configs[@]}"; do
            if [ -f "$cfg" ]; then
                local port=$(grep -E '^port[[:space:]]*=' "$cfg" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    echo "Установлен (порт $port)"
                    return 0
                fi
            fi
        done
        echo "Установлен (порт не определён)"
        return 0
    else
        echo "не обнаружен"
        return 1
    fi
}

# ── Установка SYN FIX ──────────────────────────────────────
install_syn_fix() {
    local port
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

    log_info "Установка SYN FIX на порт $port..."

    apt update
    apt install ufw -y

    ufw allow 22/tcp
    ufw allow "$port"/tcp

    ufw --force enable

    # Добавляем наши правила в /etc/ufw/before.rules (если их там ещё нет)
    if ! grep -q 'mtpr_syn_fix' /etc/ufw/before.rules; then
        cp /etc/ufw/before.rules /etc/ufw/before.rules.bak.$(date +%s)
        sed -i "/COMMIT/ i\
# MTProxy SYN FIX by MEKO (mtpr_syn_fix)\n\
-A ufw-before-input -p tcp --dport $port --syn -m hashlimit --hashlimit-name mtproto_$port --hashlimit-mode srcip --hashlimit-upto 54/minute --hashlimit-burst 1 --hashlimit-htable-expire 60000 --hashlimit-htable-size 32768 -m comment --comment \"mtpr_syn_fix\" -j ACCEPT\n\
-A ufw-before-input -p tcp --dport $port --syn -j REJECT --reject-with tcp-reset" /etc/ufw/before.rules

        if ! grep -q 'mtpr_syn_fix' /etc/ufw/before.rules; then
            log_info "COMMIT не найден, добавляем в конец before.rules"
            echo -e "\n# MTProxy SYN FIX by MEKO (mtpr_syn_fix)" >> /etc/ufw/before.rules
            echo "-A ufw-before-input -p tcp --dport $port --syn -m hashlimit --hashlimit-name mtproto_$port --hashlimit-mode srcip --hashlimit-upto 54/minute --hashlimit-burst 1 --hashlimit-htable-expire 60000 --hashlimit-htable-size 32768 -m comment --comment \"mtpr_syn_fix\" -j ACCEPT" >> /etc/ufw/before.rules
            echo "-A ufw-before-input -p tcp --dport $port --syn -j REJECT --reject-with tcp-reset" >> /etc/ufw/before.rules
        fi
    else
        log_info "Наши правила уже есть в before.rules"
    fi

    save_port "$port"
    ufw reload

    log_success "SYN FIX успешно Установлен на порт $port"
}

# ── Удаление ВСЕХ правил с tcp и syn ───────────────────────
remove_syn_fix() {
    log_info "Удаление всех правил с tcp и syn..."

    # 1. Удаляем из цепочки ufw-before-input в iptables
    local nums=()
    while IFS= read -r line; do
        if echo "$line" | grep -qiE 'tcp.*syn|syn.*tcp'; then
            num=$(echo "$line" | awk '{print $1}')
            nums+=("$num")
        fi
    done < <(iptables -L ufw-before-input --line-numbers -n 2>/dev/null)

    for num in $(printf '%s\n' "${nums[@]}" | sort -nr); do
        iptables -D ufw-before-input "$num" 2>/dev/null && log_info "Удалено правило #$num из iptables"
    done

    # 2. Удаляем строки с tcp и syn из всех .rules файлов в /etc/ufw/
    find /etc/ufw/ -name '*.rules' -type f | while read -r file; do
        if grep -qiE 'tcp.*syn|syn.*tcp' "$file"; then
            cp "$file" "$file.bak.$(date +%s)"
            sed -i '/tcp.*syn/d' "$file"
            sed -i '/syn.*tcp/d' "$file"
            sed -i '/^$/d' "$file"
            log_info "Очищен файл: $file"
        fi
    done

    ufw reload
    rm -f "$PORT_FILE"

    log_success "Все правила с tcp и syn удалены"
}

# ── Пункт 2: Optimization (пока ничего не делает) ──────────
apply_optimization() {
    log_info "Оптимизация пока не реализована"
}

# ── Очистка экрана и шапка ──────────────────────────────────
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

show_header() {
    clear_screen
    echo ""
    echo -e "  ${BOLD}Простой менеджер SYN FIX v1${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""

    # Определяем статус SYN FIX
    if is_syn_fix_installed; then
        if is_our_syn_fix_installed; then
            local port_info=$(get_saved_port)
            if [ -n "$port_info" ]; then
                echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен (MEKO)${NC} (порт $port_info)"
            else
                echo -e "  ${BOLD}SYN FIX:${NC} ${GREEN}Установлен (MEKO)${NC}"
            fi
        else
            # Любой другой SYN фикс (не наш) – отображаем явно как "другой SYN FIX"
            echo -e "  ${BOLD}SYN FIX:${NC} ${YELLOW}Установлен другой SYN FIX${NC}"
        fi
    else
        echo -e "  ${BOLD}SYN FIX:${NC} ${RED}Не установлен${NC}"
    fi

    # Telemt — теперь с цветом: зелёным если установлен, красным если нет
    if pgrep -x telemt >/dev/null 2>&1; then
        local port_info=""
        local configs=(
            "/etc/telemt/telemt.toml"
            "/etc/telemt/config.toml"
            "/etc/telemt.toml"
            "/opt/telemt/config.toml"
            "/opt/telemt/telemt.toml"
        )
        for cfg in "${configs[@]}"; do
            if [ -f "$cfg" ]; then
                local port=$(grep -E '^port[[:space:]]*=' "$cfg" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
                if [[ "$port" =~ ^[0-9]+$ ]]; then
                    port_info=" (порт $port)"
                    break
                fi
            fi
        done
        if [ -n "$port_info" ]; then
            echo -e "  ${BOLD}Telemt:${NC} ${GREEN}Установлен${NC}$port_info"
        else
            echo -e "  ${BOLD}Telemt:${NC} ${GREEN}Установлен${NC} (порт не определён)"
        fi
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
            local item1="${RED}Remove SYN FIX${NC}"
        else
            local item1="${GREEN}Install SYN FIX${NC}"
        fi

        echo -e "  ${CYAN}[1]${NC}  $item1"
        echo -e "  ${CYAN}[2]${NC}  Optimization (пока ничего не делает)"
        echo -e "  ${CYAN}[0]${NC}  Выход"
        echo ""
        echo -en "  ${BOLD}Выбор:${NC} "
        local choice
        read -r choice

        case "$choice" in
            1)
                echo ""
                if is_syn_fix_installed; then
                    log_info "Обнаружены правила с tcp и syn. Удалить их все?"
                    echo -en "  ${BOLD}Удалить? [Y/n]:${NC} "
                    local confirm
                    read -r confirm
                    # Пустой ввод (Enter) считается как Yes
                    if [[ -z "$confirm" || "$confirm" =~ ^[yY]$ ]]; then
                        remove_syn_fix
                    else
                        log_info "Отмена удаления"
                    fi
                else
                    install_syn_fix
                fi
                echo ""
                read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
                ;;
            2)
                echo ""
                apply_optimization
                echo ""
                read -rsn1 -p "  Нажмите любую клавишу для возврата в меню..."
                ;;
            0|q|Q)
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
check_root
main_menu
