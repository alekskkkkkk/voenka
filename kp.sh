#!/bin/bash

# Проверка окружения
if [[ "$OSTYPE" != "linux-gnu"* || -z "$BASH_VERSION" || $EUID -eq 0 ]]; then exit 1; fi

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
DB_FILE="$SOURCE_DIR/vko_base.db"
SQL_TEMP="$SOURCE_DIR/temp_insert.sql"
GLOBAL_DEC_LOG="$SOURCE_DIR/vko_decrypted_all.log"

# Ассоциативные массивы для умного мониторинга (Watchdog)
declare -A declared_dead
declare -A missed_beats

# При выходе удаляем временные файлы
trap "rm -f $SQL_TEMP; exit" INT TERM EXIT

# Создаем файл лога, если его нет
touch "$GLOBAL_DEC_LOG"

while true; do
    clear
    echo "========================================================"
    echo "    КОМАНДНЫЙ ПУНКТ (КП) — ИНТЕРАКТИВНЫЙ МОНИТОРИНГ"
    echo "========================================================"

    # --- 1. МОНИТОРИНГ ЖИВУЧЕСТИ СИСТЕМ (HEARTBEAT С ДОПУСКОМ) ---
    printf "%-10s | %-20s\n" "ОБЪЕКТ" "СОСТОЯНИЕ"
    echo "--------------------------------------------------------"
    
    systems=("RLS_1" "RLS_2" "RLS_3" "ZRDN_1" "ZRDN_2" "ZRDN_3" "SPRO")
    new_data_received=0

    for name in "${systems[@]}"; do
        hb_file="$SOURCE_DIR/${name}.hb"
        
        if [ -f "$hb_file" ]; then
            printf "%-10s | \e[32mАКТИВЕН\e[0m\n" "$name"
            
            # Если система была "мертвой", логируем её триумфальное возвращение
            if [[ "${declared_dead[$name]}" -eq 1 ]]; then
                ts=$(date +%H:%M:%S:%3N)
                dt=$(date +%d.%m)
                recv_msg="$dt $ts $name ИНФО: Система успешно восстановлена и вернулась в строй!"
                
                echo "$recv_msg" >> "$GLOBAL_DEC_LOG"
                new_data_received=1 # Триггер для обновления БД
            fi

            # Сбрасываем флаги при успешном отклике (система жива)
            declared_dead[$name]=0
            missed_beats[$name]=0
            rm -f "$hb_file"
        else
            # Файла пульса нет. Увеличиваем счетчик пропусков
            missed_beats[$name]=$((missed_beats[$name] + 1))
            
            # Ждем 3 цикла (около 6-9 секунд) перед тем, как бить тревогу
            if [ "${missed_beats[$name]}" -ge 3 ]; then
                printf "%-10s | \e[31mНЕ АКТИВЕН\e[0m\n" "$name"
                
                # Записываем сбой в лог только один раз
                if [[ "${declared_dead[$name]}" -ne 1 ]]; then
                    ts=$(date +%H:%M:%S:%3N)
                    dt=$(date +%d.%m)
                    fail_msg="$dt $ts $name ВНИМАНИЕ: Система вышла из строя (пропал сигнал пульса)!"
                    
                    echo "$fail_msg" >> "$GLOBAL_DEC_LOG"
                    declared_dead[$name]=1
                    new_data_received=1 # Триггер для обновления БД
                fi
            else
                # Если пропусков 1 или 2, система просто работает под высокой нагрузкой
                printf "%-10s | \e[33mОЖИДАНИЕ ОТКЛИКА...\e[0m\n" "$name"
            fi
        fi
    done
    echo "========================================================"

    # --- 2. ОБРАБОТКА БУФЕРОВ СООБЩЕНИЙ (*.msg) ---
    for msg_file in "$SOURCE_DIR"/*.msg; do
        [[ -e "$msg_file" ]] || continue
        [[ -s "$msg_file" ]] || continue # Пропуск пустых буферов
        
        new_data_received=1
        
        # Безопасное изъятие данных (чтобы не потерять пакеты во время обработки)
        batch_file=$(mktemp)
        mv "$msg_file" "$batch_file"
        touch "$msg_file"
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            
            # Дешифровка лога
            decoded=$(echo "$line" | rev | base64 -d 2>/dev/null)
            [[ -z "$decoded" ]] && continue
            
            echo "$decoded" >> "$GLOBAL_DEC_LOG"
        done < "$batch_file"
        rm -f "$batch_file"
    done

    # --- 3. СИНХРОНИЗАЦИЯ И СТАТИСТИКА (SQLite) ---
    if [ "$new_data_received" -eq 1 ]; then
       
        sort -s -k1,1 -k2,2 "$GLOBAL_DEC_LOG" -o "$GLOBAL_DEC_LOG"
        
        # Пересобираем БД для актуальной аналитики
        sqlite3 "$DB_FILE" "DROP TABLE IF EXISTS logs; CREATE TABLE logs (date TEXT, time TEXT, system TEXT, message TEXT);"
        
        echo "BEGIN TRANSACTION;" > "$SQL_TEMP"
        while IFS= read -r log_line; do
            D=$(echo "$log_line" | awk '{print $1}')
            T=$(echo "$log_line" | awk '{print $2}')
            S=$(echo "$log_line" | awk '{print $3}')
            M=$(echo "$log_line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}')
            M="${M//\'/\'\'}" # Экранирование для SQL
            echo "INSERT INTO logs (date, time, system, message) VALUES ('$D', '$T', '$S', '$M');" >> "$SQL_TEMP"
        done < "$GLOBAL_DEC_LOG"
        echo "COMMIT;" >> "$SQL_TEMP"
        
        sqlite3 "$DB_FILE" < "$SQL_TEMP"
        rm -f "$SQL_TEMP"
    fi

    # --- 4. ВЫВОД АНАЛИТИКИ ---
    echo "                  АНАЛИТИКА (SQLite)"
    echo "--------------------------------------------------------"
    if [ -f "$DB_FILE" ]; then
        echo "[1] Подтвержденные уничтожения:"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Сбито' FROM logs WHERE message LIKE '%УНИЧТОЖЕНА%' GROUP BY system;"
        echo ""
        echo "[2] Расход боеприпасов (Пуски):"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Пусков' FROM logs WHERE message LIKE '%пуск%' GROUP BY system;"
        echo ""
        echo "[3] Нехватка боекомплекта:"
        sqlite3 -header -column "$DB_FILE" "SELECT system AS 'Система', COUNT(*) AS 'Отказов' FROM logs WHERE message LIKE '%ОТСУТСТВУЮТ%' OR message LIKE '%ИСЧЕРПАН%' GROUP BY system;"
        echo ""
        echo "[4] Журнал состояний модулей:"
        sqlite3 -header -column "$DB_FILE" "SELECT time AS 'Время', system AS 'Объект', CASE WHEN message LIKE '%вышла из строя%' THEN 'СБОЙ' ELSE 'ОК (Восстановлен)' END AS 'Статус' FROM logs WHERE message LIKE '%вышла из строя%' OR message LIKE '%вернулась в строй%' ORDER BY time DESC LIMIT 5;"
    else
        echo "Данные для анализа еще не поступили."
    fi

    echo "========================================================"
    echo "Обновление: 3 сек.  Журнал: vko_decrypted_all.log"
    
    sleep 3
done