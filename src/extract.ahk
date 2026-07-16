#Requires AutoHotkey v2.1-alpha.30

#Import "IR\Struct" { Struct, Union, StructField }
#Import "IR\Function" { Function, Argument }
#Import "IR\Enum" { Enum, EnumField }
#Import "IR\Type" {
    EmittableTypedef,
    PrimitiveType,
    PointerType,
    ArrayType,
    OpaqueType,
    NamedType,
    TypedefType,
    VoidType
}
#Import "log4ahk\Log" { Log, Level as LogLevel }
#Import "libclang" {
    CXIndex,
    CXDiagnostic, CXDiagnosticSeverity,
    CXTranslationUnit, TranslationUnitFlags,
    CursorKind, CXChildVisitResult, CXTypeKind
}
#Import "Windows\Win32\UI\Shell\Apis" { PathCchRemoveFileSpec }

/**
 * Extract types and functions from the header file at `filepath` into the IR
 * 
 * @param {String} filepath path to the header file. Assumed to exist
 * @param {Map<String, Type>} registry type registry to extract types into
 * @param {Map<String, String>} preferredNames record/enum USR -> preferred display name, populated as
 *        typedefs that *define* a record/enum are encountered (see {@link ResolvePreferredNames})
 * @param {Array<String>} systemIncludePaths compiler/SDK include paths, treated as system headers
 * @param {Array<String>} userIncludePaths user-supplied (`-I`) include paths, treated as user headers
 * @returns {Map<String, Record>} map of USR -> extracted declarations
 */
export Extract(filepath, registry, preferredNames, systemIncludePaths, userIncludePaths) {
    Log.Info("Parsing header " filepath)

    idx := CXIndex.Create()

    clangArgs := ["-std=c11"]
    ; Compiler/SDK paths come in as *system* dirs (-isystem, not -I) so headers found under them are flagged as
    ; system headers.
    for path in systemIncludePaths {
        clangArgs.Push("-isystem", path)
    }

    ; User-supplied includes stay plain -I (non-system), so their alias types keep their names, same as the
    ; library's own headers reached via `parentInclude` below.
    for path in userIncludePaths {
        clangArgs.Push("-I", path)
    }

    ; If the given path is in an include directory, automatically include it
    if parentInclude := FindIncludeAncestor(filepath) {
        clangArgs.Push("-I", parentInclude)
    }

    flags := TranslationUnitFlags.SkipFunctionBodies | TranslationUnitFlags.DetailedPreprocessingRecord
    tu := idx.ParseTranslationUnit(filepath, clangArgs, flags)

    ProcessDiagnostics(tu)

    ; Keyed by USR so that `NamedType` references (and anonymous records) resolve unambiguously in a later pass.
    tu.cursor.Visit(Visit.Bind(registry, preferredNames))
}

/**
 * Visitor for the tree walk - collects types we care about into the types map
 * @param {Map<String, Record>} registry USR -> extracted declaration
 * @param {Map<String, String>} preferredNames record/enum USR -> preferred display name
 * @param {CXCursor} cursor
 * @param {CXCursor} parent
 * @returns {CXChildVisitResult}
 */
Visit(registry, preferredNames, cursor, parent) {
    if !cursor.location.IsFromMainFile || registry.Has(cursor.USR)
        return CXChildVisitResult.Continue
    
    try {
        switch cursor.kind {
            case CursorKind.FunctionDecl:
                ExtractFunction(registry, cursor)
            case CursorKind.StructDecl:
                ExtractStruct(registry, cursor)
            case CursorKind.UnionDecl:
                ExtractUnion(registry, cursor)
            case CursorKind.EnumDecl:
                ExtractEnum(registry, cursor)
            case CursorKind.TypedefDecl:
                ExtractTypedef(registry, preferredNames, cursor)
            default:
                Log.Trace(Format("Unhanlded cursor kind '{1}' ({2}): {3} ",
                    cursor.KindSpelling, cursor.kind, cursor.DisplayName))
        }
    }
    catch Error as err {
        try {
            loc := cursor.location.FileLocation()
            err.Message .= Format("`nWhile extracting {1} '{2}' from '{3}:{4}:{5}'",
                cursor.KindSpelling, cursor.spelling, loc.file.Name, loc.line, loc.column)
        }
        throw err
    }

    return CXChildVisitResult.Continue
}

