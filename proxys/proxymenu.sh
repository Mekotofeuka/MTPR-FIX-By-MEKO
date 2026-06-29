#!/bin/bash
# proxymenu.sh

while true; do
    clear
    echo ""
    echo -e "  ${BOLD}Прокси меню${NC}"
    echo -e "  ${DIM}===========================${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC}  Меню работы с Telemt"
    echo -e "  ${CYAN}[2]${NC}  Меню работы с MTProtoZig"
    echo -e "  ${CYAN}[0]${NC}  Назад в главное меню"
    echo ""
    echo -en "  ${BOLD}Выбор:${NC} "
    read -r choice

    case "$choice" in
        1)
            if [ -f "/opt/mtpr-simple/proxys/telemt1.sh" ]; then
                exec /opt/mtpr-simple/proxys/telemt1.sh
            else
                echo ""
                echo "  [✗] Файл /opt/mtpr-simple/proxys/telemt1.sh не найден"
                echo -e "  ${GRAY}Нажмите любую клавишу для возврата...${NC}"
                read -rsn1
            fi
            ;;
        2)
            if [ -f "/opt/mtpr-simple/proxys/mtprotozig1.sh" ]; then
                exec /opt/mtpr-simple/proxys/mtprotozig1.sh
            else
                echo ""
                echo "  [✗] Файл /opt/mtpr-simple/proxys/mtprotozig1.sh не найден"
                echo -e "  ${GRAY}Нажмите любую клавишу для возврата...${NC}"
                read -rsn1
            fi
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
