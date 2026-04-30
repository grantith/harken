; Directional focus hotkey bindings.
global Config

if Config.Has("directional_focus") && Config["directional_focus"]["enabled"] {
    HotIf (*) => !IsSuperKeyPressed()
    Hotkey("!h", (*) => DirectionalFocus("left"))
    Hotkey("!l", (*) => DirectionalFocus("right"))
    Hotkey("!j", (*) => DirectionalFocus("down"))
    Hotkey("!k", (*) => DirectionalFocus("up"))
    Hotkey("![", (*) => DirectionalFocusStacked("prev"))
    Hotkey("!]", (*) => DirectionalFocusStacked("next"))
    Hotkey("!+d", (*) => ToggleDirectionalFocusDebug())
    Hotkey("!+s", (*) => SetLastStackedFromActive())
    HotIf
}
