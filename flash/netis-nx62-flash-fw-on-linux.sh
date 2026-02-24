#!/usr/bin/env bash

# ================================================================================
# Скрипт автоматической прошивки роутера Netis NX62 на OpenWRT
# ================================================================================
# Автор: SevenMaxs (2026)
# ----------------------------------------------------------------------------------
# Назначение:
#   Автоматическая настройка окружения и прошивка роутера Netis NX62
#   на кастомную прошивку OpenWRT с загрузкой через TFTP
#
# 📋 Требования:
#       - ОС: Linux (Ubuntu/Debian) с пакетным менеджером apt
#       - Подключение: проводное Ethernet к роутеру
#       - Предварительная настройка: SSH-доступ с ключом Dropbear
#       - Пользователь должен иметь права sudo (будет запрошен пароль)
#
# 🔧 Что делает скрипт:
#       1. Устанавливает необходимые пакеты (network-manager, tftpd-hpa, tftp-hpa)
#       2. Проверяет SSH-подключение к роутеру
#       3. Настраивает сетевой интерфейс ПК (192.168.1.254/24)
#       4. Разворачивает TFTP-сервер для передачи recovery-образа
#       5. Скачивает образы OpenWRT (загрузчик, preloader, recovery, sysupgrade)
#       6. Записывает загрузчик в разделы BL2 и FIP через mtd
#       7. Перезагружает роутер и ожидает загрузки recovery по TFTP
#       8. Выполняет sysupgrade для установки постоянной прошивки
# ----------------------------------------------------------------------------------
# 📌 ПОДДЕРЖИВАЕМЫЕ МОДЕЛИ:
#    • Netis NX62
#    • Netcore N60 Pro
# ----------------------------------------------------------------------------------
# 🔗 GitHub: https://github.com/SevenMaxs/netis-nx62-flash-tools
# ==================================================================================

set -e  # Прерывать выполнение при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Конфигурация OpenWRT
readonly OPENWRT_VER="25.12.0-rc5"
readonly TARGET_PATH="mediatek/filogic"      # для URL
readonly TARGET_NAME="mediatek-filogic"      # для имени файла
readonly MODEL="netcore_n60-pro"
readonly BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VER}/targets/${TARGET_PATH}/"
readonly FW_DIR="/tmp/openwrt_images_netis_nx62"

# Имена файлов для скачивания
readonly UBOOT_FIP="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-bl31-uboot.fip"
readonly PRELOADER_BIN="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-preloader.bin"
readonly RECOVERY_ITB="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-initramfs-recovery.itb"
readonly SYSUPGRADE_ITB="openwrt-${OPENWRT_VER}-${TARGET_NAME}-${MODEL}-squashfs-sysupgrade.itb"

# Конфигурация модуля kmod-mtd-rw
readonly KERNEL_VER="6.12.71"
readonly KMODS_PATH="kmods/${KERNEL_VER}-1-60d938adcb727697d3015e4285d4c290"
readonly MTD_RW_APK="kmod-mtd-rw-${KERNEL_VER}.2021.02.28~e8776739-r1.apk"
readonly KMODS_URL="${KMODS_PATH}/${MTD_RW_APK}"

# Имя файла recovery на TFTP-сервере (без версии)
readonly RECOVERY_ITB_TFTP="openwrt-${TARGET_NAME}-${MODEL}-initramfs-recovery.itb"

# Параметры доступа к стоковому роутеру
readonly ROUTER_USER="useradmin"
readonly OWRT_USER="root"
readonly ROUTER_IP="192.168.1.1"
readonly SSH_KEY="${HOME}/.ssh/dropbear_key"  # Путь к вашему SSH-ключу

# Настройки IP для ПК во время прошивки
readonly PC_IP="192.168.1.254"
readonly PC_NETMASK="24"

# Временная директория для образов на ПК
readonly TMP_DIR="/tmp/openwrt_images_$$"

