global Config

global carousel_status_bar_gui := ""
global carousel_status_bar_visible := false
global carousel_status_bar_monitor := 0
global carousel_status_bar_desktop_ctrls := []
global carousel_status_bar_window_ctrls := []
global carousel_status_bar_last_key := ""
global carousel_status_bar_last_layout_key := ""
global carousel_status_bar_vd_listener_registered := false

InitCarouselStatusBar() {
    if !CarouselModeEnabled() {
        DestroyCarouselStatusBar()
        return
    }
    if !CarouselStatusBarConfigEnabled() {
        DestroyCarouselStatusBar()
        return
    }
    EnsureCarouselStatusBarListener()
    CarouselStatusBarUpdate()
}

EnsureCarouselStatusBarListener() {
    global carousel_status_bar_vd_listener_registered
    if carousel_status_bar_vd_listener_registered
        return
    if !VirtualDesktopEnabled()
        return
    VD.ListenersCurrentVirtualDesktopChanged[CarouselStatusBarDesktopChanged] := true
    carousel_status_bar_vd_listener_registered := true
}

CarouselStatusBarDesktopChanged(*) {
    CarouselStatusBarUpdate()
}

CarouselStatusBarConfigEnabled() {
    if !Config.Has("modes") || !(Config["modes"] is Map)
        return false
    if !Config["modes"].Has("carousel") || !(Config["modes"]["carousel"] is Map)
        return false
    carousel := Config["modes"]["carousel"]
    if !carousel.Has("status_bar") || !(carousel["status_bar"] is Map)
        return false
    return carousel["status_bar"]["enabled"]
}

CarouselStatusBarReservedTopPx(*) {
    if !CarouselModeEnabled() || !CarouselStatusBarConfigEnabled()
        return 0
    settings := Config["modes"]["carousel"]["status_bar"]
    if (settings["position"] != "top")
        return 0
    return settings["height_px"] + settings["reserve_gap_px"]
}

CarouselStatusBarUpdate(*) {
    global carousel_status_bar_gui, carousel_status_bar_visible, carousel_status_bar_last_key, carousel_status_bar_last_layout_key
    if !CarouselModeEnabled() || !CarouselStatusBarConfigEnabled() {
        DestroyCarouselStatusBar()
        return
    }

    settings := Config["modes"]["carousel"]["status_bar"]
    model := BuildCarouselStatusBarModel(settings)
    if !(model is Map)
        return

    view_key := model["key"]
    layout_key := model["layout_key"]
    if !carousel_status_bar_gui {
        CreateCarouselStatusBarGui(model, settings)
    } else if (carousel_status_bar_last_layout_key != layout_key) {
        RebuildCarouselStatusBarGui(model, settings)
    } else {
        UpdateCarouselStatusBarContent(model)
    }

    ShowCarouselStatusBarGui(settings)
    carousel_status_bar_last_key := view_key
    carousel_status_bar_last_layout_key := layout_key
    carousel_status_bar_visible := true
}

BuildCarouselStatusBarModel(settings) {
    desktop_total := VirtualDesktopEnabled() ? VD.getCount() : 1
    if (desktop_total <= 0)
        desktop_total := 1

    active_desktop := VirtualDesktopEnabled() ? GetCurrentDesktopNumFresh() : 1
    if (active_desktop <= 0)
        active_desktop := 1

    desktop_cells := []
    Loop desktop_total {
        desktop_num := A_Index
        desktop_cells.Push(Map(
            "num", desktop_num,
            "active", desktop_num = active_desktop
        ))
    }

    state := BuildCarouselState()
    windows := state["windows"]
    active_hwnd := state["active_hwnd"]

    window_cells := []
    for _, hwnd in windows {
        if !WindowExistsAcrossDesktops(hwnd)
            continue
        title := ""
        exe := ""
        try title := WinGetTitle("ahk_id " hwnd)
        try exe := WinGetProcessName("ahk_id " hwnd)
        if (title = "") {
            if (exe != "")
                title := RegExReplace(exe, "(?i)\.exe$", "")
            else
                title := "(untitled)"
        }
        title := CarouselStatusBarTruncate(title, settings["title_max_len"])
        window_cells.Push(Map(
            "hwnd", hwnd,
            "title", title,
            "active", hwnd = active_hwnd
        ))
    }

    key := active_desktop "/" desktop_total "|"
    for _, d in desktop_cells
        key .= d["active"] ? ("[" d["num"] "]") : d["num"]
    key .= "|"
    for _, w in window_cells
        key .= (w["active"] ? "*" : "") w["hwnd"] ":" w["title"] "|"

    layout_key := "d:" desktop_cells.Length "|w:" window_cells.Length

    model := Map(
        "desktop_total", desktop_total,
        "active_desktop", active_desktop,
        "desktop_cells", desktop_cells,
        "window_cells", window_cells,
        "layout_key", layout_key,
        "key", key
    )
    return model
}

