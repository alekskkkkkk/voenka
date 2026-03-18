#!/bin/bash
BUS="/tmp/bus"
AIR_FILE="/tmp/air.txt"
# Настройки РЛС-2 (Дарьял)
MY_X=8000000; MY_Y=7000000; MY_AZIMUTH=45 
declare -A REPORTED

while true; do
    [ ! -f "$AIR_FILE" ] && sleep 1 && continue
    while read -r id type x y v px py; do
        [[ "$type" == "АНАЛИЗ" || -n "${REPORTED[$id]}" ]] && continue

        # Считаем угол цели относительно РЛС
        DX=$(($x - $MY_X)); DY=$(($y - $MY_Y))
        # Математика угла (atan2)
        T_ANGLE=$(echo "scale=2; a=a($DY/$DX); if($DX<0) a+=3.14; a*180/3.14" | bc -l 2>/dev/null)
        # Разница с азимутом РЛС (в пределах 60 градусов в обе стороны)
        DIFF=$(echo "d=$T_ANGLE - $MY_AZIMUTH; if(d<0) d=-d; if(d>180) d=360-d; d" | bc -l)

        if (( $(echo "$DIFF <= 60" | bc -l) )); then
            echo "RLS2 | Вижу $id ($type) под углом ${T_ANGLE} | Коорд: $x $y" >> "$BUS"
            REPORTED[$id]=1
        fi
    done < "$AIR_FILE"
    sleep 1
done