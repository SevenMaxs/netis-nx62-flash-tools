#!/bin/sh

# ==================================================================================
# ╔═══════════════════════════════════════════════════════════════════════════════╗
# ║              MTD Backup Script for Netis NX62 / Netcore N60 Pro               ║
# ╚═══════════════════════════════════════════════════════════════════════════════╝
# ==================================================================================
# Автор:  SevenMaxs (2026)
# ----------------------------------------------------------------------------------
# 📋 ОПИСАНИЕ:
#   Скрипт автоматически создает полную резервную копию всех MTD разделов
#   роутера, включая загрузчик, прошивку, factory данные и конфигурации.
# ----------------------------------------------------------------------------------
# 🔧 ФУНКЦИОНАЛ:
#   ✓ Дамп всех MTD разделов (включая весь flash чип)
#   ✓ Сохранение информации о разделах
#   ✓ Создание контрольных сумм MD5 для проверки целостности
#   ✓ Автоматическая архивация в TAR.GZ
#   ✓ Детальный отчет о бекапе
# ----------------------------------------------------------------------------------
# 📌 ПОДДЕРЖИВАЕМЫЕ МОДЕЛИ:
#   • Netis NX62
#   • Netcore N60 Pro
# ----------------------------------------------------------------------------------
# 🔗 GitHub: https://github.com/SevenMaxs/netis-nx62-flash-tools
# ==================================================================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Переменные
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEVICE_MODEL="Netis_NX62"
ARCHIVE_NAME="${DEVICE_MODEL}_backup_${TIMESTAMP}.tar.gz"
FINAL_ARCHIVE="/tmp/tmp/${ARCHIVE_NAME}"
BACKUP_DIR="/tmp/tmp/${DEVICE_MODEL}_mtd_backup_${TIMESTAMP}"
TEMP_DIR="/tmp/tmp/${DEVICE_MODEL}_temp_${TIMESTAMP}"

# Создаем директории
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/mtd_dumps"
mkdir -p "$BACKUP_DIR/mtd_info"
mkdir -p "$TEMP_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   MTD Backup Tool for Netis NX62     ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Директория: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "Временная директория: ${YELLOW}$TEMP_DIR${NC}"
echo -e "Финальный архив: ${YELLOW}$FINAL_ARCHIVE${NC}"
echo -e "${BLUE}========================================${NC}\n"

# 1. Сохраняем информацию о разделах
echo -e "${GREEN}[1/5]${NC} Сохранение информации о разделах MTD..."

# Основная информация о разделах
cat /proc/mtd > "$BACKUP_DIR/mtd_info/proc_mtd.txt"
cat /proc/partitions > "$BACKUP_DIR/mtd_info/partitions.txt"

# Форматированный список разделов
{
    echo "MTD Partition Table - Netis NX62"
    echo "Дата: $(date)"
    echo ""
    echo "Device    Size       EraseSize  Name                 Size(Bytes)"
    echo "-------- ---------- ---------- -------------------- ----------"
} > "$BACKUP_DIR/mtd_info/mtd_list.txt"

