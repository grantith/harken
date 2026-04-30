# Agent Notes

This repo is AutoHotkey v2 code intended for open-source distribution. Use this file as the
canonical guidance for agentic edits.

No Cursor rules found in `.cursor/rules/` or `.cursorrules`.
No Copilot instructions found in `.github/copilot-instructions.md`.

## Quick Context
- Entry point: `harken.ahk`.
- Source modules: `src/` (hotkeys, window management, UI helpers, config loader).
- Tools: `tools/` (build script, inspector utilities).
- Config example: `config/config.example.toml` (user config lives outside the repo).

## Build / Lint / Test
This repo does not currently use a formal test or lint framework.

Build (local, produces `dist/`):
- `powershell -ExecutionPolicy Bypass -File tools/build_release.ps1 -Version dev`

Release build (tagged):
- GitHub Actions handles releases on tag push (see `.github/workflows/release.yml`).

Dev build (CI):
- GitHub Actions runs `tools/build_release.ps1 -Version dev` on `main`/`dev` when `src/` changes.

Single test / focused run:
- No unit test runner exists. Use manual verification steps (launch `harken.ahk`, validate
  hotkeys, reload flow, and Command Overlay) or run targeted helper tools in `tools/`.
- Focused validation (pick relevant items):
  - Launch `harken.ahk` with a clean config and verify: super hotkeys, window cycling, overlay.
  - If virtual desktops touched: test `super+alt+h/l`, mapped desktop hotkeys, and tray indicator.

## Code Style Guidelines

Comment the "why" in and around code to help provide context from the instructions and conversations leading to changes.

### AutoHotkey version and file headers
- Use AutoHotkey v2 syntax and conventions.
- Virtual desktop integration requires AutoHotkey v2.1 alpha (VD.ahk dependency).
- Keep `#Requires AutoHotkey v2.0` in entry points and new top-level scripts unless a file
  specifically requires v2.1 alpha features.
- Keep `#Include` statements at the top and ordered by dependency.

### Formatting
- Indentation: 4 spaces (no tabs).
- Use blank lines to separate logical blocks and sections.
- Keep lines readable; avoid overly long expressions.
- Stick to ASCII unless the existing file uses Unicode and it is necessary.

### Naming
- Functions: PascalCase (e.g., `LoadConfig`, `ValidateNode`).
- Local variables: lower_snake_case (e.g., `config_path`, `reload_mode_active`).
- Constants: UPPER_SNAKE_CASE only if truly constant across modules; otherwise use locals.
- Files: lower_snake_case for new modules, match existing patterns under `src/lib/` and `src/hotkeys/`.

### Types and data structures
- Prefer `Map()` for objects and key-value config structures.
- Prefer `Array()` or `[]` for ordered lists.
- Keep config maps shallow when possible; nested maps should be validated in schema.
- Use `CloneMap` / `CloneArray` style helpers for defensive copies.

### Imports and module structure
- Keep modules focused by domain (hotkeys, window management, utilities).
- Avoid circular dependencies; shared helpers should live in `src/lib/`.
- `harken.ahk` should remain the only top-level orchestrator.

### Error handling
- Use `try`/`catch` for file IO and JSON parsing; return structured errors where possible.
- Use clear, user-facing error messages for missing dependencies or invalid config.
- For config validation, return error arrays and handle them in the entry point.
- Avoid throwing for normal control flow.
- Guard `WinGetID("A")` calls when no active window is possible (use `try`/`catch`).

### Config handling
- Keep user configuration separate from core behavior.
- Do not edit or delete user config without backup.
- Validate config with schema before registering hotkeys.
- When adding config keys, update:
  - `DefaultConfig()` in `harken.ahk`
  - Schema in `src/lib/config_loader.ahk`
  - `config/config.example.toml`
  - `README.md`
- If adding virtual desktop hotkeys:
  - Normalize new config formats in `NormalizeVirtualDesktopConfig`.
  - Update debug logs and config validation for duplicate hotkeys.

### Hotkeys and window behavior
- Keep hotkey registration centralized under `src/hotkeys/`.
- Avoid direct global state unless required; prefer explicit `global` declarations when needed.
- For window manipulation, consider edge cases with elevated windows and multiple monitors.
- Be careful with modifier ordering: use `HotIf` guards and wildcard hotkeys when needed.

### UI helpers
- GUI helpers (overlays, inspectors) should remain non-blocking and lightweight.
- Prefer explicit refresh actions instead of continuous loops when possible.
- Command overlay behavior:
  - Normal mode: `super + /` shows temporary overlay; any key hides it.
  - Command/move modes: overlay stays visible and is centered on screen.

### Third-party code
- Keep third-party code in `src/lib/` and document licensing in `LICENSES/`.
- Update `README.md` under the Third-Party section when adding a dependency.
- Preserve license headers in vendored files.

## Repo Agreements
- Prefer small, composable modules with explicit inputs and outputs.
- Avoid breaking changes without a migration path.
- Keep new features optional and discoverable.
- Keep `README.md` and `AGENTS.md` aligned with current behavior.
- Maintain `CHANGELOG.md` for user-facing changes:
  - Add entries under `Unreleased` as part of feature/behavior work.
  - Move entries into a versioned section when cutting a release.

## Suggested Manual Checks
- Launch `harken.ahk` with a clean `harken.toml` and verify hotkeys.
- Validate reload flow (command mode).
- Confirm Command Overlay and helper tools still open and update.
- If touching config schema, ensure errors log correctly in `%APPDATA%\harken\config.errors.log`.
- If touching tray indicator: confirm tray icon updates on desktop change.
- If touching cycling: verify `super+c` (all desktops) and `super+shift+c` (current desktop).

## Paths and Layout Notes
- Main script: `harken.ahk`.
- Config loader: `src/lib/config_loader.ahk` (schema + validation).
- JSON parsing: `src/lib/JXON.ahk`.
- Window manager: `src/lib/window_manager.ahk`.
- Hotkeys: `src/hotkeys/*.ahk`.
- Virtual desktop helpers: `src/lib/virtual_desktop.ahk` + `src/lib/VD.ahk`.

## Build Artifacts
- `dist/harken.exe`
- `dist/harken-source-<version>.zip`
- `dist/harken-<version>-win64.zip`

## When In Doubt
- Keep behavior consistent with existing hotkeys and overlays.
- Document any new public functions or configuration keys.
- Favor explicitness over cleverness.

## Recent Project-Specific Notes
- Debug logs:
  - `virtual_desktop.debug_cycle` writes `%APPDATA%\harken\cycle.debug.log`.
  - `virtual_desktop.debug_hotkeys` writes `%APPDATA%\harken\vd.hotkeys.log` and `vd.actions.log`.
  - Logs reset on startup when debug flags are enabled.
- Tray indicator:
  - `virtual_desktop.tray_indicator` draws `{current}/{total}` on the existing tray icon.
  - Tooltip uses `virtual_desktop.tray_format`.
- Window cycling across desktops uses a cache to include off-desktop windows.
