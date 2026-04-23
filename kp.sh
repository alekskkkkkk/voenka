#!/bin/bash

LOG_FILE="/tmp/vko_messages.log"
DB_FILE="vko_base.txt" 
#!/bin/bash

SOURCE_DIR=$(dirname "$(readlink -f "$0")")
if [ -f "$SOURCE_DIR/config.cfg" ]; then source "$SOURCE_DIR/config.cfg"; fi



check_status() {
    local pid_file="$SOURCE_DIR/$1.pid"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "АКТИВЕН (PID: $pid)"
        else
            echo "НЕ АКТИВЕН (Процесс упал)"
        fi
    else
        echo "НЕ ЗАПУЩЕН"
    fi
}

echo "=== МОНИТОРИНГ СОСТОЯНИЯ ОБЪЕКТОВ ВКО ==="
printf "%-10s | %-20s\n" "ОБЪЕКТ" "СТАТУС"
echo "------------------------------------------"
printf "%-10s | %-20s\n" "RLS_1" "$(check_status rls_1)"
printf "%-10s | %-20s\n" "RLS_2" "$(check_status rls_2)"
printf "%-10s | %-20s\n" "RLS_3" "$(check_status rls_3)"
printf "%-10s | %-20s\n" "ZRDN_1" "$(check_status zrdn_1)"
printf "%-10s | %-20s\n" "ZRDN_2" "$(check_status zrdn_2)"
printf "%-10s | %-20s\n" "ZRDN_3" "$(check_status zrdn_3)"
printf "%-10s | %-20s\n" "SPRO" "$(check_status spro)"
echo "------------------------------------------"

if [ ! -f "$LOG_FILE" ]; then
    echo "Ошибка: Лог-файл $LOG_FILE не найден. Сначала запустите систему ВКО."
    exit 1
fi


cp "$LOG_FILE" "$DB_FILE"

echo "=== КОМАНДНЫЙ ПУНКТ (КП) - АНАЛИЗ БАЗЫ ДАННЫХ ==="
echo "Текстовая БД обновлена: $DB_FILE"
echo "--------------------------------------------------------"
echo "СТАТИСТИКА БОЕВЫХ ДЕЙСТВИЙ:"
echo "--------------------------------------------------------"

# 1. Расход боекомплекта
echo "[1] Расход боекомплекта (Количество пусков по системам):"
echo "СИСТЕМА     ПУСКОВ"
echo "------------------"
grep "Произведен пуск" "$DB_FILE" | grep -oE "ZRDN_[1-3]|SPRO" | sort | uniq -c | sort -nr | awk '{printf "%-10s %s\n", $2, $1}'
echo ""

# 2. Активность радаров
echo "[2] Активность систем (Количество обнаруженных целей):"
echo "СИСТЕМА     ОБНАРУЖЕНО"
echo "----------------------"
grep -E "Обнаружена цель|Обнаружена БР|Обнаружен Самолет|Обнаружен КР" "$DB_FILE" | grep -oE "RLS_[1-3]|ZRDN_[1-3]|SPRO" | sort | uniq -c | sort -nr | awk '{printf "%-10s %s\n", $2, $1}'
echo ""

# 3. Ситуация с боекомплектом
echo "[3] Ситуация с боекомплектом (Кто исчерпал боезапас):"
echo "СИСТЕМА"
echo "--------------------"
grep "БОЕКОМПЛЕКТ ИСЧЕРПАН" "$DB_FILE" | grep -oE "ZRDN_[1-3]|SPRO" | uniq
echo ""

# 4. Общая статистика системы ПРО
echo "[4] Общая статистика системы СПРО (Омск):"
SPRO_FIRE=$(grep "Произведен пуск" "$DB_FILE" | grep "SPRO" | wc -l)
SPRO_DETECT=$(grep "Обнаружена БР" "$DB_FILE" | grep "SPRO" | wc -l)
echo "Обнаружено баллистических ракет: $SPRO_DETECT"
echo "Выпущено противоракет: $SPRO_FIRE"
echo "--------------------------------------------------------"