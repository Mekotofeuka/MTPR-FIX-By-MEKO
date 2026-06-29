#!/bin/bash
# mtprotozig1.sh

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

# ── Функция установки Zig CLI ──────────────────────────────
install_zig_cli() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Установка Zig CLI для MTProtoZig..."
    echo ""
    if curl -fsSL https://raw.githubusercontent.com/sleep3r/mtproto.zig/main/deploy/bootstrap.sh | sudo bash; then
        echo ""
        echo -e "  ${GREEN}[✓]${NC} Zig CLI успешно установлен"
    else
        echo ""
        echo -e "  ${RED}[✗]${NC} Ошибка установки Zig CLI"
    fi
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция установки прокси ────────────────────────────────
install_proxy() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Установка MTProtoZig прокси..."
    echo ""
    echo -e "  ${BOLD}Хотите установить с параметрами по умолчанию?${NC}"
    echo ""
    echo -e "  Команда:"
    echo -e "  ${CYAN}sudo mtbuddy install --port 443 --domain rutube.ru --middle-proxy --no-tcpmss --yes${NC}"
    echo ""
    echo -e "  ${BOLD}Параметры:${NC}"
    echo -e "  • Порт: ${GREEN}443${NC}"
    echo -e "  • TLS домен: ${GREEN}rutube.ru${NC}"
    echo -e "  • MiddleProxy: ${GREEN}включён${NC}"
    echo -e "  • MSS: ${GREEN}отключён${NC}"
    echo ""
    echo -e "  ${DIM}Если желаете установить с кастомными параметрами, просто введите команду с вашими параметрами${NC}"
    echo -e "  ${DIM}Например: sudo mtbuddy install --port 8443 --domain example.com --middle-proxy --no-tcpmss --yes${NC}"
    echo ""
    echo -en "  ${BOLD}Ваш выбор (Enter/y - установить с параметрами по умолчанию, n - назад, или введите свою команду):${NC} "
    read -r choice

    case "$choice" in
        ""|y|Y)
            echo ""
            echo -e "  ${BLUE}[i]${NC} Установка с параметрами по умолчанию..."
            echo ""
            if sudo mtbuddy install --port 443 --domain rutube.ru --middle-proxy --no-tcpmss --yes; then
                echo ""
                echo -e "  ${GREEN}[✓]${NC} Прокси успешно установлен"
            else
                echo ""
                echo -e  "  ${RED}[✗]${NC} Ошибка установки прокси"
            fi
            ;;
        n|N)
            echo ""
            echo -e "  ${GRAY}Возврат в меню...${NC}"
            sleep 1
            return 0
            ;;
        *)
            # Пользователь ввёл свою команду, выполняем её
            echo ""
            echo -e "  ${BLUE}[i]${NC} Выполнение: $choice"
            echo ""
            if eval "$choice"; then
                echo ""
                echo -e "  ${GREEN}[✓]${NC} Команда выполнена успешно"
            else
                echo ""
                echo -e "  ${RED}[✗]${NC} Ошибка выполнения команды"
            fi
            ;;
    esac
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция открытия конфига ────────────────────────────────
edit_config() {
    local config_path="/opt/mtproto-proxy/config.toml"
    
    if [ ! -f "$config_path" ]; then
        echo ""
        echo -e "  ${YELLOW}[!]${NC} Файл конфига не найден по пути: $config_path"
        echo -e "  ${GRAY}Возможно, прокси ещё не установлен${NC}"
        echo ""
        echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
        read -rsn1
        return 1
    fi
    
    echo ""
    echo -e "  ${BLUE}[i]${NC} Открытие конфига: $config_path"
    echo -e "  ${GRAY}После редактирования сохраните файл (Ctrl+O) и закройте (Ctrl+X)${NC}"
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
    read -rsn1
    
    sudo nano "$config_path"
    
    echo ""
    echo -e "  ${GREEN}[✓]${NC} Редактирование завершено"
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция перезапуска прокси ──────────────────────────────
restart_proxy() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Перезапуск MTProtoZig прокси..."
    echo ""
    if sudo systemctl restart mtproto-proxy 2>/dev/null; then
        echo -e "  ${GREEN}[✓]${NC} Прокси успешно перезапущен"
    else
        echo -e "  ${YELLOW}[!]${NC} Не удалось перезапустить прокси (возможно, он не установлен как служба)"
        echo -e "  ${GRAY}Попробуйте сначала установить прокси (пункт 2)${NC}"
    fi
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Функция удаления прокси ──────────────────────────────────
purge_proxy() {
    echo ""
    echo -e "  ${RED}${BOLD}ВНИМАНИЕ:${NC} Будет выполнено полное удаление MTProtoZig!"
    echo ""
    echo -e "  ${BOLD}Будут удалены:${NC}"
    echo -e "  • Все файлы MTProtoZig"
    echo -e "  • Конфигурационные файлы"
    echo -e "  • Systemd служба"
    echo ""
    log_warning "Это действие нельзя отменить!"
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
    echo -e "  ${BLUE}[i]${NC} Удаление MTProtoZig..."
    echo ""
    if sudo mtbuddy uninstall --yes; then
        echo ""
        echo -e "  ${GREEN}[✓]${NC} MTProtoZig успешно удалён"
    else
        echo ""
        echo -e "  ${RED}[✗]${NC} Ошибка удаления MTProtoZig"
    fi
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
}

# ── Главное меню ─────────────────────────────────────────────
while true; do
    clear
    echo ""
    echo -e "  ${BOLD}MTProtoZig меню${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}  Установить Zig CLI"
    echo -e "  ${CYAN}[2]${NC}  Установить прокси"
    echo -e "  ${CYAN}[3]${NC}  Открыть конфиг"
    echo -e "  ${CYAN}[4]${NC}  Перезапустить прокси"
    echo -e "  ${RED}[5]${NC}  Удалить MTProtoZig"
    echo -e "  ${CYAN}[0]${NC}  Назад в прокси меню"
    echo ""
    echo -en "  ${BOLD}Выбор:${NC} "
    read -r choice

    case "$choice" in
        1)
            install_zig_cli
            ;;
        2)
            install_proxy
            ;;
        3)
            edit_config
            ;;
        4)
            restart_proxy
            ;;
        5)
            purge_proxy
            ;;
        0)
            exec /opt/mtpr-simple/proxys/proxymenu.sh
            ;;
        *)
            echo "  Неверный выбор"
            sleep 1
            ;;
    esac
done
