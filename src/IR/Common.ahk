#Requires AutoHotkey v2.1-alpha.30

#Import "..\config" { AbsoluteExtantPath, AbsolutePath }
#Import "Utils\Record" { Record }

/**
 * Record transform for typed arrays - use by binding a Class to the function
 */
export ArrayOf(validator, arr) {
    ; TODO should this copy the input?
    loop arr.Length {
        ; Pass through elements that already satisfy the validator class
        item := arr[A_Index]
        arr[A_Index] := (validator is Class && item is validator) ? item : validator(item)
    }

    return arr
}

/**
 * Base class for anything that we're going to emit as AHK code.
 */
export class Emittable extends Record {
    /**
     * The declaration's ***U***nified ***S***ymbol ***R***esolution. This is a stable identity key,
     * used to resolve `NamedType` references to this declaration.
     * @type {String}
     */
    usr := String

    /**
     * The declaration's name
     * @type {String}
     */
    name := String

    /**
     * The absolute path to the file that this declaration comes from
     * @type {String}
     */
    sourceFile := AbsolutePath
}