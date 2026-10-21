#!/usr/bin/env bash
#===============================================================================
# install-apple-tools.sh — Установка инструментов для работы с IPA на macOS/Windows
#===============================================================================
# Описание: Кроссплатформенный скрипт для установки ipatool (macOS) и
# IPA_Downloader, iCloud, iTunes (Windows) в папку appleDownloader
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
# Константы и конфигурация
#-------------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "${0}")"

# Определение директорий: при запуске через curl | bash BASH_SOURCE[0] не установлен
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    # Скрипт запущен как файл (bash script.sh или source script.sh)
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
    readonly APPLE_DOWNLOADER_DIR="${PROJECT_ROOT}/appleDownloader"
    readonly LOG_DIR="${PROJECT_ROOT}/logs"
else
    # Скрипт запущен через pipe (curl | bash) — используем временные пути
    readonly SCRIPT_DIR="${HOME}/.local/share/install-apple-tools"
    readonly PROJECT_ROOT="${SCRIPT_DIR}"
    readonly APPLE_DOWNLOADER_DIR="${PROJECT_ROOT}/appleDownloader"
    readonly LOG_DIR="${PROJECT_ROOT}/logs"
fi

readonly DOWNLOAD_DIR="${HOME}/Downloads"
readonly LOG_FILE="${LOG_DIR}/install-apple-tools-$(date +%Y%m%d-%H%M%S).log"

# Версии и URL
readonly IPATOOL_VERSION="2.3.2-sapfix.2"
readonly IPATOOL_REPO="ipatool-sapfix"
readonly IPATOOL_BASE_URL="https://github.com/${IPATOOL_REPO}/releases/download/v${IPATOOL_VERSION}"

# Windows URLs
readonly IPA_DOWNLOADER_REPO="kda2495/IPA_Downloader"
readonly ICLOUD_URL="http://updates-http.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe"
readonly ITUNES_URL="https://secure-appldnld.apple.com/itunes12/140-75773-20260908-6e5e0165-99cb-4b30-b541-1b615fccfc1a/iTunes64Setup.exe"

# Минимальная версия macOS для Apple Configurator
readonly MIN_MACOS_VERSION="10.15.6"  # Apple Configurator требует macOS 10.15.6+

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# Утилиты логирования
#-------------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

log() {
    local level="${1}"
    shift
    local message="${*}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info()  { log "INFO"  "${BLUE}${*}${NC}"; }
log_ok()    { log "OK"    "${GREEN}${*}${NC}"; }
log_warn()  { log "WARN"  "${YELLOW}${*}${NC}"; }
log_error() { log "ERROR" "${RED}${*}${NC}"; }
log_step()  { log "STEP"  "${CYAN}${*}${NC}"; }

#-------------------------------------------------------------------------------
# Вспомогательные функции
#-------------------------------------------------------------------------------
show_usage() {
    cat << EOF
Использование: ${SCRIPT_NAME} [ОПЦИИ]

ОПЦИИ:
    -h, --help          Показать эту справку
    -v, --verbose       Подробный вывод
    --dry-run           Показать что будет сделано, не выполняя
    --skip-macos-check  Пропустить проверку версии macOS (только для тестов)
    --force             Принудительная переустановка

ПРИМЕРЫ:
    ${SCRIPT_NAME}                    # Стандартная установка
    ${SCRIPT_NAME} --verbose          # С подробным выводом
    ${SCRIPT_NAME} --dry-run          # Проверка без изменений

EOF
}

parse_args() {
    VERBOSE=false
    DRY_RUN=false
    SKIP_MACOS_CHECK=false
    FORCE_INSTALL=false

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-macos-check)
                SKIP_MACOS_CHECK=true
                shift
                ;;
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            *)
                log_error "Неизвестная опция: ${1}"
                show_usage
                exit 1
                ;;
        esac
    done
}

run_cmd() {
    local cmd="${*}"
    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY-RUN] ${cmd}"
        return 0
    fi
    if [[ "${VERBOSE}" == true ]]; then
        log_info "Выполняется: ${cmd}"
    fi
    eval "${cmd}"
}

