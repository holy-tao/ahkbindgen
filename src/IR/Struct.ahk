#Requires AutoHotkey v2.1-alpha.30

#Import "Utils\Record" { Record }
#Import "Type" { Type, IsType }
#Import "Common" { ArrayOf, Emittable }

/**
 * A struct definition
 */
export class Struct extends Emittable {
    /**
     * The struct's fields
     * @type {Array<Field>}
     */
    fields := [ArrayOf.Bind(StructField), []]
}

/**
 * A union
 */
export class Union extends Emittable {
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
     * The field's offset within the larger struct, in bytes. For a bit field this is the byte the field starts
     * in (`bitOffset // 8`).
     * @type {Integer}
     */
    offset := NonNegativeInteger ; Actually comes from the Struct / Record's type information

    /**
     * The field's width in bits if it is a bit field, otherwise -1. A non-negative value marks this field as a
     * bit field, meaning it occupies a sub-byte region and cannot be read as a whole field of its `type`.
     * @type {Integer}
     */
    bitWidth := [Integer, -1]

    /**
     * For a bit field, the field's offset in *bits* from the start of the containing record; -1 for a
     * non-bit-field. `offset` is the byte this falls in (`bitOffset // 8`) and the shift within the field's
     * storage unit is `Mod(bitOffset, 8)`.
     * @type {Integer}
     */
    bitOffset := [Integer, -1]
}

; Private

NonNegativeInteger(i) {
    if (i := Integer(i)) < 0
        throw ValueError("Value cannot be negative", -1, i)
    return i
}