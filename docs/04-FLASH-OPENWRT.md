# 🚀 Прошивка Netis NX62 на OpenWRT с Linux

В этой инструкции описан процесс **автоматической прошивки** роутера **Netis NX62** на прошивку **OpenWRT** с использованием скрипта для пользователей Linux (Ubuntu/Debian).

> 💡 **Примечание:** Это **единственный поддерживаемый способ** прошивки. Скрипт полностью автоматизирует весь процесс — от настройки окружения до установки постоянной прошивки.

## 📋 Предварительные требования

- ✅ ПК под управлением **Ubuntu/Debian** с пакетным менеджером `apt`
- ✅ Права **root** или доступ к `sudo`
- ✅ Проводное Ethernet-подключение к роутеру
- ✅ Выполнена настройка SSH доступа ([01-SSH-CONNECTION.md](01-SSH-CONNECTION.md))
- ✅ Роутер работает под управлением **стоковой прошивки**
- ✅ Доступ в интернет для скачивания образов OpenWRT **ИЛИ** заранее скачанные файлы прошивки

## 📦 Что делает скрипт

Скрипт `netis-nx62-flash-fw-on-linux.sh` автоматически выполняет:

1. **Установку необходимых пакетов** (`network-manager`, `tftpd-hpa`, `tftp-hpa`, `openssh-client`, `wget`)
2. **Проверку SSH-ключа** и подключения к роутеру
3. **Настройку сетевого интерфейса** ПК (статический IP `192.168.1.254/24`)
4. **Настройку TFTP-сервера** для передачи recovery-образа
5. **Скачивание образов OpenWRT** (загрузчик, preloader, recovery, sysupgrade, kmod-mtd-rw)
6. **Запись загрузчика FIP** через `mtd write` (на стоковой прошивке)
7. **Форматирование UBI раздела**
8. **Перезагрузку роутера** и загрузку recovery-образа по TFTP
9. **Установку kmod-mtd-rw** (из репозитория или локально) — **только в recovery**
10. **Запись preloader в раздел BL2** — **только в recovery** (т.к. требуется kmod-mtd-rw)
11. **Форматирование UBI и установку постоянной прошивки** через `sysupgrade`

> 💡 **Важно:** Preloader записывается **после загрузки recovery**, потому что только в этом режиме доступен модуль `kmod-mtd-rw`, необходимый для записи в раздел BL2.

---

## 🚀 Пошаговая инструкция

### Шаг 1: Скачивание скрипта на компьютер

```bash
git clone https://github.com/SevenMaxs/netis-nx62-flash-tools.git
cd netis-nx62-flash-tools/flash/
```

Или скачайте только скрипт:

```bash
wget https://raw.githubusercontent.com/SevenMaxs/netis-nx62-flash-tools/main/flash/netis-nx62-flash-fw-on-linux.sh
chmod +x netis-nx62-flash-fw-on-linux.sh
```

---

### Шаг 2: Подготовка SSH-ключа (если не выполнен)

Если вы ещё не настроили SSH-доступ, выполните:

```bash
# Генерация ключа
ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/dropbear_key

# Копирование на роутер
cat ~/.ssh/dropbear_key.pub | ssh useradmin@192.168.1.1 'cat >> /etc/dropbear/authorized_keys'

# Проверка подключения после перезагрузки роутера
ssh -i ~/.ssh/dropbear_key useradmin@192.168.1.1 'echo OK'
```

---

### Шаг 3: Запуск скрипта прошивки

```bash
sudo ./netis-nx62-flash-fw-on-linux.sh
```

> ⚠️ **Важно:** Скрипт требует запуск от **root** (через `sudo`)

---

### Шаг 4: Выбор сетевого интерфейса

Скрипт покажет список доступных Ethernet-интерфейсов:

```
Доступные проводные интерфейсы:
1. eth0 (connected)
2. eth1 (disconnected)

Выберите номер интерфейса для соединения с роутером:
```

Введите номер интерфейса, **подключенного к роутеру**.

---

### Шаг 5: Настройка TFTP-сервера

Скрипт предложит настроить TFTP-сервер:

```
Настроить TFTP-сервер для прошивки? (y/n):
```

Введите **`y`** для настройки (рекомендуется).

> 📝 Скрипт автоматически:
> - Создаст директорию `/srv/tftp`
> - Настроит `tftpd-hpa`
> - Откроет порт 69/udp в UFW (если активен)
> - Запустит сервис

---

### Шаг 6: Запуск прошивки

Скрипт предложит начать прошивку:

```
Хотите выполнить прошивку роутера OpenWRT? (y/n):
```

Введите **`y`** для начала процесса.

---

### Шаг 7: Ожидание завершения

Далее скрипт выполнит все этапы автоматически:

```
=== Скачивание образов OpenWRT v25.12.0 ===
=== Копирование загрузчика на роутер и запись в flash ===
=== Подготовка TFTP recovery ===
=== Перезагрузка роутера и ожидание recovery ===
=== Установка постоянной прошивки (sysupgrade) ===
```