version_ge() {
    # Проверяет, что версия $1 >= версии $2
    # Использует sort -V для сравнения версий
    [[ "$(printf '%s\n' "${2}" "${1}" | sort -V | head -n1)" == "${2}" ]]
}

get_macos_version() {
    sw_vers -productVersion
}

get_macos_build() {
    sw_vers -buildVersion
}

check_macos_version() {
    local current_version
    current_version="$(get_macos_version)"

    log_step "Проверка версии macOS: ${current_version}"

    if ! version_ge "${current_version}" "${MIN_MACOS_VERSION}"; then
        log_error "macOS ${current_version} ниже минимально требуемой версии ${MIN_MACOS_VERSION}"
        log_error "Apple Configurator требует macOS ${MIN_MACOS_VERSION} или новее"
        log_error "Обновите macOS перед продолжением установки"
        return 1
    fi

    log_ok "Версия macOS ${current_version} соответствует требованиям (>= ${MIN_MACOS_VERSION})"
    return 0
}

# URL Apple Configurator 2 в Mac App Store
readonly APPLE_CONFIGURATOR_APP_STORE_URL="https://apps.apple.com/app/apple-configurator-2/id1037126344"
readonly APPLE_CONFIGURATOR_BUNDLE_ID="com.apple.configurator2"
readonly HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Проверка и установка Homebrew
ensure_homebrew() {
    log_step "Проверка Homebrew"
    
    if command -v brew &>/dev/null; then
        local version
        version="$(brew --version | head -n1)"
        log_ok "Homebrew уже установлен: ${version}"
        return 0
    fi

    log_warn "Homebrew не найден"
    
    if [[ "${DRY_RUN}" == true ]]; then
        log_warn "[DRY-RUN] Пропуск установки Homebrew"
        return 1
    fi

    log_info "Установка Homebrew..."
    run_cmd "/bin/bash -c \"$(curl -fsSL ${HOMEBREW_INSTALL_URL})\"" || {
        log_error "Не удалось установить Homebrew"
        log_error "Попробуйте вручную: /bin/bash -c \"$(curl -fsSL ${HOMEBREW_INSTALL_URL})\""
        return 1
    }

    # Добавляем brew в PATH для текущей сессии (Apple Silicon)
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f "/usr/local/bin/brew" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        log_ok "Homebrew успешно установлен"
        return 0
    else
        log_error "Homebrew установлен, но не найден в PATH"
        return 1
    fi
}

# Установка mas (Mac App Store CLI)
ensure_mas() {
    log_step "Проверка mas (Mac App Store CLI)"

    if command -v mas &>/dev/null; then
        local version
        version="$(mas version 2>/dev/null || echo "unknown")"
        log_ok "mas уже установлен: ${version}"
        return 0
    fi

    log_warn "mas не найден"

    # Сначала убеждаемся, что Homebrew есть
    if ! ensure_homebrew; then
        log_error "Homebrew не установлен, не могу установить mas"
        return 1
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        log_warn "[DRY-RUN] Пропуск установки mas"
        return 1
    fi

    log_info "Установка mas через Homebrew..."
    run_cmd "brew install mas" || {
        log_error "Не удалось установить mas"
        return 1
    }

    if command -v mas &>/dev/null; then
        log_ok "mas успешно установлен"
        return 0
    else
        log_error "mas установлен, но не найден в PATH"
        return 1
    fi
}

# Установка Apple Configurator через mas (Mac App Store CLI) или открытие App Store
install_apple_configurator() {
    log_step "Попытка установки Apple Configurator"

    # Сначала убеждаемся, что mas установлен
    if ! ensure_mas; then
        log_warn "Не удалось подготовить mas"
        log_info "Открываем страницу App Store для ручной установки..."
        run_cmd "open '${APPLE_CONFIGURATOR_APP_STORE_URL}'"
        return 1
    fi

    log_info "Найден mas (Mac App Store CLI), пытаемся установить..."
    run_cmd "mas install 1037126344" || {
        log_warn "Установка через mas не удалась (возможно, не авторизованы в App Store)"
        log_info "Открываем страницу App Store для ручной установки..."
        run_cmd "open '${APPLE_CONFIGURATOR_APP_STORE_URL}'"
        return 1
    }
    log_ok "Apple Configurator установлен через mas"
    return 0
}

