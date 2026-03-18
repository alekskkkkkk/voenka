#!/bin/bash
BUS="/tmp/bus"
AIR_FILE="/tmp/air.txt"
DDIR="/tmp/GenTargets/Destroy"
MY_X=5000000; MY_Y=5000000 # Координаты дивизиона
RADIUS=1500000             # 1500 км (в единицах карты)
AMMO=20

while true; do
    if [ "$AMMO" -le 0 ]; then echo "ZRDN | БК ПУСТ!" >> "$BUS"; sleep 10; AMMO=20; continue; fi
    
    while read -r id type x y v px py; do
        [[ "$type" == "ББ_БР" || "$v" -eq 0 ]] && continue
        
        # Считаем расстояние до цели по Пифагору
        DIST=$(echo "scale=0; sqrt(($x - $MY_X)^2 + ($y - $MY_Y)^2)" | bc -l)

        if [ "$DIST" -le "$RADIUS" ]; then
            echo "ZRDN | ЦЕЛЬ В ЗОНЕ! ID:$id Дистанция: $DIST" >> "$BUS"
            # Выстрел
            echo "ZRDN_FIRE" > "$DDIR/$id"
            ((AMMO--))
            echo "ZRDN | ПУСК по $id! Осталось ракет: $AMMO" >> "$BUS"
            sleep 0.5 # Чтобы не выстрелить все ракеты в одну цель за секунду
        fi
    done < "$AIR_FILE"
    sleep 1
done