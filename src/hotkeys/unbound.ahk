; Unbound hotkey helper + reserved key detection.
global Config

RegisterUnboundHotkeys() {
    used_keys := Map()

    AddUsedKey(used_keys, Config["window"]["center_width_cycle_hotkey"])
    AddUsedKey(used_keys, Config["window"]["cycle_app_windows_hotkey"])
    AddUsedKey(used_keys, Config["window"]["cycle_app_windows_current_hotkey"])
    AddUsedKey(used_keys, "m")
    AddUsedKey(used_keys, "q")
    AddUsedKey(used_keys, "h")
    AddUsedKey(used_keys, "j")
    AddUsedKey(used_keys, "k")
    AddUsedKey(used_keys, "l")
    AddUsedKey(used_keys, "u")
    AddUsedKey(used_keys, "o")
    AddUsedKey(used_keys, "n")

    if Config.Has("screen_search") && Config["screen_search"]["enabled"]
        AddUsedKey(used_keys, Config["screen_search"]["hotkey"])

    for _, app in Config["apps"] {
        if app.Has("hotkey") && app["hotkey"] != ""
            AddUsedKey(used_keys, app["hotkey"])
    }

    for _, hotkey_config in Config["global_hotkeys"] {
        if hotkey_config["enabled"]
            AddUsedKey(used_keys, hotkey_config["hotkey"])
    }

    candidates := BuildUnboundCandidateKeys()
    HotIf IsSuperKeyPressed
    for _, key in candidates {
        if !used_keys.Has(StrLower(key))
            Hotkey(key, (*) => FlashUnboundHotkey())
    }
    HotIf
}

AddUsedKey(used_keys, key) {
    if !key
        return
    used_keys[StrLower(key)] := true
}

BuildUnboundCandidateKeys() {
    keys := []
    loop 26
        keys.Push(Chr(96 + A_Index))
    loop 10
        keys.Push(A_Index - 1)
    return keys
}

FlashUnboundHotkey() {
    FlashFocusBorder(0xB0B0B0, 130)
}

RegisterUnboundHotkeys()
