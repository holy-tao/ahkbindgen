#Requires AutoHotkey v2.1-alpha.30+

#Import "Type" { IsType }
#Import "Utils\Record" { Record }
#Import "Common" { ArrayOf, Emittable }

/**
 * A function declaration
 */
export class Function extends Emittable {
    /**
     * The function's non-variadic arguments
     * @type {Array<Argument>}
     */
    arguments := ArrayOf.Bind(Argument)

    /**
     * The function's return type
     * @type {Type}
     */
    returnType := IsType
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