check_apple_configurator() {
    log_step "Проверка наличия Apple Configurator"

    # Проверяем через Spotlight/mdfind (bundle ID для версии 2)
    local configurator_path
    configurator_path="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.configurator2'" 2>/dev/null | head -n1)"

    if [[ -n "${configurator_path}" && -d "${configurator_path}" ]]; then
        local version
        version="$(defaults read "${configurator_path}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
        log_ok "Apple Configurator найден: ${configurator_path} (версия ${version})"
        return 0
    fi

    # Проверяем в /Applications — ищем оба варианта имени
    for app_name in "Apple Configurator.app" "Apple Configurator 2.app"; do
        local app_path="/Applications/${app_name}"
        if [[ -d "${app_path}" ]]; then
            local version
            version="$(defaults read "${app_path}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
            log_ok "Apple Configurator найден в /Applications: ${app_name} (версия ${version})"
            return 0
        fi
    done

    log_warn "Apple Configurator не найден в системе"
    
    # Предлагаем установку
    if [[ "${DRY_RUN}" != true ]]; then
        log_info "Apple Configurator 2 можно установить только через Mac App Store"
        log_info "Попробуем установить автоматически..."
        install_apple_configurator
        
        # Проверяем снова после попытки установки
        sleep 2
        configurator_path="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.configurator2'" 2>/dev/null | head -n1)"
        if [[ -n "${configurator_path}" && -d "${configurator_path}" ]]; then
            local version
            version="$(defaults read "${configurator_path}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
            log_ok "Apple Configurator успешно установлен: ${configurator_path} (версия ${version})"
            return 0
        fi
        
        for app_name in "Apple Configurator.app" "Apple Configurator 2.app"; do
            local app_path="/Applications/${app_name}"
            if [[ -d "${app_path}" ]]; then
                local version
                version="$(defaults read "${app_path}/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")"
                log_ok "Apple Configurator найден в /Applications: ${app_name} (версия ${version})"
                return 0
            fi
        done
        
        log_warn "Автоматическая установка не удалась"
        log_warn "Установите вручную: ${APPLE_CONFIGURATOR_APP_STORE_URL}"
        log_warn "После установки запустите скрипт снова"
    else
        log_warn "[DRY-RUN] Пропуск попытки установки Apple Configurator"
        log_warn "Установите вручную: ${APPLE_CONFIGURATOR_APP_STORE_URL}"
    fi
    return 1
}

check_command() {
    local cmd="${1}"
    local name="${2:-${cmd}}"

    if command -v "${cmd}" &>/dev/null; then
        local version
        # Используем timeout для предотвращения зависания (например, ipatool --version)
        version="$(timeout 5 ${cmd} --version 2>/dev/null | head -n1 || echo "unknown")"
        log_ok "${name} уже установлен: ${version}"
        return 0
    fi
    log_info "${name} не найден, будет установлен"
    return 1
}

ensure_directory() {
    local dir="${1}"
    if [[ ! -d "${dir}" ]]; then
        log_step "Создание директории: ${dir}"
        run_cmd "mkdir -p '${dir}'"
    else
        log_info "Директория уже существует: ${dir}"
    fi
}

download_file() {
    local url="${1}"
    local output="${2}"
    local description="${3:-файл}"

    log_step "Скачивание ${description}: ${url}"

    if [[ -f "${output}" && "${FORCE_INSTALL}" != true ]]; then
        log_info "${description} уже существует, пропуск (используйте --force для перезаписи)"
        return 0
    fi

    run_cmd "curl -L --fail --progress-bar -o '${output}' '${url}'"
    log_ok "${description} скачан: ${output}"
}

extract_archive() {
    local archive="${1}"
    local dest_dir="${2}"

    log_step "Распаковка архива: ${archive}"

    run_cmd "tar -xzf '${archive}' -C '${dest_dir}'"
    log_ok "Архив распакован в: ${dest_dir}"
}

