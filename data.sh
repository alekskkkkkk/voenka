#!/bin/bash

TARGETS_DIR="/tmp/GenTargets/Targets"
DATA_FILE="/tmp/air_situation.txt"

# Хранилище для расчета параметров и отслеживания состояния
declare -A PREV_X PREV_Y
declare -A CURRENT_IDS  # Список ID, которые были в прошлом цикле

decrypt_id() {
    local filename=$1
    local hex_id=""
    for (( i=2; i<${#filename}-2; i+=4 )); do
        hex_id="${hex_id}${filename:$i:2}"
    done
    echo -n "$hex_id" | xxd -r -p 2>/dev/null
}

echo "Сервер сбора данных запущен..."

while true; do
    FILES=$(ls -t "$TARGETS_DIR" 2>/dev/null | head -n 50)
    
    # Очищаем временный файл шины
    > "${DATA_FILE}.tmp"

    clear
    echo "=== ЦЕНТРАЛЬНЫЙ ПРОЦЕССОР СБОРА ДАННЫХ (ЦПСД) ==="
    echo "Обновление: $(date +%T) | Объектов в небе: $(echo "$FILES" | wc -w)"
    echo "----------------------------------------------------------------------"
    printf "%-10s | %-12s | %-8s | %-10s | %-10s\n" "ID" "ТИП" "V м/с" "X" "Y"
    echo "----------------------------------------------------------------------"

    # Массив для ID, которые мы увидим в ЭТОМ цикле
    declare -A SEEN_NOW
    declare -A NEW_PREV_X NEW_PREV_Y

    for file in $FILES; do
        [ ! -f "$TARGETS_DIR/$file" ] && continue
        
        ID=$(decrypt_id "$file")
        [ -z "$ID" ] && continue
        
        SEEN_NOW[$ID]=1
        DATA=$(head -n 1 "$TARGETS_DIR/$file")
        CUR_X=$(echo "$DATA" | grep -oP 'X:\s*\K\d+')
        CUR_Y=$(echo "$DATA" | grep -oP 'Y:\s*\K\d+')

        V=0; TYPE="АНАЛИЗ"; COLOR="\e[37m"

        if [[ -n "${PREV_X[$ID]}" ]]; then
            DX=$(( CUR_X - PREV_X[$ID] ))
            DY=$(( CUR_Y - PREV_Y[$ID] ))
            V=$(echo "scale=0; sqrt($DX*$DX + $DY*$DY)" | bc -l 2>/dev/null)
            
            if [ "$V" -ge 8000 ]; then TYPE="ББ_БР"; COLOR="\e[31m"
            elif [ "$V" -ge 250 ]; then TYPE="КР"; COLOR="\e[33m"
            else TYPE="САМОЛЕТ"; COLOR="\e[32m"; fi
        fi

        # Вывод строки цели
        printf "${COLOR}%-10s | %-12s | %-8s | %-10s | %-10s\e[0m\n" \
               "$ID" "$TYPE" "$V" "$CUR_X" "$CUR_Y"

        # Пишем в шину для клиентов
        echo "$ID $TYPE $CUR_X $CUR_Y $V ${PREV_X[$ID]:-0} ${PREV_Y[$ID]:-0}" >> "${DATA_FILE}.tmp"

        NEW_PREV_X[$ID]=$CUR_X
        NEW_PREV_Y[$ID]=$CUR_Y
    done

    # ПРОВЕРКА НА УНИЧТОЖЕНИЕ (сравнение старых ID с новыми)
    for old_id in "${!CURRENT_IDS[@]}"; do
        if [[ -z "${SEEN_NOW[$old_id]}" ]]; then
            echo -e "\e[41m\e[37m[ СОБЫТИЕ ] Цель $old_id уничтожена или потеряна \e[0m"
            # Можно добавить запись этого события в лог КП
            echo "$(date +%T) Цель $old_id пропала с радаров" >> ./battle_history.log
        fi
    done

    # Обновляем список "живых" ID для следующего цикла
    unset CURRENT_IDS
    declare -A CURRENT_IDS
    for id in "${!SEEN_NOW[@]}"; do
        CURRENT_IDS[$id]=1
    done

    # Синхронизация координат
    unset PREV_X PREV_Y
    declare -A PREV_X PREV_Y
    for id in "${!NEW_PREV_X[@]}"; do
        PREV_X[$id]=${NEW_PREV_X[$id]}
        PREV_Y[$id]=${NEW_PREV_Y[$id]}
    done

    mv "${DATA_FILE}.tmp" "$DATA_FILE"
    echo "----------------------------------------------------------------------"
    sleep 1
done

