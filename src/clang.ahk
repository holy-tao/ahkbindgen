#Requires AutoHotkey v2.1-alpha.30

#Import "log4ahk\Log" { Log }
#Import "Utils\shell\Cmd" { Cmd, CmdExpect }

/**
 * Utils for finding and invoking clang and its related items. Also resolving include paths now.
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
 * Find default include paths from:
 * - The Windows SDK (typically required, the C stdlib comes from here)
 * - Clang's default
 * - MSVC's include path
 * 
 * @param {String} clangPath path to clang.exe 
 * @returns {Array<String>} the standard include paths we could find 
 */
export GetDefaultIncludePaths(clangPath) {
    paths := []
    paths.Push(GetClangDefaultIncludePaths(clangPath)*)
    paths.Push(GetWindowsSDKCStdLibPaths()*)
    paths.Push(GetMSVCIncludePath())
    return paths
}

/**
 * Try to find the default Windows SDK and C Stdlib include directories. This searches
 * the typical install locations that the Visual Studio Installer uses.
 * 
 * @returns {Array<String>} Windows SDK and C stdlib paths found (might be empty)
 */
GetWindowsSDKCStdLibPaths() {
    WindowsKitsRoot := RegRead("HKLM\SOFTWARE\Microsoft\Windows Kits\Installed Roots", "KitsRoot10", "")
    if !WindowsKitsRoot
        goto NoSdk

    ; Find the most recent Windows SDK available
    ; TODO maybe allow specifying a version? This is probably good enough for 99% of cases
    sdkPath := "", newestVersion := "0.0.0.0"
    loop files WindowsKitsRoot "Include\*", "D" {
        if VerCompare(A_LoopFileName, newestVersion) >= 0 {
            newestVersion := A_LoopFileName
            sdkPath := A_LoopFileFullPath
        }
    }

    if !sdkPath
        goto NoSdk

    return [
        sdkPath "\ucrt",
        sdkPath "\shared",
        sdkPath "\um",
        sdkPath "\winrt",
    ].Filter(DirExist)

NoSdk:
    msg := Format("
    (
        No Windows Kits were found under '{1}'.
        The C standard library and windows APIs may not be available to clang.
        Consider installing using the Visual Studio Installer: https://visualstudio.microsoft.com/downloads/
    )", WindowsKitsRoot)
    Log.Warn(msg)
    return []
}

/**
 * Get the default include paths from clang. Unfortunately there's no way to
 * do this with libclang, so we have to parse clang's output (which is, mercifully,
 * pretty straightforward)
 * 
 * @param {String} clangPath path to clang.exe
 * @returns {Array<String>} array of default include paths 
 */
GetClangDefaultIncludePaths(clangPath) {
    ; TODO we can improve performance by working out some actual subprocess plumbing
    (!DirExist(A_Temp "\ahkbindgen\") )&& DirCreate(A_Temp "\ahkbindgen\")
    
    tempFile := A_Temp "\ahkbindgen\" A_ThisFunc "-" A_Now A_MSec ".tmp"
    FileAppend("", tempFile) ; Create the file

    clangCmd := Format("`"{1}`" -E -v -x c NUL", clangPath)
    Log.Debug(clangCmd)

    exitCode := Cmd(clangCmd, , &out)
    if exitCode != 0 {
        throw Error("Clang exited with non-zero exit code " exitCode)
    }

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

    Log.Trace("Got default search list from clang: " String(list))
    return list
}

/**
 * Find the MSVC include path using vswhere. This will use the latest installed MSVC.
 * 
 * @returns {String} the MSVC include path
 */
GetMSVCIncludePath() {
    ; MSVC component for VSWHERE
    static MSVC := "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
    static VSWHERE := "`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe`""

    command := VSWHERE " -latest -products `"*`" -requires " MSVC " -property installationPath"

    installPath := CmdExpect(command)
    toolsVersion := FileRead(installPath "\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt")

    return installPath "\VC\Tools\MSVC\" toolsVersion "\include"
}