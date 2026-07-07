#Requires AutoHotkey v2.1-alpha.30 

#Import "Utils\Record" { Record }
#Import "IR\Common" { ArrayOf }

/** 
 * Record transform that asserts that `path` is a path to a real file or directory
 * and returns its full path name
 * 
 * @returns {String} `path`, canonicalized
 */
AbsoluteExtantPath(path) {
    chars := DllCall("GetFullPathNameW", IntPtr, StrPtr(path),
        Int32, 0, IntPtr, 0, IntPtr, 0, Int32)

    strBuf := Buffer(chars * 2, 0)
    DllCall("GetFullPathNameW",
        IntPtr, StrPtr(path),
        Int32, chars,
        IntPtr, strBuf.ptr,
        IntPtr, 0,
        Int32
    ) || throw(OSError())
    
    fullPath := StrGet(strBuf, "UTF-16")
    if !FileExist(fullPath) && !DirExist(fullPath)
        throw ValueError("No such file or directory: " fullPath)

    return fullPath
}

/**
 * Configuration for the program
 */
export class Config extends Record {

    /**
     * The name of the dll that the functions come from.
     * TODO: stop assuming that they're all in the same .dll file
     * @type {String}
     */
    dll := String

    /**
     * The paths, which may be either paths to files or directories (but which must exist),
     * supplied at the command line.
     * @type {Array<String>}
     */
    paths := ArrayOf.Bind(AbsoluteExtantPath)
}
