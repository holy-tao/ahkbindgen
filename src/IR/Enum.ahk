#Requires AutoHotkey v2.1-alpha.30+

#Import "Utils\Record" { Record }
#Import "Type" { PrimitiveType }
#Import "Common" { ArrayOf, Emittable }

/**
 * An enum
 */
export class Enum extends Emittable {
    /**
     * The enum's underlying type
     * @type {PrimitiveType}
     */
    underlying := PrimitiveType

    /**
     * The enum's fields
     * @type {Array<EnumField>}
     */
    fields := [ArrayOf.Bind(EnumField), []]
}

/**
 * An individual enum field - a name assosciated with an integer value.
 */
class EnumField extends Record {
    /**
     * The name of the enum field
     * @type {String}
     */
    name := String

    /**
     * The enum field's value
     * @type {Integer}
     */
    value := Integer
}