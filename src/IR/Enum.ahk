#Requires AutoHotkey v2.1-alpha.30+

#Import "Utils\Record" { Record }
#Import "Type" { PrimitiveType }
#Import "Common" { ArrayOf }

/**
 * An enum
 */
export class Enum extends Record {
    /**
     * The declaration's USR - a stable identity key, used to resolve `NamedType` references to this struct.
     * @type {String}
     */
    usr := String

    /**
     * The enum's name
     * @type {String}
     */
    name := String

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

    /**
     * The file that this declaration comes from
     * @type {String}
     */
    sourceFile := String
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