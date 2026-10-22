# install-apple-tools.sh

Универсальный скрипт установки инструментов для работы с IPA:
- **macOS**: ipatool + Apple Configurator 2 (автоустановка через `mas`)
- **Windows**: IPA_Downloader + iCloud + iTunes

## Установка одной командой

```bash
# macOS / Linux (WSL)
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash

# С параметрами
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash -s -- --verbose
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash -s -- --dry-run
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash -s -- --force
```

## Что делает скрипт

### macOS:
1. Проверяет версию macOS (≥ 10.15.6)
2. Проверяет/устанавливает Apple Configurator 2 (через `mas` или открывает App Store)
3. Определяет архитектуру (arm64/x86_64)
4. Скачивает и устанавливает ipatool в `/usr/local/bin`

### Windows (WSL/Git Bash):
1. Скачивает последнюю версию IPA_Downloader с GitHub
2. Распаковывает в папку `IPA_Downloader/`
3. Скачивает `iCloudSetup.exe` и `iTunes64Setup.exe`
4. Все файлы кладутся в папку `appleDownloader/`

## Опции

| Опция | Описание |
|-------|----------|
| `-h, --help` | Показать справку |
| `-v, --verbose` | Подробный вывод |
| `--dry-run` | Показать что будет сделано, не выполняя |
| `--skip-macos-check` | Пропустить проверку версии macOS (для тестов) |
| `--force` | Принудительная переустановка |

## Требования

- **macOS**: 10.15.6+ (для Apple Configurator 2)
- **Windows**: 10/11 с WSL2 или Git Bash
- **Инструменты**: `curl`, `unzip`, `tar`, `sudo`
- **Опционально**: `mas` (Mac App Store CLI) для автоустановки Configurator
  ```bash
  brew install mas
  ```

## Установка Git Bash на Windows

Git Bash — это эмулятор терминала, включающий bash и базовые Unix-утилиты. Он поставляется вместе с **Git for Windows**.

### Способ 1: Официальный установщик (рекомендуется)

1. Скачайте установщик с официального сайта: https://git-scm.com/download/win
2. Запустите `.exe` файл
3. В настройках установки оставьте значения по умолчанию, **важно**:
   - ✅ **Use Git from the Windows Command Prompt** (или "Git from the command line and also from 3rd-party software")
   - ✅ **Use the OpenSSL library**
   - ✅ **Checkout Windows-style, commit Unix-style line endings**
   - ✅ **Use MinTTY** (терминал по умолчанию для Git Bash)
4. После установки откройте **Git Bash** из меню Пуск

### Способ 2: Через winget (Windows 10/11)

```powershell
# В PowerShell от имени администратора
winget install --id Git.Git -e --source winget
```

### Способ 3: Через Chocolatey

```powershell
# В PowerShell от имени администратора
choco install git -y
```

### Способ 4: Через Scoop

```powershell
scoop install git
```

### Проверка установки

Откройте **Git Bash** и выполните:

```bash
bash --version
# Должно показать что-то вроде: GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)

curl --version
# Должно показать версию curl

git --version
# Должно показать версию Git
```

После этого скрипт запустится в Git Bash так же, как на macOS/Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash -s -- --verbose
```

## Логирование

Все действия логируются в:
```
~/development/sh-scripts/logs/install-apple-tools-<timestamp>.log
```

## Примеры использования

```bash
# Стандартная установка
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash

# Проверка без изменений
curl -fsSL https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh | bash -s -- --dry-run

# Сохранить локально и запустить
curl -fsSL -o install-apple-tools.sh https://raw.githubusercontent.com/aekozhevnikov/apple-tools-installer/main/install-apple-tools.sh
chmod +x install-apple-tools.sh
./install-apple-tools.sh --verbose
```

## Как работает установка Apple Configurator 2

Скрипт проверяет наличие Apple Configurator. Если не найден:
1. Пытается найти `mas` (Mac App Store CLI)
2. Если `mas` есть — выполняет `mas install 1037126344`
3. Если `mas` нет — открывает страницу App Store в браузере
4. После установки проверяет снова

> **Важно**: Apple Configurator 2 можно установить только через Mac App Store. Прямых ссылок на `.dmg`/`.pkg` нет.

## Лицензия

MIT