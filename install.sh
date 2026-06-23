#!/bin/bash

set -e

SCRIPT_URL="https://raw.githubusercontent.com/Mekotofeuka/MTPR-FIX-By-MEKO/main/main.sh"
LOCAL_FILE="/opt/mtpr-simple/main.sh"
VERSION_FILE="/opt/mtpr-simple/version"

if [ "$(id -u)" -ne 0 ]; then
    echo "root only"
    exit 1
fi

mkdir -p /opt/mtpr-simple

rm -f "$LOCAL_FILE"

curl -fsSL "$SCRIPT_URL" -o "$LOCAL_FILE"

chmod +x "$LOCAL_FILE"

md5sum "$LOCAL_FILE" | awk '{print $1}' > "$VERSION_FILE"

ln -sf "$LOCAL_FILE" /usr/local/bin/mekopr

echo "OK updated"
exec "$LOCAL_FILE" </dev/tty