> ⏱️ **Время выполнения:** 5-10 минут (в зависимости от скорости интернета)

---

### Шаг 8: Завершение

После успешной прошивки вы увидите:

```
=== Прошивка успешно завершена! ===
Роутер Netis NX62 теперь работает под управлением OpenWRT 25.12.0.
Адрес для доступа: http://192.168.1.1 (логин root, без пароля).
```

---

## 🔄 Детальное описание этапов прошивки

### Этап 1: Подготовка окружения на ПК
- Установка пакетов: `network-manager`, `tftpd-hpa`, `tftp-hpa`
- Создание сетевого соединения с статическим IP `192.168.1.254`
- Настройка TFTP-сервера в директории `/srv/tftp`

### Этап 2: Скачивание образов
Скрипт загружает следующие файлы:
- **openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-bl31-uboot.fip** — загрузчик U-Boot (записывается в раздел FIP)
- **openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-preloader.bin** — препроцессор (записывается в раздел BL2)
- **openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-initramfs-recovery.itb** — recovery-образ для первой загрузки
- **openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-squashfs-sysupgrade.itb** — постоянная прошивка
- **kmod-mtd-rw-6.12.71.2021.02.28~e8776739-r1.apk** — модуль для записи в защищённые разделы

### Этап 3: Запись загрузчика FIP (на стоковой прошивке)
- Копирование `bl31-uboot.fip` на роутер через SCP
- Запись в раздел `FIP` через `mtd write`
- Форматирование раздела `UBI` для подготовки к новой прошивке

### Этап 4: Первая загрузка через TFTP
- Перезагрузка роутера
- Загрузка `recovery.itb` по TFTP (автоматически)
- Роутер получает IP `192.168.1.1` и запускает SSH

### Этап 5: Запись preloader BL2 (только в recovery)
- Проверка доступа в интернет с роутера
- Установка `kmod-mtd-rw` (из репозитория или локального `.apk`)
- Запись `preloader.bin` в раздел `BL2` через `mtd write` с использованием `mtd-rw`

> **Почему только в recovery?** Раздел `BL2` защищён от записи в стоковой прошивке.  
> Модуль `kmod-mtd-rw` снимает эту защиту, но доступен только в recovery-образе OpenWRT.

### Этап 6: Установка постоянной прошивки
- Форматирование UBI раздела
- Создание разделов `ubootenv` и `ubootenv2`
- Запуск `sysupgrade` с образом постоянной прошивки
- Автоматическая перезагрузка в новую прошивку

---

## 🔧 Ручная настройка TFTP-сервера (опционально)

Если вы хотите настроить TFTP вручную:

```bash
# Установка пакетов
sudo apt install tftpd-hpa tftp-hpa

# Создание директории
sudo mkdir -p /srv/tftp
sudo chown tftp:tftp /srv/tftp

# Редактирование конфига
sudo nano /etc/default/tftpd-hpa

# Содержимое:
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure --create"

# Перезапуск сервиса
sudo systemctl restart tftpd-hpa
sudo systemctl enable tftpd-hpa
```

---

## ⚙️ Параметры конфигурации скрипта

Скрипт использует следующие параметры конфигурации:

### Основные параметры:
- **Версия OpenWRT**: 25.12.0
- **Целевая архитектура**: mediatek/filogic
- **Модель устройства**: netcore_n60-pro
- **Базовый URL для скачивания**: https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/

### Имена файлов образов:
- **Загрузчик (FIP)**: openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-bl31-uboot.fip
- **Прелоадер (BL2)**: openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-preloader.bin
- **Recovery-образ**: openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-initramfs-recovery.itb
- **Sysupgrade-образ**: openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-squashfs-sysupgrade.itb
- **Модуль kmod-mtd-rw**: kmod-mtd-rw-6.12.71.2021.02.28~e8776739-r1.apk

### Параметры подключения:
- **Пользователь стокового роутера**: useradmin
- **Пользователь OpenWRT**: root
- **IP-адрес роутера**: 192.168.1.1
- **Путь к SSH-ключу**: ~/.ssh/dropbear_key

### Сетевые параметры:
- **IP-адрес ПК**: 192.168.1.254
- **Маска подсети**: 24
- **Директория TFTP-сервера**: /srv/tftp

---

## 📥 Использование локальных файлов прошивки (без интернета)

Если у Вас **отсутствует доступ в интернет**, скрипт поддерживает работу с **локально скачанными файлами** прошивки.

### Подготовка локальных файлов

1. **Создайте директорию** для файлов прошивки:

```bash
mkdir -p /tmp/openwrt_images_netis_nx62
```

> ⚠️ **Важно:** Скрипт ожидает файлы именно в этой директории: `/tmp/openwrt_images_netis_nx62`

2. **Скачайте все необходимые файлы** в эту директорию:

