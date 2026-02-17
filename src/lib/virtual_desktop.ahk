#Include %A_LineFile%\..\VD.ahk

; Virtual desktop integration (tray indicator, auto-assign, helpers).
VirtualDesktopEnabled() {
    global Config
    if !IsSet(Config)
        return false
    if !Config.Has("virtual_desktop")
        return false
    return Config["virtual_desktop"]["enabled"]
}

global vd_auto_assign_timer := 0

VirtualDesktopTrayEnabled() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    return Config["virtual_desktop"].Has("tray_indicator") && Config["virtual_desktop"]["tray_indicator"]
}

VirtualDesktopSwitchOnFocus() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    return Config["virtual_desktop"]["switch_on_focus"]
}

InitVirtualDesktop() {
    if !VirtualDesktopEnabled()
        return
    ensure_count := Config["virtual_desktop"]["ensure_count"]
    if (ensure_count > 0)
        VD.createUntil(ensure_count)
    InitVirtualDesktopTrayIndicator()
    InitVirtualDesktopAutoAssign()
}

InitVirtualDesktopAutoAssign() {
    if !VirtualDesktopEnabled()
        return
    if !Config["virtual_desktop"].Has("auto_assign") || !Config["virtual_desktop"]["auto_assign"]
        return
    ; Polling watcher only handles newly created windows; users can move later.
    interval := 500
    if Config["virtual_desktop"].Has("auto_assign_interval_ms")
        interval := Config["virtual_desktop"]["auto_assign_interval_ms"]
    StartVirtualDesktopAutoAssign(interval)
}

StartVirtualDesktopAutoAssign(interval_ms) {
    global vd_auto_assign_timer
    if vd_auto_assign_timer
        SetTimer(vd_auto_assign_timer, 0)
    vd_auto_assign_timer := VirtualDesktopAutoAssignTick
    SetTimer(vd_auto_assign_timer, interval_ms)
}

VirtualDesktopAutoAssignTick(*) {
    static seen_hwnds := Map()
    if !VirtualDesktopEnabled()
        return
    if !Config.Has("virtual_desktop") || !Config["virtual_desktop"].Has("auto_assign") || !Config["virtual_desktop"]["auto_assign"]
        return

    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    win_list := WinGetList()
    A_DetectHiddenWindows := bak_detect_hidden_windows

    for _, hwnd in win_list {
        if seen_hwnds.Has(hwnd)
            continue
        seen_hwnds[hwnd] := true
        ; Assign once per window so manual moves are respected afterward.
        TryAutoAssignWindow(hwnd)
    }

    for hwnd, _ in seen_hwnds {
        if !WindowExistsAcrossDesktops(hwnd)
            seen_hwnds.Delete(hwnd)
    }
}

TryAutoAssignWindow(hwnd) {
    if !WindowExistsAcrossDesktops(hwnd)
        return
    try ex_style := WinGetExStyle("ahk_id " hwnd)
    catch
        return
    if (ex_style & 0x80) || (ex_style & 0x08000000)
        return

    for _, app in Config["apps"] {
        if !(app is Map)
            continue
        if !app.Has("desktop")
            continue
        if !AppConfigMatchesWindow(app, hwnd)
            continue
        if AppConfigIgnoresWindow(app, hwnd)
            continue
        target_desktop := app["desktop"]
        if (target_desktop <= 0)
            return
        total := VD.getCount()
        if (target_desktop > total) {
            ; Ensure the destination desktop exists before moving the window.
            VD.createUntil(target_desktop)
            VD.IVirtualDesktopListChanged()
            total := VD.getCount()
        }
        if (target_desktop > total)
            return
        follow_on_spawn := true
        if app.Has("follow_on_spawn")
            follow_on_spawn := app["follow_on_spawn"]
        VD.MoveWindowToDesktopNum("ahk_id " hwnd, target_desktop, follow_on_spawn)
        if follow_on_spawn {
            VD.goToDesktopNum(target_desktop)
            VD.WaitDesktopSwitched(target_desktop)
        }
        return
    }
}

ReapplyDesktopAssignments(*) {
    if !VirtualDesktopEnabled()
        return
    win_list := GetWindowsAcrossDesktops()
    for _, hwnd in win_list
        EnforceAppDesktopAssignment(hwnd)
}

