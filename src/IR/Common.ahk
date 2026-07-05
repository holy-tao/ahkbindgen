#Requires AutoHotkey v2.1-alpha.30

/**
 * Record transform for typed arrays - use by binding a Class to the function
 */
export ArrayOf(validator, arr) {
    ; TODO should this copy the input?
    loop arr.Length {
        try {
            ; Pass through elements that already satisfy the validator class
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