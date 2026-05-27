; Carousel mode hotkeys.
global Config

if CarouselModeEnabled() {
    carousel := Config["modes"]["carousel"]

    ; Bind focus moves with explicit modifier guards so Shift variants remain
    ; available for tile reordering and do not get swallowed by super+h/l.
    HotIf (*) => IsSuperKeyPressed() && !IsAltPressed() && !GetKeyState("Shift", "P") && !GetKeyState("Ctrl", "P") && !Window.IsMoveMode()
    Hotkey(carousel["focus_left_hotkey"], (*) => CarouselFocus("left"))
    Hotkey(carousel["focus_right_hotkey"], (*) => CarouselFocus("right"))
    HotIf
    RegisterSuperComboHotkey(carousel["desktop_prev_hotkey"], (*) => CarouselHandleDesktopKey(-1))
    RegisterSuperComboHotkey(carousel["desktop_next_hotkey"], (*) => CarouselHandleDesktopKey(1))
    RegisterSuperComboHotkey(carousel["center_hotkey"], (*) => CarouselRelayout("center"))
    RegisterSuperComboHotkey(carousel["width_decrease_hotkey"], (*) => CarouselAdjustCenterWidth(-1))
    RegisterSuperComboHotkey(carousel["width_increase_hotkey"], (*) => CarouselAdjustCenterWidth(1))
    RegisterSuperComboHotkey(carousel["overview_hotkey"], CarouselOpenOverview)
    if (carousel["toggle_follow_hotkey"] != "")
        RegisterSuperComboHotkey(carousel["toggle_follow_hotkey"], (*) => ToggleCarouselDesktopMoveFollow())

    ; Modified hotkeys (Shift/Ctrl variants) must use HotIf/Hotkey,
    ; because combo bindings cannot include AHK modifier prefixes like + or ^.
    HotIf (*) => IsSuperKeyPressed() && !IsAltPressed() && GetKeyState("Shift", "P") && !GetKeyState("Ctrl", "P") && !Window.IsMoveMode()
    Hotkey(carousel["move_left_hotkey"], (*) => CarouselMove("left"))
    Hotkey(carousel["move_right_hotkey"], (*) => CarouselMove("right"))
    HotIf

    ; Snap windows into carousel layout shortly after startup/reload.
    SetTimer((*) => CarouselRelayout("startup"), -150)
    SetTimer(CarouselFocusWatcherTick, 250)
    SetTimer((*) => EnsureCarouselTrailingEmptyDesktop(), -600)
    SetTimer((*) => InitCarouselStatusBar(), -200)
}