EnforceAppDesktopAssignment(hwnd) {
    if !WindowExistsAcrossDesktops(hwnd)
        return false
    try ex_style := WinGetExStyle("ahk_id " hwnd)
    catch
        return false
    if (ex_style & 0x80) || (ex_style & 0x08000000)
        return false

    for _, app in Config["apps"] {
        if !(app is Map)
            continue
        if !app.Has("desktop")
            continue
        if !AppConfigMatchesWindow(app, hwnd)
            continue
        if AppConfigIgnoresWindow(app, hwnd)
            continue
        target_desktop := app["desktop"]
        if (target_desktop <= 0)
            return false

        assigned_desktop := GetWindowDesktopNum(hwnd)
        if (assigned_desktop = target_desktop)
            return true

        total := VD.getCount()
        if (target_desktop > total) {
            ; Ensure the destination desktop exists before moving the window.
            VD.createUntil(target_desktop)
            VD.IVirtualDesktopListChanged()
            total := VD.getCount()
        }
        if (target_desktop > total)
            return false
        VD.MoveWindowToDesktopNum("ahk_id " hwnd, target_desktop, false)
        return true
    }
    return false
}

AppConfigMatchesWindow(app, hwnd) {
    if AppConfigExcludesTitle(app, hwnd)
        return false
    if app.Has("match") && (app["match"] is Map)
        return MatchWindowFields(app["match"], hwnd)

    if app.Has("win_title") && app["win_title"] != "" {
        try return WinExist(app["win_title"] " ahk_id " hwnd)
    }
    return false
}

AppConfigIgnoresWindow(app, hwnd) {
    if !(app is Map)
        return false
    if !app.Has("ignore_classes") || !(app["ignore_classes"] is Array)
        return false
    try class_name := WinGetClass("ahk_id " hwnd)
    catch
        return false
    for _, ignore_class in app["ignore_classes"] {
        if (StrLower(ignore_class) = StrLower(class_name))
            return true
    }
    return false
}

InitVirtualDesktopTrayIndicator() {
    if !VirtualDesktopTrayEnabled()
        return
    ; Update via VD notifications to avoid timer polling.
    UpdateVirtualDesktopTrayIndicator()
    VD.ListenersCurrentVirtualDesktopChanged[UpdateVirtualDesktopTrayIndicator] := true
}

UpdateVirtualDesktopTrayIndicator(*) {
    if !VirtualDesktopTrayEnabled()
        return
    current := GetCurrentDesktopNumFresh()
    if (current <= 0)
        current := VD.getCurrentDesktopNum()
    total := VD.getCount()
    if (total <= 0)
        return
    text := FormatVirtualDesktopTrayText(current, total)
    try A_TrayMenu.SetTip(text)
    SetTrayIconText(text)
}

FormatVirtualDesktopTrayText(current, total) {
    global Config
    format := "{current}/{total}"
    if Config.Has("virtual_desktop") && Config["virtual_desktop"].Has("tray_format")
        format := Config["virtual_desktop"]["tray_format"]
    format := StrReplace(format, "{current}", current)
    format := StrReplace(format, "{total}", total)
    return format
}

SetTrayIconText(text) {
    if (text = "")
        return
    ; Draw text onto the existing AHK tray icon (current/total).
    hicon := CreateTextTrayIcon(text)
    if !hicon
        return
    TraySetIcon("HICON:" hicon)
    global tray_indicator_hicon
    if (IsSet(tray_indicator_hicon) && tray_indicator_hicon)
        DllCall("user32\DestroyIcon", "Ptr", tray_indicator_hicon)
    tray_indicator_hicon := hicon
}

