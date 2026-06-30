#!/bin/bash
set -e

BASE_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPROTO_FIX_By_MEKO/main"
FILES=("main.sh" "proxys/proxymenu.sh" "proxys/telemt1.sh" "proxys/mtprotozig1.sh")

# ── Цвета ─────────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Проверка root ────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[✗]${NC} Запустите от root: ${BOLD}curl -fsSL ... | sudo bash${NC}" >&2
    exit 1
fi

# ── Шапка ─────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}${CYAN}⚙️ УСТАНОВКА MEKOPR${NC}"
echo -e "  ${BOLD}${DIM}═════════════════════════════════════════════════${NC}"
echo ""

# ── Создание директорий ──────────────────────────────────────
mkdir -p /opt/mtpr-simple/proxys

# ── Асинхронное скачивание ──────────────────────────────────
download_file() {
    local file="$1"
    local url="$BASE_URL/$file"
    local dest="/opt/mtpr-simple/$file"
    local name=$(basename "$file")
    
    # Получаем размер файла
    local size=$(curl -sI "$url" 2>/dev/null | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    local size_str="?"
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        if [ "$size" -gt 1048576 ]; then
            size_str="$(echo "scale=1; $size/1048576" | bc) MB"
        elif [ "$size" -gt 1024 ]; then
            size_str="$(echo "scale=0; $size/1024" | bc) KB"
        else
            size_str="$size B"
        fi
    fi
    
    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} ${BOLD}${name}${NC} (${size_str})"
    else
        echo -e "  ${RED}✗${NC} ${BOLD}${name}${NC} — ошибка загрузки"
    fi
}
export -f download_file
export BASE_URL

# ── Запуск параллельной загрузки ────────────────────────────
echo -e "  ${BOLD}Загрузка файлов...${NC}"
echo ""

printf "%s\n" "${FILES[@]}" | xargs -P 4 -I {} bash -c 'download_file "$@"' _ {}

# ── Установка прав и создание ссылки ────────────────────────
echo ""
echo -ne "  ${CYAN}[+]${NC} Установка прав выполнения... "
chmod +x /opt/mtpr-simple/main.sh && chmod +x /opt/mtpr-simple/proxys/*.sh && echo -e "${GREEN}✓${NC}"

echo -ne "  ${CYAN}[+]${NC} Создание ссылки ${BOLD}mekopr${NC}... "
ln -sf /opt/mtpr-simple/main.sh /usr/local/bin/mekopr && echo -e "${GREEN}✓${NC}"

# ── Завершение ───────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}${GREEN}✅ Установка MEKOPR успешно завершена${NC}"
echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  Для открытия меню используйте команду ${BOLD}mekopr${NC}"
echo ""

# ── Проверяем наличие TTY перед запуском меню ──────────────
if [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; then
    echo -e "  ${CYAN}[i]${NC} Запуск меню..."
    echo ""
    exec /opt/mtpr-simple/main.sh </dev/tty
else
    echo -e "  ${YELLOW}[!]${NC} Интерактивный режим недоступен (нет TTY)."
    echo -e "  ${GRAY}${BOLD}Запустите меню вручную командой: ${BOLD}${NC} sudo mekopr${NC}"
    exit 0
fi
