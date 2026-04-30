; Minimal TOML parser/loader used for config.
TomlLoadFile(file_path) {
    toml_text := FileRead(file_path, "UTF-8")
    return TomlParse(toml_text)
}

TomlParse(toml_text) {
    data := Map()
    current_context := data

    lines := StrSplit(toml_text, "`n", "`r")
    for _, raw_line in lines {
        line := Trim(TomlStripComment(raw_line))
        if (line = "")
            continue

        if (SubStr(line, 1, 2) = "[[" && SubStr(line, -2) = "]]" ) {
            section_path := Trim(SubStr(line, 3, StrLen(line) - 4))
            current_context := TomlGetOrCreateArrayItem(data, section_path)
            continue
        }

        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            section_path := Trim(SubStr(line, 2, StrLen(line) - 2))
            current_context := TomlGetOrCreateSection(data, section_path)
            continue
        }

        if InStr(line, "=") {
            kv := TomlSplitKeyValue(line)
            if (kv.Has("key") && kv["key"] != "")
                TomlSetNestedKey(current_context, kv["key"], TomlParseValue(kv["value"]))
        }
    }

    return data
}

TomlStripComment(line) {
    in_double := false
    in_single := false
    escaped := false
    result := ""

    loop parse, line {
        ch := A_LoopField
        if (escaped) {
            result .= ch
            escaped := false
            continue
        }

        if (ch = "\\" && in_double) {
            escaped := true
            result .= ch
            continue
        }

        if (ch = '"' && !in_single)
            in_double := !in_double
        else if (ch = "'" && !in_double)
            in_single := !in_single

        if (ch = "#" && !in_double && !in_single)
            break

        result .= ch
    }

    return result
}

TomlSplitKeyValue(line) {
    in_double := false
    in_single := false
    escaped := false

    loop parse, line {
        ch := A_LoopField
        if (escaped) {
            escaped := false
            continue
        }
        if (ch = "\\" && in_double) {
            escaped := true
            continue
        }
        if (ch = '"' && !in_single)
            in_double := !in_double
        else if (ch = "'" && !in_double)
            in_single := !in_single

        if (ch = "=" && !in_double && !in_single) {
            key := Trim(SubStr(line, 1, A_Index - 1))
            value := Trim(SubStr(line, A_Index + 1))
            return Map("key", key, "value", value)
        }
    }

    return Map()
}

TomlGetOrCreateSection(data, section_path) {
    parts := StrSplit(section_path, ".")
    current := data
    for _, part in parts {
        if (!current.Has(part) || !(current[part] is Map))
            current[part] := Map()
        current := current[part]
    }
    return current
}

TomlGetOrCreateArrayItem(data, section_path) {
    parts := StrSplit(section_path, ".")
    if (parts.Length = 1) {
        array_name := parts[1]
        if (!data.Has(array_name) || !(data[array_name] is Array))
            data[array_name] := []
        data[array_name].Push(Map())
        return data[array_name][data[array_name].Length]
    }

    parent := TomlGetOrCreateSection(data, TomlJoinRange(parts, ".", 1, parts.Length - 1))
    array_name := parts[parts.Length]
    if (!parent.Has(array_name) || !(parent[array_name] is Array))
        parent[array_name] := []
    parent[array_name].Push(Map())
    return parent[array_name][parent[array_name].Length]
}

TomlSetNestedKey(root, key_path, value) {
    parts := StrSplit(key_path, ".")
    current := root
    loop parts.Length - 1 {
        part := parts[A_Index]
        if (!current.Has(part) || !(current[part] is Map))
            current[part] := Map()
        current := current[part]
    }
    current[parts[parts.Length]] := value
}

