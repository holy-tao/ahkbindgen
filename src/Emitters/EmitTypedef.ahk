#Requires AutoHotkey v2.1-alpha.30

/**
 * Emit a top-level typedef into the StringBuilder
 * 
 * @param {IR.Type.EmittableTypedef} typedefType the type to emut 
 * @param {Map<String, Type>} registry type registry, for looking up embedded structs
 * @param {StringBuilder} sb StringBuilder to emit into
 * @returns {void} 
 */
export default EmitTypedef(typedefType, registry, sb) {
    sb.AppendLine("struct " typedefType.name " {")
    sb.AppendLine("    value: " typedefType.underlying.ToSpecifier())
    sb.AppendLine("    __value {")
    ; No getter so that returned typedefs are able to have methods and properties
    sb.AppendLine("        set => this.value := (value is " typedefType.name ") ? value.value : value")
    sb.AppendLine("    }")
    sb.AppendLine("}")
}