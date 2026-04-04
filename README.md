# 🔧 Netis NX62 Flash Tools

Набор скриптов для работы с роутером **Netis NX62** (Netcore N60 Pro): резервное копирование и установка OpenWRT.

## 📦 Состав репозитория

```
├── backup/     # Скрипты для резервного копирования
│   ├── netis-nx62-mtd-backup.sh             # Дамп всех MTD разделов
│   └── netis-nx62-config-backup.sh          # Бекап конфигурационных файлов
├── flash/      # Скрипты для прошивки
│   ├── netis-nx62-flash-fw-on-linux.sh      # Полная прошивка с ПК (Linux)
│   └── netis-nx62-update-fw-on-router.sh    # Обновление прошивки на роутере (On-Router)
├── docs/       # Документация
│   ├── 01-SSH-CONNECTION.md                 # Настройка SSH доступа
│   ├── 01-SSH-CONNECTION-WINDOWS.md         # Настройка SSH доступа на Windows
│   ├── 02-BACKUP-MTD.md                     # Инструкция по бекапу MTD
│   ├── 03-BACKUP-CONFIG.md                  # Инструкция по бекапу конфигураций
│   ├── 04-FLASH-OPENWRT.md                  # Прошивка с ПК через TFTP
│   └── 05-UPDATE-FW-ON-ROUTER.md            # Обновление прошивки на роутере
└── LICENSE     # Лицензия проекта
```

## 🚀 Быстрый старт

1. **Настройте SSH доступ** (см. [docs/01-SSH-CONNECTION.md](docs/01-SSH-CONNECTION.md))
2. **Сделайте бекап разделов** (см. [docs/02-BACKUP-MTD.md](docs/02-BACKUP-MTD.md))
3. **Сделайте бекап конфигураций** (см. [docs/03-BACKUP-CONFIG.md](docs/03-BACKUP-CONFIG.md))
4. **Установите загрузчик и постоянную прошивку OpenWRT** (см. [docs/04-FLASH-OPENWRT.md](docs/04-FLASH-OPENWRT.md))

## 📋 Требования

- Роутер **Netis NX62** / **Netcore N60 Pro**
- Стоковая прошивка
- SSH доступ к роутеру
- ~200 МБ свободного места ОЗУ на роутере (для бекапа MTD)
- ~50 МБ свободного места в `/tmp/tmp` (для прошивки загрузчика)
- **Для прошивки с ПК:** Linux (Ubuntu/Debian) с пакетным менеджером `apt`
- **Для прошивки без интернета:** заранее скачанные файлы прошивки в `/tmp/openwrt_images_netis_nx62`

## 📚 Документация

| Документ | Описание |
|----------|----------|
| [01-SSH-CONNECTION.md](docs/01-SSH-CONNECTION.md) | Настройка SSH доступа с ключом Dropbear |
| [01-SSH-CONNECTION-WINDOWS.md](docs/01-SSH-CONNECTION-WINDOWS.md) | Настройка SSH доступа с ключом Dropbear на Windows |
| [02-BACKUP-MTD.md](docs/02-BACKUP-MTD.md) | Полное резервное копирование MTD разделов |
| [03-BACKUP-CONFIG.md](docs/03-BACKUP-CONFIG.md) | Бекап конфигурационных файлов OpenWRT |
| [04-FLASH-OPENWRT.md](docs/04-FLASH-OPENWRT.md) | Автоматическая прошивка с ПК на Linux через TFTP |
| [05-UPDATE-FW-ON-ROUTER.md](docs/05-UPDATE-FW-ON-ROUTER.md) | Обновление прошивки непосредственно на роутере |

## 👥 Участники

Спасибо следующим людям за их вклад в этот проект:

- [@levtlevt](https://github.com/levtlevt) - Настройка SSH доступа с ключом Dropbear на Windows (PR#4)

---

## ⚠️ Важно

- 🔴 **Скрипты в папке `flash/` требуют особой осторожности** — неправильное использование может привести к неработоспособности роутера
- 💾 **Всегда делайте бекап** перед любыми операциями с прошивкой
- ⚡ **Не прерывайте питание** роутера во время записи загрузчика или прошивки
- 🌐 **Автоматическая прошивка с ПК** поддерживает работу как с интернетом, так и с локальными файлами прошивки

---

<div align="center">

[📘 Настройка SSH](docs/01-SSH-CONNECTION.md) •
[📦 Бекап MTD](docs/02-BACKUP-MTD.md) •
[📋 Бекап конфигураций](docs/03-BACKUP-CONFIG.md) •
[🚀 Прошивка с ПК](docs/04-FLASH-OPENWRT.md) •
[🔄 Обновление на роутере](docs/05-UPDATE-FW-ON-ROUTER.md)

</div>
