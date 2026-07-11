#Requires AutoHotkey v2.1-alpha.30 

#Import "Utils\Record" { Record }
#Import "IR\Common" { ArrayOf }
#Import "Windows\Win32\Storage\FileSystem\Apis" { GetFullPathNameW }

/**
 * Converts `path` into an absolute path
 * 
 * @param {String} path a path 
 * @returns {String} `path` absolute
 */
AbsolutePath(path) {
    chars := GetFullPathNameW(path, 0, 0, 0)
    strBuf := Buffer(chars * 2, 0)
    GetFullPathNameW(path, chars, strBuf.ptr, 0)
    
    return StrGet(strBuf, "UTF-16")
}

/** 
 * Record transform that asserts that `path` is a path to a real file or directory
 * and returns its full path name
 * 
 * @returns {String} `path`, canonicalized
 */
AbsoluteExtantPath(path) {
    fullPath := AbsolutePath(path)
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

    /**
     * List of user-supplied include paths, *appended* (same as clang) to the default
     * include path
     * @type {Array<String>}
     */
    includes := ArrayOf.Bind(AbsoluteExtantPath)

    /**
     * Path to the output directory for generated files
     * @type {String}
     */
    output := AbsolutePath
}
