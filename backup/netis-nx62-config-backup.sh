#!/bin/sh

# ==================================================================================
# ╔═══════════════════════════════════════════════════════════════════════════════╗
# ║           Config Backup Script for Netis NX62 / OpenWrt                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════╝
# ==================================================================================
# Автор:  SevenMaxs (2026)
# ----------------------------------------------------------------------------------
# 📋 ОПИСАНИЕ:
#   Скрипт создает резервную копию важных конфигурационных файлов OpenWrt
#   роутера Netis NX62, включая настройки сети, пользователя, беспроводных сетей,
#   файрвола и другие важные конфигурации.
# ----------------------------------------------------------------------------------
# 🔧 ФУНКЦИОНАЛ:
#   ✓ Резервное копирование конфигурационных файлов OpenWrt
#   ✓ Сохранение информации о системе
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
ARCHIVE_NAME="${DEVICE_MODEL}_config_backup_${TIMESTAMP}.tar.gz"
FINAL_ARCHIVE="/tmp/tmp/${ARCHIVE_NAME}"
BACKUP_DIR="/tmp/tmp/${DEVICE_MODEL}_config_backup_${TIMESTAMP}"
TEMP_DIR="/tmp/tmp/${DEVICE_MODEL}_config_temp_${TIMESTAMP}"