TomlParseValue(value) {
    if (value = "")
        return ""

    if (SubStr(value, 1, 1) = "{" && SubStr(value, -1) = "}") {
        table_content := Trim(SubStr(value, 2, StrLen(value) - 2))
        return TomlParseInlineTable(table_content)
    }

    if (SubStr(value, 1, 1) = "[" && SubStr(value, -1) = "]") {
        array_content := Trim(SubStr(value, 2, StrLen(value) - 2))
        return TomlParseArray(array_content)
    }

    if (SubStr(value, 1, 1) = '"' && SubStr(value, -1) = '"') {
        inner := SubStr(value, 2, StrLen(value) - 2)
        inner := StrReplace(inner, "\\`"", "`"")
        inner := StrReplace(inner, "\\\\", "\\")
        return inner
    }

    if (SubStr(value, 1, 1) = "'" && SubStr(value, -1) = "'")
        return SubStr(value, 2, StrLen(value) - 2)

    if (value = "true")
        return true
    if (value = "false")
        return false

    if (value ~= "^-?\d+$")
        return Integer(value)
    if (value ~= "^-?\d+\.\d+$")
        return Float(value)

    return value
}

TomlParseInlineTable(content) {
    table := Map()
    if (content = "")
        return table

    elements := []
    in_double := false
    in_single := false
    escaped := false
    depth := 0
    current := ""

    loop parse, content {
        ch := A_LoopField
        if (escaped) {
            current .= ch
            escaped := false
            continue
        }

        if (ch = "\\" && in_double) {
            escaped := true
            current .= ch
            continue
        }

        if (ch = '"' && !in_single)
            in_double := !in_double
        else if (ch = "'" && !in_double)
            in_single := !in_single

        if (!in_double && !in_single) {
            if (ch = "[" || ch = "{")
                depth += 1
            else if (ch = "]" || ch = "}")
                depth -= 1
        }

        if (ch = "," && !in_double && !in_single && depth = 0) {
            elements.Push(Trim(current))
            current := ""
            continue
        }

        current .= ch
    }

    if (Trim(current) != "")
        elements.Push(Trim(current))

    for _, element in elements {
        kv := TomlSplitKeyValue(element)
        if (kv.Has("key") && kv["key"] != "")
            TomlSetNestedKey(table, kv["key"], TomlParseValue(kv["value"]))
    }

    return table
}

TomlParseArray(content) {
    result := []
    if (content = "")
        return result

    elements := []
    in_double := false
    in_single := false
    escaped := false
    depth := 0
    current := ""

    loop parse, content {
        ch := A_LoopField
        if (escaped) {
            current .= ch
            escaped := false
            continue
        }

        if (ch = "\\" && in_double) {
            escaped := true
            current .= ch
            continue
        }

        if (ch = '"' && !in_single)
            in_double := !in_double
        else if (ch = "'" && !in_double)
            in_single := !in_single

        if (ch = "[" && !in_double && !in_single)
            depth += 1
        else if (ch = "]" && !in_double && !in_single)
            depth -= 1

        if (ch = "," && !in_double && !in_single && depth = 0) {
            elements.Push(Trim(current))
            current := ""
            continue
        }

        current .= ch
    }

    if (Trim(current) != "")
        elements.Push(Trim(current))

    for _, element in elements
        result.Push(TomlParseValue(element))

    return result
}

TomlDump(config, table_array_keys := []) {
    lines := []

    for key, value in config {
        if (value is Map)
            continue
        if (TomlIsTableArrayKey(key, value, table_array_keys))
            continue
        lines.Push(key " = " TomlFormatValue(value))
    }

    if (lines.Length)
        lines.Push("")

    for key, value in config {
        if (TomlIsTableArrayKey(key, value, table_array_keys)) {
            for _, item in value {
                lines.Push("[[" key "]]" )
                for item_key, item_value in item
                    lines.Push(item_key " = " TomlFormatValue(item_value))
                lines.Push("")
            }
        }
    }

    for key, value in config {
        if (value is Map)
            TomlAppendSection(lines, key, value)
    }

    while (lines.Length && lines[lines.Length] = "")
        lines.Pop()

    return TomlJoin(lines, "`n")
}

TomlAppendSection(lines, section_path, section_map) {
    lines.Push("[" section_path "]")
    nested_sections := []

    for key, value in section_map {
        if (value is Map) {
            nested_sections.Push(Map("path", section_path "." key, "map", value))
            continue
        }
        lines.Push(key " = " TomlFormatValue(value))
    }

    lines.Push("")

    for _, nested in nested_sections
        TomlAppendSection(lines, nested["path"], nested["map"])
}

TomlIsTableArrayKey(key, value, table_array_keys) {
    if (value is Array) {
        if (value.Length > 0 && value[1] is Map)
            return true
        for _, table_key in table_array_keys {
            if (key = table_key)
                return true
        }
    }
    return false
}

TomlFormatValue(value) {
    if (value is Array) {
        if (value.Length = 0)
            return "[]"
        elements := []
        for _, item in value
            elements.Push(TomlFormatValue(item))
        return "[" TomlJoin(elements, ", ") "]"
    }

    if (value is Integer || value is Float)
        return value

    if (value = true)
        return "true"
    if (value = false)
        return "false"

    return TomlQuoteString(value)
}

TomlQuoteString(value) {
    escaped := StrReplace(value, "\\", "\\\\")
    escaped := StrReplace(escaped, "`"", "\\`"")
    return "`"" escaped "`""
}

TomlJoin(items, sep) {
    output := ""
    for i, item in items {
        if (i > 1)
            output .= sep
        output .= item
    }
    return output
}

TomlJoinRange(parts, sep, start_index, length) {
    output := ""
    end_index := start_index + length - 1
    loop length {
        idx := start_index + A_Index - 1
        if (idx > end_index)
            break
        if (output != "")
            output .= sep
        output .= parts[idx]
    }
    return output
}
