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

SwitchCurtainEnabled() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    if !Config["virtual_desktop"].Has("switch_curtain")
        return false
    curtain := Config["virtual_desktop"]["switch_curtain"]
    if !(curtain is Map)
        return false
    if !curtain.Has("enabled")
        return false
    return curtain["enabled"]
}

SwitchCurtainOpacity() {
    global Config
    opacity := 204
    if Config["virtual_desktop"].Has("switch_curtain") {
        curtain := Config["virtual_desktop"]["switch_curtain"]
        if (curtain is Map && curtain.Has("opacity"))
            opacity := curtain["opacity"]
    }
    if !(opacity is Number)
        opacity := 204
    return Max(0, Min(255, Round(opacity)))
}

SwitchCurtainColor() {
    global Config
    color := "#202020"
    if Config["virtual_desktop"].Has("switch_curtain") {
        curtain := Config["virtual_desktop"]["switch_curtain"]
        if (curtain is Map && curtain.Has("color"))
            color := curtain["color"]
    }
    return NormalizeHexColor(color, "202020")
}

NormalizeHexColor(value, fallback) {
    if !(value is String)
        return fallback
    trimmed := Trim(value)
    if (SubStr(trimmed, 1, 1) = "#")
        trimmed := SubStr(trimmed, 2)
    if (StrLen(trimmed) = 8 && RegExMatch(trimmed, "i)^0x[0-9a-f]{6}$"))
        return SubStr(trimmed, 3)
    if (StrLen(trimmed) = 6 && RegExMatch(trimmed, "i)^[0-9a-f]{6}$"))
        return trimmed
    return fallback
}

GetVirtualScreenBounds(&left, &top, &width, &height) {
    try {
        left := SysGet(76)
        top := SysGet(77)
        width := SysGet(78)
        height := SysGet(79)
    } catch {
        left := 0
        top := 0
        width := A_ScreenWidth
        height := A_ScreenHeight
    }
    if (width <= 0 || height <= 0) {
        left := 0
        top := 0
        width := A_ScreenWidth
        height := A_ScreenHeight
    }
}

global switch_curtain_gui := ""
global switch_curtain_visible := false

ShowSwitchCurtain() {
    global switch_curtain_gui, switch_curtain_visible
    if !SwitchCurtainEnabled()
        return false
    if !switch_curtain_gui {
        switch_curtain_gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "harken Desktop Switch")
        switch_curtain_gui.MarginX := 0
        switch_curtain_gui.MarginY := 0
        switch_curtain_gui.BackColor := SwitchCurtainColor()
    }
    GetVirtualScreenBounds(&left, &top, &width, &height)
    switch_curtain_gui.BackColor := SwitchCurtainColor()
    switch_curtain_gui.Show("NoActivate x" left " y" top " w" width " h" height)
    WinSetTransparent(SwitchCurtainOpacity(), switch_curtain_gui)
    switch_curtain_visible := true
    return true
}

HideSwitchCurtain() {
    global switch_curtain_gui, switch_curtain_visible
    if !switch_curtain_gui
        return
    switch_curtain_gui.Hide()
    switch_curtain_visible := false
}

BeginDesktopSwitchCurtain() {
    if !SwitchCurtainEnabled()
        return false
    return ShowSwitchCurtain()
}

EndDesktopSwitchCurtain(was_shown := false) {
    if !was_shown
        return
    HideSwitchCurtain()
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

VirtualDesktopFocusDebugEnabled() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    return Config["virtual_desktop"].Has("debug_focus") && Config["virtual_desktop"]["debug_focus"]
}

EnsureFocusDebugLogInit() {
    global focus_debug_log_initialized
    if !IsSet(focus_debug_log_initialized)
        focus_debug_log_initialized := false
    if focus_debug_log_initialized
        return
    if !VirtualDesktopFocusDebugEnabled()
        return
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    TryResetFocusLogFile(log_dir "\\vd.focus.debug.log")
    focus_debug_log_initialized := true
}

TryResetFocusLogFile(path) {
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend("", path)
    }
}

InitVirtualDesktop() {
    if !VirtualDesktopEnabled()
        return
    ensure_count := Config["virtual_desktop"]["ensure_count"]
    if (ensure_count > 0)
        VD.createUntil(ensure_count)
    SetTimer((*) => EnsureVirtualDesktopTrailingEmpty(), -500)
    InitVirtualDesktopTrayIndicator()
    InitVirtualDesktopAutoAssign()
    EnsureFocusDebugLogInit()
}

VirtualDesktopFastSwitchNonCarousel() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    if !Config["virtual_desktop"].Has("fast_switch_non_carousel")
        return false
    return Config["virtual_desktop"]["fast_switch_non_carousel"]
}