# Добавляем информацию о каждом разделе
while read -r line; do
    echo "$line" | grep -q "dev:" && continue
    dev=$(echo "$line" | awk -F':' '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    erasesize=$(echo "$line" | awk '{print $3}')
    name=$(echo "$line" | awk '{print $4}' | tr -d '"')
    size_bytes=$((0x$size))
    printf "%-8s %-10s %-10s %-20s %d\n" "$dev" "$size" "$erasesize" "$name" "$size_bytes" >> "$BACKUP_DIR/mtd_info/mtd_list.txt"
done < /proc/mtd

echo "" >> "$BACKUP_DIR/mtd_info/mtd_list.txt"

# 2. Получаем детальную информацию о каждом MTD устройстве
echo -e "${GREEN}[2/5]${NC} Получение информации о MTD устройствах..."

while read -r line; do
    echo "$line" | grep -q "dev:" && continue

    dev=$(echo "$line" | awk -F':' '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    erasesize=$(echo "$line" | awk '{print $3}')
    name=$(echo "$line" | awk '{print $4}' | tr -d '"')
    size_bytes=$((0x$size))

    # Детальная информация по каждому разделу
    {
        echo "========================================="
        echo "MTD Device Information"
        echo "========================================="
        echo "Device:      $dev"
        echo "Name:        $name"
        echo "Size (hex):  $size"
        echo "Size (dec):  $size_bytes bytes"
        echo "Size (hr):   $((size_bytes / 1048576))MB"
        echo "Erase Size:  $erasesize"
        echo "Device path: /dev/$dev"
        echo "Read-only:   /dev/${dev}ro"
        echo "========================================="
    } > "$BACKUP_DIR/mtd_info/${dev}_${name}_info.txt"

done < /proc/mtd

# Выводим таблицу разделов
echo -e "\n${YELLOW}Найденные разделы:${NC}"
echo -e "${BLUE}----------------------------------------${NC}"
printf "${YELLOW}%-8s %-10s %-12s %-20s${NC}\n" "Device" "Size" "EraseSize" "Name"
echo -e "${BLUE}----------------------------------------${NC}"

# Пропускаем первые 5 строки (заголовок, дата, пустая строка, заголовки колонок)
tail -n +6 "$BACKUP_DIR/mtd_info/mtd_list.txt" | while read -r line; do
    # Пропускаем пустые строки
    [ -z "$line" ] && continue
    
    dev=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    erasesize=$(echo "$line" | awk '{print $3}')
    name=$(echo "$line" | awk '{print $4}')
    
    # Подсветка важных разделов
    case "$name" in
        *BL2*|*FIP*|*Factory*|*spi*)
            printf "${GREEN}%-8s %-10s %-12s %-20s${NC}\n" "$dev" "$size" "$erasesize" "$name"
            ;;
        *ubi*)
            printf "${CYAN}%-8s %-10s %-12s %-20s${NC}\n" "$dev" "$size" "$erasesize" "$name"
            ;;
        *)
            printf "%-8s %-10s %-12s %-20s\n" "$dev" "$size" "$erasesize" "$name"
            ;;
    esac
done
echo -e "${BLUE}----------------------------------------${NC}\n"