/**
 * Extract a type definition into the registry
 * 
 * @param {Map<String, Type>} registry type registry, keyed by USR
 * @param {CXCursor} cursor Cursor, type assumed to be TypedefDecl
 * @returns {void} 
 */
ExtractTypedef(registry, preferredNames, cursor) {
    canon := cursor.UnderlyingType.Canonical

    ; A typedef whose canonical type is a record or enum is that declaration's public name - we don't emit a
    ; separate wrapper (the record/enum is extracted on its own). When the record/enum is *defined by* this
    ; typedef (e.g. `typedef struct tagRECT { ... } RECT;`) the tag ("tagRECT") is throwaway and callers use
    ; the typedef name ("RECT"), so we record it as the preferred name.
    if canon.kind == CXTypeKind.Record || canon.kind == CXTypeKind.Enum {
        decl := canon.Declaration
        if IsDefinedByTypedef(cursor, decl) && !preferredNames.Has(decl.USR)
            preferredNames[decl.USR] := cursor.Spelling
        return
    }

    extracted := EmittableTypedef({
        usr: cursor.USR,
        sourceFile: cursor.location.FileLocation().file.name,
        name: cursor.Spelling,
        underlying: ExtractType(cursor.UnderlyingType) 
    })

    Log.Debug("Extracted " String(extracted))
    registry[extracted.usr] := extracted
}

/**
 * Whether `recordDecl` is defined *inside* the given typedef declaration - i.e. the typedef introduces the
 * record/enum, as in `typedef struct tagRECT { ... } RECT;`, rather than aliasing one declared elsewhere. Decided
 * by checking whether the record's declaration location falls within the typedef's source extent.
 *
 * @param {CXCursor} typedefCursor a TypedefDecl cursor
 * @param {CXCursor} recordDecl the struct/union/enum declaration the typedef canonicalizes to
 * @returns {Integer} 1 if the record is defined by the typedef, else 0
 */
IsDefinedByTypedef(typedefCursor, recordDecl) {
    extent := typedefCursor.Extent
    start := extent.Start.FileLocation()
    end := extent.End.FileLocation()
    rec := recordDecl.Location.FileLocation()

    ; `offset` is a character offset within its file; compare file identity too so offsets from different files
    ; in the same translation unit can't spuriously overlap.
    return rec.file.ptr == start.file.ptr && rec.offset >= start.offset && rec.offset < end.offset
}

/**
 * Second pass over the registry: rename each record/enum that a typedef defined under a nicer name to that name,
 * and rewrite every `NamedType` reference to it so declarations and their uses stay consistent. Extraction runs
 * this once, after all headers are parsed, so it is order-independent (a reference can be extracted before the
 * typedef that renames its target). See {@link IsDefinedByTypedef}.
 *
 * @param {Map<String, Record>} registry the type registry, keyed by USR
 * @param {Map<String, String>} preferredNames record/enum USR -> preferred display name
 * @returns {void}
 */
export ResolvePreferredNames(registry, preferredNames) {
    if !preferredNames.Count
        return

    for usr, decl in registry {
        if (decl is Struct || decl is Union || decl is Enum) && preferredNames.Has(decl.usr)
            decl.name := preferredNames[decl.usr]

        for type in _DeclTypes(decl)
            _RenameTypeRefs(type, preferredNames)
    }
}

/**
 * The constituent `Type`s of a declaration - the places a `NamedType` reference can appear.
 * @param {Record} decl a top-level declaration
 * @returns {Array<Type>}
 */
_DeclTypes(decl) {
    types := []
    switch true {
        case decl is Struct, decl is Union:
            for field in decl.fields
                types.Push(field.type)
        case decl is Function:
            types.Push(decl.returnType)
            for arg in decl.arguments
                types.Push(arg.type)
        case decl is EmittableTypedef:
            types.Push(decl.underlying)
    }
    return types
}

/**
 * Rewrite any `NamedType` reference within `type` (through pointer/array/typedef wrappers) whose USR has a
 * preferred name, so uses match the renamed declaration.
 * @param {Type} type the type to rewrite in place
 * @param {Map<String, String>} preferredNames record/enum USR -> preferred display name
 * @returns {void}
 */
