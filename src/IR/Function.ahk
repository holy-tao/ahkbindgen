#Requires AutoHotkey v2.1-alpha.30+

#Import "Type" { IsType }
#Import "Utils\Record" { Record }
#Import "Common" { ArrayOf }

/**
 * A function declaration
 */
export class Function extends Record {
    /**
     * Stable identifier for the function type
     * @type {String}
     */
    usr := String

    /**
     * The function's name
     * @type {String}
     */
    name := String

    /**
     * The function's non-variadic arguments
     * @type {Array<Argument>}
     */
    arguments := ArrayOf.Bind(Argument)

    /**
     * The function's return type
     * @type {Type}
     */
    returnType := Type

    /**
     * The file that this declaration comes from
     * @type {String}
     */
    sourceFile := String
}

export class Argument extends Record {
    /**
     * The name of the argument
     * @type {String}
     */
    name := String

    /**
     * The type of the argument
     * @type {Type}
     */
    type := IsType
}