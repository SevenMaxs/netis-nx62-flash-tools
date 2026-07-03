#!/bin/sh

# ==================================================================================
# ╔═══════════════════════════════════════════════════════════════════════════════╗
# ║        Firmware Update Script for Netis NX62 / Netcore N60 Pro (On-Router)    ║
# ╚═══════════════════════════════════════════════════════════════════════════════╝
# ==================================================================================
# Автор:  SevenMaxs (2026)
# ----------------------------------------------------------------------------------
# 📋 ОПИСАНИЕ:
#   Скрипт для автоматического обновления загрузчика (FIP/BL2) и прошивки
#   OpenWRT непосредственно на роутере Netis NX62 / Netcore N60 Pro.
# ----------------------------------------------------------------------------------
# 🔧 ФУНКЦИОНАЛ:
#   ✓ Определение версии OpenWRT (24.x или 25.x)
#   ✓ Автоматическая установка kmod-mtd-rw
#   ✓ Скачивание образов OpenWRT (FIP, preloader, sysupgrade)
#   ✓ Запись загрузчика в разделы FIP и BL2
#   ✓ Установка постоянной прошивки через sysupgrade
#   ✓ Детальный отчет о процессе прошивки
# ----------------------------------------------------------------------------------
# 📌 ПОДДЕРЖИВАЕМЫЕ МОДЕЛИ:
#   • Netis NX62
#   • Netcore N60 Pro
# ----------------------------------------------------------------------------------
# ⚠️ ТРЕБОВАНИЯ:
#   • Роутер уже работает под управлением OpenWRT 24.x или 25.x
#   • Доступ в интернет со роутера (для скачивания образов)
#   • ~50 МБ свободного места в /tmp
# ----------------------------------------------------------------------------------
# 🔗 GitHub: https://github.com/SevenMaxs/netis-nx62-flash-tools
# ==================================================================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Статическая конфигурация (не зависит от версии)
readonly TARGET_PATH="mediatek/filogic"      # для URL
readonly TARGET_NAME="mediatek-filogic"      # для имени файла
readonly MODEL="netcore_n60-pro"
readonly FW_DIR="/tmp/tmp"

# Версия по умолчанию (переопределяется через -v или автоопределение)
OPENWRT_VER="25.12.5"
# Переменные, зависящие от версии (устанавливаются в main() после resolve)
BASE_URL=""
UBOOT_FIP=""
PRELOADER_BIN=""
SYSUPGRADE_ITB=""

# ==============================================================================
# Вспомогательные функции
# ==============================================================================