# 3. Создаем общий отчет
{
    echo "========================================="
    echo "MTD Backup Report - Netis NX62"
    echo "========================================="
    echo "Дата: $(date)"
    echo "Устройство: $(cat /proc/sys/kernel/hostname 2>/dev/null || echo 'unknown')"
    echo "OpenWrt: $(cat /etc/openwrt_version 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Структура разделов:"
    echo "-----------------------------------------"
    cat "$BACKUP_DIR/mtd_info/proc_mtd.txt"
    echo ""
    echo "Размеры в байтах:"
    echo "-----------------------------------------"
    while read -r line; do
        echo "$line" | grep -q "dev:" && continue
        dev=$(echo "$line" | awk -F':' '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | awk '{print $4}' | tr -d '"')
        size_bytes=$((0x$size))
        echo "$dev ($name): $size_bytes bytes ($((size_bytes / 1048576)) MB)"
    done < /proc/mtd
    echo "========================================="
} > "$BACKUP_DIR/MTD_BACKUP_REPORT.txt"

# 4. Создаем файл контрольных сумм и сразу пишем заголовок
ALL_CHECKSUMS_FILE="$BACKUP_DIR/mtd_info/all_mtd_checksums.txt"
{
    echo "========================================="
    echo "MTD Partition Checksums - Netis NX62"
    echo "========================================="
    echo "Дата: $(date)"
    echo ""
    echo "MD5 Hash                             File Name"
    echo "------------------------------------ --------------------"
} > "$ALL_CHECKSUMS_FILE"

# 5. Дамп всех MTD разделов (ВКЛЮЧАЯ spi0.1)
echo -e "${GREEN}[3/5]${NC} Дамп MTD разделов (включая весь flash чип)..."
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"

# Счетчики
TOTAL_DUMPS=0
SUCCESS_DUMPS=0
FAILED_DUMPS=0
CHECKSUM_COUNT=0
CURRENT_NUM=0

# Подсчитываем общее количество разделов MTD
TOTAL_MTD=$(grep -c "^mtd[0-9]" /proc/mtd)

while read -r line; do
    echo "$line" | grep -q "dev:" && continue

    dev=$(echo "$line" | awk -F':' '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    name=$(echo "$line" | awk '{print $4}' | tr -d '"')
    
    mtd_device="/dev/${dev}"
    size_bytes=$((0x$size))
    size_kb=$((size_bytes / 1024))
    size_mb=$((size_bytes / 1048576))
    CURRENT_NUM=$((CURRENT_NUM + 1))
    
    # Формируем имена файлов
    dump_file="${TEMP_DIR}/${name}_${dev}.bin"
    md5_file="${TEMP_DIR}/${name}_${dev}.md5"
    archive_file="${BACKUP_DIR}/mtd_dumps/${name}_${dev}.tar.gz"
    
    TOTAL_DUMPS=$((TOTAL_DUMPS + 1))
    
    # Заголовок раздела
    echo -e "\n${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}▶ Раздел ${CURRENT_NUM}/${TOTAL_MTD}:${NC} ${YELLOW}${dev} (${name})${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BLUE}Размер:${NC}     $([ $size_mb -gt 0 ] && echo "${size_mb} MB" || echo "${size_kb} KB") ($size байт)"
    echo -e "  ${BLUE}Устройство:${NC} ${mtd_device}"
    echo -e "  ${BLUE}Архив:${NC}      $(basename $archive_file)"
    echo -e "  ${BLUE}Статус:${NC}     ${YELLOW}Чтение раздела...${NC}"
    
    # Дамп раздела
    if [ -c "$mtd_device" ]; then
        # Используем dd для дампа
        dd if="$mtd_device" of="$dump_file" bs=1024 count="$size_kb" 2>/dev/null
        
        if [ $? -eq 0 ] && [ -f "$dump_file" ]; then
            # Проверка размера
            if command -v stat >/dev/null 2>&1; then
                file_size=$(stat -c%s "$dump_file" 2>/dev/null)
            else
                file_size=$(wc -c < "$dump_file" 2>/dev/null | tr -d ' ')
            fi
            
            if [ "$file_size" -eq "$size_bytes" ]; then
                # Вычисляем MD5
                md5_hash=$(md5sum "$dump_file" | cut -d' ' -f1)
                
                # Сохраняем MD5 во временный файл
                echo "$md5_hash  $(basename $dump_file)" > "$md5_file"
                
                # Сразу добавляем контрольную сумму в общий файл
                echo "$md5_hash  ${name}_${dev}.bin" >> "$ALL_CHECKSUMS_FILE"
                CHECKSUM_COUNT=$((CHECKSUM_COUNT + 1))
                
                # Создаем README для этого раздела
                readme_file="${TEMP_DIR}/${name}_${dev}_readme.txt"
                {
                    echo "========================================="
                    echo "MTD Partition Dump - $name"
                    echo "========================================="
                    echo "Device:      $dev"
                    echo "Name:        $name"
                    echo "Date:        $(date)"
                    echo "Size (hex):  $size"
                    echo "Size (dec):  $size_bytes bytes"
                    echo "Size (hr):   $size_mb MB"
                    echo "MD5:         $md5_hash"
                    echo ""
                    echo "Restore command:"
                    echo "-----------------------------------------"
                    echo "mtd write ${name}_${dev}.bin $name"
                    echo ""
                    echo "Verify command:"
                    echo "-----------------------------------------"
                    echo "md5sum -c ${name}_${dev}.md5"
                    echo "========================================="
                } > "$readme_file"
                
                # Создаем архив с дампом, MD5 и README
                tar -czf "$archive_file" \
                    -C "$TEMP_DIR" "$(basename $dump_file)" \
                    -C "$TEMP_DIR" "$(basename $md5_file)" \
                    -C "$TEMP_DIR" "$(basename $readme_file)" 2>/dev/null
                
                # Проверяем что архив создан
                if [ -f "$archive_file" ]; then
                    # Удаляем временные файлы
                    rm -f "$dump_file" "$md5_file" "$readme_file"
                    
                    # Информация о результате
                    echo -e "  ${BLUE}Результат:${NC}  ${GREEN}✓ УСПЕШНО${NC}"
                    echo -e "  ${BLUE}MD5:${NC}        ${CYAN}${md5_hash:0:8}...${md5_hash: -8}${NC}"
                    
                    # Информация о размере архива
                    archive_size=$(du -h "$archive_file" | cut -f1)
                    echo -e "  ${BLUE}Архив:${NC}      ${YELLOW}${archive_size}${NC} (сжато)"
                    
                    if [ $size_mb -gt 10 ]; then
                        # Получаем размер архива безопасным способом
                        if command -v stat >/dev/null 2>&1; then
                            archive_bytes=$(stat -c%s "$archive_file" 2>/dev/null)
                        else
                            archive_bytes=$(wc -c < "$archive_file" 2>/dev/null | tr -d ' ')
                        fi
                        
                        # Проверяем что получили число
                        if [ -n "$archive_bytes" ] && [ "$archive_bytes" -gt 0 ] 2>/dev/null; then
                            compression=$(( (100 * archive_bytes) / size_bytes ))
                            echo -e "  ${BLUE}Сжатие:${NC}     ${YELLOW}${compression}%${NC} от оригинала"
                        else
                            echo -e "  ${BLUE}Сжатие:${NC}     ${YELLOW}${archive_size}${NC} (размер после сжатия)"
                        fi
                    fi
                    
                    SUCCESS_DUMPS=$((SUCCESS_DUMPS + 1))
                else
                    echo -e "  ${BLUE}Результат:${NC}   ${RED}✗ ОШИБКА АРХИВАЦИИ${NC}"
                    FAILED_DUMPS=$((FAILED_DUMPS + 1))
                    # Удаляем добавленную контрольную сумму
                    sed -i "/$md5_hash/d" "$ALL_CHECKSUMS_FILE" 2>/dev/null
                    CHECKSUM_COUNT=$((CHECKSUM_COUNT - 1))
                fi
            else
                echo -e "  ${BLUE}Результат:${NC}   ${RED}✗ НЕСООТВЕТСТВИЕ РАЗМЕРА${NC}"
                echo -e "  ${BLUE}Ожидалось:${NC}   $size_bytes байт"
                echo -e "  ${BLUE}Получено:${NC}    $file_size байт"
                FAILED_DUMPS=$((FAILED_DUMPS + 1))
                rm -f "$dump_file" 2>/dev/null
            fi
        else
            echo -e "  ${BLUE}Результат:${NC}   ${RED}✗ ОШИБКА ЧТЕНИЯ${NC}"
            FAILED_DUMPS=$((FAILED_DUMPS + 1))
            rm -f "$dump_file" 2>/dev/null
        fi
    else
        echo -e "  ${BLUE}Результат:${NC}   ${RED}✗ УСТРОЙСТВО НЕ НАЙДЕНО${NC}"
        FAILED_DUMPS=$((FAILED_DUMPS + 1))
    fi
    
    # Разделитель между разделами (кроме последнего)
    if [ $CURRENT_NUM -lt $TOTAL_MTD ]; then
        echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    fi
    
done < /proc/mtd

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}\n"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}\n"

# Завершаем файл контрольных сумм
{
    echo "----------------------------------------"
    echo ""
    echo "Всего записей: $CHECKSUM_COUNT"
    echo "========================================="
} >> "$ALL_CHECKSUMS_FILE"

echo -e "${GREEN}  Контрольные суммы сохранены: $CHECKSUM_COUNT записей${NC}"

# 6. Создаем финальный TAR.GZ архив
echo -e "${GREEN}[4/5]${NC} Создание финального TAR.GZ архива..."

# Создаем TAR.GZ архив
cd "$(dirname "$BACKUP_DIR")"
tar -czf "$FINAL_ARCHIVE" "$(basename "$BACKUP_DIR")" 2>/dev/null
cd - > /dev/null

# Проверяем что архив создался
if [ -f "$FINAL_ARCHIVE" ]; then
    ARCHIVE_SIZE=$(du -h "$FINAL_ARCHIVE" | cut -f1)
    echo -e "  ${GREEN}✓ TAR.GZ архив создан успешно${NC}"
    echo -e "  ${GREEN}  Размер: $ARCHIVE_SIZE${NC}"
else
    echo -e "${RED}  ✗ Не удалось создать TAR.GZ архив!${NC}"
fi

# 7. Очистка временных файлов
echo -e "${GREEN}[5/5]${NC} Очистка временных файлов..."

CLEANUP_SUCCESS=true
CLEANUP_MESSAGE=""

# Проверяем что финальный архив существует
if [ -f "$FINAL_ARCHIVE" ]; then
    # Проверяем размер архива
    ARCHIVE_SIZE_BYTES=$(stat -c%s "$FINAL_ARCHIVE" 2>/dev/null || wc -c < "$FINAL_ARCHIVE" 2>/dev/null)
    
    if [ "$ARCHIVE_SIZE_BYTES" -gt 1000000 ]; then  # Больше 1MB
        echo -e "  ${GREEN}✓ Финальный архив корректен (размер: $(du -h "$FINAL_ARCHIVE" | cut -f1))${NC}"
        
        # Проверяем содержимое архива
        echo -e "  ${YELLOW}  Проверка содержимого архива...${NC}"
        FILE_COUNT=$(tar -tzf "$FINAL_ARCHIVE" 2>/dev/null | wc -l)
        
        if [ "$FILE_COUNT" -gt 10 ]; then
            echo -e "  ${GREEN}  ✓ Архив содержит $FILE_COUNT файлов${NC}"
            
            # Удаляем временные директории
            if [ -d "$TEMP_DIR" ]; then
                rm -rf "$TEMP_DIR"
                echo -e "  ${GREEN}  ✓ Временная директория удалена: $(basename "$TEMP_DIR")${NC}"
            fi
            
            if [ -d "$BACKUP_DIR" ]; then
                rm -rf "$BACKUP_DIR"
                echo -e "  ${GREEN}  ✓ Директория бекапа удалена: $(basename "$BACKUP_DIR")${NC}"
            fi
            
            CLEANUP_MESSAGE="Все временные файлы успешно удалены"
        else
            echo -e "  ${RED}  ✗ Архив поврежден или пуст (только $FILE_COUNT файлов)!${NC}"
            CLEANUP_SUCCESS=false
            CLEANUP_MESSAGE="Архив поврежден, временные файлы сохранены"
        fi
    else
        echo -e "  ${RED}  ✗ Финальный архив слишком мал ($ARCHIVE_SIZE_BYTES байт)!${NC}"
        CLEANUP_SUCCESS=false
        CLEANUP_MESSAGE="Финальный архив поврежден, временные файлы сохранены"
    fi
else
    echo -e "  ${RED}  ✗ Финальный архив не найден!${NC}"
    CLEANUP_SUCCESS=false
    CLEANUP_MESSAGE="Финальный архив не найден, временные файлы сохранены"
fi

# Финальный отчет
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}         MTD БЕКАП ЗАВЕРШЕН!          ${NC}"
echo -e "${GREEN}========================================${NC}"

