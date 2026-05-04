#!/bin/bash

if [[ "$OSTYPE" != "linux-gnu"* || -z "$BASH_VERSION" || $EUID -eq 0 ]]; then exit 1; fi

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
DB_FILE="$SOURCE_DIR/vko_base.db"
SQL_TEMP="$SOURCE_DIR/temp_insert.sql"
GLOBAL_DEC_LOG="$SOURCE_DIR/vko_decrypted_all.log"


trap "rm -f $SQL_TEMP; exit" INT TERM EXIT

while true; do
    clear 
    echo "========================================================"
    echo "    КОМАНДНЫЙ ПУНКТ (КП) - СТАТУС И СТАТИСТИКА (LIVE)"
    echo "========================================================"

    
    printf "%-10s | %-20s\n" "ОБЪЕКТ" "СОСТОЯНИЕ"
    echo "--------------------------------------------------------"
    systems=("RLS_1:rls_1.pid" "RLS_2:rls_2.pid" "RLS_3:rls_3.pid" "ZRDN_1:zrdn_1.pid" "ZRDN_2:zrdn_2.pid" "ZRDN_3:zrdn_3.pid" "SPRO:spro.pid")

    for sys in "${systems[@]}"; do
        name="${sys%%:*}"
        pid_file="$SOURCE_DIR/${sys##*:}"
        
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                printf "%-10s | \e[32mАКТИВЕН\e[0m (PID: %s)\n" "$name" "$pid"
            else
                printf "%-10s | \e[31mНЕ АКТИВЕН\e[0m (Упал)\n" "$name"
            fi
        else
            printf "%-10s | \e[33mНЕ ЗАПУЩЕН\e[0m\n" "$name"
        fi
    done
    echo "========================================================"


    sqlite3 "$DB_FILE" "DROP TABLE IF EXISTS logs; CREATE TABLE logs (date TEXT, time TEXT, system TEXT, message TEXT);"
    > "$GLOBAL_DEC_LOG" 

    echo "BEGIN TRANSACTION;" > "$SQL_TEMP"

    found_logs=0
    for enc_file in "$SOURCE_DIR"/*_enc.log; do
        [[ -e "$enc_file" ]] || continue
        found_logs=1
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
       
            decoded=$(echo "$line" | rev | base64 -d 2>/dev/null)
            [[ -z "$decoded" ]] && continue
            
            echo "$decoded" >> "$GLOBAL_DEC_LOG"
            
            D=$(echo "$decoded" | awk '{print $1}')
            T=$(echo "$decoded" | awk '{print $2}')
            S=$(echo "$decoded" | awk '{print $3}')
            M=$(echo "$decoded" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}')
            
            M="${M//\'/\'\'}" 
            echo "INSERT INTO logs (date, time, system, message) VALUES ('$D', '$T', '$S', '$M');" >> "$SQL_TEMP"
        done < "$enc_file"
    done

    if [ "$found_logs" -eq 1 ]; then

        sort "$GLOBAL_DEC_LOG" -o "$GLOBAL_DEC_LOG"

        echo "COMMIT;" >> "$SQL_TEMP"
        sqlite3 "$DB_FILE" < "$SQL_TEMP"
        rm -f "$SQL_TEMP"
    fi

    echo "                  АНАЛИТИКА БД"
    echo "--------------------------------------------------------"

    if [ "$found_logs" -eq 1 ]; then
        echo "[1] Расход ракет (Пуски по системам):"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Пусков' FROM logs WHERE message LIKE '%Произведен пуск%' GROUP BY system ORDER BY COUNT(*) DESC;"
        echo ""

        echo "[2] Точность (Количество подтвержденных уничтожений):"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Сбито целей' FROM logs WHERE message LIKE '%УНИЧТОЖЕНА%' GROUP BY system ORDER BY COUNT(*) DESC;"
        echo ""

        echo "[3] Ситуация с боекомплектом (Внимание: БК исчерпан):"
        sqlite3 -header -column "$DB_FILE" "SELECT DISTINCT system AS 'Система (Пустой БК)' FROM logs WHERE message LIKE '%БОЕКОМПЛЕКТ ИСЧЕРПАН%';"
        echo ""

        echo "[4] Пропуски целей (Нехватка БК):"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Пропущено целей' FROM logs WHERE message LIKE '%НО БОЕПРИПАСЫ ОТСУТСТВУЮТ%' GROUP BY system;"
        echo ""

        echo "[5] Эффективность ПРО Омска (СПРО):"
        sqlite3 -header -column "$DB_FILE" "
        SELECT 
            (SELECT COUNT(*) FROM logs WHERE system='SPRO' AND message LIKE '%Обнаружена БР%') AS 'Обнаружено БР',
            (SELECT COUNT(*) FROM logs WHERE system='SPRO' AND message LIKE '%Произведен пуск%') AS 'Выпущено ракет',
            (SELECT COUNT(*) FROM logs WHERE system='SPRO' AND message LIKE '%УНИЧТОЖЕНА%') AS 'Уничтожено БР';"
    else
        echo "Зашифрованные логи не найдены. Ожидание данных..."
    fi
    
    echo "========================================================"
    sleep 3
done