# Директория TFTP (должна совпадать с настройками tftpd-hpa)
readonly TFTP_DIR="/srv/tftp"

# -------------------------------------------------------------------
# Функция проверки наличия sudo и прав
# -------------------------------------------------------------------
check_sudo() {
    if ! command -v sudo &>/dev/null; then
        echo -e "${RED}sudo не установлен. Пожалуйста, установите sudo.${NC}"
        exit 1
    fi
    
    # Проверяем, может ли пользователь использовать sudo
    if ! sudo -v &>/dev/null; then
        echo -e "${RED}У вас нет прав на использование sudo или неверный пароль.${NC}"
        echo "Пожалуйста, убедитесь, что вы настроены в sudoers и знаете свой пароль."
        exit 1
    fi
    
    # Обновляем временную метку sudo, чтобы не запрашивать пароль слишком часто
    sudo -v
    
    echo -e "${GREEN}Проверка sudo выполнена успешно.${NC}"
}

# -------------------------------------------------------------------
# Функция проверки и установки пакетов
# -------------------------------------------------------------------
install_packages() {
    local pkgs=("$@")
    local to_install=()
    
    echo -e "${YELLOW}Проверка необходимых пакетов...${NC}"
    
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l 2>/dev/null | grep -qw "$pkg"; then
            to_install+=("$pkg")
        fi
    done
    
    if [ ${#to_install[@]} -gt 0 ]; then
        echo -e "${YELLOW}Будут установлены отсутствующие пакеты: ${to_install[*]}${NC}"
        sudo apt update
        sudo apt install -y "${to_install[@]}"
        echo -e "${GREEN}Пакеты успешно установлены.${NC}"
    else
        echo -e "${GREEN}Все необходимые пакеты уже установлены.${NC}"
    fi
}

# -------------------------------------------------------------------
# Функция проверки SSH-ключа
# -------------------------------------------------------------------
check_ssh_key() {
    if [ ! -f "$SSH_KEY" ]; then
        echo -e "${RED}SSH-ключ $SSH_KEY не найден!${NC}"
        echo "Сгенерируйте ключ для Dropbear:"
        echo "  ssh-keygen -t rsa -b 2048 -N \"\" -f $SSH_KEY"
        echo "И скопируйте его на роутер:"
        echo "  cat ${SSH_KEY}.pub | ssh ${ROUTER_USER}@${ROUTER_IP} 'cat >> /etc/dropbear/authorized_keys'"
        exit 1
    fi
    
    # Проверяем, работает ли подключение с ключом
    echo -e "${YELLOW}Проверка подключения к роутеру с SSH-ключом...${NC}"
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "${ROUTER_USER}@${ROUTER_IP}" "echo OK" 2>/dev/null; then
        echo -e "${RED}Не удалось подключиться к роутеру с использованием SSH-ключа.${NC}"
        echo "Убедитесь, что ключ скопирован правильно:"
        echo "  cat ${SSH_KEY}.pub | ssh ${ROUTER_USER}@${ROUTER_IP} 'cat >> /etc/dropbear/authorized_keys'"
        exit 1
    fi
    echo -e "${GREEN}Подключение по SSH работает!${NC}"
}

# -------------------------------------------------------------------
# Функция удаления существующего соединения OpenWRT
# -------------------------------------------------------------------
remove_existing_connection() {
    if sudo nmcli connection show "OpenWRT" &>/dev/null; then
        echo -e "${YELLOW}Соединение с именем OpenWRT уже существует. Удаляем...${NC}"
        sudo nmcli connection delete "OpenWRT"
    fi
}

# -------------------------------------------------------------------
# Функция настройки TFTP-сервера
# -------------------------------------------------------------------
setup_tftp_server() {
    echo -e "${GREEN}=== Настройка TFTP-сервера для прошивки роутера ===${NC}"

    if [ ! -d "$TFTP_DIR" ]; then
        sudo mkdir -p "$TFTP_DIR"
        echo "Создана директория $TFTP_DIR"
    else
        echo "Директория $TFTP_DIR уже существует."
    fi

    sudo chmod 755 "$TFTP_DIR"

    # Бэкап конфигурации
    local CONFIG_FILE="/etc/default/tftpd-hpa"
    if [ -f "$CONFIG_FILE" ]; then
        sudo cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
        echo "Создан бэкап $CONFIG_FILE"
    fi

    echo "# /etc/default/tftpd-hpa
TFTP_USERNAME=\"tftp\"
TFTP_DIRECTORY=\"$TFTP_DIR\"
TFTP_ADDRESS=\"0.0.0.0:69\"
TFTP_OPTIONS=\"--secure --create\"" | sudo tee "$CONFIG_FILE" > /dev/null
    echo "Конфигурация TFTP-сервера обновлена: $CONFIG_FILE"

    # Открываем порт в UFW, если активен
    if command -v ufw &>/dev/null && sudo ufw status | grep -q active; then
        sudo ufw allow 69/udp comment 'TFTP для прошивки OpenWRT'
        echo "Порт 69/udp открыт в UFW."
    else
        echo "UFW не активен или не установлен, пропускаем настройку файрвола."
    fi

    sudo systemctl restart tftpd-hpa
    sudo systemctl enable tftpd-hpa
    sudo systemctl status tftpd-hpa --no-pager

    echo -e "${GREEN}TFTP-сервер настроен и запущен. Директория: $TFTP_DIR${NC}"
}

# -------------------------------------------------------------------
# Функция скачивания образов OpenWRT
# -------------------------------------------------------------------
download_files() {
    echo -e "${GREEN}=== Скачивание образов OpenWRT v${OPENWRT_VER} ===${NC}"
    
    # Проверяем наличие интернета
    if ! check_internet_access; then
        echo -e "${YELLOW}Доступ в интернет отсутствует. Проверяем локальные файлы...${NC}"
        
        # Проверяем существование директории
        if [ ! -d "$FW_DIR" ]; then
            echo -e "${RED}Ошибка: Локальная директория $FW_DIR не существует${NC}"
            echo -e "${RED}Необходимо наличие следующих файлов:${NC}"
            echo -e "${RED}  - $UBOOT_FIP${NC}"
            echo -e "${RED}  - $PRELOADER_BIN${NC}"
            echo -e "${RED}  - $RECOVERY_ITB${NC}"
            echo -e "${RED}  - $SYSUPGRADE_ITB${NC}"
            echo -e "${RED}  - $MTD_RW_APK${NC}"
            exit 1
        fi
        
        # Проверяем наличие всех необходимых файлов
        local missing_files=()
        local files=("$UBOOT_FIP" "$PRELOADER_BIN" "$RECOVERY_ITB" "$SYSUPGRADE_ITB" "$MTD_RW_APK")
        
        for file in "${files[@]}"; do
            if [ ! -f "$FW_DIR/$file" ]; then
                missing_files+=("$file")
            fi
        done
        
        # Если есть отсутствующие файлы, выводим сообщение об ошибке
        if [ ${#missing_files[@]} -gt 0 ]; then
            echo -e "${RED}Ошибка: Отсутствуют необходимые файлы в $FW_DIR${NC}"
            echo -e "${RED}Необходимо наличие следующих файлов:${NC}"
            for missing_file in "${missing_files[@]}"; do
                echo -e "${RED}  - $missing_file${NC}"
            done
            exit 1
        fi
        
        # Копируем файлы из локальной директории в временную
        mkdir -p "$TMP_DIR"
        cd "$TMP_DIR"
        echo "Копирование файлов из $FW_DIR..."
        cp "$FW_DIR"/* .
        
        echo -e "${GREEN}Все образы успешно скопированы из локальной директории${NC}"
        ls -lh "$TMP_DIR"
    else
        # Если интернет есть, используем обычную логику загрузки
        mkdir -p "$TMP_DIR"
        cd "$TMP_DIR"

        local files=("$UBOOT_FIP" "$PRELOADER_BIN" "$RECOVERY_ITB" "$SYSUPGRADE_ITB" "$KMODS_URL")
        local all_exist=true

        for file in "${files[@]}"; do
            if [ ! -f "$file" ]; then
                all_exist=false
                echo "Скачивание $file ..."
                wget --show-progress -q "${BASE_URL}${file}" || {
                    echo -e "${RED}Ошибка скачивания $file${NC}"
                    exit 1
                }
            else
                echo "Файл $file уже существует."
            fi
        done

        echo -e "${GREEN}Все образы успешно загружены в $TMP_DIR${NC}"
        ls -lh "$TMP_DIR"
    fi
}

# -------------------------------------------------------------------
# Функция копирования uboot на роутер и записи в flash
# -------------------------------------------------------------------
copy_and_write_uboot() {
    echo -e "${GREEN}=== Копирование загрузчика на роутер и запись в flash ===${NC}"

    # Проверка доступности роутера
    if ! ping -c1 -W2 "$ROUTER_IP" &>/dev/null; then
        echo -e "${RED}Роутер $ROUTER_IP недоступен. Проверьте соединение.${NC}"
        exit 1
    fi

    # Копирование файлов на роутер
    echo "Копирование $UBOOT_FIP на роутер..."
    scp -i "$SSH_KEY" -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$TMP_DIR/$UBOOT_FIP" \
        "${ROUTER_USER}@${ROUTER_IP}:/tmp/" || {
        echo -e "${RED}Ошибка копирования файлов на роутер.${NC}"
        exit 1
    }

    # Выполнение команд mtd и форматирование UBI
    echo "Запись uboot..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${ROUTER_USER}@${ROUTER_IP}" \
        "mtd write /tmp/$UBOOT_FIP FIP" || {
        echo -e "${RED}Ошибка при записи через mtd.${NC}"
        exit 1
    }

    # Форматирование UBI раздела
    echo "Форматирование UBI раздела..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${ROUTER_USER}@${ROUTER_IP}" \
        "mtd erase ubi" || {
        echo -e "${RED}Ошибка при форматировании UBI.${NC}"
        exit 1
    }

    echo -e "${GREEN}Uboot успешно записан, UBI отформатирован.${NC}"
}

# -------------------------------------------------------------------
# Функция проверки доступа в интернет с роутера
# -------------------------------------------------------------------
check_router_internet() {
    echo -e "${YELLOW}Проверка доступа в интернет с роутера...${NC}"
    
    # Пробуем пропинговать Google DNS или OpenWRT сайт
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${OWRT_USER}@${ROUTER_IP}" \
        "ping -c1 -W3 8.8.8.8 >/dev/null 2>&1 || ping -c1 -W3 downloads.openwrt.org >/dev/null 2>&1"; then
        echo -e "${GREEN}✓ Доступ в интернет с роутера есть${NC}"
        return 0
    else
        echo -e "${YELLOW}✗ Доступ в интернет с роутера отсутствует${NC}"
        return 1
    fi
}

# -------------------------------------------------------------------
# Функция проверки доступа в интернет с локальной машины
# -------------------------------------------------------------------
check_internet_access() {
    echo -e "${YELLOW}Проверка доступа в интернет с локальной машины...${NC}"
    
    # Пробуем пропинговать Google DNS
    if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Доступ в интернет с локальной машины есть${NC}"
        return 0
    else
        echo -e "${YELLOW}✗ Доступ в интернет с локальной машины отсутствует${NC}"
        return 1
    fi
}

# -------------------------------------------------------------------
# Функция копирования preloader на роутер и записи в flash
# -------------------------------------------------------------------
copy_and_write_preloader() {
    echo -e "${GREEN}=== Копирование preloader на роутер и запись в flash ===${NC}"

    # Проверка доступности роутера
    if ! ping -c1 -W2 "$ROUTER_IP" &>/dev/null; then
        echo -e "${RED}Роутер $ROUTER_IP недоступен. Проверьте соединение.${NC}"
        exit 1
    fi

    # Копирование preloader на роутер
    echo "Копирование $PRELOADER_BIN на роутер..."
    scp -i "$SSH_KEY" -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$TMP_DIR/$PRELOADER_BIN" "${OWRT_USER}@${ROUTER_IP}:/tmp/" || {
        echo -e "${RED}Ошибка копирования $PRELOADER_BIN на роутер.${NC}"
        exit 1
    }

    # Проверяем, нужно ли копировать kmod-mtd-rw
    local use_local_apk=false
    
    # Проверяем доступ в интернет с роутера
    if check_router_internet; then
        echo -e "${GREEN}Будет выполнена установка kmod-mtd-rw из репозитория${NC}"
        use_local_apk=false
    else
        echo -e "${YELLOW}Интернет на роутере недоступен, используем скаченный ранее локальный .apk файл${NC}"
        
        # Копируем локальный .apk файл на роутер
        if [ -f "$TMP_DIR/$MTD_RW_APK" ]; then
            echo "Копирование $MTD_RW_APK на роутер..."
            scp -i "$SSH_KEY" -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                "$TMP_DIR/$MTD_RW_APK" "${OWRT_USER}@${ROUTER_IP}:/tmp/" || {
                echo -e "${RED}Ошибка копирования $MTD_RW_APK на роутер.${NC}"
                exit 1
            }
            use_local_apk=true
        else
            echo -e "${RED}Локальный файл $MTD_RW_APK не найден в $TMP_DIR${NC}"
            echo "Скачайте его вручную или обеспечьте доступ в интернет с роутера."
            exit 1
        fi
    fi

    # Выполняем установку kmod-mtd-rw в зависимости от доступности интернета
    echo "Установка kmod-mtd-rw..."
    
    if [ "$use_local_apk" = false ]; then
        # Установка из репозитория
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "${OWRT_USER}@${ROUTER_IP}" \
            "apk update && apk add kmod-mtd-rw" || {
            echo -e "${RED}Ошибка при установке kmod-mtd-rw из репозитория.${NC}"
            exit 1
        }
    else
        # Установка из локального .apk файла
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "${OWRT_USER}@${ROUTER_IP}" \
            "apk add --allow-untrusted --no-network --force-missing-repositories --force-non-repository /tmp/$MTD_RW_APK" || {
            echo -e "${RED}Ошибка при установке kmod-mtd-rw из локального файла.${NC}"
            exit 1
        }
    fi
    
    echo -e "${GREEN}✓ kmod-mtd-rw успешно установлен${NC}"

    # Выполняем запись preloader
    echo "Запись preloader в раздел BL2..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${OWRT_USER}@${ROUTER_IP}" \
        "insmod mtd-rw i_want_a_brick=1 && mtd write /tmp/$PRELOADER_BIN bl2" || {
        echo -e "${RED}Ошибка при записи preloader через mtd.${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Preloader успешно записан в BL2${NC}"
}

# -------------------------------------------------------------------
# Функция подготовки TFTP (копирование recovery-образа с переименованием)
# -------------------------------------------------------------------
prepare_tftp_recovery() {
    echo -e "${GREEN}=== Подготовка TFTP recovery ===${NC}"
    
    # Копируем файл с переименованием (убираем версию из имени)
    sudo cp "$TMP_DIR/$RECOVERY_ITB" "$TFTP_DIR/$RECOVERY_ITB_TFTP" || {
        echo -e "${RED}Не удалось скопировать recovery-образ в $TFTP_DIR${NC}"
        exit 1
    }
    sudo chown tftp:tftp "$TFTP_DIR/$RECOVERY_ITB_TFTP"
    sudo chmod 644 "$TFTP_DIR/$RECOVERY_ITB_TFTP"
    echo "Recovery-образ скопирован в $TFTP_DIR/$RECOVERY_ITB_TFTP"
    echo "(исходное имя: $RECOVERY_ITB)"
}

# -------------------------------------------------------------------
# Функция перезагрузки роутера и ожидания загрузки recovery
# -------------------------------------------------------------------
reboot_and_wait_recovery() {
    echo -e "${GREEN}=== Перезагрузка роутера и ожидание recovery ===${NC}"
    echo "Роутер будет перезагружен. После перезагрузки он должен запросить образ по TFTP."
    read -p "Нажмите Enter для перезагрузки (или Ctrl+C для отмены)..." dummy

    # Отправляем команду reboot
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${ROUTER_USER}@${ROUTER_IP}" "reboot" || echo "Команда reboot отправлена."

    echo "Ждём 10 секунд перед началом проверки доступности recovery..."
    sleep 10

    # Ожидаем загрузку recovery
    local recovery_ready=false
    local max_attempts=30
    local attempt=0

    echo "Ожидание загрузки recovery (может занять до 2 минут)..."
    while [ $attempt -lt $max_attempts ]; do
        if ping -c1 -W2 "$ROUTER_IP" &>/dev/null; then
            # Проверим SSH (порт 22)
            if nc -z -w5 "$ROUTER_IP" 22 2>/dev/null; then
                echo -e "${GREEN}Роутер доступен по SSH (recovery загружен).${NC}"
                recovery_ready=true
                break
            fi
        fi
        attempt=$((attempt+1))
        echo -n "."
        sleep 5
    done

    if [ "$recovery_ready" = false ]; then
        echo -e "${RED}Роутер не загрузил recovery за отведённое время.${NC}"
        echo "Проверьте, включён ли TFTP-сервер, и нет ли ошибок в /var/log/syslog."
        exit 1
    fi
}

# -------------------------------------------------------------------
# Функция автоматической установки sysupgrade (в recovery)
# -------------------------------------------------------------------
auto_sysupgrade() {
    echo -e "${GREEN}=== Установка постоянной прошивки (sysupgrade) ===${NC}"
    
    # Копируем sysupgrade-образ в /tmp роутера (recovery)
    echo "Копирование sysupgrade-образа на роутер..."
    scp -i "$SSH_KEY" -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$TMP_DIR/$SYSUPGRADE_ITB" "${OWRT_USER}@${ROUTER_IP}:/tmp/" || {
        echo -e "${RED}Ошибка копирования sysupgrade-образа.${NC}"
        exit 1
    }

    # Форматирование UBI раздела
    echo "Форматирование UBI раздела..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${OWRT_USER}@${ROUTER_IP}" \
        "ubidetach -p /dev/mtd4 && ubiformat -y /dev/mtd4 && ubiattach -p /dev/mtd4 && ubimkvol /dev/ubi0 -n 0 -N ubootenv -s 128KiB && ubimkvol /dev/ubi0 -n 1 -N ubootenv2 -s 128KiB" || {
        echo -e "${RED}Ошибка при форматировании UBI.${NC}"
        exit 1
    }

    # Выполняем sysupgrade
    echo "Запуск sysupgrade (роутер перезагрузится)..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${OWRT_USER}@${ROUTER_IP}" \
        "sysupgrade -n /tmp/$SYSUPGRADE_ITB" || {
        echo -e "${YELLOW}Команда sysupgrade завершилась (соединение разорвано).${NC}"
    }

    echo "Ожидание завершения перезагрузки (до 3 минут)..."
    sleep 60

    # Проверяем доступность роутера с основной прошивкой
    local final_ready=false
    for i in {1..36}; do
        if ping -c1 -W2 "$ROUTER_IP" &>/dev/null; then
            echo -e "${GREEN}Роутер снова доступен. Прошивка завершена!${NC}"
            final_ready=true
            break
        fi
        echo -n "."
        sleep 5
    done

    if [ "$final_ready" = false ]; then
        echo -e "${RED}Роутер не вернулся в сеть после sysupgrade. Проверьте вручную.${NC}"
        exit 1
    fi
}

# -------------------------------------------------------------------
# Функция проверки TFTP-сервера
# -------------------------------------------------------------------
check_tftp() {
    echo -e "${YELLOW}Проверка TFTP-сервера...${NC}"
    
    # Проверяем, запущен ли сервис
    if ! sudo systemctl is-active --quiet tftpd-hpa; then
        echo -e "${RED}TFTP-сервер не запущен. Запустите: sudo systemctl start tftpd-hpa${NC}"
        return 1
    fi
    
    # Проверяем наличие файла в директории TFTP
    if [ ! -f "$TFTP_DIR/$RECOVERY_ITB_TFTP" ]; then
        echo -e "${RED}Файл $RECOVERY_ITB_TFTP не найден в $TFTP_DIR${NC}"
        echo "Скопируйте файл:"
        echo "  sudo cp $RECOVERY_ITB_TFTP $TFTP_DIR"
        echo "  sudo chown tftp:tftp $TFTP_DIR/$RECOVERY_ITB_TFTP"
        echo "  sudo chmod 644 $TFTP_DIR/$RECOVERY_ITB_TFTP"
        return 1
    fi
    
    # Проверяем доступность через TFTP
    if command -v tftp &>/dev/null; then
        echo "Проверка скачивания recovery-образа через TFTP с ${PC_IP}..."
        
        # Создаем временную директорию для теста
        local tmp_dir="/tmp/tftp_test_$$"
        mkdir -p "$tmp_dir"
        cd "$tmp_dir"
        
        # Пробуем скачать файл и проверяем результат по наличию файла
        if tftp "$PC_IP" <<EOF > /dev/null 2>&1
get $RECOVERY_ITB_TFTP
quit
EOF
        then
            # Проверяем, скачался ли файл
            if [ -f "$tmp_dir/$RECOVERY_ITB_TFTP" ]; then
                local file_size=$(stat -c%s "$tmp_dir/$RECOVERY_ITB_TFTP" 2>/dev/null || stat -f%z "$tmp_dir/$RECOVERY_ITB_TFTP" 2>/dev/null)
                if [ "$file_size" -gt 0 ]; then
                    echo -e "${GREEN}✓ TFTP-сервер работает правильно, файл доступен (${file_size} байт).${NC}"
                    rm -rf "$tmp_dir"
                    return 0
                fi
            fi
        fi
       
        rm -rf "$tmp_dir"
        
        echo ""
        echo -e "${YELLOW}Попробуйте проверить вручную:${NC}"
        echo "  tftp $PC_IP"
        echo "  get $RECOVERY_ITB_TFTP"
        echo "  quit"
        echo "  ls -l $RECOVERY_ITB_TFTP  # должен появиться файл"
        
        return 1
    fi
    
    echo -e "${GREEN}TFTP-сервер запущен (пропускаем детальную проверку).${NC}"
    return 0
}

# -------------------------------------------------------------------
# Функция проверки, что интерфейс получил нужный IP
# -------------------------------------------------------------------
check_ip() {
    local interface="$1"
    local ip_addr="$2"
    
    echo "Проверка IP-адреса на интерфейсе $interface..."
    local current_ip=$(ip -4 addr show "$interface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ "$current_ip" = "$ip_addr" ]; then
        echo -e "${GREEN}IP-адрес $ip_addr правильно настроен на интерфейсе $interface.${NC}"
        return 0
    else
        echo -e "${YELLOW}Текущий IP на интерфейсе $interface: $current_ip, ожидался $ip_addr${NC}"
        return 1
    fi
}

# -------------------------------------------------------------------
# Основная логика
# -------------------------------------------------------------------
main() {
    # Проверка наличия sudo и прав
    check_sudo

    # Установка необходимых пакетов
    install_packages network-manager tftpd-hpa tftp-hpa openssh-client wget

    # Проверка SSH-ключа
    check_ssh_key

    # --- Часть 1: Настройка сетевого соединения ---
    echo -e "${GREEN}=== Настройка сетевого соединения ПК для прошивки ===${NC}"

    # Получаем список Ethernet-интерфейсов
    mapfile -t lines < <(sudo nmcli -t -f TYPE,DEVICE,STATE device status | grep '^ethernet:' 2>/dev/null || true)

    if [ ${#lines[@]} -eq 0 ]; then
        echo -e "${RED}Ошибка: не найдено ни одного проводного Ethernet-интерфейса.${NC}"
        exit 1
    fi

    devices=()
    states=()
    for line in "${lines[@]}"; do
        IFS=':' read -r type device state <<< "$line"
        devices+=("$device")
        states+=("$state")
    done

    echo "Доступные проводные интерфейсы:"
    for i in "${!devices[@]}"; do
        echo "$((i+1)). ${devices[$i]} (${states[$i]})"
    done

    # Выбор интерфейса
    while true; do
        read -p "Выберите номер интерфейса для соединения с роутером: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#devices[@]} ]; then
            index=$((choice-1))
            IFACE="${devices[$index]}"
            echo "Выбран интерфейс: $IFACE"
            break
        else
            echo "Некорректный ввод. Введите число от 1 до ${#devices[@]}."
        fi
    done

    # Настройка соединения OpenWRT
    remove_existing_connection
    echo "Создание соединения OpenWRT на интерфейсе $IFACE..."
    sudo nmcli connection add type ethernet con-name "OpenWRT" ifname "$IFACE"
    sudo nmcli connection modify "OpenWRT" \
        ipv4.method manual \
        ipv4.addresses "${PC_IP}/${PC_NETMASK}" \
        ipv4.gateway "$ROUTER_IP" \
        ipv4.dns "8.8.8.8"

    echo "Активация соединения..."
    if ! sudo nmcli connection up "OpenWRT"; then
        echo -e "${RED}Ошибка активации соединения. Возможно, интерфейс занят.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Соединение OpenWRT настроено (IP ${PC_IP}/${PC_NETMASK}).${NC}"
    
    # Проверка, что IP назначился правильно
    sleep 2
    check_ip "$IFACE" "$PC_IP" || {
        echo -e "${YELLOW}Предупреждение: IP-адрес мог назначиться неверно. Проверьте вручную.${NC}"
    }

    # Настройка TFTP-сервера (опционально)
    echo ""
    read -p "Настроить TFTP-сервер для прошивки? (y/n): " answer_tftp
    if [[ "$answer_tftp" =~ ^[YyДд] ]]; then
        setup_tftp_server
    fi

    # Скачиваем образы
    download_files

    # Подготавливаем TFTP recovery
    prepare_tftp_recovery

    # Проверка TFTP перед прошивкой
    check_tftp || {
        echo -e "${YELLOW}Продолжаем, но убедитесь, что TFTP работает.${NC}"
    }

    # --- Часть 2: Прошивка роутера ---
    echo ""
    read -p "Хотите выполнить прошивку роутера OpenWRT? (y/n): " answer_flash
    if [[ ! "$answer_flash" =~ ^[YyДд] ]]; then
        echo "Выход без прошивки."
        exit 0
    fi

    # Копируем uboot, выполняем mtd write и затираем ubi
    copy_and_write_uboot

    # Перезагружаем роутер и ждём recovery
    reboot_and_wait_recovery

    # Копируем preloader и выполняем mtd write
    copy_and_write_preloader

    # Устанавливаем sysupgrade
    auto_sysupgrade

    echo -e "${GREEN}=== Прошивка успешно завершена! ===${NC}"
    echo "Роутер Netis NX62 теперь работает под управлением OpenWRT $OPENWRT_VER."
    echo "Адрес для доступа: http://$ROUTER_IP (логин root, без пароля)."
    echo "Можете изменить сетевые настройки ПК обратно, если необходимо."
}

# Запуск основной функции
main
