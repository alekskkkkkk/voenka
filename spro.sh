#!/bin/bash
BUS="/tmp/bus"
AIR_FILE="/tmp/air.txt"
DDIR="/tmp/GenTargets/Destroy"
OBJ_X=5000000; OBJ_Y=4000000 # Координаты Москвы
SAFE_RADIUS=1000000          # Радиус защиты 1000 км
AMMO=10

while true; do
    if [ "$AMMO" -le 0 ]; then echo "SPRO | БК ПУСТ!" >> "$BUS"; sleep 10; AMMO=10; continue; fi
    
    while read -r id type x y v px py; do
        [[ "$type" != "ББ_БР" || "$v" -eq 0 ]] && continue

        # Расстояние от ЦЕЛИ до ОБЪЕКТА
        DIST_TO_OBJ=$(echo "scale=0; sqrt(($x - $OBJ_X)^2 + ($y - $OBJ_Y)^2)" | bc -l)

        if [ "$DIST_TO_OBJ" -le "$SAFE_RADIUS" ]; then
            echo "SPRO | УГРОЗА ОБЪЕКТУ! ББ_БР $id на дистанции $DIST_TO_OBJ" >> "$BUS"
            echo "SPRO_SYSTEM" > "$DDIR/$id"
            ((AMMO--))
            echo "SPRO | ПЕРЕХВАТ $id выполнен. Ракет: $AMMO" >> "$BUS"
        fi
    done < "$AIR_FILE"
    sleep 1
done