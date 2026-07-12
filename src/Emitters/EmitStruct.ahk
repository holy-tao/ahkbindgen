#Requires AutoHotkey v2.1-alpha.30

    ; TODO handle bitfields, anonymous embedded structs


/**
 * Emit a struct type into a StringBuilder
 * 
 * @param {IR.Struct.Struct} structType type to emit 
 * @param {Map<String, Type>} registry type registry, for looking up embedded structs
 * @param {StringBuilder} sb StringBuilder to emit into
 * @returns {void} 
 */
export EmitStruct(structType, registry, sb) {
    sb.AppendLine("struct " structType.name " {")

    for field in structType.fields {
        line := Format("    {1}: {2}", field.name, field.type.ToSpecifier())
        sb.AppendLine(line)
    }

    sb.AppendLine("}")
}

/**
 * Emit a union type into a StringBuilder
 * 
 * @param {IR.Struct.Struct} structType type to emit 
 * @param {Map<String, Type>} registry type registry, for looking up embedded structs
 * @param {StringBuilder} sb StringBuilder to emit into
 * @returns {void} 
 */
export EmitUnion(unionType, registry, sb) {
    sb.AppendLine("struct " unionType.name " {")

    ; Generate DefineProp calls in __New; we can't do this declaratively    
    sb.AppendLine("    static __New() {")
    for field in unionType.fields {
        line := Format("        DefineProp(this.Prototype, `"{1}`", { Type: {2}, Offset: {3} })",
            field.name, field.type.ToSpecifier(), field.offset)
        sb.AppendLine(line)
    }

    sb.AppendLine("    }")
    sb.AppendLine("}")  
}
