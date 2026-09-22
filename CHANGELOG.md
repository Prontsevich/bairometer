# Changelog

All notable changes to Bairometer are documented in this file.

## v0.6.0 - 2026-09-22

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

## v0.5.0 - 2026-08-28

### Added

- Experimental MiniMax Global Token Plan usage source for remaining capacity.
- Subscription Key setup in Settings, with each saved key stored only in the macOS Keychain.
- MiniMax account controls in Settings for managing its Subscription Key.
- MiniMax quota presentation on the dashboard, with independent Current and Weekly windows for each supported category.

### Notes

- The MiniMax source is opt-in and experimental. It supports the Global personal Default Team boundary only; it does not combine Teams, regions, or credentials.