```bash
cd /tmp/openwrt_images_netis_nx62

# Загрузчик (FIP)
wget https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-bl31-uboot.fip

# Прелоадер (BL2)
wget https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-preloader.bin

# Recovery-образ
wget https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-initramfs-recovery.itb

# Sysupgrade-образ
wget https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-squashfs-sysupgrade.itb

# Модуль kmod-mtd-rw
wget https://downloads.openwrt.org/releases/25.12.0/targets/mediatek/filogic/kmods/6.12.71-1-60d938adcb727697d3015e4285d4c290/kmod-mtd-rw-6.12.71.2021.02.28~e8776739-r1.apk
```

3. **Проверьте наличие всех файлов**:

```bash
ls -lh /tmp/openwrt_images_netis_nx62/
```

Должны присутствовать:
- `openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-bl31-uboot.fip`
- `openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-preloader.bin`
- `openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-initramfs-recovery.itb`
- `openwrt-25.12.0-mediatek-filogic-netcore_n60-pro-squashfs-sysupgrade.itb`
- `kmod-mtd-rw-6.12.71.2021.02.28~e8776739-r1.apk`

### Запуск скрипта с локальными файлами

После подготовки файлов просто запустите скрипт:

```bash
sudo ./netis-nx62-flash-fw-on-linux.sh
```

Скрипт **автоматически обнаружит отсутствие интернета** и:
- Проверит наличие всех необходимых файлов в `/tmp/openwrt_images_netis_nx62`
- Скопирует файлы во временную директорию для работы
- Продолжит прошивку в обычном режиме

> 💡 **Совет:** Если скрипт сообщает об отсутствии файлов, проверьте, что все 5 файлов присутствуют в директории `/tmp/openwrt_images_netis_nx62` и их имена **точно совпадают** с ожидаемыми.

### Альтернативный способ загрузки файлов

Если у вас есть доступ к интернету с другого компьютера, вы можете:
1. Скачать файлы на другом устройстве
2. Передать их на ПК для прошивки через USB-накопитель
3. Поместить в директорию `/tmp/openwrt_images_netis_nx62`

---

## ⚠️ Важные замечания

- 🔴 **Не прерывайте процесс прошивки** — это может привести к кирпичу роутера
- 💾 **Сделайте резервную копию** перед прошивкой ([02-BACKUP-MTD.md](02-BACKUP-MTD.md))
- 🔌 **Используйте проводное подключение** — WiFi может отключиться в процессе
- ⚡ **Обеспечьте стабильное питание** — используйте ИБП при возможности
- 🌐 **Отключите другие сетевые интерфейсы** — во избежание конфликтов
- 💻 **Требуется ~200 МБ свободного места на ПК** для временных файлов образов

---

## ❓ Часто задаваемые вопросы

**Q: Что делать если скрипт не находит SSH-ключ?**
A: Убедитесь, что ключ сгенерирован и скопирован на роутер (см. Шаг 2)

**Q: Скрипт не может настроить сетевой интерфейс**
A: Проверьте, что интерфейс подключен к роутеру и не используется другими службами

**Q: TFTP-сервер не запускается**
A: Проверьте логи: `sudo journalctl -u tftpd-hpa`

**Q: Роутер не загрузил recovery по TFTP**
A: Убедитесь, что:
- TFTP-сервер запущен и доступен
- Файл recovery находится в `/srv/tftp`
- Брандмауэр не блокирует порт 69/udp

**Q: Прошивка завершилась ошибкой**
A: Проверьте логи в `/var/log/syslog` и попробуйте снова с шага 1

**Q: Можно ли прошить с macOS/Windows?**
A: Данный скрипт предназначен только для Linux (Ubuntu/Debian). Для прошивки с других ОС:
- Используйте виртуальную машину с Linux (VirtualBox, VMware)
- Загрузитесь с LiveUSB с дистрибутивом Linux
- Используйте WSL 2 на Windows с пробросом USB-устройств

---

## 🔍 Восстановление после неудачной прошивки

Если прошивка не удалась:

1. **Попробуйте загрузить recovery вручную** через TFTP
2. **Используйте режим восстановления** (если доступен на вашей модели)
3. **Восстановите загрузчик** через UART/SPI-программатор
4. **Обратитесь к документации** OpenWRT для вашей модели

---

## 📚 Дополнительные ресурсы

- [Настройка SSH доступа](01-SSH-CONNECTION.md)
- [Резервное копирование MTD](02-BACKUP-MTD.md)
- [Резервное копирование конфигурации](03-BACKUP-CONFIG.md)
- [OpenWRT для Netis NX62 (Netcore N60 Pro)](https://openwrt.org/toh/netcore/n60_pro)
- [Официальная документация OpenWRT](https://openwrt.org/docs/guide-user/installation/start)

---

<div align="center">
<b>Netis NX62 Flash Tools</b> | <a href="https://github.com/SevenMaxs/netis-nx62-flash-tools">GitHub</a>
</div>
