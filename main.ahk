#Requires AutoHotkey v2.1-alpha.30 

#Import "libclang" { CXString }
#Import "log4ahk\Log" { Log }

; Side-effect adds more methods to Array and Map Prototypes
#Import "Extensions\ArrayExtensions"
#Import "Extensions\MapExtensions"

#Import "src\cli.ahk" { ParseArgs }
#Import "src\clang" { LoadLibClang, FindClang, GetDefaultIncludePaths }
#Import "src\extract.ahk" { Extract }
#Import "src\emit.ahk" { Emit }

; 1. Parse args and find libclang
config := ParseArgs(A_Args)

LoadLibClang()
clangPath := FindClang()
includePaths := GetDefaultIncludePaths(clangPath)
includePaths.Push(config.includes*)

Log.Info(DllCall("libclang\clang_getClangVersion", CXString).ToString())

worklist := config.paths.clone()
registry := Map()

while worklist.Length > 0 {
    path := worklist.RemoveAt(1)
    if InStr(FileGetAttrib(path), "D") {
        ; Directory - collect all paths in it
        loop files path "\*.h", "FR" {
            worklist.push(A_LoopFileFullPath)
        }
        continue
    }

    Extract(path, registry, includePaths)
}

emitted := Emit(registry)

for header, code in emitted {
    f := FileOpen(header ".ahk", "w", "UTF-8")
    f.Write(code.ToString())
    f.Close()
}
