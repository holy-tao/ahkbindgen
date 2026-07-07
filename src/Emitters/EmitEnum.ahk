#Requires AutoHotkey v2.1-alpha.30 

/**
 * Emit an enum type
 * @param {Enum} enumType the enum to emit 
 * @param {StringBuilder} sb StringBuilder to emit into
 * @returns {void} 
 */
export default EmitEnum(enumType, sb) {
    global _ValueCode
    sb.AppendLine("struct " enumType.name " {")
    sb.AppendLine("    value: " enumType.underlying.ToSpecifier())
    sb.AppendLine("    __value {")
    sb.AppendLine("        get => this.value")
    sb.AppendLine("        set => this.value := value")
    sb.AppendLine("    }")
    sb.AppendLine()

    ; Strip shared prefixes, so things like Lib_ActualName get reduced to ActualName
    fieldNames := enumType.Fields.Map(f => f.name)
    prefix := LongestSharedPrefix(fieldNames*)
    fieldNames := fieldNames.Map(n => StrReplace(n, prefix))

    align := Max(fieldNames.Map(StrLen)*)
    for i, field in enumType.fields {
        sb.AppendLine(Format("    static {1:-" align "} => {2}", 
            fieldNames[i], field.value))
    }

    sb.AppendLine("}")
}

/**
 * Given an array of strings, returns the longest prefix shared between them
 * @param {Array<String>} strs strings
 * @returns {String} 
 */
LongestSharedPrefix(strs*) {
    if strs.Length <= 0
        return ""

    ; Find the shortst string in strs, any prefix must be a substring of it
    shortest := Min(strs.Map(StrLen)*)
    prefix := ""

    loop StrLen(shortest) {
        i := A_Index ; A_Index in array.All is the index of the .All loop, not ours
        char := SubStr(shortest, i, 1)

        if !strs.All(s => SubStr(s, i, 1) == char) {
            break
        }

        prefix .= char
    }

    return prefix
}