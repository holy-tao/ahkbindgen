
#Import "libclang" { CXString }
#Import "log4ahk\Log" { Log }
#Import "utils\StringBuilder" { StringBuilder }

; Side-effect adds more methods to Array and Map Prototypes
#Import "Extensions\ArrayExtensions"
#Import "Extensions\MapExtensions"

#Import "src\cli.ahk" { ParseArgs, LoadLibClang }
#Import "src\extract.ahk" { Extract }
#Import "src\emit.ahk" { Emit }

; 1. Parse args and find libclang
paths := ParseArgs(A_Args)
LoadLibClang()
Log.Info(DllCall("libclang\clang_getClangVersion", CXString).ToString())

for path in paths {
    isDirectory := inStr(FileGetAttrib(path), "D")
    Extract(path, registry := Map())
}

emitted := Emit(registry)

for header, code in emitted {
    f := FileOpen(header ".ahk", "w", "UTF-8")
    f.Write(code.ToString())
    f.Close()
}