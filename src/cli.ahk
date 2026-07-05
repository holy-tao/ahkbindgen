#Requires AutoHotkey v2.1-alpha.30

/**
 * Side-effect module parses arguments and configures logging and other global settings
 * TODO make a nicer CLI with an argument parser, this gives pretty rough error messages
 */

#Import "log4ahk\appenders\FileAppender" { FileAppender, ConsoleAppender }
#Import "log4ahk\Log" { Log, Logger, Level as LogLevel }

Log.Configure(LogLevel.INFO)
globalLogger := Logger()
    .WithAppender(ConsoleAppender().WithPattern("[{Level}] {Message}"))
Log.ToLogger(globalLogger)

; Treat any error that makes it this far as fatal, regardless of whether it's technically
; continuable
OnError((thrown, mode) {
    Log.LogMessage(LogLevel.FATAL, thrown)
    ExitApp(2) 
})

; Specifically for argument parsing, get arr[idx] or die with the given message
Expect(arr, idx, errMessage) => idx > arr.Length ? throw(errMessage) : arr[idx]

/**
 * Parse and validate arguments, configure global settings, returning the filepaths specified
 * by the caller
 * 
 * @param {Array<String>} args argv array to parse - should be A_Args
 * @returns {Array<String>} the filepaths specified by the caller
 */
export ParseArgs(args) {
    i := 0
    paths := []

    while(i < args.Length) {
        switch arg := args[++i] {
            case "--log-level":
                level := Expect(args, ++i, "--log-level requires an argument")
                Log.Configure(LogLevel.Resolve(level))
            case "--log-file":
                path := Expect(args, ++i, "--log-file requires an argument")
                globalLogger.WithAppender(FileAppender(path))
            default:
                ; Assume non-flag options are paths
                if !FileExist(arg) && !DirExist(arg)
                    throw Format("Path '{1}' does not exist", arg)
                paths.Push(arg)
        }
    }

    return paths
}

/**
 * Finds and loads `libclang.dll`, or errors out if not succesful. Tries, in order:
 * 1. the `LIBCLANG_PATH` environment variable (which, by convention, is assumed to point at the actual .dll file
 *    and not a directory).
 * 2. `A_ProgramFiles\LLVM\bin\libclang.dll` (the default install path on Windows)
 * 3. The default dll search path (via `LoadLibraryW`)
 * 
 * If libclang isn't found the program exits with a fatal error.
 */
export LoadLibClang() {
    ; Not worried about the HMODULE, fine to keep the lib loaded the whole time
    TryLoad(path) => DllCall("LoadLibraryW", IntPtr, StrPtr(path), IntPtr)

    probes := [
        A_ProgramFiles "\LLVM\bin\libclang.dll"
    ]

    if envPath := EnvGet("LIBCLANG_PATH")
        probes.InsertAt(0, envPath)

    ;https://releases.llvm.org/download.html

    for path in probes {
        Log.Trace(Format.Bind("Probing '{1}' for libclang.dll", path))

        if FileExist(path) && TryLoad(path){
            Log.Debug(Format.Bind("Loaded libclang.dll from '{1}'", path))
            return
        }
    }

    ; last resort, try the standard search path
    if !TryLoad("libclang.dll") {
        Log.Fatal("Failed to load libclang.dll.`nDownload it from https://releases.llvm.org/, or try setting the LIBCLANG_PATH environment variable")
        ExitApp(2)
    }
}