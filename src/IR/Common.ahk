#Requires AutoHotkey v2.1-alpha.30

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