#-------------------------------------------------------------------------------
# macOS установка
#-------------------------------------------------------------------------------
install_macos() {
    log_step "=== Установка для macOS ==="

    # 1. Проверка версии macOS
    if [[ "${SKIP_MACOS_CHECK}" != true ]]; then
        if ! check_macos_version; then
            log_error "Установка прервана: несовместимая версия macOS"
            exit 1
        fi
    else
        log_warn "Проверка версии macOS пропущена (--skip-macos-check)"
    fi

    # 2. Проверка Apple Configurator 2
    check_apple_configurator || true  # Не прерываем, только предупреждаем

    # 3. Определение архитектуры
    local arch
    arch="$(uname -m)"
    log_step "Архитектура системы: ${arch}"

    local ipatool_archive
    local ipatool_binary
    local ipatool_extracted_name

    case "${arch}" in
        arm64)
            ipatool_archive="ipatool-${IPATOOL_VERSION}-macos-arm64.tar.gz"
            ipatool_binary="ipatool-${IPATOOL_VERSION}-macos-arm64"
            ipatool_extracted_name="bin/ipatool-${IPATOOL_VERSION}-macos-arm64"
            ;;
        x86_64)
            ipatool_archive="ipatool-${IPATOOL_VERSION}-macos-amd64.tar.gz"
            ipatool_binary="ipatool-${IPATOOL_VERSION}-macos-amd64"
            ipatool_extracted_name="bin/ipatool-${IPATOOL_VERSION}-macos-amd64"
            ;;
        *)
            log_error "Неподдерживаемая архитектура: ${arch}"
            exit 1
            ;;
    esac

    # 4. Проверка, установлен ли уже ipatool
    if check_command "ipatool" "ipatool" && [[ "${FORCE_INSTALL}" != true ]]; then
        log_ok "ipatool уже установлен, пропуск установки"
        return 0
    fi

    # 5. Подготовка директорий
    ensure_directory "${DOWNLOAD_DIR}"
    ensure_directory "/usr/local/bin"
    ensure_directory "${APPLE_DOWNLOADER_DIR}"

    # 6. Скачивание ipatool
    local archive_path="${DOWNLOAD_DIR}/${ipatool_archive}"
    local download_url="${IPATOOL_BASE_URL}/${ipatool_archive}"

    download_file "${download_url}" "${archive_path}" "ipatool (${arch})"

    # 7. Распаковка и установка
    local extract_dir="${DOWNLOAD_DIR}/ipatool-extract-$$"
    ensure_directory "${extract_dir}"

    extract_archive "${archive_path}" "${extract_dir}"

    local binary_path="${extract_dir}/${ipatool_extracted_name}"

    if [[ ! -f "${binary_path}" ]]; then
        # Попробуем найти бинарник
        binary_path="$(find "${extract_dir}" -name 'ipatool*' -type f -perm +111 2>/dev/null | head -n1)"
        if [[ -z "${binary_path}" ]]; then
            log_error "Не найден исполняемый файл ipatool в архиве"
            log_error "Содержимое архива:"
            run_cmd "find '${extract_dir}' -type f | head -20"
            exit 1
        fi
    fi

    log_step "Установка ipatool в /usr/local/bin/ipatool"
    run_cmd "sudo install -m 0755 '${binary_path}' /usr/local/bin/ipatool"

    # 8. Очистка временных файлов
    run_cmd "rm -rf '${extract_dir}'"

    # 9. Проверка установки
    log_step "Проверка установки ipatool"
    if check_command "ipatool" "ipatool"; then
        log_ok "ipatool успешно установлен!"
        run_cmd "ipatool --version"
    else
        log_error "Установка ipatool не удалась"
        exit 1
    fi
}

