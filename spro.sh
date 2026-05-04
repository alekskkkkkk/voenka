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

MESSAGES_LOG="$SOURCE_DIR/vko_messages.log"

ENC_LOG="$SOURCE_DIR/${SPRO_NAME}_enc.log"

TARGETS_DIR="/tmp/GenTargets/Targets"
DESTROY_DIR="/tmp/GenTargets/Destroy"

mkdir -p "$DESTROY_DIR"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then exit 1; fi
fi
echo $$ > "$PID_FILE"
trap "rm -f $PID_FILE; exit" INT TERM EXIT


write_log() {
    local ts="$1"
    local msg="$2"
    local log_line="$(date +%d.%m) $ts $SPRO_NAME $msg"


    echo "$log_line" >> "$MESSAGES_LOG"
    
    
    local encoded=$(echo -n "$log_line" | base64 -w 0 | rev)
    echo "$encoded" >> "$ENC_LOG"
}

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
    
  
    for file in $FILES; do
        ID=$(decrypt_id "$file")
        [[ -n "$ID" ]] && SEEN_NOW[$ID]="$file"
    done

    
    for target_id in "${!FIRED_TARGETS[@]}"; do
        if [[ -z "${SEEN_NOW[$target_id]}" ]]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            MSG_HIT="ПОДТВЕРЖДЕНО: БР ID:$target_id УНИЧТОЖЕНА (пропала с радаров)!"
            echo "[$SPRO_NAME] $TIMESTAMP $MSG_HIT"
            write_log "$TIMESTAMP" "$MSG_HIT"
            unset FIRED_TARGETS[$target_id]
        fi
    done

    
    for ID in "${!SEEN_NOW[@]}"; do
        file="${SEEN_NOW[$ID]}"
        
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

        
        if [[ -n "${FIRED_TARGETS[$ID]}" ]]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            if [ "$DX" -eq 0 ] && [ "$DY" -eq 0 ]; then
                MSG_HIT="ПОДТВЕРЖДЕНО: БР ID:$ID УНИЧТОЖЕНА!"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_HIT"
                write_log "$TIMESTAMP" "$MSG_HIT"
            else
                MSG_MISS="ПРОМАХ! БР ID:$ID продолжает движение."
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_MISS"
                write_log "$TIMESTAMP" "$MSG_MISS"
                unset REPORTED_IDS[$ID] 
            fi
            unset FIRED_TARGETS[$ID]
        fi

       
        if [ "$DX" -eq 0 ] && [ "$DY" -eq 0 ]; then
            PREV_X[$ID]=$CUR_X
            PREV_Y[$ID]=$CUR_Y
            continue
        fi
        
        [[ -n "${REPORTED_IDS[$ID]}" ]] && continue

        V=$(echo "scale=0; sqrt($DX*$DX + $DY*$DY)" | bc -l)
        V=${V%.*}

        
        if [ "$V" -ge 8000 ]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            TYPE_STR="БР"
            
           
            if [ "$CURRENT_AMMO" -le 0 ]; then
                MSG_NO_AMMO="ВНИМАНИЕ! $TYPE_STR ID:$ID в зоне ответственности, НО ПРОТИВОРАКЕТЫ ОТСУТСТВУЮТ!"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_NO_AMMO"
                write_log "$TIMESTAMP" "$MSG_NO_AMMO"
                REPORTED_IDS[$ID]=1
                
            
            else
                MSG="Обнаружена $TYPE_STR ID:$ID с координатами $CUR_X $CUR_Y"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG"
                write_log "$TIMESTAMP" "$MSG"
                
                echo "$SPRO_NAME" > "$DESTROY_DIR/$ID"
                ((CURRENT_AMMO--))
                
                FIRED_TARGETS[$ID]=1
                REPORTED_IDS[$ID]=1
                
                MSG_FIRE="Произведен пуск противоракеты по ID:$ID. Остаток: $CURRENT_AMMO"
                echo "[$SPRO_NAME] $TIMESTAMP $MSG_FIRE"
                write_log "$TIMESTAMP" "$MSG_FIRE"

                if [ "$CURRENT_AMMO" -eq 0 ]; then
                    MSG_EMPTY="ВНИМАНИЕ! БОЕКОМПЛЕКТ ПРО ИСЧЕРПАН."
                    echo "[$SPRO_NAME] $TIMESTAMP $MSG_EMPTY"
                    write_log "$TIMESTAMP" "$MSG_EMPTY"
                fi
            fi
        fi

        PREV_X[$ID]=$CUR_X
        PREV_Y[$ID]=$CUR_Y
    done

    
    for id in "${!PREV_X[@]}"; do
        if [[ -z "${SEEN_NOW[$id]}" ]]; then
            unset PREV_X[$id] PREV_Y[$id] REPORTED_IDS[$id]
        fi
    done

    sleep 1
done