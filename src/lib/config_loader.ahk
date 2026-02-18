; Config loading + schema validation + normalization.
LoadConfig(config_path, default_config := Map()) {
    config := CloneMap(default_config)
    errors := []
    warnings := []

    if FileExist(config_path) {
        try {
            user_config := TomlLoadFile(config_path)
            config := DeepMergeMaps(config, user_config)
        } catch as err {
            errors.Push("config.parse: " err.Message)
            return Map(
                "config", config,
                "errors", errors,
                "warnings", warnings
            )
        }
    }

    NormalizeSuperKeyConfig(config)
    NormalizeVirtualDesktopConfig(config)
    NormalizeAppsConfig(config, errors)
    ValidateConfig(config, ConfigSchema(), errors, warnings)
    ValidateSuperKeys(config, errors)
    ValidateApps(config, errors)
    ValidateVirtualDesktopHotkeys(config, errors)

    return Map(
        "config", config,
        "errors", errors,
        "warnings", warnings
    )
}

ConfigSchema() {
    return Map(
        "config_version", "number",
        "super_key", ["string"],
        "apps", [Map(
            "id", "string",
            "hotkey", OptionalSpec("string"),
            "win_title", OptionalSpec("string"),
            "match", OptionalSpec(Map(
                "exe", OptionalSpec("string"),
                "exe_regex", OptionalSpec("bool"),
                "class", OptionalSpec("string"),
                "class_regex", OptionalSpec("bool"),
                "title", OptionalSpec("string"),
                "title_regex", OptionalSpec("bool"),
                "process_tree", OptionalSpec(Map(
                    "mode", OptionalSpec("string"),
                    "exe", OptionalSpec(["string"]),
                    "exe_regex", OptionalSpec("bool"),
                    "max_depth", OptionalSpec("number"),
                    "negate", OptionalSpec("bool"),
                    "debug", OptionalSpec("bool")
                ))
            )),
            "run", OptionalSpec("string"),
            "run_start_in", OptionalSpec("string"),
            "run_paths", OptionalSpec(["string"]),
            "desktop", OptionalSpec("number"),
            "follow_on_spawn", OptionalSpec("bool"),
            "ignore_classes", OptionalSpec(["string"]),
            "exclude_titles", OptionalSpec(["string"]),
            "focus_border", OptionalSpec(Map(
                "border_color", OptionalSpec("string"),
                "move_mode_color", OptionalSpec("string"),
                "command_mode_color", OptionalSpec("string"),
                "border_thickness", OptionalSpec("number"),
                "corner_radius", OptionalSpec("number"),
                "update_interval_ms", OptionalSpec("number")
            ))
        )],
        "global_hotkeys", [Map(
            "enabled", "bool",
            "hotkey", "string",
            "target_exes", OptionalSpec(["string"]),
            "send_keys", "string"
        )],
        "window", Map(
            "resize_step", "number",
            "move_step", "number",
            "super_double_tap_ms", "number",
            "move_mode", Map(
                "enable", "bool",
                "cancel_key", "string"
            ),
            "cycle_app_windows_hotkey", "string",
            "cycle_app_windows_current_hotkey", "string",
            "center_width_cycle_hotkey", "string",
            "minimize_others_hotkey", OptionalSpec("string")
        ),
        "window_selector", Map(
            "enabled", "bool",
            "hotkey", "string",
            "max_results", "number",
            "title_preview_len", "number",
            "match_title", "bool",
            "match_exe", "bool",
            "include_minimized", "bool",
            "close_on_focus_loss", "bool"
        ),
        "window_manager", Map(
            "grid_size", "number",
            "margins", Map(
                "top", "number",
                "left", "number",
                "right", "number",
                "bottom", "number"
            ),
            "gap_px", "number",
            "exceptions_regex", "string"
        ),
        "virtual_desktop", Map(
            "enabled", "bool",
            "switch_on_focus", "bool",
            "ensure_count", "number",
            "cycle_prefer_current", "bool",
            "prev_hotkey", "string",
            "next_hotkey", "string",
            "move_prev_hotkey", "string",
            "move_next_hotkey", "string",
            "desktop_hotkeys", OptionalSpec([Map(
                "desktop", "number",
                "hotkey", "string"
            )]),
            "goto_hotkeys", [Map(
                "hotkey", "string",
                "desktop", "number"
            )],
            "move_hotkeys", [Map(
                "hotkey", "string",
                "desktop", "number"
            )],
            "debug_cycle", "bool",
            "debug_hotkeys", "bool",
            "debug_focus", OptionalSpec("bool"),
            "tray_indicator", "bool",
            "tray_format", "string",
            "auto_assign", "bool",
            "auto_assign_interval_ms", "number",
            "desktop_hotkeys_duplicates", OptionalSpec([Map(
                "hotkey", "string",
                "desktop", "number",
                "existing", "number"
            )])
        ),
        "directional_focus", Map(
            "enabled", "bool",
            "stacked_overlap_threshold", "number",
            "stack_tolerance_px", "number",
            "prefer_topmost", "bool",
            "prefer_last_stacked", "bool",
            "frontmost_guard_px", "number",
            "perpendicular_overlap_min", "number",
            "cross_monitor", "bool",
            "debug_enabled", "bool"
        ),
        "focus_border", Map(
            "enabled", "bool",
            "border_color", "string",
            "move_mode_color", "string",
            "command_mode_color", "string",
            "border_thickness", "number",
            "corner_radius", "number",
            "update_interval_ms", "number"
        ),
        "helper", Map(
            "enabled", "bool",
            "overlay_opacity", "number"
        ),
        "config_watch", Map(
            "enabled", "bool",
            "interval_ms", "number"
        )
    )
}

