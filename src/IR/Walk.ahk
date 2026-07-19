#Requires AutoHotkey v2.1-alpha.30

#Import "Struct" { Struct, Union }
#Import "Function" { Function }
#Import "Type" { EmittableTypedef, PointerType, ArrayType, NamedType, TypedefType }

/**
 * The constituent `Type`s of a top-level declaration - every place a type reference can appear.
 *
 * @param {Emittable} decl a top-level declaration (Struct, Union, Function, EmittableTypedef, Enum)
 * @returns {Array<Type>} the types referenced directly by `decl`
 */
export DeclTypes(decl) {
    types := []
    switch true {
        case decl is Struct, decl is Union:
            for field in decl.fields
                types.Push(field.type)
        case decl is Function:
            types.Push(decl.returnType)
            for arg in decl.arguments
                types.Push(arg.type)
        case decl is EmittableTypedef:
            types.Push(decl.underlying)
    }
    return types
}

/**
 * Walk the reference-bearing nodes of a `Type` tree. Pointer and array wrappers are unwrapped automatically;
 * the two node kinds that carry a cross-declaration reference are handed to callbacks:
 *
 * - `onNamed(named)` for each {@link NamedType}.
 * - `onTypedef(typedef, recurse)` for each {@link TypedefType}. A typedef can be treated either as a reference
 *   in its own right or as a transparent alias, so the callback decides whether to descend: call the supplied
 *   `recurse()` to walk the typedef's underlying type, or don't to stop at the alias.
 *
 * @param {Type} type the root type to walk
 * @param {Func(NamedType) => void} onNamed function to call for each named type
 * @param {Func(TypedefType, () => void) => void} onTypedef function to call for each typedef type
 * @returns {void}
 */
export WalkTypeRefs(type, onNamed, onTypedef) {
    switch true {
        case type is PointerType:
            WalkTypeRefs(type.pointee, onNamed, onTypedef)
        case type is ArrayType:
            WalkTypeRefs(type.elementType, onNamed, onTypedef)
        case type is NamedType:
            onNamed(type)
        case type is TypedefType:
            onTypedef(type, WalkTypeRefs.Bind(type.underlying, onNamed, onTypedef))
    }
}
