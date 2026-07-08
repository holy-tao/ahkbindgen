#Requires AutoHotkey v2.1-alpha.30

#Import "log4ahk\Log" { Log }
#Import "Utils\shell\Cmd" { Cmd }

/**
 * Utils for finding and invoking clang and related binaries
 */

/**
 * Finds and loads `libclang.dll`, or errors out if not succesful. Tries, in order:
 * 1. the `LIBCLANG_PATH` environment variable (which, by convention, is assumed to point at the actual .dll file
 *    and not a directory).
 * 2. `A_ProgramFiles\LLVM\bin\libclang.dll` (the default install path on Windows)
 * 3. If the `VCINSTALLDIR` environment variable is set `%VCINSTALLDIR%\Tools\Llvm\bin\libclang.dll`
 * 4. The current working directory
 * 5. The default dll search path (via `LoadLibraryW`)
 * 
 * If libclang isn't found the program exits with a fatal error.
 */
export LoadLibClang() {
    ; Not worried about the HMODULE, fine to keep the lib loaded the whole time
    TryLoad(path) => DllCall("LoadLibraryW", IntPtr, StrPtr(path), IntPtr)

    probes := [
        A_ProgramFiles "\LLVM\bin\libclang.dll",
        A_WorkingDir
    ]

    if vcInstallDir := EnvGet("VCINSTALLDIR")
        probes.InsertAt(0, vcInstallDir "\Tools\Llvm\bin\libclang.dll")

    if envPath := EnvGet("LIBCLANG_PATH")
        probes.InsertAt(0, envPath)

    ;https://releases.llvm.org/download.html

    for path in probes {
        Log.Trace(Format.Bind("Probing '{1}' for libclang.dll", path))

        if FileExist(path) && TryLoad(path) {
            Log.Debug(Format.Bind("Loaded libclang.dll from '{1}'", path))
            return
        }
    }

    ; last resort, try the standard search path
    if !TryLoad("libclang.dll") {
        Log.Fatal(
            "Failed to load libclang.dll.`nDownload it from https://releases.llvm.org/, or try setting the LIBCLANG_PATH environment variable"
        )
        ExitApp(2)
    }
}

/**
 * Find clang.exe, or error if it can't be found. Tries, in order:
 * 
 * 1. The `CLANG_PATH` environment variable
 * 2. The `PATH` environment variable
 * 3. `A_ProgramFiles\LLVM\bin\clang.exe`
 * 4. The current working directory
 * 
 * @returns {String} the path to clang.exe 
 */
export FindClang() {
    probes := [A_ProgramFiles "\LLVM\bin\clang.exe"]
    probes.Push(StrSplit(EnvGet("PATH"), ";")*)
    probes.Push(A_WorkingDir)

    if envPath := EnvGet("CLANG_PATH")
        probes.InsertAt(0, envPath)

    for path in probes {
        Log.Trace(Format.Bind("Probing '{1}' for clang.exe", path))

        if FileExist(path) {
            Log.Debug(Format("Found clang.exe at '{1}'", path))
            return path
        }
    }

    msg := "Could not find clang.exe at any of the following locations:"
    for path in probes {
        msg .= "  " path "`r`n"
    }

    Log.Fatal(msg)
    ExitApp(2)
}

/**
 * Get the default include paths from clang. Unfortunately there's no way to
 * do this with libclang, so we have to parse clang's output (which is, mercifully,
 * pretty straightforward)
 * 
 * @param {String} clangPath path to clang.exe
 * @returns {Array<String>} array of default include paths 
 */
export GetDefaultIncludePaths(clangPath) {
    ; TODO we can improve performance by working out some actual subprocess plumbing
    (!DirExist(A_Temp "\ahkbindgen\") )&& DirCreate(A_Temp "\ahkbindgen\")
    
    tempFile := A_Temp "\ahkbindgen\" A_ThisFunc "-" A_Now A_MSec ".tmp"
    FileAppend("", tempFile) ; Create the file

    clangCmd := Format("`"{1}`" -E -v -x c NUL", clangPath)
    fullCmd := Format("{1} /c {2} 2>{3}", A_ComSpec, clangCmd, tempFile)
    Log.Debug(fullCmd)

    exitCode := RunWait(fullCmd, , "Hide")
    if exitCode != 0 {
        detail := "no additional details"
        try detail := FileRead(tempFile)
        throw Error("Clang exited with non-zero exit code " exitCode, , detail)
    }

    Log.Trace(FileRead.Bind(tempFile))
    out := FileOpen(tempFile, "r")
    list := []
    inSearchList := false

    loop {
        switch line := out.ReadLine() {
            case "#include `"...`" search starts here:", "#include <...> search starts here:":
                inSearchList := true
                continue
            case "End of search list.":
                break
            default:
                (inSearchList) && list.Push(Trim(line))
        }
    }
    until out.AtEOF

    Log.Debug("Got default search list: " String(list))
    return list
}