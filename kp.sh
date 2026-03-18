#!/bin/bash
source ./security_check.sh # Подключаем защиту

DB_FILE="./vko_base.db"
MAIN_LOG="./system_work.log"
BUS="/tmp/vko_bus" # Файл-шина для сообщений

# Инициализация БД
sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS stats (element TEXT, event TEXT, target_id TEXT, coords TEXT, timestamp DATETIME DEFAULT CURRENT_TIMESTAMP);"

echo "--- КП ВКО ЗАПУЩЕН ---" | tee -a "$MAIN_LOG"

while true; do
    # 1. Прием сообщений из шины
    if [ -s "$BUS" ]; then
        while read -r line; do
            # Парсим сообщение: ТАЙМШТАМП | КТО | ЧТО | ID | COORDS
            time_msg=$(echo "$line" | cut -d'|' -f1)
            sender=$(echo "$line" | cut -d'|' -f2)
            event=$(echo "$line" | cut -d'|' -f3)
            tid=$(echo "$line" | cut -d'|' -f4)
            coords=$(echo "$line" | cut -d'|' -f5)

            # Запись в главный журнал
            echo "$time_msg $sender $event $tid $coords" >> "$MAIN_LOG"
            # Запись в БД
            sqlite3 "$DB_FILE" "INSERT INTO stats (element, event, target_id, coords) VALUES ('$sender', '$event', '$tid', '$coords');"
        done < "$BUS"
        > "$BUS" # Очистка шины
    fi

    # 2. Проверка работоспособности (Health Check) каждые 10 секунд
    if (( $(date +%s) % 10 == 0 )); then
        for element in "RLS1" "RLS2" "RLS3" "ZRDN1" "SPRO"; do
            PID_F="/tmp/${element}.sh.pid" # Проверяем PID файлы
            if [ -f "$PID_F" ] && kill -0 $(cat "$PID_F") 2>/dev/null; then
                echo "$(date +%T) $element работоспособность подтверждена" >> "$MAIN_LOG"
            else
                echo "$(date +%T) $element ОТКАЗ СИСТЕМЫ" >> "$MAIN_LOG"
            fi
        done
    fi

    # 3. Ограничение размера лога (храним последние 1000 строк)
    if [ $(wc -l < "$MAIN_LOG") -gt 2000 ]; then
        sed -i '1,500d' "$MAIN_LOG"
    fi

    sleep 1
done