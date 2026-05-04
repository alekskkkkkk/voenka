#!/bin/bash

if [[ "$OSTYPE" != "linux-gnu"* || -z "$BASH_VERSION" || $EUID -eq 0 ]]; then exit 1; fi

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "$SOURCE_DIR/config.cfg" ]; then
    source "$SOURCE_DIR/config.cfg"
else
    exit 1
fi


RLS_NAME=$RLS2_NAME
RLS_X=$RLS2_X
RLS_Y=$RLS2_Y
RLS_R=$RLS2_R
RLS_AZ=$RLS2_AZIMUTH
RLS_FOV=$RLS2_FOV
PID_FILE="$SOURCE_DIR/rls_2.pid"


MESSAGES_LOG="$SOURCE_DIR/vko_messages.log"

ENC_LOG="$SOURCE_DIR/${RLS_NAME}_enc.log"

TARGETS_DIR="/tmp/GenTargets/Targets"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then exit 1; fi
fi
echo $$ > "$PID_FILE"
trap "rm -f $PID_FILE; exit" INT TERM EXIT



write_log() {
    local ts="$1"
    local msg="$2"
    local log_line="$(date +%d.%m) $ts $RLS_NAME $msg"

   
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
    local dx=$((tx - RLS_X))
    local dy=$((ty - RLS_Y))
    
    local dist=$(echo "scale=0; sqrt($dx*$dx + $dy*$dy)" | bc -l)
    if [ "$dist" -gt "$RLS_R" ]; then return 1; fi

    local angle=$(echo "scale=4; a2=$dy/$dx; if($dx<0) { if($dy>=0) { a($dy/$dx)*57.29+180 } else { a($dy/$dx)*57.29-180 } } else { a($dy/$dx)*57.29 }" | bc -l)
    angle=$(echo "if($angle < 0) $angle + 360 else $angle" | bc -l)

    local diff=$(echo "d = $angle - $RLS_AZ; if(d < 0) d = -d; if(d > 180) d = 360 - d; d" | bc -l)
    local half_fov=$(echo "$RLS_FOV / 2" | bc -l)

    if (( $(echo "$diff <= $half_fov" | bc -l) )); then return 0; else return 1; fi
}

get_dist_to_spro() {
    local tx=$1 ty=$2
    local dx=$((tx - SPRO_X))
    local dy=$((ty - SPRO_Y))
    echo "scale=0; sqrt($dx*$dx + $dy*$dy)" | bc -l
}

declare -A PREV_X PREV_Y
declare -A REPORTED_IDS

echo "[$RLS_NAME] Станция запущена. Ждем появления целей..."

while true; do
    FILES=$(ls -t "$TARGETS_DIR" 2>/dev/null | head -n 50)
    declare -A SEEN_NOW
    
    for file in $FILES; do
        ID=$(decrypt_id "$file")
        [[ -z "$ID" ]] && continue
        
        
        DATA=$(head -n 1 "$TARGETS_DIR/$file" 2>/dev/null)
        CUR_X=$(echo "$DATA" | grep -oP 'X:\s*\K\d+')
        CUR_Y=$(echo "$DATA" | grep -oP 'Y:\s*\K\d+')

        if [[ -z "$CUR_X" || -z "$CUR_Y" ]]; then continue; fi
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
        
        if [ "$V" -ge 8000 ]; then
            TIMESTAMP=$(date +"%H:%M:%S:%3N")
            MSG="Обнаружена цель ID:$ID с координатами $CUR_X $CUR_Y"
            
            echo "[$RLS_NAME] $TIMESTAMP $MSG"
           
            write_log "$TIMESTAMP" "$MSG"

            D1=$(get_dist_to_spro "${PREV_X[$ID]}" "${PREV_Y[$ID]}")
            D2=$(get_dist_to_spro "$CUR_X" "$CUR_Y")

            if (( $(echo "$D2 < $D1" | bc -l) )); then
                MSG_SPRO="Цель ID:$ID движется в направлении СПРО"
                echo "[$RLS_NAME] $TIMESTAMP $MSG_SPRO"
                write_log "$TIMESTAMP" "$MSG_SPRO"
            fi

            REPORTED_IDS[$ID]=1
        fi
        PREV_X[$ID]=$CUR_X
        PREV_Y[$ID]=$CUR_Y
    done

    for id in "${!PREV_X[@]}"; do
        if [[ -z "${SEEN_NOW[$id]}" ]]; then
            unset PREV_X[$id] PREV_Y[$id] REPORTED_IDS[$id]
        fi
    done
    unset SEEN_NOW

    sleep 1
done