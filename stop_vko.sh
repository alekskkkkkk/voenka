#!/bin/bash

# Определяем директорию, где лежит скрипт
SOURCE_DIR=$(dirname "$(readlink -f "$0")")

echo "=== ОСТАНОВКА СИСТЕМЫ ВКО ==="

# 1. Поиск и остановка процессов по PID-файлам
# Скрипт ищет все файлы с расширением .pid в текущей папке
PID_FILES=$(ls "$SOURCE_DIR"/*.pid 2>/dev/null)

if [ -z "$PID_FILES" ]; then
    echo "Активных PID-файлов не найдено. Возможно, система уже остановлена."
else
    for pid_file in $PID_FILES; do
        PID=$(cat "$pid_file")
        NAME=$(basename "$pid_file" .pid)
        
        # Проверяем, существует ли процесс с таким PID
        if kill -0 "$PID" 2>/dev/null; then
            echo "Завершение работы $NAME (PID: $PID)..."
            kill "$PID"
            
            # Ждем до 2 секунд, пока процесс реально исчезнет
            COUNT=0
            while kill -0 "$PID" 2>/dev/null && [ $COUNT -lt 20 ]; do
                sleep 0.1
                ((COUNT++))
            done
        else
            echo "Процесс $NAME (PID: $PID) уже не активен."
        fi
        
        # Удаляем файл идентификатора
        rm -f "$pid_file"
    done
fi

# 2. Остановка генератора целей
echo "Остановка генератора целей..."
pkill -f "GenTargets.sh"

# 3. Дополнительная страховка (на случай, если PID-файл был удален вручную)
# Принудительно ищем и завершаем оставшиеся скрипты по маскам имен
pkill -f "rls[1-3].sh"
pkill -f "zrdn[1-3].sh"
pkill -f "spro.sh"

echo "Все компоненты ВКО и генератор целей успешно остановлены."