#Requires AutoHotkey v2.1-alpha.30

#Import "Utils\Record" { Record }
#Import "Type" { Type, IsType }
#Import "Common" { ArrayOf }

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
    fields := [ArrayOf.Bind(StructField), []]
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
    fields := [ArrayOf.Bind(StructField), []]
}

/**
 * A struct or union field (c++ classes are not supported)
 */
export class StructField extends Record {
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

NonNegativeInteger(i) {
    if (i := Integer(i)) < 0
        throw ValueError("Value cannot be negative", -1, i)
    return i
}