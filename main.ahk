
#Import "libclang" { CXString }
#Import "log4ahk\Log" { Log }

; Side-effect adds more methods to Array.Prototype
#Import "Extensions\ArrayExtensions"

#Import "src\cli.ahk" { ParseArgs, LoadLibClang }
#Import "src\extract.ahk" { Extract }

; 1. Parse args and find libclang
paths := ParseArgs(A_Args)
LoadLibClang()
Log.Info(DllCall("libclang\clang_getClangVersion", CXString).ToString())

for path in paths {
    isDirectory := inStr(FileGetAttrib(path), "D")
    Extract(path)
}