#!/bin/bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly renderer="${script_dir}/render_release_notes.sh"
readonly temporary_directory="$(mktemp -d)"

cleanup() {
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_rejected() {
    local description="$1"
    shift

    if "$renderer" "$@" >"${temporary_directory}/stdout" 2>"${temporary_directory}/stderr"; then
        fail "$description was accepted"
    fi
}

"$renderer" v0.5.0 >"${temporary_directory}/actual"

cat >"${temporary_directory}/expected" <<'EOF'
## English

### Added

- Experimental MiniMax Global Token Plan usage source for remaining capacity.
- Subscription Key setup in Settings, with each saved key stored only in the macOS Keychain.
- MiniMax account controls in Settings for managing its Subscription Key.
- MiniMax quota presentation on the dashboard, with independent Current and Weekly windows for each supported category.

### Notes

- The MiniMax source is opt-in and experimental. It supports the Global personal Default Team boundary only; it does not combine Teams, regions, or credentials.

## Русский

### Добавлено

- Экспериментальный источник использования MiniMax Global Token Plan для просмотра оставшихся лимитов.
- Настройка Subscription Key в Settings; каждый сохранённый ключ хранится только в macOS Keychain.
- Элементы управления аккаунтом MiniMax в Settings для управления его Subscription Key.
- Представление квот MiniMax на dashboard с независимыми окнами Current и Weekly для каждой поддерживаемой категории.

### Примечания

- Источник MiniMax подключается пользователем по желанию и является экспериментальным. Он поддерживает только Global personal Default Team и не объединяет Teams, регионы или credentials.
EOF

if ! diff -u "${temporary_directory}/expected" "${temporary_directory}/actual"; then
    fail 'v0.5.0 output did not match the release notes source'
fi

"$renderer" v0.6.0 >"${temporary_directory}/actual"

cat >"${temporary_directory}/expected" <<'EOF'
## English

### Added

- Ollama Cloud's experimental web-page source now recognizes the monthly
  `Included usage` meter and shows its used amount, limit, percentage, and reset
  time when available.
- Ollama usage refreshes now accept whichever supported usage sections the
  settings page exposes: Session, Weekly, Monthly, or a combination of them.

### Changed

- Bairometer now uses its final technical identity throughout the app bundle,
  helper, storage, Keychain service, signing, and release archives.

### Upgrade Notes

- This is a breaking pre-release rename. Provider accounts, isolated web
  sessions, Keychain credentials, and Claude Code `statusLine` configuration
  from an earlier pre-release installation are not migrated automatically.
  Configure affected accounts again and reinstall the bundled `statusLine`
  helper from Settings.

## Русский

### Добавлено

- Экспериментальный источник Ollama Cloud теперь распознаёт месячный индикатор
  `Included usage` и показывает использованную сумму, лимит, процент и время
  сброса, когда они доступны.
- Обновление использования Ollama теперь принимает любые поддерживаемые
  разделы страницы Settings: Session, Weekly, Monthly или их сочетание.

### Изменено

- Bairometer теперь использует окончательную техническую идентичность в
  bundle приложения, helper, хранилище, сервисе Keychain, signing и архивах
  релиза.

### При обновлении

- Это несовместимое prerelease-переименование. Аккаунты провайдеров,
  изолированные web-сессии, credentials в Keychain и конфигурация Claude Code
  `statusLine` из прежней prerelease-установки автоматически не переносятся.
  Настройте нужные аккаунты заново и переустановите bundled `statusLine`
  helper из Settings.
EOF

if ! diff -u "${temporary_directory}/expected" "${temporary_directory}/actual"; then
    fail 'v0.6.0 output did not match the release notes source'
fi

assert_rejected 'missing version'
assert_rejected 'invalid semantic version' 0.5.0
assert_rejected 'noncanonical semantic version' v01.2.3
assert_rejected 'missing changelog section' v9.9.9

printf 'PASS: release notes renderer\n'
