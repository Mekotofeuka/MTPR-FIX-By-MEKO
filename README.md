# MTPROTO FIX By MEKO 
[![Latest Release](https://img.shields.io/github/v/release/Mekotofeuka/MTPR-FIX-By-MEKO?color=neon)](https://github.com/Mekotofeuka/MTPR-FIX-By-MEKO/releases/latest) [![Stars](https://img.shields.io/github/stars/Mekotofeuka/MTPR-FIX-By-MEKO?style=social)](https://github.com/Mekotofeuka/MTPR-FIX-By-MEKO/stargazers) [![Forks](https://img.shields.io/github/forks/Mekotofeuka/MTPR-FIX-By-MEKO?style=social)](https://github.com/Mekotofeuka/MTPR-FIX-By-MEKO/network/members)

Данный скрипт используется для серверов с Telemt, фиксит проблему долгого первичного TCP-подключения клиентов, в отличие от созданных и популярных в сообществе ранее фиксов с SYN limit имеет ряд преимуществ:
- Быстрое подключение за <3-8 сек. (Оригинальный SYN Limit: >10-20сек.) даже при большом количестве юзеров
- Один порт для Ios/Android/Macos/Desktop etc.
- Медиа грузят практически с прежней скоростью
- Ставится в один клик

# Быстрый старт:

1. Установить стандартный Telemt
2. Установить/обновить наш скрипт:
```Bash
curl -fsSL https://raw.githubusercontent.com/Mekotofeuka/MTPR-FIX-By-MEKO/main/install.sh | sudo bash
```
3. Выполнить удаление старого SYN limit, (если он уже стоял на сервере ранее) нажав 1. Выполнить установку нашего фикса снова нажав 1.
4. Отключить MSS нажав 2 (если он уже был добавлен в конфиг телемт на сервер ранее)
5. Готово.
- Бонус:
Клавиша 3 выполнит базовую оптимизацию сервера под прокси.

Открыть меню:
```Bash
mekopr
```

# Как работает:
- iOS отдельно
  - У iOS в отличии от Android и Desktop разные паттерны подключений. В одном лимите они мешают друг другу. Разделение на порты конечно решение, но костыльное. Наш же фикс производит разделение этих клиентов по TTL
- 54/minute (а не 1 сек)
  - В iptables модуль hashlimit не поддерживает миллисекунды. 54/минута = 1.1 сек на соединение. Запас в 100 мс нужен, чтобы исключить погрешность возникающую при мгновенном Reject
- REJECT вместо DROP
  - DROP просто обрывает соединение клиента, не сообщая ему об этом, из-за чего происходят таймауты (3-5 сек) -> ретраи с бОльшими паузами -> бОльшая задержка. REJECT с RST же в свою очередь обрывая соединение даёт мгновенный ответ клиенту об обрыве из-за чего он(клиент) пробует переподключаться без ожидания.
- В MSS просто нет необходимости для данного билда


## ☕ Поддержать проект

**MEKO fix** — создан в свободное время для сообщества.  
Ваша поддержка поможет проводить дальнейшие тесты;)

💰 **Криптовалюта:**  

[![Поддержать проект](https://cdn4.telesco.pe/file/ir6J9wZBdI4Awllfusv8Q9erj5UrcsNfQGY1VFkRd8_qe8IosjtPgSMKzeInCZIiguSsGYUfAyqcSt-8j0gfgt3yCjc6oF0BxoqhVWMm01P5hiMykAZcGkmQE9MCk32qCp3ZVtfrVe5P7gIw7pWAz_V3w1g8iNNodtMhRtL4H7MSM2es9toIIDfbR2rEq5cYJkBgSYYsYz97hZaqngdJh1RjFPnurgcdnEup8lfLgsz2l3Cn0Gph22wpVafwgCAfAwB2TqCMp3vgVkwk2_TW8nbtAEUA6OC3IeojEAklNIziA5oBflpq9wolKmc8bezyP97X6LvkjbNL7ueLioQoNw.jpg)](https://t.me/send?start=IVlaFvgWdkxH)

от **0.1 USDT**



Также вы можете поддержать меня, воспользовавшись моим сервисом:

[<img width="300" height="300" alt="MEKO bot" src="https://github.com/user-attachments/assets/8db41a95-79f2-40d6-9777-50b6ffb6fa48" />](https://t.me/projectmeko_bot)




## Отдельное спасибо за вклад в разработку:
- [@CryZFix](https://github.com/CryZFix/)
- [@Bxhost](https://github.com/bxhost)
