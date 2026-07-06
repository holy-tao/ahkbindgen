#Requires AutoHotkey v2.1-alpha.30

#Import "IR\Struct" { Struct, Union, StructField }
#Import "IR\Enum" { Enum, EnumField }
#Import "IR\Type" { Type, PrimitiveType, PointerType, ArrayType, OpaqueType, NamedType, TypedefType }
#Import "log4ahk\Log" { Log, Level as LogLevel }
#Import "libclang" {
    CXIndex,
    CXDiagnostic, CXDiagnosticSeverity,
    CXTranslationUnit, TranslationUnitFlags,
    CursorKind, CXChildVisitResult, CXTypeKind
}
/**
 * Extract types and functions from the header file at `filepath` into the IR
 * 
 * @param {String} filepath path to the header file. Assumed to exist 
 * @returns {unset?} 
 */
export Extract(filepath) {
    Log.Info("Parsing header " filepath)

    idx := CXIndex.Create()
    ; FIXME don't hardcode include paths - either search or take cli args (or both)
    includePath := "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\include"

    flags := TranslationUnitFlags.SkipFunctionBodies | TranslationUnitFlags.DetailedPreprocessingRecord
    tu := idx.ParseTranslationUnit(filepath, ["-std=c11", "-I", includePath], flags)

    ProcessDiagnostics(tu)

    ; Keyed by USR so that `NamedType` references (and anonymous records) resolve unambiguously in a later pass.
    registry := Map()
    tu.cursor.Visit(Visit.Bind(registry))
}

/**
 * Visitor for the tree walk - collects types we care about into the types map
 * @param {Map<String, Type>} registry USR -> extracted declaration
 * @param {CXCursor} cursor
 * @param {CXCursor} parent
 * @returns {CXChildVisitResult}
 */
Visit(registry, cursor, parent) {
    ; TODO check source file and excluded libraries
    switch cursor.kind {
        case CursorKind.StructDecl:
            ExtractStruct(registry, cursor)
        case CursorKind.UnionDecl:
            ExtractUnion(registry, cursor)
        case CursorKind.EnumDecl:
            ExtractEnum(registry, cursor)
        default:
            Log.Trace(Format("Unhanlded cursor kind '{1}' ({2}): {3} ",
                cursor.KindSpelling, cursor.kind, cursor.DisplayName))
    }

    return CXChildVisitResult.Continue
}

/**
 * Extract a struct type into the registry
 *
 * @param {Map<String, Type>} registry type registry, keyed by USR
 * @param {CXCursor} cursor Cursor, type assumed to be StructDecl
 * @returns {void} nothing
 */
ExtractStruct(registry, cursor) => _ExtractRecordType(Struct, registry, cursor)

/**
 * Extract a union into the registry
 * 
 * @param {Map<String, Type>} registry type registry, keyed by USR
 * @param {CXCursor} cursor Cursor, type assumed to be UnionDecl
 * @returns {void} nothing 
 */
ExtractUnion(registry, cursor) => _ExtractRecordType(Union, registry, cursor)

/**
 * Internal function to extract either a union or a struct - their shapes are identical,
 * just the types differ
 */
_ExtractRecordType(recordType, registry, cursor) {
    cursorType := cursor.Type   ; Save some DllCalls
    extracted := recordType.Call({
        usr: cursor.USR,
        name: cursor.Spelling,
        fields: cursor.Children()
            .Filter((c) => c.kind == CursorKind.FieldDecl)
            .Map((c) => StructField({
                name: c.Spelling,
                type: ExtractType(c.Type),
                ; libclang reports field offsets in bits
                offset: (bits := cursorType.OffsetOf(c.Spelling)) >= 0 ? bits // 8 : bits
            }))
    })

    Log.Debug("Extracted " String(extracted))
    registry[extracted.usr] := extracted
}

/**
 * Extract an enum into the registry
 * 
 * @param {Map<String, Type>} registry type registry, keyed by USR
 * @param {CXCursor} cursor Cursor, type assumed to be EnumDecl
 * @returns {void} nothing 
 */
ExtractEnum(registry, cursor) {
    extracted := Enum({
        usr: cursor.USR,
        name: cursor.Spelling,
        underlying: ExtractType(cursor.EnumIntegerType),
        fields: cursor.Children()
            .Filter((c) => c.kind == CursorKind.EnumConstantDecl)
            .Map((c) => EnumField({
                name: c.Spelling,
                value: c.EnumConstantValue
            }))
    })

    Log.Debug("Extracted " String(extracted))
    registry[extracted.usr] := extracted
}

/**
 * Extract a value type into an IR `Type`. Canonicalizes first so typedef/elaborated/attributed sugar collapses,
 * then maps the underlying kind onto an AHK v2.1 type. Types with no representable value but a known size become an
 * {@link OpaqueType} (a byte blob preserving layout); genuinely un-layoutable types (unsized / C++-only) throw.
 *
 * @param {CXType} type the type to extract
 * @returns {Type} the extracted IR type
 */
