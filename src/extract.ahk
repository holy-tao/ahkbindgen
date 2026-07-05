#Requires AutoHotkey v2.1-alpha.30

#Import "IR" { Type, Struct }
#Import "log4ahk\Log" { Log, Level as LogLevel }
#Import "libclang" {
    CXIndex,
    CXDiagnostic, CXDiagnosticSeverity,
    CXTranslationUnit, TranslationUnitFlags,
    CXType,
    CXTypeKind,
}
/**
 * Extract types and functions from the header file at `filepath` into the IR
 * 
 * @param {String} filepath path to the header file. Assumed to exist 
 * @returns {unset?} 
 */
export Extract(filepath) {
    types := Map()

    Log.Info("Parsing header " filepath)

    idx := CXIndex.Create()
    ; FIXME don't hardcode include paths - either search or take cli args (or both)
    includePath := "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\include"

    flags := TranslationUnitFlags.SkipFunctionBodies | TranslationUnitFlags.DetailedPreprocessingRecord
    tu := idx.ParseTranslationUnit(filepath, ["-std=c11", "-I", includePath], flags)

    ProcessDiagnostics(tu)
}

/**
 * Log the translation unit's diagnostics and die if there are any errors
 * @param {CXTranslationUnit} tu translation unit
 */
ProcessDiagnostics(tu) {
    loop tu.NumDiagnostics {
        diag := tu.Diagnostic(A_Index - 1)

        switch diag.severity {
            case CXDiagnosticSeverity.Fatal: level := LogLevel.FATAL
            case CXDiagnosticSeverity.Error: level := LogLevel.ERROR
            case CXDiagnosticSeverity.Warning: level := LogLevel.WARN
            case CXDiagnosticSeverity.Note: level := LogLevel.DEBUG
            case CXDiagnosticSeverity.Ignored: level := LogLevel.TRACE
            default:
                level := LogLevel.WARN
        }

        Log.LogMessage(level, diag.Format())
    }

    if tu.HasErrors {
        Log.Fatal("Libclang encountered error(s). Review the output above")
        ExitApp(2)
    }
}