#!/bin/bash

# --- ПРОВЕРКИ БЕЗОПАСНОСТИ ---
if [[ "$OSTYPE" != "linux-gnu"* || -z "$BASH_VERSION" || $EUID -eq 0 ]]; then exit 1; fi

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "$SOURCE_DIR/config.cfg" ]; then
    source "$SOURCE_DIR/config.cfg"
else
    exit 1
fi

# ==========================================
# ПАРАМЕТРЫ ЗРДН (Менять для zrdn2 и zrdn3)
# ==========================================
ZRDN_NAME=$ZRDN3_NAME
ZRDN_X=$ZRDN3_X
ZRDN_Y=$ZRDN3_Y
ZRDN_R=$ZRDN3_R
CURRENT_AMMO=$ZRDN3_AMMO
PID_FILE="$SOURCE_DIR/zrdn_3.pid"
# ==========================================

MESSAGES_LOG="/tmp/vko_messages.log"
TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

# ЗРДН создает папку уничтожения, если её нет
mkdir -p "$DESTROY_DIR"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then exit 1; fi
fi
echo $$ > "$PID_FILE"
trap "rm -f $PID_FILE; exit" INT TERM EXIT

decrypt_id() {
    local filename=$1
    local hex_id=""
    for (( i=2; i<${#filename}-2; i+=4 )); do hex_id="${hex_id}${filename:$i:2}"; done
    echo -n "$hex_id" | xxd -r -p 2>/dev/null
}

# Для ЗРДН зона - это просто круг (Пифагор)
check_visibility() {
    local tx=$1 ty=$2
    local dx=$((tx - ZRDN_X))
    local dy=$((ty - ZRDN_Y))
    local dist=$(echo "scale=0; sqrt($dx*$dx + $dy*$dy)" | bc -l)
    if [ "$dist" -le "$ZRDN_R" ]; then return 0; else return 1; fi
}

declare -A PREV_X PREV_Y
declare -A REPORTED_IDS

echo "[$ZRDN_NAME] Дивизион запущен. Ракет: $CURRENT_AMMO. Ждем цели..."

while true; do
    FILES=$(ls -t "$TARGETS_DIR" 2>/dev/null | head -n 50)
    declare -A SEEN_NOW
    
    for file in $FILES; do
        ID=$(decrypt_id "$file")
        [[ -z "$ID" ]] && continue
        
        DATA=$(head -n 1 "$TARGETS_DIR/$file")
        CUR_X=$(echo "$DATA" | grep -oP 'X:\s*\K\d+')
        CUR_Y=$(echo "$DATA" | grep -oP 'Y:\s*\K\d+')

        # Наши золотые патчи от багов
        if [[ -z "$CUR_X" || -z "$CUR_Y" || ${#CUR_X} -lt 5 || ${#CUR_Y} -lt 5 ]]; then continue; fi
        if ! check_visibility "$CUR_X" "$CUR_Y"; then continue; fi
        
        SEEN_NOW[$ID]=1
        [[ -n "${REPORTED_IDS[$ID]}" ]] && continue

        if [[ -z "${PREV_X[$ID]}" ]]; then
            PREV_X[$ID]=$CUR_X
            PREV_Y[$ID]=$CUR_Y
            continue
        fi

        DX=$((CUR_X - PREV_X[$ID]))
        DY=$((CUR_Y - PREV_Y[$ID]))
        V=$(echo "scale=0; sqrt($DX*$DX + $DY*$DY)" | bc -l)
        V=${V%.*}

        # ЗРДН бьет только КР и Самолеты (до 1000 м/с)
        if [ "$V" -le 1000 ]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            if [ "$V" -ge 250 ]; then TYPE_STR="КР"; else TYPE_STR="Самолет"; fi
            
            MSG="Обнаружен $TYPE_STR ID:$ID с координатами $CUR_X $CUR_Y"
            echo "[$ZRDN_NAME] $TIMESTAMP $MSG"
            echo "$(date +%d.%m) $TIMESTAMP $ZRDN_NAME $MSG" >> "$MESSAGES_LOG"

            # ЛОГИКА СТРЕЛЬБЫ
            if [ "$CURRENT_AMMO" -gt 0 ]; then
                # ТЗ: Для попытки уничтожения цели необходимо создать файл в каталоге Destroy
                echo "$ZRDN_NAME" > "$DESTROY_DIR/$ID"
                ((CURRENT_AMMO--))
                
                MSG_FIRE="Произведен пуск по ID:$ID. Остаток ракет: $CURRENT_AMMO"
                echo "[$ZRDN_NAME] $TIMESTAMP $MSG_FIRE"
                echo "$(date +%d.%m) $TIMESTAMP $ZRDN_NAME $MSG_FIRE" >> "$MESSAGES_LOG"

                if [ "$CURRENT_AMMO" -eq 0 ]; then
                    MSG_EMPTY="ВНИМАНИЕ! БОЕКОМПЛЕКТ ИСЧЕРПАН. ПЕРЕХОД В РЕЖИМ ОБНАРУЖЕНИЯ."
                    echo "[$ZRDN_NAME] $MSG_EMPTY"
                    echo "$(date +%d.%m) $TIMESTAMP $ZRDN_NAME $MSG_EMPTY" >> "$MESSAGES_LOG"
                fi
            fi

            REPORTED_IDS[$ID]=1
        fi

        # Патч: обновление координат
        PREV_X[$ID]=$CUR_X
        PREV_Y[$ID]=$CUR_Y
    done

    # Очистка памяти
    for id in "${!PREV_X[@]}"; do
        if [[ -z "${SEEN_NOW[$id]}" ]]; then
            unset PREV_X[$id] PREV_Y[$id] REPORTED_IDS[$id]
        fi
    done
    unset SEEN_NOW

    sleep 1
done