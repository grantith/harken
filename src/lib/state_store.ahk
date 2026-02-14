LoadState() {
    state_path := GetStatePath()
    if !FileExist(state_path)
        return Map()

    try {
        json_text := FileRead(state_path)
        state := Jxon_Load(&json_text)
        if (state is Map)
            return state
    } catch {
    }
    return Map()
}

; Persist small runtime state (overlay toggle, etc.).
SaveState(state) {
    if !(state is Map)
        return

    state_path := GetStatePath()
    DirCreate(GetConfigDir())
    state_text := Jxon_Dump(state, 2)
    if FileExist(state_path)
        FileDelete(state_path)
    FileAppend(state_text, state_path)
}

GetStatePath() {
    return GetConfigDir() "\state.json"
}
