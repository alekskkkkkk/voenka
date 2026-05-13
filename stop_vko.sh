#!/bin/bash


SOURCE_DIR=$(dirname "$(readlink -f "$0")")

echo "=== ОСТАНОВКА СИСТЕМЫ ВКО ==="


PID_FILES=$(ls "$SOURCE_DIR"/*.pid 2>/dev/null)

if [ -z "$PID_FILES" ]; then
    echo "Активных PID-файлов не найдено. Возможно, система уже остановлена."
else
    for pid_file in $PID_FILES; do
        PID=$(cat "$pid_file")
        NAME=$(basename "$pid_file" .pid)
        
        
        if kill -0 "$PID" 2>/dev/null; then
            echo "Завершение работы $NAME (PID: $PID)..."
            kill "$PID"
            
            
            COUNT=0
            while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 20 ]; do
                sleep 0.1
                ((COUNT++))
            done
        else
            echo "Процесс $NAME (PID: $PID) уже не активен."
        fi
        
       
        rm -f "$pid_file"
    done
fi


echo "Остановка генератора целей..."
pkill -f "GenTargets.sh"


pkill -f "rls[1-3].sh"
pkill -f "zrdn[1-3].sh"
pkill -f "spro.sh"

echo "Все компоненты ВКО и генератор целей успешно остановлены."