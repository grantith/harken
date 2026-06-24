; Directional focus hotkey bindings.
global Config

if Config.Has("directional_focus") && Config["directional_focus"]["enabled"] {
    HotIf (*) => IsSuperKeyPressed() && !IsAltPressed() && !GetKeyState("Ctrl", "P") && !GetKeyState("Shift", "P")
    Hotkey("h", (*) => DirectionalFocus("left"))
    Hotkey("l", (*) => DirectionalFocus("right"))
    Hotkey("[", (*) => DirectionalFocusStacked("prev"))
    Hotkey("]", (*) => DirectionalFocusStacked("next"))
    HotIf (*) => IsSuperKeyPressed() && !IsAltPressed() && GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P")
    Hotkey("^+d", (*) => ToggleDirectionalFocusDebug())
    Hotkey("^+s", (*) => SetLastStackedFromActive())
    HotIf
}