# Статус очистки
if [ "$CLEANUP_SUCCESS" = true ]; then
    echo -e "${GREEN}✅ $CLEANUP_MESSAGE${NC}"
else
    echo -e "${RED}❌ $CLEANUP_MESSAGE${NC}"
fi
echo -e ""

# Информация о финальном архиве
if [ -f "$FINAL_ARCHIVE" ]; then
    echo -e "📦 Финальный архив: ${YELLOW}$FINAL_ARCHIVE${NC}"
    echo -e "   Размер: ${YELLOW}$(du -h "$FINAL_ARCHIVE" | cut -f1)${NC}"
    echo -e "   MD5: ${YELLOW}$(md5sum "$FINAL_ARCHIVE" | cut -d' ' -f1)${NC}"
    echo -e "   Файлов в архиве: ${YELLOW}$(tar -tzf "$FINAL_ARCHIVE" 2>/dev/null | wc -l)${NC}"
else
    echo -e "📁 Директория бекапа: ${YELLOW}$BACKUP_DIR${NC}"
fi
echo -e ""

# Информация о разделах
echo -e "${CYAN}Статистика бекапа:${NC}"
echo -e "  • Всего разделов: ${YELLOW}$TOTAL_DUMPS${NC}"
echo -e "  • Успешно: ${GREEN}$SUCCESS_DUMPS${NC}"
echo -e "  • Ошибки: ${RED}$FAILED_DUMPS${NC}"
echo -e "  • Контрольные суммы: ${GREEN}$CHECKSUM_COUNT${NC}"
echo -e ""

