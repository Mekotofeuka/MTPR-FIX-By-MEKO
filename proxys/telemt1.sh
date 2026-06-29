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

    # ── Проверяем, что указанный файл конфига действительно существует ──
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

    # ── Сохраняем путь ──────────────────────────────────────
    mkdir -p /opt/mtpr-simple
    echo "$CONFIG_TELEMT_INPUT" > "$CONFIG_PATH_FILE"
    echo -e "  ${GREEN}[✓]${NC} Путь сохранён: $CONFIG_TELEMT_INPUT"
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для возврата в меню...${NC}"
    read -rsn1
    return 0
}

# ── Функция установки Telemt ────────────────────────────────
install_telemt() {
    echo ""
    echo -e "  ${BLUE}[i]${NC} Установка Telemt версии 3.4.18..."
    echo ""
    if curl -fsSL https://raw.githubusercontent.com/telemt/telemt/main/install.sh | sh -s -- 3.4.18; then
        echo ""
        echo -e "  ${GREEN}[✓]${NC} Telemt успешно установлен"
    else
        echo ""
        echo -e "  ${RED}[✗]${NC} Ошибка установки Telemt"
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
    
    # Проверяем, существует ли файл
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
    echo -e "  ${GRAY}После редактирования сохраните файл (Ctrl+O) и закройте (Ctrl+X)${NC}"
    echo ""
    echo -e "  ${GRAY}Нажмите любую клавишу для продолжения...${NC}"
    read -rsn1
    
    nano "$config_path"
    
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
    echo -e "  ${BOLD}Telemt меню v0.2${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}  ${BOLD}Установить Telemt 3.4.18"
    echo -e "  ${CYAN}[2]${NC}  ${BOLD}Открыть конфиг Telemt"
    echo -e "  ${CYAN}[3]${NC}  ${BOLD}Перезапустить Telemt"
    echo -e "  ${CYAN}[4]${NC}  ${BOLD}Обновить путь к конфигу Telemt"
    echo -e "  ${RED}[5]${NC}  ${BOLD}Удалить Telemt"
    echo -e "  ${CYAN}[0]${NC}  ${BOLD}Назад в прокси меню"
    echo ""
    
    # Проверяем, установлен ли Telemt, и показываем соответствующий статус
    if is_telemt_installed; then
        current_path=$(get_config_path)
        echo -e "  ${DIM}Текущий путь к конфигу: ${current_path}${NC}"
    else
        echo -e "  ${YELLOW}Telemt не установлен${NC}"
    fi
    echo ""
    
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