#-------------------------------------------------------------------------------
# Windows установка (через WSL или Git Bash)
#-------------------------------------------------------------------------------
install_windows() {
    log_step "=== Установка для Windows ==="

    # Проверяем, что мы в WSL или Git Bash
    if [[ ! -f /proc/version ]] || ! grep -qi microsoft /proc/version 2>/dev/null; then
        if [[ "${OSTYPE}" != "msys" && "${OSTYPE}" != "cygwin" ]]; then
            log_warn "Скрипт запущен не в WSL/Git Bash. Для Windows рекомендуется запускать в WSL2 или Git Bash"
        fi
    fi

    ensure_directory "${APPLE_DOWNLOADER_DIR}"

    log_step "Скачивание компонентов в: ${APPLE_DOWNLOADER_DIR}"

    # 1. IPA_Downloader - получаем последнюю версию с GitHub
    log_step "Получение информации о последней версии IPA_Downloader"
    local api_url="https://api.github.com/repos/${IPA_DOWNLOADER_REPO}/releases/latest"
    local release_info
    release_info="$(run_cmd "curl -s '${api_url}'")"

    local download_url
    download_url="$(echo "${release_info}" | grep -o '"browser_download_url": "[^"]*\.zip"' | head -n1 | cut -d'"' -f4)"

    if [[ -z "${download_url}" ]]; then
        log_error "Не удалось найти ZIP-архив в последнем релизе IPA_Downloader"
        log_info "Проверьте вручную: https://github.com/${IPA_DOWNLOADER_REPO}/releases"
        return 1
    fi

    local ipa_downloader_zip="${APPLE_DOWNLOADER_DIR}/IPA_Downloader_latest.zip"
    download_file "${download_url}" "${ipa_downloader_zip}" "IPA_Downloader"

    # Распаковка IPA_Downloader
    local ipa_downloader_dir="${APPLE_DOWNLOADER_DIR}/IPA_Downloader"
    ensure_directory "${ipa_downloader_dir}"
    log_step "Распаковка IPA_Downloader"
    run_cmd "unzip -o '${ipa_downloader_zip}' -d '${ipa_downloader_dir}'"
    log_ok "IPA_Downloader распакован в: ${ipa_downloader_dir}"

    # 2. iCloud
    local icloud_exe="${APPLE_DOWNLOADER_DIR}/iCloudSetup.exe"
    download_file "${ICLOUD_URL}" "${icloud_exe}" "iCloud Setup"

    # 3. iTunes
    local itunes_exe="${APPLE_DOWNLOADER_DIR}/iTunes64Setup.exe"
    download_file "${ITUNES_URL}" "${itunes_exe}" "iTunes 64-bit"

    log_ok "Все компоненты для Windows скачаны и распакованы в ${APPLE_DOWNLOADER_DIR}"
    log_info "Структура:"
    log_info "  ${APPLE_DOWNLOADER_DIR}/IPA_Downloader/     — распакованное приложение"
    log_info "  ${APPLE_DOWNLOADER_DIR}/iCloudSetup.exe     — установщик iCloud"
    log_info "  ${APPLE_DOWNLOADER_DIR}/iTunes64Setup.exe   — установщик iTunes"
    log_info ""
    log_info "Запустите установку:"
    log_info "  1. iCloudSetup.exe"
    log_info "  2. iTunes64Setup.exe"
    log_info "  3. IPA_Downloader — запустите .exe из папки IPA_Downloader/"
}

#-------------------------------------------------------------------------------
# Основная функция
#-------------------------------------------------------------------------------
main() {
    log_step "Запуск ${SCRIPT_NAME}"
    log_info "Проект: ${PROJECT_ROOT}"
    log_info "Лог: ${LOG_FILE}"

    parse_args "$@"

    # Определение платформы
    local platform
    case "$(uname -s)" in
        Darwin)
            platform="macos"
            ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                platform="windows-wsl"
            else
                platform="linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            platform="windows"
            ;;
        *)
            platform="unknown"
            ;;
    esac

    log_info "Обнаружена платформа: ${platform}"

    case "${platform}" in
        macos)
            install_macos
            ;;
        windows|windows-wsl)
            install_windows
            ;;
        linux)
            log_error "Linux не поддерживается этим скриптом"
            exit 1
            ;;
        *)
            log_error "Неизвестная платформа: ${platform}"
            exit 1
            ;;
    esac

    log_ok "Установка завершена успешно!"
    log_info "Лог сохранён в: ${LOG_FILE}"
}

# Запуск: если скрипт запущен как файл (не через pipe) — проверяем BASH_SOURCE
# Если через pipe (curl | bash) — BASH_SOURCE не установлен, запускаем main всегда
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi