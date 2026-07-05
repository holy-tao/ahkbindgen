#Requires AutoHotkey v2.1-alpha.30

#Import "Utils\Record" { Record }
#Import "Type" { Type, IsType }

/**
 * A struct definition
 */
export class Struct extends Record {
    /**
     * The declaration's USR - a stable identity key, used to resolve `NamedType` references to this struct.
     * @type {String}
     */
    usr := String

    /**
     * The name of the struct (may be empty for an anonymous struct; synthesized at emit time)
     * @type {String}
     */
    name := String

    /**
     * The struct's fields
     * @type {Array<Field>}
     */
    fields := [ArrayOf.Bind(Field), []]
}

/**
 * A union
 */
export class Union extends Record {
    /**
     * The declaration's USR - a stable identity key, used to resolve `NamedType` references to this union.
     * @type {String}
     */
    usr := String

    /**
     * The name of the union (may be empty for an anonymous union; synthesized at emit time)
     * @type {String}
     */
    name := String

    /**
     * The union's fields
     * @type {Array<Field>}
     */
    fields := [ArrayOf.Bind(Field), []]
}

/**
 * A struct or union field (c++ classes are not supported)
 */
export class Field extends Record {
    /**
     * The field's type
     * @type {Type}
     */
    type := IsType

    /**
     * The name of the field
     * @type {String}
     */
    name := String

    /**
     * The field's offset within the larger struct
     * @type {Integer}
     */
    offset := NonNegativeInteger ; Actually comes from the Struct / Record's type information
}

; Private

ArrayOf(validator, arr) {
    ; TODO should this copy the input?
    loop arr.Length {
        try {
            ; Pass through elements that already satisfy the validator class - Record's copy-construct is unreliable,
            ; and re-validating an already-built element (e.g. a Field) would otherwise trip it.
            item := arr[A_Index]
            arr[A_Index] := (validator is Class && item is validator) ? item : validator(item)
        }
        catch Error as err {
            ; Attach context
            err.Message .= "`nCaught by ArrayOf at index " A_Index
            throw err
        }
    }

    return arr
}

NonNegativeInteger(i) {
    if (i := Integer(i)) < 0
        throw ValueError("Value cannot be negative", -1, i)
    return i
}