ExtractType(type) {
    ; Preserve typedef identity before canonicalization strips it away, recursing one alias link at a time.
    if type.kind == CXTypeKind.Typedef {
        decl := type.Declaration
        return TypedefType({
            spelling:   type.Spelling,
            canonical:  type.Canonical.Spelling,
            size:       type.SizeOf,
            alignment:  type.AlignOf,
            name:       decl.Spelling,
            underlying: ExtractType(decl.UnderlyingType)
        })
    }

    c := type.Canonical
    meta := {
        spelling:  type.Spelling,
        canonical: c.Spelling,
        size:      c.SizeOf,
        alignment: c.AlignOf
    }

    switch c.kind {
        ; pointers
        case CXTypeKind.Pointer, CXTypeKind.BlockPointer:
            pointee := c.Pointee
            ; void* and function pointers have no meaningful pointee, treat as a raw pointer sized int
            if pointee.kind == CXTypeKind.Void || pointee.kind == CXTypeKind.FunctionProto || pointee.kind == CXTypeKind.FunctionNoProto
                return Primitive(meta, "IntPtr")
            meta.pointee := ExtractType(pointee)
            return PointerType(meta)

        ; aggregates: reference by identity, do NOT recurse into fields (a later pass resolves it)
        case CXTypeKind.Record:
            decl := c.Declaration
            meta.usr := decl.USR
            meta.name := decl.Spelling
            return NamedType(meta)

        case CXTypeKind.ConstantArray:
            meta.elementType := ExtractType(c.ElementType)
            meta.length := c.ArraySize
            return ArrayType(meta)
        case CXTypeKind.IncompleteArray:
            meta.elementType := ExtractType(c.ElementType)
            meta.length := -1
            return ArrayType(meta)

        ; an enum stores as its underlying integer typ
        case CXTypeKind.Enum:
            intType := c.Declaration.EnumIntegerType
            return Primitive(meta, IntSpecifier(IsUnsignedIntKind(intType.kind), intType.SizeOf))

        ; scalar: kind + size gets width
        ; TODO accept compiler (MSVC, gcc) as arg and adjust this accordingly? Is that even possible using libclang?
        case CXTypeKind.Bool:
            return Primitive(meta, "UInt8")
        case CXTypeKind.Float, CXTypeKind.Double, CXTypeKind.LongDouble:
            return Primitive(meta, c.SizeOf == 4 ? "Float32" : "Float64")
        case CXTypeKind.UChar, CXTypeKind.Char_U, CXTypeKind.UShort, CXTypeKind.UInt,
             CXTypeKind.ULong, CXTypeKind.ULongLong, CXTypeKind.Char16, CXTypeKind.Char32, CXTypeKind.WChar:
            return Primitive(meta, IntSpecifier(true, c.SizeOf))
        case CXTypeKind.SChar, CXTypeKind.Char_S, CXTypeKind.Short, CXTypeKind.Int,
             CXTypeKind.Long, CXTypeKind.LongLong:
            return Primitive(meta, IntSpecifier(false, c.SizeOf))

        ; everything else: C++ refs/member ptrs, __int128, _Complex, __m128, _Float16, unexposed, etc
        default:
            if c.SizeOf > 0 {
                Log.Warn(Format("Type '{1}' ({2}) is not representable in AHK; emitting a {3}-byte opaque blob",
                    type.Spelling, c.KindSpelling, c.SizeOf))
                return OpaqueType(meta)
            }
            ; The type is unrepresentible even as an opaque blob (VLA, incomplete, dependent, invalid). At this point
            ; we give up
            throw ValueError("Cannot lay out type '" type.Spelling "' (" c.KindSpelling ", size " c.SizeOf ")", -1)
    }
}

/**
 * Build a {@link PrimitiveType} from the shared `meta` plus an AHK v2.1 numeric class name.
 */
Primitive(meta, specifier) {
    meta.specifier := specifier
    return PrimitiveType(meta)
}

/**
 * The AHK v2.1 numeric class name for an integer of `bytes` width. AHK has no unsigned 64-bit type, so an 8-byte
 * unsigned integer maps to signed `Int64` (two's-complement makes this safe for storage/DllCall).
 */
IntSpecifier(unsigned, bytes) {
    switch bytes {
        case 1: return unsigned ? "UInt8"  : "Int8"
        case 2: return unsigned ? "UInt16" : "Int16"
        case 4: return unsigned ? "UInt32" : "Int32"
        case 8: return "Int64"
        default: throw ValueError("No AHK integer class for a " bytes "-byte integer", -1, bytes)
    }
}

/**
 * Whether a builtin integer `CXTypeKind` is unsigned. Used to classify an enum's underlying integer type.
 */
IsUnsignedIntKind(kind) {
    switch kind {
        case CXTypeKind.Bool, CXTypeKind.UChar, CXTypeKind.Char_U, CXTypeKind.UShort,
             CXTypeKind.UInt, CXTypeKind.ULong, CXTypeKind.ULongLong,
             CXTypeKind.Char16, CXTypeKind.Char32, CXTypeKind.WChar:
            return true
        default:
            return false
    }
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