#Requires AutoHotkey v2.1-alpha.30

/**
 * Side-effect module parses arguments and configures logging and other global settings
 * TODO make a nicer CLI with an argument parser, this gives pretty rough error messages
 */

#Import "log4ahk\appenders\FileAppender" { FileAppender, ConsoleAppender }
#Import "log4ahk\Log" { Log, Logger, Level as LogLevel }
#Import "Config" { Config }

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
Expect(arr, idx, argName) => idx > arr.Length ? throw(argName " requires an argument") : arr[idx]

/**
 * Parse and validate arguments, configure global settings, returning the filepaths specified
 * by the caller
 * 
 * @param {Array<String>} args argv array to parse - should be A_Args
 * @returns {Config} the filepaths specified by the caller
 */
export ParseArgs(args) {
    i := 0
    paths := []
    dll := ""
    includes := []
    output := A_WorkingDir

    while(i < args.Length) {
        switch arg := args[++i] {
            case "--log-level":
                level := Expect(args, ++i, arg)
                Log.Configure(LogLevel.Resolve(level))
            case "--log-file":
                path := Expect(args, ++i, arg)
                globalLogger.WithAppender(FileAppender(path))
            case "--dll":
                dll := Expect(args, ++i, arg)
            case "-I", "--include":
                includes.Push(Expect(args, ++i, arg))
            case "-o", "--output":
                output := Expect(args, ++i, arg)
            default:
                ; Assume non-flag options are paths
                if !FileExist(arg) && !DirExist(arg)
                    throw Format("Path '{1}' does not exist", arg)
                paths.Push(arg)
        }
    }

    ; TODO read this from config file
    (dll) || throw(Error("--dll is required"))

    return Config({
        dll: dll,
        paths: paths,
        includes: includes,
        output: output
    })
}