CarouselStatusBarTruncate(text, max_len) {
    if (max_len <= 0)
        return ""
    if (StrLen(text) <= max_len)
        return text
    if (max_len <= 3)
        return SubStr(text, 1, max_len)
    return SubStr(text, 1, max_len - 3) "..."
}

CreateCarouselStatusBarGui(model, settings) {
    global carousel_status_bar_gui
    carousel_status_bar_gui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "harken Carousel Status")
    carousel_status_bar_gui.MarginX := 10
    carousel_status_bar_gui.MarginY := 6
    carousel_status_bar_gui.BackColor := NormalizeHexColor(settings["background_color"], "181818")
    RebuildCarouselStatusBarGui(model, settings)
}

RebuildCarouselStatusBarGui(model, settings) {
    global carousel_status_bar_gui, carousel_status_bar_desktop_ctrls, carousel_status_bar_window_ctrls
    if carousel_status_bar_gui
        carousel_status_bar_gui.Destroy()
    carousel_status_bar_gui := ""
    carousel_status_bar_desktop_ctrls := []
    carousel_status_bar_window_ctrls := []

    carousel_status_bar_gui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "harken Carousel Status")
    carousel_status_bar_gui.MarginX := 10
    carousel_status_bar_gui.MarginY := 6
    carousel_status_bar_gui.BackColor := NormalizeHexColor(settings["background_color"], "181818")

    BuildCarouselStatusBarControls(model, settings)
}

BuildCarouselStatusBarControls(model, settings) {
    global carousel_status_bar_gui, carousel_status_bar_desktop_ctrls, carousel_status_bar_window_ctrls

    font_size := settings["font_size"]
    text_color := NormalizeHexColor(settings["text_color"], "CCCCCC")
    active_color := NormalizeHexColor(settings["active_color"], "A020F0")

    carousel_status_bar_gui.SetFont("s" font_size " w600 c" text_color, "Segoe UI")
    desktop_label := carousel_status_bar_gui.AddText("xm ym", "Desktops:")
    carousel_status_bar_desktop_ctrls.Push(desktop_label)

    max_desktop_digits := StrLen("" model["desktop_total"])
    if (max_desktop_digits < 1)
        max_desktop_digits := 1
    ; Keep each desktop token wide enough for bracketed active state, e.g. [12].
    desktop_token_chars := max_desktop_digits + 2
    desktop_token_w := Round(font_size * desktop_token_chars * 0.7) + 10
    if (desktop_token_w < 20)
        desktop_token_w := 20

    is_first_desktop := true
    for _, cell in model["desktop_cells"] {
        token := cell["active"] ? ("[" cell["num"] "]") : cell["num"]
        color := cell["active"] ? active_color : text_color
        weight := cell["active"] ? "w700" : "w500"
        opts := is_first_desktop ? "x+8 yp w" desktop_token_w " Center" : "x+4 yp w" desktop_token_w " Center"
        carousel_status_bar_gui.SetFont("s" font_size " " weight " c" color, "Segoe UI")
        desktop_token_ctrl := carousel_status_bar_gui.AddText(opts, token)
        carousel_status_bar_desktop_ctrls.Push(desktop_token_ctrl)
        is_first_desktop := false
    }

    carousel_status_bar_gui.SetFont("s" font_size " c" text_color, "Segoe UI")
    windows_prefix := carousel_status_bar_gui.AddText("x+20 yp", "Strip:")
    carousel_status_bar_window_ctrls.Push(windows_prefix)

    win_cells := model["window_cells"]
    if (win_cells.Length = 0) {
        empty_ctrl := carousel_status_bar_gui.AddText("x+8 yp", "(no windows)")
        carousel_status_bar_window_ctrls.Push(empty_ctrl)
        return
    }

    is_first := true
    for _, cell in win_cells {
        color := cell["active"] ? active_color : text_color
        weight := "w500"
        token := " " cell["title"] " "
        opts := is_first ? "x+8 yp" : "x+10 yp"
        carousel_status_bar_gui.SetFont("s" font_size " " weight " c" color, "Segoe UI")
        ctrl := carousel_status_bar_gui.AddText(opts " +Border", token)
        carousel_status_bar_window_ctrls.Push(ctrl)
        is_first := false
    }
}