ValidateConfig(config, schema, errors, warnings) {
    ValidateNode(config, schema, "config", errors, warnings)
}

NormalizeSuperKeyConfig(config) {
    if !config.Has("super_key")
        return

    super_value := config["super_key"]
    if (super_value is String)
        config["super_key"] := [super_value]
}

NormalizeAppsConfig(config, errors) {
    if !config.Has("apps")
        return

    apps := config["apps"]
    if (apps is Array)
        return

    if !(apps is Map) {
        errors.Push("config.apps should be an array or object")
        return
    }

    normalized := []
    for app_id, app_config in apps {
        if !(app_config is Map) {
            errors.Push("config.apps." app_id " should be an object")
            continue
        }
        if app_config.Has("id") {
            errors.Push("config.apps." app_id " should not set id when using named tables")
            app_config.Delete("id")
        }
        app_config["id"] := app_id
        NormalizeAppProcessTreeConfig(app_config)
        normalized.Push(app_config)
    }

    config["apps"] := normalized
}

NormalizeAppProcessTreeConfig(app_config) {
    if !(app_config is Map)
        return
    if !app_config.Has("match") || !(app_config["match"] is Map)
        return
    match := app_config["match"]
    if !match.Has("process_tree") || !(match["process_tree"] is Map)
        return
    process_tree := match["process_tree"]
    if process_tree.Has("exe") && (process_tree["exe"] is String)
        process_tree["exe"] := [process_tree["exe"]]
    if !process_tree.Has("mode") || process_tree["mode"] = ""
        process_tree["mode"] := "descendant"
}


