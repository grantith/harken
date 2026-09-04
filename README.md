# Harken
A window manager written in AutoHotkey v2.

Harken allows a keyboard-centered workflow on Windows: a single super modifier, mnemonic app keys, and fast window actions. Alt+Tab and Win+Tab still work, but you will hardly use them.

## Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Default Config Keys](#default-config-keys)
- [Window Matching](#window-matching)
- [Path Expansion](#path-expansion)
- [Window Manager Exceptions](#window-manager-exceptions)
- [Helper Utility](#helper-utility)
- [Command Overlay](#command-overlay)
- [Known Limitations](#known-limitations)
- [Layout](#layout)
- [Third-Party](#third-party)

## Overview

> [!NOTE]
> CapsLock is the default super key, because who needs it?

### Features

- Launch-or-focus your most common programs with the hotkeys you assign in your config file.
- Focused tile includes border highlight that can be customized, including per app, window class, or window title.
- Snap tiles to grid and cycle through various positions with subsequent key presses.
- Freely move tiles with your keyboard.
- Resize tiles and their edges with your keyboard.
- Directional focus changes with vim-like motions.
- Cycle stacked tiles with `super + [` and `super + ]`.
- Cycle focus between tiles of the same program with `super + c`.
- Show a hotkey menu with `super + /`.
- Screen search hints with `super + .`.
- Virtual desktops (native)
  - Navigate between desktops with better hotkeys
  - Assign custom hotkeys for the index-based virtual desktops.



Launch-or-focus a program with `super + [letter]`, or directionally change window focus with `super + h/l` (left/right) and `super + [` / `super + ]` for back/forward in a stack.
![Alt text](docs/assets/focus.gif)

Cycle centered window widths with `super + spacebar`.
![Alt text](docs/assets/center-cycle.gif)

Maximizes/restores with `super + m`.
![Alt text](docs/assets/maximize.gif)

Move a window with `super + ctrl + h/j/k/l`.
![Alt text](docs/assets/move.gif)

Freely move a window from command mode, then use h/j/k/l.
![Alt text](docs/assets/free-move.gif)

Resize edges with `super + arrows`.
![Alt text](docs/assets/resize.gif)

Resize from the center with `super + alt + arrows`.

Show the [Command Overlay](#command-overlay) when the super key is held. Disable through command mode.
![Alt text](docs/assets/command_overlay.png)

Use the "window switcher" (like powertoys window walker) with `super + w`.
![Alt text](docs/assets/window_switcher.png)

Other
- `super + alt` sends `ctrl + tab` (configurable via `global_hotkeys`)
- `super + c` cycle through windows of the same app
- `super + shift + c` cycle through windows of the same app on the current desktop
- `super + .` screen search (click hints)
- `super + j/k` switch to next/previous virtual desktop
- `super + shift + j/k` move the active window to next/previous desktop (follow)
- `super + w` open Window Selector (fuzzy find open windows)
- `super + h/l` move window focus left/right
- `super + [` / `super + ]` move window focus forward/back through stacked windows
- `super + u/i` focus previous/next monitor
- `super + shift + u/i` move the active window to previous/next monitor

Enter Command Mode with `super + ;`.
- `r` to reload program/config
- `e` to open config file
- `w` opens a new window for the active program, if the program supports it
- `g` reapply app desktop assignments
- `n` toggles the command overlay on or off
- `i` opens the [Helper Utility](#helper-utility)

## TODO

- Clarify and work on areas of state
  - saving layouts
  - per app configs determining where things go (virtual desktop destination is supported now)
- Possibly rework the config schema. It's hectic.


## Configuration

### Quick start

- If not using the binary, make sure to install AutoHotKey 2.1-alpha18 or newer.
- Start the program and enter command mode with `super + ;`. The binary is not currently signed and you will be warned by Windows. Clone and use `harken.ahk` directly as an alternative.
- The program might fail on first run? Probably something to do with the config. For now you can create the config first to _maybe_ avoid the initial-crash scenario.
- Press `e` to open the config file. You can also find it manually in `~/.config/harken/harken.toml` as it will be created on first run.
- After making changes to your config you can reload (the entire program) with `r` while in command mode.

## Window Matching

App entries under `apps` can match windows via `win_title` or a `match` map. The `match` map accepts
`exe`, `class`, and `title`, plus `*_regex = true` to treat the value as a regex. You can also match
by process tree with `match.process_tree`, which checks for ancestor/descendant executables.

Use `exclude_titles` to ignore specific window titles for a given app. Each entry is a regex pattern
and the match is case-insensitive unless you include your own `(?i)` prefix.

```toml
[apps.editor]
hotkey = "v"
match = { exe = "Code.exe", title = " - Visual Studio Code$", title_regex = true }
exclude_titles = ["^Settings$", "^Welcome$"]
```

Process tree matching can split apps that share the same window executable:

```toml
[[apps]]
id = "terminal"
hotkey = "s"
match = { exe = "alacritty.exe", process_tree = { mode = "descendant", exe = ["yazi.exe"], negate = true } }

[[apps]]
id = "yazi"
hotkey = "y"
match = { exe = "alacritty.exe", process_tree = { mode = "descendant", exe = ["yazi.exe"] } }
```

Add `debug = true` under `match.process_tree` to log process tree details to
`%APPDATA%\harken\process_tree.debug.log`.

### All default keybindings

#### Window management (Super)

| Shortcut | Action |
| --- | --- |
| `super + /` | Show command overlay (temporary) |
| `super + w` | Window selector (window walker) |
| `super + .` | Screen search (click hints) |
| `super + c` | Cycle app windows across desktops |
| `super + shift + c` | Cycle app windows on current desktop |
| `super + space` | Center width cycle |
| `super + m` | Maximize/un-maximize |
| `alt + q` | Close window |
| `super + Left/Right/Up/Down` | Resize window and snap to grids |
| `super + alt + Left/Right/Up/Down` | Resize centered |
| `super + ctrl + h/j/k/l` | Move/snap window |
| `super + u/i` | Focus previous/next monitor |
| `super + shift + u/i` | Move window to previous/next monitor |
| `super + o` | Open native Task View overview |
| `window.super_double_tap_action = "overview"` | Optionally make double-super open native Task View overview |

When `modes.active = "carousel"` and `modes.carousel.enabled = true`, these key behaviors change:

| Shortcut | Action |
| --- | --- |
| `super + h/l` | Carousel focus left/right (current desktop + active monitor) |
| `super + shift + h/l` | Move carousel order left/right |
| `super + j/k` | Next/previous virtual desktop |
| `super + shift + j/k` | Move focused window to next/previous desktop |
| `super + space` | Center active tile on demand |
| `super + - / =` | Decrease/increase focused tile width |
| `super + o` | Open native Task View overview |
| `super + f` | Toggle desktop move follow behavior |

Carousel mode also maintains one trailing empty virtual desktop when
`modes.carousel.ensure_empty_desktop = true`.

The desktop status bar is globally enabled through `virtual_desktop.status_bar.enabled`.
Set `virtual_desktop.status_bar.show_in_non_carousel = true` to show it outside carousel mode too.
Carousel mode adds the current desktop's window strip using the appearance settings under
`modes.carousel.status_bar` such as `window_display`.
Status bar design inspiration: EngineeringMechanicsB's AHKVirtualDesktop project.

Carousel mode also does best-effort persistence for per-app tile width and strip order.
Order restore is keyed by `desktop:monitor` scope and app executable name, so it cannot
distinguish multiple windows from the same executable across restarts, and restore quality
can degrade when desktop indices or monitor numbering change.

#### Window management (Move mode)

| Shortcut | Action |
| --- | --- |
| `h/j/k/l` | Move window |
| `Esc` or `super` | Exit move mode |

#### Focus navigation

| Shortcut | Action |
| --- | --- |
| `super + h/l` | Focus left/right |
| `super + [` / `super + ]` | Cycle stacked (prev/next) |

#### Virtual desktops

| Shortcut | Action |
| --- | --- |
| `super + j/k` | Next/previous desktop |
| `super + WheelUp/WheelDown` | Previous/next desktop (when `virtual_desktop.scroll_switch = true`) |
| `super + shift + j/k` | Move window to next/previous desktop (follow) |
| `super + alt + shift + WheelUp/WheelDown` | Move window to previous/next desktop (when `virtual_desktop.scroll_switch = true`) |
| `super + <key>` | Go to mapped desktop (`[[virtual_desktop.<N>]]`) |
| `super + alt + <key>` | Expel window to mapped desktop without following |
| `super + alt + shift + <key>` | Move window to mapped desktop (follow) |
| `virtual_desktop.fast_switch_non_carousel` | Skip the post-switch wait in non-carousel mode for faster desktop focus changes |
| `virtual_desktop.ensure_trailing_empty` | Keep exactly one trailing empty virtual desktop by creating and pruning as needed |
| `virtual_desktop.auto_assign` | Move newly created windows that match `apps[]` with `desktop` set |
| `virtual_desktop.debug_focus` | Log cross-desktop focus attempts to `%APPDATA%\harken\vd.focus.debug.log` |
| `virtual_desktop.switch_curtain` | Dim overlay during desktop switches to reduce flicker |
| `virtual_desktop.status_bar` | Global desktop status bar enablement; `show_in_non_carousel` extends it beyond carousel mode |

#### Apps (defaults)

These are examples for the launch-or-focus keybindings.

| Shortcut | Action |
| --- | --- |
| `super + e` | Files (`explorer.exe`) |
| `super + v` | Editor (`Code.exe`) |
| `super + s` | Terminal (`WindowsTerminal.exe`) |
| `super + n` | Notes (`notepad++.exe`) |

#### Command mode

| Shortcut | Action |
| --- | --- |
| `super + ;` | Enter command mode |
| `r` | Reload program/config |
| `e` | Open config file |
| `w` | Open a new window for the active app |
| `n` | Toggle command overlay |
| `i` | Open window inspector |
| `m` | Enter move mode |
| `Esc` | Exit command mode |


### Helper Utility
- `tools/window_inspector.ahk` lists active window titles, exe names, classes, and PIDs.
- Use it to identify values for `apps[].win_title` in your config.
- In Command Mode, press `i` to launch the window inspector.
- Use Refresh to update the list; Copy Selected/All or Export to save results.

### Config watcher

Optional config file watcher that reloads the program when your config changes.

```toml
[config_watch]
enabled = false
interval_ms = 2500
```

### Screen search

```toml
[screen_search]
enabled = true
hotkey = "."
hint_chars = "asdfghjklqwertyuiopzxcvbnm"
max_results = 200
min_size_px = 12
min_distance_px = 40
hint_opacity = 235
debug_log = false
```

## Limitations
- This has not been tested with multi-monitor setups or much outside of ultra-wide monitors.
- Virtual desktop integration requires AutoHotkey v2.1-alpha-18 or later.
- Some apps (e.g., Discord) launch via `Update.exe` and keep versioned subfolders, which makes auto-resolution unreliable for launching or focusing more challenging.
- For some apps that minimize or close to the system tray, it's recommended you disable that in the program. Otherwise you can try to set `apps[].run` to a stable full path (or use `run_paths`) in your config.
- Windows with elevated permissions may ignore Harken hotkeys unless Harken is run as Administrator.

## Third-Party
- JXON (AHK v2 JSON serializer) from https://github.com/TheArkive/JXON_ahk2
  - License: `LICENSES/JXON_ahk2-LICENSE.md`
- VD.ahk from https://github.com/FuPeiJiang/VD.ahk
  - License: `LICENSES/VD.ahk-LICENSE.md`
- UIA.ahk v1.1.2 from https://github.com/Descolada/UIA-v2
  - License: `LICENSES/UIA.ahk-LICENSE.md`

## Similar tools and inspirations

For this project I was primarily inspired by what I was able to accomplish with [Raycast](https://www.raycast.com/) on macOS. Between [Karabiner](https://karabiner-elements.pqrs.org/), Raycast, and [HammerSpoon](https://www.hammerspoon.org/) one could achieve all of Harken and more on macOS. I needed to move back to windows for work, and I wanted a way to use the same flow on Windows that I had become accustomed to on macOS.

Other macOS tools that I tried for more than five minutes were [AeroSpace](https://github.com/nikitabobko/AeroSpace) and [Loop](https://github.com/MrKai77/Loop).

The foundation of Harken was built upon [this reddit post](https://old.reddit.com/r/AutoHotkey/comments/17qv594/window_management_tool/), shared by u/CrashKZ -- Thanks to [/u/plankoe](https://old.reddit.com/user/plankoe) for their initial contributions, too.

### [FancyZones](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones)

FancyZones is okay, but it doesn't remove the need to know where things are in order to focus on them, and its features are insufficient for a truly keyboard-centered workflow.

### [Komorebi](https://github.com/LGUG2Z/komorebi)

I really like komorebi--though I didn't use it for long and I have never been able to stick with tiling in the long run--but for those who prefer the tiling approach this might be the best option on Windows.

### [GlazeWM](https://github.com/glzr-io/glazewm)

GlazeWM is another popular tiling window manager for Windows operating systems.


### Feature comparison (Harken vs similar Windows tools)

| Feature | Harken | [FancyZones](https://learn.microsoft.com/en-us/windows/powertoys/fancyzones) | [komorebi](https://github.com/LGUG2Z/komorebi) | [GlazeWM](https://github.com/glzr-io/glazewm) |
| --- | --- | --- | --- | --- |
| Primary interaction model | Keyboard-first hotkeys and commands | Zone-based snapping (mouse + keyboard) | Dynamic tiling WM | Dynamic tiling WM |
| Launch-or-focus app hotkeys | Yes (configurable per app) | No (outside scope) | Possible via external tooling/scripts | Possible via external tooling/scripts |
| Directional focus movement | Yes (`super + h/l`) | No | Yes | Yes |
| Stack/window cycling | Yes (`super + [` / `super + ]`, app cycling) | Mostly | Yes (tiling containers/workspaces) | Yes (tiling containers/workspaces) |
| Virtual desktop hotkeys | Yes (native desktop integration) | Indirect (PowerToys + Windows shortcuts) | Yes | Yes |
| Freeform floating adjustments | Yes (move mode + resize controls) | Primarily zone snapping | Primarily tiling; floating is secondary | Primarily tiling; floating is secondary |
| Built-in command/help overlay | Yes (`super + /`, command mode) | No | No built-in overlay | No built-in overlay |
| Config format | TOML | GUI + JSON settings | JSON/YAML-style config | YAML |
| Best fit | Users who want keyboard speed without fully committing to tiling | Users who want quick snap layouts | Users who want full tiling workflows | Users who want full tiling workflows |

