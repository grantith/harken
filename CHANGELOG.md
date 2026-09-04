# Changelog

All notable changes to this project are documented here. This changelog is human curated.

## [Unreleased]
### Added
- Screen Search (`super + .`) with clickable hints (like vimium/surfingkeys/homerow but jankier).
- UI Automation support via `src/lib/UIA.ahk` with licensing documentation.
- Command mode action to send windows to their assigned desktops.
- App matching enhancements: process-tree targeting and `ignore_classes` support.
- `docs/COMPILE.md` with build and packaging notes.
- Virtual desktop scroll navigation and move-window scroll support (`super+scroll` & `super+alt+shift+scroll`).
- Optional desktop switch curtain to mask brief background flashes.
- Project now uses CHANGELOG.md
- Optional `modes.carousel` mode with niri-like horizontal focus/move behavior scoped to current virtual desktop and active monitor.
- Carousel mode desktop move follow toggle (`super+f`) and native overview shortcut (`super+o`).
- Carousel mode width controls (`super+-` / `super+=`) and auto-maintained trailing empty desktop support.
- Persistent carousel status bar with desktop count, active desktop highlight, and current strip window titles.
- `[[virtual_desktop.N]]` desktop mappings now support `super+<key>` goto and `super+alt+<key>` no-follow window expel.

### Changed
- Default non-carousel hotkeys now follow a niri-like layout: `super+h/l` focus, `super+j/k` desktop navigation, `super+ctrl+h/j/k/l` window movement, and `super+shift+j/k` window-to-desktop moves.
- Centered resize moved to `super+alt+arrows`; monitor focus/move now uses `super+u/i` and `super+shift+u/i`.
- Legacy `super+alt+h/l` and `super+alt+shift+h/l` virtual desktop defaults are disabled, while config support remains.
- Double-super overview is now disabled by default and can be restored with `window.super_double_tap_action = "overview"`.
- Move mode is entered from command mode, and h/j/k/l navigate Task View.
- Super+scroll switches virtual desktops (replacing the prior super+alt+scroll combo).
- Config flow favors `config_watch` instead of a dedicated reload section.
- Example config updates (apps list and focus border thickness).
- App matching now uses cached window metadata and PID-based lookups for off-desktop windows, with focus diagnostics logging.
- README adds a comparison section with similar tools.
- Config validation favors warnings over hard errors where possible.
- Window manager grid movement hotkeys yield to carousel mode when active.
- Carousel mode now auto-relayouts after external focus changes (Task View selection and app focus hotkeys).
- Carousel tile width adjustments now persist per app executable across restarts.
- Carousel strip order now restores best-effort per desktop+monitor scope using app executable order.
- Non-carousel desktop switching can now skip the post-switch wait for faster focus changes, and trailing empty desktop management now creates and prunes desktops to keep exactly one empty desktop at the end.
- Status bar enablement is now controlled globally from `virtual_desktop.status_bar`, with optional visibility in non-carousel mode.

### Fixed
- Mapped desktop hotkeys now use true super-combo registration so `super+1/2/3/4/5` works with CapsLock/F24 super keys.
- Window walker rendering issues when the resolution changes.
- Window cycling now includes more than two tiles reliably.
- Grid snapping edge cases.
- EnumWindows callback signature.
- UI Automation no longer sets the Windows screen-reader flag, avoiding PowerShell PSReadLine warnings.

## [0.2.1] - 2026-02-07
### Added
- New entry point `harken.ahk` and TOML configuration support with a TOML example config.
- Virtual desktop integration via `VD.ahk` with licensing documentation.

### Changed
- Project rename to Harken and migration away from JSON config.
- Install, release, and build tooling updated for the new name/config.
- README refreshed to reflect the new app name and setup steps.

## [0.2.0] - 2026-02-03
### Added
- Directional focus hotkeys and supporting window focus helpers.
- Window switcher (window walker) UI and hotkeys.
- State store for persisted app state.
- Additional documentation assets for the overlay and switcher UI.

### Changed
- README updates with new features and sources.
- Config example refreshed for the new hotkeys.

## [0.0.1] - 2026-01-28
### Added
- Initial public release of the original script.