# -----------------------------------------------------------------------------
# Вывод сообщения об ошибке и выход
# -----------------------------------------------------------------------------
die() {
    echo -e "${RED}❌ ОШИБКА: $1${NC}" >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Вывод информационного сообщения
# -----------------------------------------------------------------------------
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# -----------------------------------------------------------------------------
# Вывод предупреждения
# -----------------------------------------------------------------------------
warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# -----------------------------------------------------------------------------
# Вывод успешного сообщения
# -----------------------------------------------------------------------------
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# ==============================================================================
# Основные функции
# ==============================================================================

# -----------------------------------------------------------------------------
# Функция проверки версии OpenWRT
# -----------------------------------------------------------------------------
check_openwrt_version() {
    info "Проверка версии OpenWRT..."

    # Проверяем /etc/openwrt_release
    if [ -f /etc/openwrt_release ]; then
        local release=$(grep 'DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
        
        # Проверяем, не SNAPSHOT ли это
        if [ "$release" = "SNAPSHOT" ]; then
            success "Обнаружена OpenWRT SNAPSHOT (используем apk)"
            return 25
        fi
        
        # Проверяем версию (24.x или 25.x)
        local major=$(echo "$release" | cut -d'.' -f1)
        if [ "$major" = "25" ]; then
            success "Обнаружена OpenWRT версии 25.x"
            return 25
        elif [ "$major" = "24" ]; then
            success "Обнаружена OpenWRT версии 24.x"
            return 24
        fi
    fi

    # Если не удалось определить по release, проверяем наличие apk
    if command -v apk >/dev/null 2>&1; then
        success "Пакетный менеджер apk обнаружен (OpenWRT 25.x или SNAPSHOT)"
        return 25
    elif command -v opkg >/dev/null 2>&1; then
        success "Пакетный менеджер opkg обнаружен (OpenWRT 24.x)"
        return 24
    fi

    # По умолчанию предполагаем 25.x
    warn "Не удалось определить версию OpenWRT, предполагаем >= 25"
    return 25
}

# -----------------------------------------------------------------------------
# Функция установки kmod-mtd-rw
# -----------------------------------------------------------------------------
install_mtd_rw() {
    info "Установка модуля kmod-mtd-rw для записи в защищённые разделы..."

    # Проверяем, загружен ли уже модуль
    if lsmod | grep -q mtd_rw 2>/dev/null; then
        success "Модуль mtd-rw уже загружен"
        return 0
    fi

    # Определяем пакетный менеджер
    local pkg_manager=""
    if command -v apk >/dev/null 2>&1; then
        pkg_manager="apk"
    elif command -v opkg >/dev/null 2>&1; then
        pkg_manager="opkg"
    else
        die "Не найден пакетный менеджер (apk или opkg)"
    fi

    info "Используемый пакетный менеджер: $pkg_manager"

    # Обновляем списки пакетов и устанавливаем
    info "Обновление репозиториев (может занять время)..."
    if [ "$pkg_manager" = "apk" ]; then
        apk update || warn "Не удалось обновить репозитории apk, пробуем установить..."
        info "Установка kmod-mtd-rw..."
        apk add kmod-mtd-rw || die "Не удалось установить kmod-mtd-rw"
    else
        opkg update || warn "Не удалось обновить репозитории opkg, пробуем установить..."
        info "Установка kmod-mtd-rw..."
        opkg install kmod-mtd-rw || die "Не удалось установить kmod-mtd-rw"
    fi

    # Загружаем модуль
    info "Загрузка модуля mtd-rw..."
    if ! insmod mtd-rw i_want_a_brick=1; then
        die "Не удалось загрузить модуль mtd-rw. Убедитесь, что он установлен."
    fi

    success "Модуль mtd-rw успешно загружен (i_want_a_brick=1)"
    return 0
}

# -----------------------------------------------------------------------------
# Функция проверки свободного места
# -----------------------------------------------------------------------------
check_disk_space() {
    info "Проверка свободного места в $FW_DIR..."
    
    # Создаём директорию если нет
    mkdir -p "$FW_DIR" || die "Не удалось создать директорию $FW_DIR"
    
    # Получаем свободное место в КБ
    local free_kb=$(df -k "$FW_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
    
    if [ -z "$free_kb" ]; then
        warn "Не удалось определить свободное место"
        return 0
    fi

    # Нужно ~50 МБ
    local required_kb=51200

    if [ "$free_kb" -lt "$required_kb" ]; then
        local free_mb=$((free_kb / 1024))
        die "Недостаточно свободного места. Требуется: ~50 МБ, доступно: ${free_mb} МБ"
    fi

    local free_mb=$((free_kb / 1024))
    success "Свободно: ${free_mb} МБ (требуется: ~50 МБ)"
    return 0
}

# -----------------------------------------------------------------------------
# Функция скачивания образов OpenWRT
# -----------------------------------------------------------------------------
download_images() {
    info "Скачивание образов OpenWRT v${OPENWRT_VER}..."
    
    mkdir -p "$FW_DIR" || die "Не удалось создать директорию $FW_DIR"
    cd "$FW_DIR" || die "Не удалось перейти в директорию $FW_DIR"
    
    local files_to_download="$UBOOT_FIP $PRELOADER_BIN $SYSUPGRADE_ITB"
    
    for file in $files_to_download; do
        if [ -f "$file" ]; then
            info "Файл $file уже существует, пропускаем"
        else
            info "Скачивание: $file"
            if wget -q --no-check-certificate -O "$file" "$BASE_URL$file"; then
                success "$file скачан"
            else
                rm -f "$file" 2>/dev/null
                die "Ошибка скачивания $file"
            fi
        fi
    done
    
    # Проверка размеров файлов
    for file in $files_to_download; do
        if [ ! -f "$file" ]; then
            die "Файл $file не найден после скачивания"
        fi
        
        local size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
        if [ -z "$size" ] || [ "$size" -lt 1000 ] 2>/dev/null; then
            die "Файл $file слишком мал или не удалось определить размер"
        fi
        info "$file: $size байт"
    done
    
    success "Все образы успешно загружены в $FW_DIR"
    ls -lh "$FW_DIR"
    return 0
}

# -----------------------------------------------------------------------------
# Функция прошивки FIP и preloader
# -----------------------------------------------------------------------------
flash_bootloader() {
    info "Начало прошивки загрузчика..."
    
    # Проверяем, загружен ли модуль mtd-rw
    if ! lsmod | grep -q mtd_rw 2>/dev/null; then
        install_mtd_rw
    fi
    
    # Запись preloader в BL2
    info "Запись preloader в раздел BL2..."
    if [ ! -f "$FW_DIR/$PRELOADER_BIN" ]; then
        die "Файл preloader не найден: $FW_DIR/$PRELOADER_BIN"
    fi
    
    if ! mtd erase bl2; then
        warn "Не удалось выполнить erase bl2, пробуем записать напрямую..."
    fi
    
    if ! mtd write "$FW_DIR/$PRELOADER_BIN" bl2; then
        die "Ошибка записи preloader в раздел BL2"
    fi
    success "Preloader успешно записан в BL2"
    
    # Запись U-Boot в FIP
    info "Запись U-Boot в раздел FIP..."
    if [ ! -f "$FW_DIR/$UBOOT_FIP" ]; then
        die "Файл U-Boot не найден: $FW_DIR/$UBOOT_FIP"
    fi
    
    if ! mtd erase fip; then
        warn "Не удалось выполнить erase fip, пробуем записать напрямую..."
    fi
    
    if ! mtd write "$FW_DIR/$UBOOT_FIP" fip; then
        die "Ошибка записи U-Boot в раздел FIP"
    fi
    success "U-Boot успешно записан в FIP"
    
    return 0
}

# -----------------------------------------------------------------------------
# Функция выполнения sysupgrade
# -----------------------------------------------------------------------------
do_sysupgrade() {
    info "Выполнение sysupgrade..."
    
    if [ ! -f "$FW_DIR/$SYSUPGRADE_ITB" ]; then
        die "Файл sysupgrade не найден: $FW_DIR/$SYSUPGRADE_ITB"
    fi
    
    local size=$(wc -c < "$FW_DIR/$SYSUPGRADE_ITB" 2>/dev/null | tr -d ' ')
    info "Размер образа sysupgrade: $size байт"
    
    warn "ВНИМАНИЕ: Сейчас начнётся прошивка. НЕ ОТКЛЮЧАЙТЕ ПИТАНИЕ!"
    warn "Роутер перезагрузится автоматически через 2-3 минуты."
    
    # Выполняем sysupgrade
    # Флаг -n означает "не сохранять настройки"
    if ! sysupgrade -n "$FW_DIR/$SYSUPGRADE_ITB"; then
        warn "Команда sysupgrade завершилась с ошибкой (это нормально, т.к. соединение разорвётся)"
    fi
    
    success "Sysupgrade запущен. Ожидайте перезагрузки..."
    
    return 0
}

# -----------------------------------------------------------------------------
# Функция подтверждения от пользователя
# -----------------------------------------------------------------------------
confirm_action() {
    local message="$1"
    echo -e "${YELLOW}$message${NC}"
    read -p "Продолжить? (y/n): " answer < /dev/tty

    case "$answer" in
        [YyДд]*)
            return 0
            ;;
        *)
            echo "Операция отменена пользователем."
            exit 0
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Функция получения списка актуальных версий OpenWRT
# Возвращает самую новую версию с поддержкой target
# Побочный эффект: выводит топ-5 найденных версий на экран
# -----------------------------------------------------------------------------
fetch_latest_versions() {
    local releases_url="https://downloads.openwrt.org/releases/"
    local html
    local all_versions
    local matching_versions=""
    local count=0

    html=$(wget -q -T 10 --no-check-certificate -4 -O - "$releases_url" 2>/dev/null) || {
        warn "Не удалось получить список релизов с $releases_url" >&2
        return 1
    }

    # Извлекаем все стабильные версии из href="X.Y.Z/"
    all_versions=$(echo "$html" | sed -n 's/.*href="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\/".*/\1/p' | sort -t. -k1,1n -k2,2n -k3,3n -r)

    if [ -z "$all_versions" ]; then
        warn "Не удалось найти стабильные версии в списке релизов" >&2
        return 1
    fi

    # Проверяем каждую версию на наличие target (не более 20)
    local checked=0
    for ver in $all_versions; do
        checked=$((checked + 1))
        [ "$checked" -gt 20 ] && break
        local target_url="https://downloads.openwrt.org/releases/${ver}/targets/${TARGET_PATH}/"
        if wget -q -T 5 --no-check-certificate -4 -O /dev/null "$target_url" 2>/dev/null; then
            if [ -z "$matching_versions" ]; then
                matching_versions="$ver"
            else
                matching_versions="$matching_versions
$ver"
            fi
            count=$((count + 1))
            [ "$count" -ge 5 ] && break
        fi
    done

    if [ -z "$matching_versions" ]; then
        warn "Ни одна версия не содержит target ${TARGET_PATH}" >&2
        return 1
    fi

    # Выводим топ-5
    info "Найдены версии с поддержкой ${TARGET_PATH}:" >&2
    echo "" >&2
    local first=true
    local i=1
    echo "$matching_versions" | while read -r ver; do
        if [ "$first" = true ]; then
            printf "     %s. ${GREEN}%-10s${NC} ${BLUE}← будет использована${NC}\n" "$i" "$ver"
            first=false
        else
            printf "     %s. %s\n" "$i" "$ver"
        fi
        i=$((i + 1))
    done >&2
    echo "" >&2

    # Возвращаем самую новую (первую в списке)
    echo "$matching_versions" | head -1
    return 0
}

# -----------------------------------------------------------------------------
# Функция разрешения версии OpenWRT (аргумент или автоопределение)
# -----------------------------------------------------------------------------
resolve_openwrt_version() {
    local arg_version="$1"

    if [ -n "$arg_version" ]; then
        info "Используется указанная версия: $arg_version" >&2
        echo "$arg_version"
        return 0
    fi

    info "Определение актуальной версии OpenWRT для ${MODEL}..." >&2

    local latest
    if latest=$(fetch_latest_versions); then
        success "Будет использована версия: $latest" >&2
        echo "$latest"
        return 0
    fi

    warn "Не удалось определить версию, используется версия по умолчанию: ${OPENWRT_VER}" >&2
    echo "$OPENWRT_VER"
    return 0
}

# -----------------------------------------------------------------------------
# Установка переменных, зависящих от версии
# -----------------------------------------------------------------------------
set_version_vars() {
    local ver="$1"
    OPENWRT_VER="$ver"
    BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VER}/targets/${TARGET_PATH}/"
    UBOOT_FIP="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-bl31-uboot.fip"
    PRELOADER_BIN="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-preloader.bin"
    SYSUPGRADE_ITB="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-squashfs-sysupgrade.itb"
}

# ==============================================================================
# Основная функция
# ==============================================================================
AUTO_CONFIRM=false

main() {
    local version_arg=""

    # Обработка аргументов
    while [ $# -gt 0 ]; do
        case "$1" in
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -v|--version)
                if [ -z "$2" ]; then
                    die "Аргумент --version требует указания версии (например: --version 25.12.2)"
                fi
                version_arg="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Определение версии OpenWRT
    local resolved_version
    resolved_version=$(resolve_openwrt_version "$version_arg")
    set_version_vars "$resolved_version"

    echo ""
    echo "=================================================================================="
    echo "  Прошивка Netis NX62 / Netcore N60 Pro непосредственно на роутере"
    echo "  Версия OpenWRT: $OPENWRT_VER"
    echo "=================================================================================="
    echo ""

    # Проверка прав root
    if [ "$(id -u)" != "0" ]; then
        die "Этот скрипт должен выполняться от root"
    fi
    success "Запуск от root подтверждён"

    # Проверка модели устройства (опционально)
    info "Проверка модели устройства..."
    if [ -f /etc/board.json ]; then
        local model=$(grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' /etc/board.json 2>/dev/null | cut -d'"' -f4)
        if [ -n "$model" ]; then
            info "Модель устройства: $model"
        fi
    fi

    # Проверка свободного места
    check_disk_space

    # Скачивание образов
    download_images

    # Вывод информации о скачанных файлах
    echo ""
    info "Подготовленные файлы:"
    ls -lh "$FW_DIR"
    echo ""

    # Подтверждение пользователя
    if [ "$AUTO_CONFIRM" = false ]; then
        confirm_action "Готовы начать прошивку загрузчика и установку OpenWRT?"
    else
        warn "Автоматическое подтверждение (флаг -y)"
    fi

    # Установка kmod-mtd-rw
    install_mtd_rw

    # Прошивка загрузчика
    flash_bootloader

    # Подтверждение перед sysupgrade
    if [ "$AUTO_CONFIRM" = false ]; then
        confirm_action "Готовы выполнить sysupgrade? Роутер перезагрузится."
    else
        warn "Автоматическое подтверждение sysupgrade (флаг -y)"
    fi

    # Выполнение sysupgrade
    do_sysupgrade

    # Финальное сообщение
    echo ""
    echo "=================================================================================="
    success "Прошивка успешно завершена!"
    echo "  Роутер перезагружается с новой прошивкой OpenWRT $OPENWRT_VER"
    echo "  Адрес для доступа: http://192.168.1.1"
    echo "  Логин: root (без пароля)"
    echo "=================================================================================="
    echo ""
    info "Ожидайте загрузки роутера (1-3 минуты)..."

    return 0
}

# Запуск основной функции
main "$@"