NormalizeVirtualDesktopConfig(config) {
    if !config.Has("virtual_desktop") || !(config["virtual_desktop"] is Map)
        return

    vd_config := config["virtual_desktop"]
    desktop_hotkeys := []
    duplicates := []
    seen_hotkeys := Map()
    keys_to_remove := []

    for key, val in vd_config {
        if !IsInteger(key)
            continue
        keys_to_remove.Push(key)
        desktop_num := Integer(key)
        if (val is Array) {
            for _, entry in val {
                if !(entry is Map)
                    continue
                if entry.Has("hotkey") && entry["hotkey"] != "" {
                    hotkey := entry["hotkey"]
                    if seen_hotkeys.Has(hotkey) {
                        duplicates.Push(Map("hotkey", hotkey, "desktop", desktop_num, "existing", seen_hotkeys[hotkey]))
                    } else {
                        seen_hotkeys[hotkey] := desktop_num
                        desktop_hotkeys.Push(Map(
                            "desktop", desktop_num,
                            "hotkey", hotkey
                        ))
                    }
                }
            }
        } else if (val is Map) {
            if val.Has("hotkey") && val["hotkey"] != "" {
                hotkey := val["hotkey"]
                if seen_hotkeys.Has(hotkey) {
                    duplicates.Push(Map("hotkey", hotkey, "desktop", desktop_num, "existing", seen_hotkeys[hotkey]))
                } else {
                    seen_hotkeys[hotkey] := desktop_num
                    desktop_hotkeys.Push(Map(
                        "desktop", desktop_num,
                        "hotkey", hotkey
                    ))
                }
            }
        }
    }

    if (desktop_hotkeys.Length > 0)
        vd_config["desktop_hotkeys"] := desktop_hotkeys

    if (duplicates.Length > 0)
        vd_config["desktop_hotkeys_duplicates"] := duplicates

    for _, key in keys_to_remove
        vd_config.Delete(key)
}

ValidateSuperKeys(config, errors) {
    if !config.Has("super_key")
        return
    super_keys := config["super_key"]
    if (super_keys is Array && super_keys.Length = 0)
        errors.Push("config.super_key should contain at least one key")
}

ValidateApps(config, errors) {
    if !config.Has("apps") || !(config["apps"] is Array)
        return

    for index, app in config["apps"] {
        if !(app is Map)
            continue

        has_hotkey := app.Has("hotkey") && (app["hotkey"] != "")
        has_win_title := app.Has("win_title") && (app["win_title"] != "")
        has_match := app.Has("match") && (app["match"] is Map)

        if !has_win_title && !has_match
            errors.Push("config.apps[" index "] must define win_title or match")

        if has_hotkey && (!app.Has("run") || app["run"] = "")
            errors.Push("config.apps[" index "].run is required when hotkey is set")

        if has_match {
            match := app["match"]
            has_exe := match.Has("exe") && (match["exe"] != "")
            has_class := match.Has("class") && (match["class"] != "")
            has_title := match.Has("title") && (match["title"] != "")
            has_process_tree := match.Has("process_tree") && (match["process_tree"] is Map)
            if !has_exe && !has_class && !has_title && !has_process_tree
                errors.Push("config.apps[" index "].match must define exe, class, title, or process_tree")

            if (match.Has("exe_regex") && !has_exe)
                errors.Push("config.apps[" index "].match.exe_regex requires exe")
            if (match.Has("class_regex") && !has_class)
                errors.Push("config.apps[" index "].match.class_regex requires class")
            if (match.Has("title_regex") && !has_title)
                errors.Push("config.apps[" index "].match.title_regex requires title")

            if has_process_tree {
                process_tree := match["process_tree"]
                has_tree_exe := process_tree.Has("exe") && (process_tree["exe"] is Array) && process_tree["exe"].Length
                if !has_tree_exe
                    errors.Push("config.apps[" index "].match.process_tree.exe must define one or more executables")
                if process_tree.Has("exe_regex") && !has_tree_exe
                    errors.Push("config.apps[" index "].match.process_tree.exe_regex requires exe")
                mode := process_tree.Has("mode") ? process_tree["mode"] : "descendant"
                if (mode != "ancestor" && mode != "descendant" && mode != "either")
                    errors.Push("config.apps[" index "].match.process_tree.mode must be ancestor, descendant, or either")
                if process_tree.Has("max_depth") && (process_tree["max_depth"] < 0)
                    errors.Push("config.apps[" index "].match.process_tree.max_depth must be >= 0")
            }
        }
    }
}