# Список файлов и директорий для бекапа
CONFIG_FILES="
/etc/config/
/etc/passwd
/etc/shadow
/etc/group
/etc/hosts
/etc/hostname
/etc/resolv.conf
/etc/rc.local
/etc/crontabs/
/etc/firewall.user
/etc/profile
/etc/profile.d/
/etc/dropbear/
/etc/uhttpd.crt
/etc/uhttpd.key
/etc/wpa_supplicant.conf
/etc/ethers
/etc/networks
/etc/services
/etc/protocols
/etc/rpc
/etc/fstab
/etc/inittab
/etc/sysctl.conf
/etc/modules-boot.d/
/etc/modules.d/
/etc/hotplug.d/
/etc/uci-defaults/
/etc/banner
/etc/motd
/etc/openwrt_release
/etc/os-release
"

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}   Config Backup Tool for Netis NX62   ${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Директория: ${YELLOW}$BACKUP_DIR${NC}"
echo -e "Временная директория: ${YELLOW}$TEMP_DIR${NC}"
echo -e "Финальный архив: ${YELLOW}$FINAL_ARCHIVE${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Создаем директории
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/config_files"
mkdir -p "$BACKUP_DIR/system_info"
mkdir -p "$TEMP_DIR"

# 1. Сохраняем информацию о системе
echo -e "${GREEN}[1/4]${NC} Сохранение информации о системе..."

# Версия OpenWrt
cat /etc/openwrt_version > "$BACKUP_DIR/system_info/openwrt_version.txt" 2>/dev/null || echo "unknown" > "$BACKUP_DIR/system_info/openwrt_version.txt"

# Информация о системе
{
    echo "System Information - Netis NX62"
    echo "Дата: $(date)"
    echo "Hostname: $(cat /proc/sys/kernel/hostname 2>/dev/null || echo 'unknown')"
    echo "Version: $(cat /etc/openwrt_version 2>/dev/null || cat /etc/openwrt_release 2>/dev/null || echo 'unknown')"
    echo "Kernel: $(uname -r 2>/dev/null || echo 'unknown')"
    echo "Architecture: $(uname -m 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Memory Info:"
    cat /proc/meminfo | head -10
    echo ""
    echo "Disk Usage:"
    df -h
    echo ""
    echo "Mount Points:"
    mount | grep -E "(rootfs|\/overlay|\/rom|\/tmp\/tmp)"
} > "$BACKUP_DIR/system_info/system_info.txt"

# 2. Сохраняем информацию о сетевых интерфейсах
echo -e "${GREEN}[2/4]${NC} Сохранение информации о сетевых настройках..."

# Конфигурации UCI
for config in /etc/config/*; do
    if [ -f "$config" ]; then
        uci show "$(basename "$config")" > "$BACKUP_DIR/system_info/uci_$(basename "$config").txt" 2>/dev/null || echo "# No UCI settings for $(basename "$config")" > "$BACKUP_DIR/system_info/uci_$(basename "$config").txt"
    fi
done

# Статус сетевых интерфейсов
{
    echo "Network Interface Status"
    echo "Date: $(date)"
    echo ""
    uci show network 2>/dev/null || echo "uci: network config not found"
    echo ""
    uci show wireless 2>/dev/null || echo "uci: wireless config not found"
} > "$BACKUP_DIR/system_info/network_status.txt"

# 3. Копируем конфигурационные файлы
echo -e "${GREEN}[3/4]${NC} Копирование конфигурационных файлов..."

# Счетчики
TOTAL_FILES=0
COPIED_FILES=0
FAILED_COPIES=0

# Создаем список файлов для обработки
echo "$CONFIG_FILES" | while read -r item; do
    # Пропускаем пустые строки
    [ -z "$item" ] && continue
    
    # Убираем лишние пробелы
    item=$(echo "$item" | xargs)
    
    # Проверяем существование файла/директории
    if [ -e "$item" ] || [ -L "$item" ]; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # Определяем имя файла для сохранения
        dest_dir="$TEMP_DIR$(dirname "$item")"
        mkdir -p "$dest_dir"
        
        # Копируем файл или директорию
        if [ -d "$item" ]; then
            cp -r "$item" "$TEMP_DIR/"
        else
            cp "$item" "$TEMP_DIR/"
        fi
        
        if [ $? -eq 0 ]; then
            COPIED_FILES=$((COPIED_FILES + 1))
            echo -e "  ${GREEN}✓${NC} $item"
        else
            FAILED_COPIES=$((FAILED_COPIES + 1))
            echo -e "  ${RED}✗${NC} $item"
        fi
    elif [ -n "$item" ]; then
        # Файл не существует, но это может быть нормально для некоторых файлов
        echo -e "  ${YELLOW}-${NC} $item (не существует)"
    fi
done

# Копируем все файлы в TEMP_DIR в BACKUP_DIR/config_files
if [ -d "$TEMP_DIR" ]; then
    cp -r "$TEMP_DIR"/* "$BACKUP_DIR/config_files/" 2>/dev/null || true
fi

# 4. Создаем общий отчет
{
    echo "========================================="
    echo "Config Backup Report - Netis NX62"
    echo "========================================="
    echo "Дата: $(date)"
    echo "Устройство: $(cat /proc/sys/kernel/hostname 2>/dev/null || echo 'unknown')"
    echo "OpenWrt: $(cat /etc/openwrt_version 2>/dev/null || echo 'unknown')"
    echo "Версия ядра: $(uname -r 2>/dev/null || echo 'unknown')"
    echo ""
    echo "Статистика:"
    echo "Всего файлов: $TOTAL_FILES"
    echo "Скопировано: $COPIED_FILES"
    echo "Ошибки: $FAILED_COPIES"
    echo ""
    echo "Важные конфигурационные файлы:"
    echo "-----------------------------------------"
    echo "$CONFIG_FILES" | while read -r item; do
        [ -z "$item" ] && continue
        item=$(echo "$item" | xargs)
        if [ -e "$item" ]; then
            size=$(du -h "$item" 2>/dev/null | cut -f1)
            echo "  $item ($size)"
        fi
    done
    echo "========================================="
} > "$BACKUP_DIR/CONFIG_BACKUP_REPORT.txt"

# 5. Создаем файл контрольных сумм
echo -e "${GREEN}[4/4]${NC} Создание контрольных сумм и архива..."

# Создаем файл контрольных сумм
{
    echo "========================================="
    echo "Config Files Checksums - Netis NX62"
    echo "========================================="
    echo "Дата: $(date)"
    echo ""
    echo "MD5 Hash                             File Name"
    echo "------------------------------------ --------------------"
} > "$BACKUP_DIR/config_files_checksums.txt"

# Вычисляем MD5 для всех скопированных файлов
find "$BACKUP_DIR/config_files" -type f -exec md5sum {} \; | sort -k 2 >> "$BACKUP_DIR/config_files_checksums.txt"

# Завершаем файл контрольных сумм
{
    echo "----------------------------------------"
    echo ""
    echo "Всего записей: $(grep -c "^[a-fA-F0-9]\{32\}" "$BACKUP_DIR/config_files_checksums.txt")"
    echo "========================================="
} >> "$BACKUP_DIR/config_files_checksums.txt"

# Создаем финальный архив
echo -e "  ${YELLOW}Создание финального архива...${NC}"
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

# Очистка временных файлов
echo -e "${GREEN}[5/5]${NC} Очистка временных файлов..."

CLEANUP_SUCCESS=true
CLEANUP_MESSAGE=""

# Проверяем что финальный архив существует
if [ -f "$FINAL_ARCHIVE" ]; then
    # Проверяем размер архива
    ARCHIVE_SIZE_BYTES=$(stat -c%s "$FINAL_ARCHIVE" 2>/dev/null || wc -c < "$FINAL_ARCHIVE" 2>/dev/null)
    
    if [ "$ARCHIVE_SIZE_BYTES" -gt 1024 ]; then  # Больше 1KB
        echo -e "  ${GREEN}✓ Финальный архив корректен (размер: $(du -h "$FINAL_ARCHIVE" | cut -f1))${NC}"
        
        # Проверяем содержимое архива
        echo -e "  ${YELLOW}  Проверка содержимого архива...${NC}"
        FILE_COUNT=$(tar -tzf "$FINAL_ARCHIVE" 2>/dev/null | wc -l)
        
        if [ "$FILE_COUNT" -gt 1 ]; then
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
echo -e "${GREEN}      CONFIG БЕКАП ЗАВЕРШЕН!          ${NC}"
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

# Информация о копировании
echo -e "${CYAN}Статистика бекапа:${NC}"
echo -e "  • Всего файлов: ${YELLOW}$TOTAL_FILES${NC}"
echo -e "  • Скопировано: ${GREEN}$COPIED_FILES${NC}"
echo -e "  • Ошибки: ${RED}$FAILED_COPIES${NC}"
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
if [ "$CLEANUP_SUCCESS" = true ] && [ $FAILED_COPIES -eq 0 ]; then
    echo -e "${GREEN}🎉 CONFIG БЕКАП ВЫПОЛНЕН ИДЕАЛЬНО!${NC}"
    echo -e "${GREEN}   Все конфигурационные файлы сохранены, временные файлы очищены${NC}"
    echo -e "${GREEN}   Финальный архив готов к скачиванию${NC}"
elif [ "$CLEANUP_SUCCESS" = true ]; then
    echo -e "${GREEN}📦 Бекап завершен, временные файлы очищены${NC}"
    echo -e "${YELLOW}   Но некоторые файлы не сохранились ($FAILED_COPIES ошибок)${NC}"
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
