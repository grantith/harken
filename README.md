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
- Virtual desktops (native)
  - Navigate between desktops with better hotkeys
  - Assign custom hotkeys for the index-based virtual desktops.



Launch-or-focus a program with `super + [letter]`, or directionally change window focus with `alt + h/l/j/k` (left, right, down, up) and `alt + [` / `alt + ]` for back/forward in a stack.
![Alt text](docs/assets/focus.gif)

Cycle centered window widths with `super + spacebar`.
![Alt text](docs/assets/center-cycle.gif)

Maximizes/restores with `super + m`.
![Alt text](docs/assets/maximize.gif)

Move a window with `super + h/j/k/l`.
![Alt text](docs/assets/move.gif)

Freely move a window with double tap super + h/j/k/l
![Alt text](docs/assets/free-move.gif)

Resize edges with `super + shift + h/j/k/l`.
![Alt text](docs/assets/resize.gif)

Show the [Command Overlay](#command-overlay) when the super key is held. Disable through command mode.
![Alt text](docs/assets/command_overlay.png)

Use the "window switcher" (like powertoys window walker) with `super + w`.
![Alt text](docs/assets/window_switcher.png)

Other
- `super + alt` sends `ctrl + tab` (configurable via `global_hotkeys`)
- `super + c` cycle through windows of the same app
- `super + shift + c` cycle through windows of the same app on the current desktop
- `super + alt + h/l` switch to previous/next virtual desktop
- `super + alt + shift + h/l` move the active window to previous/next desktop (follow)
- `super + w` open Window Selector (fuzzy find open windows)
- `alt + h/l` move window focus left/right
- `alt + j/k` move window focus down/up (non-stacked)
- `alt + [` / `alt + ]` move window focus forward/back through stacked windows
- `super + alt + h/l` to move between desktops
- `super + shift + alt + h/l` send current tile to adjacent desktop

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
| `super + c` | Cycle app windows across desktops |
| `super + shift + c` | Cycle app windows on current desktop |
| `super + space` | Center width cycle |
| `super + m` | Maximize/un-maximize |
| `alt + q` | Close window |
| `super + Left/Right/Up/Down` | Resize window and snap to grids |
| `super + shift + h/j/k/l` | Resize centered |
| `super + ctrl + h/j/k/l` | Move window |
| `super` (double tap) | Toggle move mode |

#### Window management (Move mode)

| Shortcut | Action |
| --- | --- |
| `h/j/k/l` | Move window |
| `Esc` or `super` | Exit move mode |

#### Focus navigation (Alt)

| Shortcut | Action |
| --- | --- |
| `alt + h/l` | Focus left/right |
| `alt + j/k` | Focus down/up |
| `alt + [` / `alt + ]` | Cycle stacked (prev/next) |

#### Virtual desktops

| Shortcut | Action |
| --- | --- |
| `super + alt + h/l` | Previous/next desktop |
| `super + alt + shift + h/l` | Move window to previous/next desktop (follow) |
| `super + alt + <key>` | Go to mapped desktop (`[[virtual_desktop.<N>]]`) |
| `super + alt + shift + <key>` | Move window to mapped desktop (follow) |
| `virtual_desktop.auto_assign` | Move newly created windows that match `apps[]` with `desktop` set |

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