_RenameTypeRefs(type, preferredNames) {
    switch true {
        case type is PointerType:
            _RenameTypeRefs(type.pointee, preferredNames)
        case type is ArrayType:
            _RenameTypeRefs(type.elementType, preferredNames)
        case type is TypedefType:
            _RenameTypeRefs(type.underlying, preferredNames)
        case type is NamedType:
            if preferredNames.Has(type.usr)
                type.name := preferredNames[type.usr]
    }
}

/**
 * Extract a function type into the registry.
 * 
 * @param {Map<String, Type>} registry type registry, keyed by USR
 * @param {CXCursor} cursor Cursor, type assumed to be FunctionDecl
 * @returns {void} 
 */
ExtractFunction(registry, cursor) {
    extracted := Function({
        usr: cursor.USR,
        sourceFile: cursor.location.FileLocation().file.name,
        name: cursor.Spelling,
        returnType: ExtractType(cursor.ResultType),
        arguments: _ExtractArguments(cursor)
    })

    Log.Debug("Extracted " String(extracted))
    registry[extracted.usr] := extracted
}

/**
 * Extract and return an array of function arguments, given a cursor to the function
 * 
 * @param {CXCursor} cursor Cursor, type assumed to be FunctionDecl
 * @returns {Array<Argument>} the arguments
 */
_ExtractArguments(cursor) {
    args := []
    loop cursor.NumArguments {
        arg := cursor.Argument(A_Index - 1)
        extracted := Argument({
            name: arg.Spelling,
            type: ExtractType(arg.Type)
        })
        args.Push(extracted)
    }

    return args
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
        sourceFile: cursor.location.FileLocation().file.name,
        name: cursor.Spelling,
        fields: cursor.Children()
            .Filter((c) => c.kind == CursorKind.FieldDecl)
            ; Anonymous bit-fields are unnamed padding and OffsetOf cannot resolve them. Drop them
            ; so that lookups for the actual named fields can resolve
            .Filter((c) => !(c.Spelling == "" && c.BitWidth >= 0))
            .Map(_ExtractField.Bind(cursorType))
    })

    Log.Debug("Extracted " String(extracted))
    registry[extracted.usr] := extracted
}

/**
 * Extract a single struct/union field
 *
 * @param {CXType} recordType the containing record's type, used to query field offsets
 * @param {CXCursor} cursor a FieldDecl cursor
 * @returns {StructField} the extracted field
 */
_ExtractField(recordType, cursor) {
    ; libclang reports field offsets in bits; for a non-bit-field this is always a whole number of bytes.
    bits := recordType.OffsetOf(cursor.Spelling)
    if bits < 0
        throw ValueError(Format("libclang could not compute the offset of field '{1}' (layout error {2})",
            cursor.Spelling, bits), -1, bits)

    bitWidth := cursor.BitWidth   ; -1 when this field is not a bit field
    return StructField({
        name: cursor.Spelling,
        type: ExtractType(cursor.Type),
        offset: bits // 8,
        bitWidth: bitWidth,
        bitOffset: bitWidth >= 0 ? bits : -1
    })
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
        sourceFile: cursor.location.FileLocation().file.name,
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
            usr:        decl.USR,
            name:       decl.Spelling,
            underlying: ExtractType(decl.UnderlyingType),
            isSystem:   type.Declaration.Location.IsInSystemHeader
        })
    }

    c := type.Canonical
    meta := {
        spelling:  type.Spelling,
        canonical: c.Spelling,
        size:      c.SizeOf,
        alignment: c.AlignOf,
        isSystem:  type.Declaration.Location.IsInSystemHeader
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

        case CXTypeKind.Void:
            return VoidType(meta)

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

/**
 * If `path` is inside an `include` folder, returns the full path to that folder,
 * otherwise an empty string
 * 
 * @param {String} path path to check 
 * @returns {String} include path, or "" if not in one 
 */
FindIncludeAncestor(path) {
    #DllLoad api-ms-win-core-path-l1-1-0.dll

    static S_OK := 0
    loop {
        prevLen := StrLen(path)
        if PathCchRemoveFileSpec(StrPtr(path), StrLen(path) + 1) != S_OK
            break
        VarSetStrCapacity(&path, -1)

        if path.EndsWith("include")
            return path

        ; Root paths (e.g. "C:\") are returned unaltered with S_OK; we must break manually
        if StrLen(path) == prevLen
            break
    }

    return ""
}
