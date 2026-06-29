#!/bin/bash
# proxymenu.sh

while true; do
    clear
    echo ""
    echo -e "  ${BOLD}Прокси меню${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}  Действие 1 (в разработке)"
    echo -e "  ${CYAN}[2]${NC}  Действие 2 (в разработке)"
    echo -e "  ${CYAN}[0]${NC}  Назад в главное меню"
    echo ""
    echo -en "  ${BOLD}Выбор:${NC} "
    read -r choice

    case "$choice" in
        1)
            echo ""
            echo "  Действие 1 — в разработке"
            echo -e "  ${GRAY}Нажмите любую клавишу для возврата...${NC}"
            read -rsn1
            ;;
        2)
            echo ""
            echo "  Действие 2 — в разработке"
            echo -e "  ${GRAY}Нажмите любую клавишу для возврата...${NC}"
            read -rsn1
            ;;
        0)
            exec /opt/mtpr-simple/main.sh
            ;;
        *)
            echo "  Неверный выбор"
            sleep 1
            ;;
    esac
done