ValidateVirtualDesktopHotkeys(config, errors) {
    if !config.Has("virtual_desktop") || !(config["virtual_desktop"] is Map)
        return
    vd_config := config["virtual_desktop"]
    if vd_config.Has("desktop_hotkeys_duplicates") && (vd_config["desktop_hotkeys_duplicates"] is Array) {
        for _, entry in vd_config["desktop_hotkeys_duplicates"] {
            if !(entry is Map)
                continue
            hotkey := entry.Has("hotkey") ? entry["hotkey"] : ""
            desktop := entry.Has("desktop") ? entry["desktop"] : ""
            existing := entry.Has("existing") ? entry["existing"] : ""
            if (hotkey != "")
                errors.Push("config.virtual_desktop.hotkey '" hotkey "' maps to desktop " desktop " but is already mapped to " existing)
        }
    }
}

ValidateNode(value, spec, path, errors, warnings) {
    if (spec is Map) {
        if spec.Has("__optional__") {
            if (value = "")
                return
            return ValidateNode(value, spec["spec"], path, errors, warnings)
        }
        if !(value is Map) {
            errors.Push(path " should be an object")
            return
        }

        for key, _ in spec {
            if !value.Has(key) {
                if (spec[key] is Map && spec[key].Has("__optional__") && spec[key]["__optional__"])
                    continue
                errors.Push(path "." key " is missing")
            }
        }

        for key, val in value {
            if !spec.Has(key) {
                warnings.Push(path "." key " is unknown")
                continue
            }
            if (spec[key] is Map && spec[key].Has("__optional__") && spec[key]["__optional__"]) {
                ValidateNode(val, spec[key]["spec"], path "." key, errors, warnings)
            } else {
                ValidateNode(val, spec[key], path "." key, errors, warnings)
            }
        }
        return
    }

    if (spec is Array) {
        if !(value is Array) {
            errors.Push(path " should be an array")
            return
        }
        if (spec.Length = 0)
            return
        item_spec := spec[1]
        for i, item in value {
            ValidateNode(item, item_spec, path "[" i "]", errors, warnings)
        }
        return
    }

    if (spec = "string") {
        if !(value is String)
            errors.Push(path " should be a string")
        return
    }

    if (spec = "number") {
        if !IsNumber(value)
            errors.Push(path " should be a number")
        return
    }

    if (spec = "integer") {
        if !IsInteger(value)
            errors.Push(path " should be an integer")
        return
    }

    if (spec = "bool") {
        if !IsBooleanValue(value)
            errors.Push(path " should be a boolean")
        return
    }
}


OptionalSpec(spec) {
    return Map(
        "__optional__", true,
        "spec", spec
    )
}

IsBooleanValue(value) {
    if (value is Integer)
        return (value = 0 || value = 1)
    return (value = true || value = false)
}

DeepMergeMaps(base_map, override_map) {
    if !(override_map is Map)
        return base_map

    for key, val in override_map {
        if (val is Array) {
            base_map[key] := val
            continue
        }
        if base_map.Has(key) && (base_map[key] is Map) && (val is Map) {
            base_map[key] := DeepMergeMaps(base_map[key], val)
        } else {
            base_map[key] := val
        }
    }
    return base_map
}

CloneMap(source) {
    if !(source is Map)
        return source

    clone := Map()
    for key, val in source {
        if (val is Map)
            clone[key] := CloneMap(val)
        else if (val is Array)
            clone[key] := CloneArray(val)
        else
            clone[key] := val
    }
    return clone
}

CloneArray(source) {
    if !(source is Array)
        return source

    clone := []
    for _, val in source {
        if (val is Map)
            clone.Push(CloneMap(val))
        else if (val is Array)
            clone.Push(CloneArray(val))
        else
            clone.Push(val)
    }
    return clone
}
