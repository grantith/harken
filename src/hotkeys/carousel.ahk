; Carousel mode hotkeys.
global Config

if CarouselModeEnabled() {
    carousel := Config["modes"]["carousel"]

    RegisterSuperComboHotkey(carousel["focus_left_hotkey"], (*) => CarouselHandleHorizontalKey("left"))
    RegisterSuperComboHotkey(carousel["focus_right_hotkey"], (*) => CarouselHandleHorizontalKey("right"))
    RegisterSuperComboHotkey(carousel["desktop_prev_hotkey"], (*) => CarouselHandleDesktopKey(-1))
    RegisterSuperComboHotkey(carousel["desktop_next_hotkey"], (*) => CarouselHandleDesktopKey(1))
    RegisterSuperComboHotkey(carousel["center_hotkey"], (*) => CarouselRelayout("center"))
    RegisterSuperComboHotkey(carousel["width_decrease_hotkey"], (*) => CarouselAdjustCenterWidth(-1))
    RegisterSuperComboHotkey(carousel["width_increase_hotkey"], (*) => CarouselAdjustCenterWidth(1))
    RegisterSuperComboHotkey(carousel["overview_hotkey"], CarouselOpenOverview)
    if (carousel["toggle_follow_hotkey"] != "")
        RegisterSuperComboHotkey(carousel["toggle_follow_hotkey"], (*) => ToggleCarouselDesktopMoveFollow())

    ; Snap windows into carousel layout shortly after startup/reload.
    SetTimer((*) => CarouselRelayout("startup"), -150)
    SetTimer(CarouselFocusWatcherTick, 250)
    SetTimer((*) => EnsureCarouselTrailingEmptyDesktop(), -600)
    SetTimer((*) => InitCarouselStatusBar(), -200)
}

CarouselHandleHorizontalKey(direction) {
    if !CarouselModeEnabled() || Window.IsMoveMode()
        return
    if IsAltPressed()
        return
    if GetKeyState("Ctrl", "P")
        return
    if GetKeyState("Shift", "P") {
        CarouselMove(direction)
        return
    }
    CarouselFocus(direction)
}