# Информация о временных файлах
echo -e "${CYAN}Состояние файловой системы:${NC}"
if [ -d "$BACKUP_DIR" ]; then
    echo -e "  • Директория бекапа: ${YELLOW}СОХРАНЕНА${NC} - $(du -sh "$BACKUP_DIR" | cut -f1)"
else
    echo -e "  • Директория бекапа: ${GREEN}УДАЛЕНА${NC}"
fi

if [ -d "$TEMP_DIR" ]; then
    echo -e "  • Временная директория: ${YELLOW}СОХРАНЕНА${NC} - $(du -sh "$TEMP_DIR" | cut -f1)"
else
    echo -e "  • Временная директория: ${GREEN}УДАЛЕНА${NC}"
fi
echo -e ""

# Инструкция по скачиванию
echo -e "${CYAN}Скачайте архив на компьютер:${NC}"
if [ -f "$FINAL_ARCHIVE" ]; then
    echo -e "  ${YELLOW}scp -O useradmin@192.168.1.1:$FINAL_ARCHIVE ./${NC}"
else
    echo -e "  ${YELLOW}scp -O -r useradmin@192.168.1.1:$BACKUP_DIR ./${NC}"
    echo -e "  ${YELLOW}ssh useradmin@192.168.1.1 \"tar -czf - -C /tmp/tmp $(basename $BACKUP_DIR)\" > ./${ARCHIVE_NAME}${NC}"
