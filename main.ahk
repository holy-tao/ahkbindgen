#Requires AutoHotkey v2.1-alpha.30 

#Import "libclang" { CXString }
#Import "log4ahk\Log" { Log }

; Side-effect adds more methods to Array and Map Prototypes
#Import "Extensions\ArrayExtensions"
#Import "Extensions\MapExtensions"
#Import "Extensions\StringExtensions"

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
Log.Debug("Include path(s): " String(includePaths))

worklist := config.paths.clone()
registry := Map()

; 2. Extract types
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

;3. Render types into strings in memory
emitted := Emit(registry, config.dll)

; 4. Write types out to files on disk (parallelized)
if !DirExist(config.output)
    DirCreate(config.output)

emitted.ForEach((h, c) => SetTimer(EmitOne.Bind(h, c), -1))

EmitOne(header, code) {
    try {
        f := FileOpen(config.output "\" header ".ahk", "w", "UTF-8")
        f.Write(code.ToString())
        f.Close()
    }
    catch Error as err {
        err.Message .= "`nEmitting ahk code for header " header
        Log.Error(err)
    }
}