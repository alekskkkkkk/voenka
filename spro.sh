#!/bin/bash

if [[ "$OSTYPE" != "linux-gnu"* || -z "$BASH_VERSION" || $EUID -eq 0 ]]; then exit 1; fi

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "$SOURCE_DIR/config.cfg" ]; then
    source "$SOURCE_DIR/config.cfg"
else
    exit 1
fi

SPRO_NAME=$SPRO_NAME
SPRO_X=$SPRO_X
SPRO_Y=$SPRO_Y
SPRO_R=$SPRO_R
CURRENT_AMMO=$SPRO_AMMO
PID_FILE="$SOURCE_DIR/spro.pid"
# ==========================================
MESSAGES_LOG="$SOURCE_DIR/vko_messages.log"
TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

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

check_visibility() {
    local tx=$1 ty=$2
    local dx=$((tx - SPRO_X))
    local dy=$((ty - SPRO_Y))
    local dist=$(echo "scale=0; sqrt($dx*$dx + $dy*$dy)" | bc -l)
    if [ "$dist" -le "$SPRO_R" ]; then return 0; else return 1; fi
}

declare -A PREV_X PREV_Y
declare -A REPORTED_IDS
declare -A FIRED_TARGETS 

echo "[$SPRO_NAME] Система ПРО запущена. Противоракет: $CURRENT_AMMO. Ждем БР..."

while true; do
    FILES=$(ls -t "$TARGETS_DIR" 2>/dev/null | head -n 50)
    declare -A SEEN_NOW
    
    # ШАГ 1: Собираем текущие цели
    for file in $FILES; do
        ID=$(decrypt_id "$file")
        [[ -n "$ID" ]] && SEEN_NOW[$ID]="$file"
    done

    # ШАГ 2: ПРОВЕРКА ИСЧЕЗНУВШИХ ФАЙЛОВ (Если генератор всё же удалил файл)
    for target_id in "${!FIRED_TARGETS[@]}"; do
        if [[ -z "${SEEN_NOW[$target_id]}" ]]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            MSG_HIT="ПОДТВЕРЖДЕНО: БР ID:$target_id УНИЧТОЖЕНА (пропала с радаров)!"
            echo "[$SPRO_NAME] $TIMESTAMP $MSG_HIT"
            echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_HIT" >> "$MESSAGES_LOG"
            unset FIRED_TARGETS[$target_id]
        fi
    done

    # ШАГ 3: ПОИСК НОВЫХ ЦЕЛЕЙ И ПУСК
    for ID in "${!SEEN_NOW[@]}"; do
        file="${SEEN_NOW[$ID]}"
        
        # 2>/dev/null предотвращает ошибку, если генератор успел удалить файл
        DATA=$(head -n 1 "$TARGETS_DIR/$file" 2>/dev/null)
        CUR_X=$(echo "$DATA" | grep -oP 'X:\s*\K\d+')
        CUR_Y=$(echo "$DATA" | grep -oP 'Y:\s*\K\d+')

        if [[ -z "$CUR_X" || -z "$CUR_Y" || ${#CUR_X} -lt 5 || ${#CUR_Y} -lt 5 ]]; then continue; fi
        if ! check_visibility "$CUR_X" "$CUR_Y"; then continue; fi
        
        if [[ -z "${PREV_X[$ID]}" ]]; then
            PREV_X[$ID]=$CUR_X
            PREV_Y[$ID]=$CUR_Y
            continue
        fi

        DX=$((CUR_X - PREV_X[$ID]))
        DY=$((CUR_Y - PREV_Y[$ID]))

        # --- НОВАЯ ЛОГИКА: ПРОВЕРКА ПОПАДАНИЯ ПО ОСТАНОВКЕ ЦЕЛИ ---
        if [[ -n "${FIRED_TARGETS[$ID]}" ]]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            if [ "$DX" -eq 0 ] && [ "$DY" -eq 0 ]; then
                MSG_HIT="ПОДТВЕРЖДЕНО: БР ID:$ID УНИЧТОЖЕНА!"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_HIT"
                echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_HIT" >> "$MESSAGES_LOG"
            else
                MSG_MISS="ПРОМАХ! БР ID:$ID продолжает движение."
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_MISS"
                echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_MISS" >> "$MESSAGES_LOG"
                unset REPORTED_IDS[$ID] # Снимаем флаг, разрешаем второй пуск
            fi
            unset FIRED_TARGETS[$ID]
        fi

        # Пропускаем "мертвые" (остановившиеся) цели, чтобы не тратить ракеты впустую
        if [ "$DX" -eq 0 ] && [ "$DY" -eq 0 ]; then
            PREV_X[$ID]=$CUR_X
            PREV_Y[$ID]=$CUR_Y
            continue
        fi
        
        [[ -n "${REPORTED_IDS[$ID]}" ]] && continue

        V=$(echo "scale=0; sqrt($DX*$DX + $DY*$DY)" | bc -l)
        V=${V%.*}

        # СПРО бьет ТОЛЬКО БР
        if [ "$V" -ge 8000 ]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            TYPE_STR="БР"
            
            # ЛОГИКА: ЦЕЛЬ В ЗОНЕ, НО НЕТ БК
            if [ "$CURRENT_AMMO" -le 0 ]; then
                MSG_NO_AMMO="ВНИМАНИЕ! $TYPE_STR ID:$ID в зоне ответственности, НО ПРОТИВОРАКЕТЫ ОТСУТСТВУЮТ!"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_NO_AMMO"
                echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_NO_AMMO" >> "$MESSAGES_LOG"
                REPORTED_IDS[$ID]=1
                
            # ЛОГИКА: СТРЕЛЬБА
            else
                MSG="Обнаружена $TYPE_STR ID:$ID с координатами $CUR_X $CUR_Y"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG"
                echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG" >> "$MESSAGES_LOG"
                
                echo "$SPRO_NAME" > "$DESTROY_DIR/$ID"
                ((CURRENT_AMMO--))
                
                FIRED_TARGETS[$ID]=1 # ДОБАВЛЯЕМ ЦЕЛЬ В ОЧЕРЕДЬ ПРОВЕРКИ
                REPORTED_IDS[$ID]=1
                
                MSG_FIRE="Произведен пуск противоракеты по ID:$ID. Остаток: $CURRENT_AMMO"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_FIRE"
                echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_FIRE" >> "$MESSAGES_LOG"

                if [ "$CURRENT_AMMO" -eq 0 ]; then
                    MSG_EMPTY="ВНИМАНИЕ! БОЕКОМПЛЕКТ ПРО ИСЧЕРПАН."
                    echo "[$SPRO_NAME] $TIMESTAMP $MSG_EMPTY"
                    echo "$(date +%d.%m) $TIMESTAMP $SPRO_NAME $MSG_EMPTY" >> "$MESSAGES_LOG"
                fi
            fi
        fi

        PREV_X[$ID]=$CUR_X
        PREV_Y[$ID]=$CUR_Y
    done

    # Очистка памяти
    for id in "${!PREV_X[@]}"; do
        if [[ -z "${SEEN_NOW[$id]}" ]]; then
            unset PREV_X[$id] PREV_Y[$id] REPORTED_IDS[$id]
        fi
    done

    sleep 1
done