VirtualDesktopTrailingEmptyEnabled() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    if !Config["virtual_desktop"].Has("ensure_trailing_empty")
        return false
    return Config["virtual_desktop"]["ensure_trailing_empty"]
}

VirtualDesktopStatusBarEnabled() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    if Config["virtual_desktop"].Has("status_bar") {
        status_bar := Config["virtual_desktop"]["status_bar"]
        if (status_bar is Map && status_bar.Has("enabled"))
            return status_bar["enabled"]
    }

    ; Preserve existing user configs until they migrate to the global setting.
    if Config.Has("modes") && (Config["modes"] is Map) && Config["modes"].Has("carousel") {
        carousel := Config["modes"]["carousel"]
        if (carousel is Map && carousel.Has("status_bar")) {
            settings := carousel["status_bar"]
            if (settings is Map && settings.Has("enabled"))
                return settings["enabled"]
        }
    }
    return false
}

VirtualDesktopStatusBarShowInNonCarousel() {
    global Config
    if !VirtualDesktopEnabled()
        return false
    if !Config["virtual_desktop"].Has("status_bar")
        return false
    status_bar := Config["virtual_desktop"]["status_bar"]
    if !(status_bar is Map) || !status_bar.Has("show_in_non_carousel")
        return false
    return status_bar["show_in_non_carousel"]
}

VirtualDesktopStatusBarVisibleInCurrentMode() {
    if !VirtualDesktopStatusBarEnabled()
        return false
    return CarouselModeEnabled() || VirtualDesktopStatusBarShowInNonCarousel()
}

global vd_trailing_empty_pending := false
global vd_trailing_empty_signature := ""
global vd_trailing_empty_stable_count := 0

ScheduleEnsureVirtualDesktopTrailingEmpty(delay_ms := 700) {
    global vd_trailing_empty_pending
    if vd_trailing_empty_pending
        return
    vd_trailing_empty_pending := true
    SetTimer(VirtualDesktopEnsureTrailingEmptyDeferredTick, -delay_ms)
}

VirtualDesktopEnsureTrailingEmptyDeferredTick(*) {
    global vd_trailing_empty_pending
    try EnsureVirtualDesktopTrailingEmpty()
    vd_trailing_empty_pending := false
}

EnsureVirtualDesktopTrailingEmpty(force := false) {
    global vd_trailing_empty_signature, vd_trailing_empty_stable_count
    if !force && !VirtualDesktopTrailingEmptyEnabled()
        return false

    occupied := GetOccupiedDesktopSetAcrossDesktops()
    highest_occupied := 0
    for desktop_num, _ in occupied {
        if (desktop_num > highest_occupied)
            highest_occupied := desktop_num
    }

    desired := Max(1, highest_occupied + 1)
    RefreshVirtualDesktopState()
    count := VD.getCount()
    changed := false
    signature := BuildVirtualDesktopOccupancySignature(occupied, count)

    if (signature = vd_trailing_empty_signature)
        vd_trailing_empty_stable_count += 1
    else {
        vd_trailing_empty_signature := signature
        vd_trailing_empty_stable_count := 1
    }

    if (count < desired) {
        VD.createUntil(desired)
        changed := true
        RefreshVirtualDesktopState()
        vd_trailing_empty_signature := ""
        vd_trailing_empty_stable_count := 0
        count := VD.getCount()
    }

    ; Deleting a desktop can merge its windows into the current desktop, so only
    ; prune after repeated identical occupancy snapshots and only remove one
    ; trailing desktop per pass.
    if (count > desired) && !occupied.Has(count) && (vd_trailing_empty_stable_count >= 3) {
        fallback_desktop := Max(1, count - 1)
        try VD.removeDesktop(count, fallback_desktop)
        changed := true
        RefreshVirtualDesktopState()
        vd_trailing_empty_signature := ""
        vd_trailing_empty_stable_count := 0
        ScheduleEnsureVirtualDesktopTrailingEmpty(1200)
    }

    if changed
        try ScheduleCarouselStatusBarUpdate(80)
    return changed
}

BuildVirtualDesktopOccupancySignature(occupied, count) {
    desktop_nums := []
    for desktop_num, _ in occupied
        desktop_nums.Push(desktop_num)
    if (desktop_nums.Length > 1)
        desktop_nums.Sort()

    signature := "count=" count "|occupied="
    for _, desktop_num in desktop_nums
        signature .= desktop_num ","
    return signature
}