fi
echo -e ""

# Проверка целостности
if [ -f "$FINAL_ARCHIVE" ]; then
    echo -e "${CYAN}Проверка целостности архива после скачивания:${NC}"
    echo -e "  ${YELLOW}md5sum -c <<< \"$(md5sum "$FINAL_ARCHIVE" | cut -d' ' -f1)  ${ARCHIVE_NAME}\"${NC}"
    echo -e "  ${YELLOW}tar -tzf ${ARCHIVE_NAME} | head -20${NC}"
fi
echo -e "${GREEN}========================================${NC}\n"

# Финальное сообщение
if [ "$CLEANUP_SUCCESS" = true ] && [ $SUCCESS_DUMPS -eq $TOTAL_DUMPS ]; then
    echo -e "${GREEN}🎉 БЕКАП ВЫПОЛНЕН ИДЕАЛЬНО!${NC}"
    echo -e "${GREEN}   Все $TOTAL_DUMPS разделов сохранены, временные файлы очищены${NC}"
    echo -e "${GREEN}   Финальный архив готов к скачиванию${NC}"
elif [ "$CLEANUP_SUCCESS" = true ]; then
    echo -e "${GREEN}📦 Бекап завершен, временные файлы очищены${NC}"
    echo -e "${YELLOW}   Но некоторые разделы не сохранились ($FAILED_DUMPS ошибок)${NC}"
    echo -e "${YELLOW}   Проверьте вывод выше для диагностики${NC}"
else
    echo -e "${YELLOW}⚠️  Бекап завершен с предупреждениями${NC}"
    echo -e "   Временные файлы сохранены в:"
    echo -e "   • $BACKUP_DIR"
    if [ -d "$TEMP_DIR" ]; then
        echo -e "   • $TEMP_DIR"
    fi
    echo -e ""
    echo -e "   Для ручной очистки после успешного скачивания:"
    echo -e "   ${CYAN}rm -rf \"$BACKUP_DIR\"${NC}"
    if [ -d "$TEMP_DIR" ]; then
        echo -e "   ${CYAN}rm -rf \"$TEMP_DIR\"${NC}"
    fi
fi
echo -e "${GREEN}========================================${NC}\n"

# Предупреждение для spi0.1
if [ -f "$BACKUP_DIR/mtd_dumps/spi0.1_mtd0.tar.gz" ] || [ -f "$FINAL_ARCHIVE" ]; then
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ: Раздел spi0.1 (весь flash чип) сохранен${NC}"
    if [ -f "$BACKUP_DIR/mtd_dumps/spi0.1_mtd0.tar.gz" ]; then
        echo -e "   Размер архива раздела: $(du -h "$BACKUP_DIR/mtd_dumps/spi0.1_mtd0.tar.gz" | cut -f1)"
    fi
    echo -e "   Это полная копия всей flash памяти устройства (128MB)"
    echo -e "   Рекомендуется хранить этот файл в надежном месте"
    echo -e "${GREEN}========================================${NC}\n"
fi