CreateTextTrayIcon(text) {
    icon_size := 32
    hdc := DllCall("gdi32\CreateCompatibleDC", "Ptr", 0, "Ptr")
    if !hdc
        return 0

    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", icon_size, bi, 4)
    NumPut("Int", -icon_size, bi, 8)
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    NumPut("UInt", 0, bi, 16)
    ppv_bits := 0
    hbm_color := DllCall("gdi32\CreateDIBSection", "Ptr", hdc, "Ptr", bi, "UInt", 0, "Ptr*", &ppv_bits, "Ptr", 0, "UInt", 0, "Ptr")
    if !hbm_color {
        DllCall("gdi32\\DeleteDC", "Ptr", hdc)
        return 0
    }

    hbm_mask := DllCall("gdi32\CreateBitmap", "Int", icon_size, "Int", icon_size, "UInt", 1, "UInt", 1, "Ptr", 0, "Ptr")
    old_bmp := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", hbm_color, "Ptr")

    DllCall("gdi32\SetBkMode", "Ptr", hdc, "Int", 1)

    font_height := -Round(icon_size * 0.55)
    hfont := DllCall("gdi32\CreateFontW", "Int", font_height, "Int", 0, "Int", 0, "Int", 0, "Int", 600, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "WStr", "Segoe UI", "Ptr")
    old_font := 0
    if hfont
        old_font := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", hfont, "Ptr")

    rect := Buffer(16, 0)
    NumPut("Int", 0, rect, 0)
    NumPut("Int", 0, rect, 4)
    NumPut("Int", icon_size, rect, 8)
    NumPut("Int", icon_size, rect, 12)
    format := 0x00000001 | 0x00000004 | 0x00000020

    DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", 0x000000)
    rect_shadow := Buffer(16, 0)
    NumPut("Int", 1, rect_shadow, 0)
    NumPut("Int", 1, rect_shadow, 4)
    NumPut("Int", icon_size + 1, rect_shadow, 8)
    NumPut("Int", icon_size + 1, rect_shadow, 12)
    DllCall("user32\DrawTextW", "Ptr", hdc, "WStr", text, "Int", -1, "Ptr", rect_shadow, "UInt", format)

    DllCall("gdi32\SetTextColor", "Ptr", hdc, "UInt", 0xFFFFFF)
    DllCall("user32\DrawTextW", "Ptr", hdc, "WStr", text, "Int", -1, "Ptr", rect, "UInt", format)

    if hfont {
        if old_font
            DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old_font)
        DllCall("gdi32\DeleteObject", "Ptr", hfont)
    }
    if old_bmp
        DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", old_bmp)
    DllCall("gdi32\DeleteDC", "Ptr", hdc)

    iconinfo := Buffer(A_PtrSize == 8 ? 32 : 20, 0)
    NumPut("UInt", 1, iconinfo, 0)
    NumPut("UInt", 0, iconinfo, 4)
    NumPut("UInt", 0, iconinfo, 8)
    if (A_PtrSize == 8) {
        NumPut("Ptr", hbm_mask, iconinfo, 16)
        NumPut("Ptr", hbm_color, iconinfo, 24)
    } else {
        NumPut("Ptr", hbm_mask, iconinfo, 12)
        NumPut("Ptr", hbm_color, iconinfo, 16)
    }
    hicon := DllCall("user32\CreateIconIndirect", "Ptr", iconinfo, "Ptr")

    DllCall("gdi32\DeleteObject", "Ptr", hbm_color)
    DllCall("gdi32\DeleteObject", "Ptr", hbm_mask)

    return hicon
}

RefreshVirtualDesktopState() {
    if !VirtualDesktopEnabled()
        return
    try {
        VD.IVirtualDesktopListChanged()
        VD.currentDesktopNum := VD.IVirtualDesktopMap[VD.IVirtualDesktopManagerInternal.GetCurrentDesktop()]
    }
}

GetCurrentDesktopNumFresh() {
    if !VirtualDesktopEnabled()
        return 0
    try {
        VD.IVirtualDesktopListChanged()
        current := VD.IVirtualDesktopMap[VD.IVirtualDesktopManagerInternal.GetCurrentDesktop()]
        if (current > 0)
            VD.currentDesktopNum := current
        return current
    }
    return 0
}

GetWindowDesktopNum(hwnd) {
    if !VirtualDesktopEnabled()
        return 0
    try return VD.getDesktopNumOfHWND(hwnd)
    catch as err
        return 0
}

IsWindowOnCurrentDesktop(hwnd) {
    if !VirtualDesktopEnabled()
        return true
    desktop_num := GetWindowDesktopNum(hwnd)
    if (desktop_num <= 0)
        return true
    return desktop_num = VD.getCurrentDesktopNum()
}

GetWindowsAcrossDesktops(win_title := "") {
    if !VirtualDesktopEnabled()
        return WinGetList(win_title)
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    windows := WinGetList(win_title)
    A_DetectHiddenWindows := bak_detect_hidden_windows
    return windows
}

WindowExistsAcrossDesktops(hwnd) {
    bak_detect_hidden_windows := A_DetectHiddenWindows
    A_DetectHiddenWindows := true
    exists := WinExist("ahk_id " hwnd)
    A_DetectHiddenWindows := bak_detect_hidden_windows
    return exists
}

ActivateWindowAcrossDesktops(hwnd) {
    if !hwnd
        return 0
    if !WindowExistsAcrossDesktops(hwnd)
        return 0

    if VirtualDesktopSwitchOnFocus() {
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0 && desktop_num != VD.getCurrentDesktopNum()) {
            try {
                VD.goToDesktopOfWindow("ahk_id " hwnd, true)
            } catch as err {
                try {
                    WinActivate "ahk_id " hwnd
                } catch
                    return 0
            }
            try return WinGetID("A")
            catch
                return 0
        }

        if (desktop_num <= 0) {
            try {
                VD.goToDesktopOfWindow("ahk_id " hwnd, true)
                try return WinGetID("A")
                catch
                    return 0
            } catch as err {
                ; fall through to direct activation
            }
        }
    }

    try {
        WinActivate "ahk_id " hwnd
    } catch
        return 0
    try return WinGetID("A")
    catch
        return 0
}
