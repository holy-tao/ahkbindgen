#Requires AutoHotkey v2.1-alpha.30

/**
 * Emit a function into the given StringBuilder
 * 
 * @param {IR.Function.Function} fnType IR repr of the function to emit
 * @param {String} dll name of the dll this function lives in
 * @param {Map<String, Emittable>} registry type registry
 * @param {StringBuilder} sb the StringBuilder to emit into
 */
export default EmitFunction(fnType, dll, registry, sb) {
    argList := String.Join(", ", fnType.arguments.Map(a => a.name)*)

    sb.AppendLine(Format("export {1}({2}) {", fnType.name, argList))

    dllCallArgs := []
    for arg in fnType.arguments {
        dllCallArgs.Push(arg.type.ToSpecifier(), arg.name)
    }
    
    ; TODO don't return if return type is void
    ; TODO manage anonymous args (e.g. 1st in libclang\clang_getDefinitionSpellingAndExtent)
    ;       in this case it's the `this` arg though

    returnTypeSpec := fnType.returnType.ToSpecifier()
    hasReturn := returnTypeSpec != "void"
    if !hasReturn
        returnTypeSpec := '"void"'

    sb.AppendLine(Format("    {1}DllCall(`"{2}\{3}`", {4}, {5})",
        hasReturn ? "return " : "", dll, fnType.name, String.Join(", ", dllCallArgs*), returnTypeSpec))

    sb.AppendLine("}")
}
