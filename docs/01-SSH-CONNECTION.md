
---

# 🔐 Настройка SSH доступа к роутеру Netis NX62

## 📦 1. Установка необходимых пакетов
```bash
sudo apt update && sudo apt install openssh-client wget -y
```

## 🔑 2. Генерация SSH ключа для роутера
```bash
ssh-keygen -t rsa -b 2048 -N "" -f ~/.ssh/dropbear_key
```

## ⚙️ 3. Настройка SSH конфига

Создайте или отредактируйте `~/.ssh/config`:

```bash
cat >> ~/.ssh/config << 'EOF'

# Netis NX62 Router
Host netis-nx62
    HostName 192.168.1.1
    User useradmin
    IdentityFile ~/.ssh/dropbear_key
    IdentitiesOnly yes
EOF
```

## 📤 4. Добавление публичного ключа на роутер
```bash
cat ~/.ssh/dropbear_key.pub | ssh useradmin@192.168.1.1 'cat >> /etc/dropbear/authorized_keys'
```

## 🔄 5. Перезагрузка роутера
```bash
ssh useradmin@192.168.1.1 'reboot'
```

## ✅ 6. Проверка подключения
```bash
ssh netis-nx62 'echo "SSH работает! Хост: $(cat /proc/sys/kernel/hostname)"'
```

---

### 📌 Примечания:
- После перезагрузки подождите 1-2 минуты пока роутер загрузится
- Теперь можно подключаться командой: `ssh netis-nx62`
- Для копирования файлов: `scp -O файл netis-nx62:/tmp/`

---
<div align="center">
<b>Netis NX62 Flash Tools</b> | <a href="https://github.com/SevenMaxs/netis-nx62-flash-tools">GitHub</a>
</div>