UpdateCarouselStatusBarContent(model) {
    global carousel_status_bar_desktop_ctrls, carousel_status_bar_window_ctrls

    text_color := NormalizeHexColor(Config["modes"]["carousel"]["status_bar"]["text_color"], "CCCCCC")
    active_color := NormalizeHexColor(Config["modes"]["carousel"]["status_bar"]["active_color"], "A020F0")
    font_size := Config["modes"]["carousel"]["status_bar"]["font_size"]

    desktop_cells := model["desktop_cells"]
    for i, cell in desktop_cells {
        ctrl_index := i + 1
        if (ctrl_index > carousel_status_bar_desktop_ctrls.Length)
            continue
        ctrl := carousel_status_bar_desktop_ctrls[ctrl_index]
        token := cell["active"] ? ("[" cell["num"] "]") : cell["num"]
        color := cell["active"] ? active_color : text_color
        weight := cell["active"] ? "w700" : "w500"
        ctrl.SetFont("s" font_size " " weight " c" color, "Segoe UI")
        ctrl.Text := token
    }

    win_cells := model["window_cells"]
    for i, cell in win_cells {
        ctrl_index := i + 1
        if (ctrl_index > carousel_status_bar_window_ctrls.Length)
            continue
        ctrl := carousel_status_bar_window_ctrls[ctrl_index]
        color := cell["active"] ? active_color : text_color
        weight := "w500"
        ctrl.SetFont("s" font_size " " weight " c" color, "Segoe UI")
        ctrl.Text := " " cell["title"] " "
    }
}

ShowCarouselStatusBarGui(settings) {
    global carousel_status_bar_gui, carousel_status_bar_monitor
    if !carousel_status_bar_gui
        return

    opacity := settings["opacity"]
    opacity := Max(0, Min(255, Round(opacity)))
    if (opacity < 255)
        WinSetTransparent(opacity, carousel_status_bar_gui)

    mon := MonitorGetPrimary()
    try {
        hwnd := WinGetID("A")
        if hwnd
            mon := Screen.FromWindow("ahk_id " hwnd)
    }
    carousel_status_bar_monitor := mon

    MonitorGetWorkArea(mon, &left, &top, &right, &bottom)
    width := right - left
    height := settings["height_px"]
    if (height < 24)
        height := 24

    pos := settings["position"]
    y := (pos = "bottom") ? (bottom - height) : top
    carousel_status_bar_gui.Show("NoActivate x" left " y" y " w" width " h" height)
}

DestroyCarouselStatusBar() {
    global carousel_status_bar_gui, carousel_status_bar_visible, carousel_status_bar_last_key, carousel_status_bar_last_layout_key
    global carousel_status_bar_desktop_ctrls, carousel_status_bar_window_ctrls
    if carousel_status_bar_gui {
        carousel_status_bar_gui.Destroy()
        carousel_status_bar_gui := ""
    }
    carousel_status_bar_desktop_ctrls := []
    carousel_status_bar_window_ctrls := []
    carousel_status_bar_last_key := ""
    carousel_status_bar_last_layout_key := ""
    carousel_status_bar_visible := false
}