GetOccupiedDesktopSetAcrossDesktops() {
    set := Map()
    windows := GetWindowsAcrossDesktops()
    for _, hwnd in windows {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        if Window.IsException("ahk_id " hwnd)
            continue
        ex_style := 0
        try ex_style := WinGetExStyle("ahk_id " hwnd)
        catch
            continue
        if (ex_style & 0x80) || (ex_style & 0x8000000)
            continue
        desktop_num := GetWindowDesktopNum(hwnd)
        if (desktop_num > 0)
            set[desktop_num] := true
    }
    return set
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
            curtain_visible := BeginDesktopSwitchCurtain()
            try {
                VD.goToDesktopNum(target_desktop)
                VD.WaitDesktopSwitched(target_desktop)
            } finally {
                EndDesktopSwitchCurtain(curtain_visible)
            }
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
    desktop_num := 0
    try desktop_num := VD.getDesktopNumOfHWND(hwnd)
    catch as err
        desktop_num := 0
    if (desktop_num > 0) {
        SetWindowDesktopCache(hwnd, desktop_num)
        return desktop_num
    }
    if (desktop_num < 0)
        return desktop_num
    cached := GetWindowDesktopCache(hwnd)
    if (cached > 0)
        return cached
    return desktop_num
}

GetWindowDesktopCache(hwnd) {
    global window_desktop_cache
    if !IsSet(window_desktop_cache) || !(window_desktop_cache is Map)
        window_desktop_cache := Map()
    if !window_desktop_cache.Has(hwnd)
        return 0
    if !WindowExistsAcrossDesktops(hwnd) {
        window_desktop_cache.Delete(hwnd)
        return 0
    }
    return window_desktop_cache[hwnd]
}

SetWindowDesktopCache(hwnd, desktop_num) {
    global window_desktop_cache
    if !IsSet(window_desktop_cache) || !(window_desktop_cache is Map)
        window_desktop_cache := Map()
    if (desktop_num <= 0)
        return
    window_desktop_cache[hwnd] := desktop_num
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

    if VirtualDesktopFocusDebugEnabled()
        LogDesktopFocusDebug("activate_attempt", hwnd, GetWindowDesktopNum(hwnd))

    if VirtualDesktopSwitchOnFocus() {
        desktop_num := GetWindowDesktopNum(hwnd)
        current_desktop := GetCurrentDesktopNumFresh()
        if (desktop_num > 0 && desktop_num != current_desktop) {
            curtain_visible := BeginDesktopSwitchCurtain()
            try {
                VD.goToDesktopOfWindow("ahk_id " hwnd, true)
            } catch as err {
                ; Fallback to direct desktop switch when goToDesktopOfWindow fails.
                try {
                    if VirtualDesktopFocusDebugEnabled()
                        LogDesktopFocusDebug("switch_fallback", hwnd, desktop_num)
                    VD.goToDesktopNum(desktop_num)
                    VD.WaitDesktopSwitched(desktop_num)
                } catch {
                    LogDesktopFocusDebug("switch_failed", hwnd, desktop_num)
                    return 0
                }
            } finally {
                EndDesktopSwitchCurtain(curtain_visible)
            }
            try {
                if VirtualDesktopFocusDebugEnabled()
                    LogDesktopFocusDebug("activate_switched", hwnd, desktop_num)
                WinActivate "ahk_id " hwnd
                return WinGetID("A")
            } catch
                LogDesktopFocusDebug("activate_failed", hwnd, desktop_num)
                return 0
        }

        if (desktop_num <= 0) {
            try {
                if VirtualDesktopFocusDebugEnabled()
                    LogDesktopFocusDebug("switch_unknown", hwnd, desktop_num)
                curtain_visible := BeginDesktopSwitchCurtain()
                try {
                    VD.goToDesktopOfWindow("ahk_id " hwnd, true)
                } finally {
                    EndDesktopSwitchCurtain(curtain_visible)
                }
                try {
                    WinActivate "ahk_id " hwnd
                    return WinGetID("A")
                } catch
                    return 0
            } catch as err {
                LogDesktopFocusDebug("switch_unknown_failed", hwnd, desktop_num)
                ; fall through to direct activation
            }
        }
    }

    try {
        if VirtualDesktopFocusDebugEnabled()
            LogDesktopFocusDebug("activate_direct", hwnd, GetWindowDesktopNum(hwnd))
        WinActivate "ahk_id " hwnd
    } catch
        return 0
    try return WinGetID("A")
    catch
        return 0
}

LogDesktopFocusDebug(reason, hwnd, desktop_num := 0) {
    log_dir := GetAppDataDir()
    DirCreate(log_dir)
    log_path := log_dir "\\vd.focus.debug.log"

    exe_name := ""
    title := ""
    class_name := ""
    try exe_name := WinGetProcessName("ahk_id " hwnd)
    try title := WinGetTitle("ahk_id " hwnd)
    try class_name := WinGetClass("ahk_id " hwnd)

    line := "[" A_Now "] " reason " hwnd=" Format("0x{:X}", hwnd)
    line .= " desktop=" desktop_num " exe=" exe_name " class=" class_name " title=" title
    SafeFileAppend(line "`n", log_path)
}
