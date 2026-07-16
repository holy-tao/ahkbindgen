#Requires AutoHotkey v2.1-alpha.30

#Import "../src/extract" { ExtractType, ExtractStruct, ExtractUnion, ExtractEnum }
#Import "../src/IR" as IR

#Import "YUnit\Yunit" { Yunit }
#Import "YUnit\Assert" { Assert }

#Import "libclang" { CXIndex, CXType, CXTypeKind, CursorKind, TranslationUnitFlags }
#Import "Extensions\ArrayExtensions"

/**
 * Helper function parses a string and returns the cursor. Keep symmetric with what extract.ahk does
 * so tests remain meaningful
 * 
 * @param {String} code code to parse
 * @param {String} testFunction the unit test method - pass A_ThisFunc
 * @param {Integer} expectError if true, do not fail if libclang reports errors
 * @returns {CXTranslationUnit} the resulting parsed translation unit 
 */
_Parse(code, testFunction, expectError := false) {
    idx := CXIndex.Create()
    ; FIXME don't hardcode include paths
    includePath := "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Tools\MSVC\14.50.35717\include"

    flags := TranslationUnitFlags.SkipFunctionBodies | TranslationUnitFlags.DetailedPreprocessingRecord
    try {
        filepath := A_Temp "\" testFunction ".h"
        ; Overwrite rather than append so prior runs can't corrupt the temp file
        FileOpen(filepath, "w", "UTF-8").Write(code)
        tu := idx.ParseTranslationUnit(filepath, ["-std=c11", "-I", includePath], flags)

        if tu.HasErrors && !expectError {
            msg := "Test code parsed with error(s):`n"
            loop tu.NumDiagnostics {
                msg .= tu.Diagnostic(A_Index - 1).Format() "`n"
            }
            throw Error(msg)
        }

        return tu
    }
    finally {
        FileDelete(filepath)
    }
}

/**
 * Extract a scalar from a typedef and verify the underlying type. Typedefs are the simplest way to test
 * type extraction in isolation I think
 * 
 * @param {String} testName 
 * @param {String} code 
 * @param {IR.PrimitiveType} expected expected shape of the extracted type 
 */
_AssertTypedefExtraction(testName, code, expected) {
    tu := _Parse(code, testName)
    typedef := tu.Cursor.Children()
        .Single((c) => c.kind == CursorKind.TypedefDecl)
        .UnderlyingType

    Assert.IsType(typedef, CXType) ; in case something goes terribly wrong

    extracted := ExtractType(typedef)

    Assert.IsType(extracted, IR.Type.Type)
    YUnit.Assert(extracted.Equals(expected), Format("Expected {1} to equal {2}",
        String(extracted), String(expected)))
}

_AssertEnumExtraction(testName, code, expected) {
    tu := _Parse(code, testName)
    cursor := tu.Cursor.Children()
        .Single((c) => c.kind == CursorKind.EnumDecl)

    ExtractEnum(registry := Map(), cursor)
    extracted := registry[cursor.USR]

    ; Required but not generally known ahead of time, don't need to assert on it
    expected := expected.With({usr: extracted.usr})

    Assert.IsType(extracted, IR.Enum.Enum)
    YUnit.Assert(extracted.Equals(expected), Format("Expected {1} to equal {2}",
        String(extracted), String(expected)))
}

/**
 * Extract a struct declaration and verify its fields, types, and offsets.
 *
 * @param {String} testName the unit test method - pass A_ThisFunc
 * @param {String} code code to parse
 * @param {IR.Struct.Struct} expected expected shape of the extracted struct
 * @param {String | unset} structName spelling of the struct to assert on, if `code` declares several
 */
_AssertStructExtraction(testName, code, expected, structName?) {
    tu := _Parse(code, testName)
    cursor := tu.Cursor.Children()
        .Filter((c) => c.kind == CursorKind.StructDecl)
        .Single((c) => !IsSet(structName) || c.Spelling == structName)

    ExtractStruct(registry := Map(), cursor)
    extracted := registry[cursor.USR]

    ; Required but not generally known ahead of time, don't need to assert on it
    expected := expected.With({usr: extracted.usr})

    Assert.IsType(extracted, IR.Struct.Struct)
    YUnit.Assert(extracted.Equals(expected), Format("Expected {1} to equal {2}",
        String(extracted), String(expected)))
}

/**
 * Extract a union declaration and verify its fields, types, and offsets.
 *
 * @param {String} testName the unit test method - pass A_ThisFunc
 * @param {String} code code to parse
 * @param {IR.Struct.Union} expected expected shape of the extracted struct
 * @param {String | unset} structName spelling of the struct to assert on, if `code` declares several
 */
_AssertUnionExtraction(testName, code, expected, structName?) {
    tu := _Parse(code, testName)
    cursor := tu.Cursor.Children()
        .Filter((c) => c.kind == CursorKind.UnionDecl)
        .Single((c) => !IsSet(structName) || c.Spelling == structName)

    ExtractUnion(registry := Map(), cursor)
    extracted := registry[cursor.USR]

    ; Required but not generally known ahead of time, don't need to assert on it
    expected := expected.With({usr: extracted.usr})

    Assert.IsType(extracted, IR.Struct.Union)
    YUnit.Assert(extracted.Equals(expected), Format("Expected {1} to equal {2}",
        String(extracted), String(expected)))
}

; Builders for the primitive IR types that recur across struct field assertions. Kept as functions (rather
; than shared instances) so each assertion gets a fresh value and nothing can mutate a shared expectation.
_Int() => IR.PrimitiveType({ alignment: 4, canonical: "int", size: 4, specifier: "Int32", spelling: "int", isSystem: false })
_Short() => IR.PrimitiveType({ alignment: 2, canonical: "short", size: 2, specifier: "Int16", spelling: "short", isSystem: false })
_Char() => IR.PrimitiveType({ alignment: 1, canonical: "char", size: 1, specifier: "Int8", spelling: "char", isSystem: false })
_UInt() => IR.PrimitiveType({ alignment: 4, canonical: "unsigned int", size: 4, specifier: "UInt32", spelling: "unsigned int", isSystem: false })

class ExtractTests {
    class Types {
        SignedScalars_AreExtractedCorrectly() => _AssertTypedefExtraction(
            A_ThisFunc,
            "typedef long test_t;", 
            IR.PrimitiveType({
                alignment: 4,
                canonical: "long",
                size: 4,
                specifier: "Int32",
                spelling: "long",
                isSystem: false
            }))

        UnsignedScalars_AreExtractedCorrectly() => _AssertTypedefExtraction(
            A_ThisFunc,
            "typedef unsigned long test_t;", 
            IR.PrimitiveType({
                alignment: 4,
                canonical: "unsigned long",
                size: 4,
                specifier: "UInt32",
                spelling: "unsigned long",
                isSystem: false
            }))

        UnrepresentableTypes_AreExtractedAsOpaqueBlobs() => _AssertTypedefExtraction(
            A_ThisFunc,
            "typedef __int128 test_t;",
            IR.OpaqueType({
                alignment: 16,
                canonical: "__int128",
                size: 16,
                spelling: "__int128",
                isSystem: false
            })
        )

        PointerTypes_AreExtractedCorrectly() => _AssertTypedefExtraction(
            A_ThisFunc,
            "typedef char* test_t;",
            IR.PointerType({
                spelling: "char *",
                canonical: "char *",
                size: 8,
                alignment: 8,
                pointee: _Char(),
                isSystem: false
            })
        )
    }

    class Structs {
        Structs_WithScalarFields_AreExtractedCorrectly() {
            code := "
            (
                struct Point {
                    int x;
                    int y;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Point",
                fields: [
                    IR.Struct.StructField({ name: "x", type: _Int(), offset: 0 }),
                    IR.Struct.StructField({ name: "y", type: _Int(), offset: 4 }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        ; Mixed field widths force the compiler to insert padding; the extracted offsets should reflect
        ; the real (aligned) layout, not a naive running sum of field sizes.
        Structs_ComputeFieldOffsets_AccountingForPadding() {
            code := "
            (
                struct Padded {
                    char  a;
                    int   b;
                    char  c;
                    short d;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Padded",
                fields: [
                    IR.Struct.StructField({ name: "a", type: _Char(),  offset: 0 }),
                    IR.Struct.StructField({ name: "b", type: _Int(),   offset: 4 }),
                    IR.Struct.StructField({ name: "c", type: _Char(),  offset: 8 }),
                    IR.Struct.StructField({ name: "d", type: _Short(), offset: 10 }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        Structs_WithPointerFields_AreExtractedCorrectly() {
            code := "
            (
                struct Buffer {
                    int   len;
                    char *data;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Buffer",
                fields: [
                    IR.Struct.StructField({ name: "len", type: _Int(), offset: 0 }),
                    IR.Struct.StructField({
                        name: "data",
                        offset: 8,
                        type: IR.PointerType({
                            spelling: "char *",
                            canonical: "char *",
                            size: 8,
                            alignment: 8,
                            pointee: _Char(),
                            isSystem: false
                        })
                    }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        Structs_WithArrayFields_AreExtractedCorrectly() {
            code := "
            (
                struct Vec3 {
                    float coords[3];
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Vec3",
                fields: [
                    IR.Struct.StructField({
                        name: "coords",
                        offset: 0,
                        type: IR.ArrayType({
                            spelling: "float[3]",
                            canonical: "float[3]",
                            size: 12,
                            alignment: 4,
                            length: 3,
                            isSystem: false,
                            elementType: IR.PrimitiveType({
                                alignment: 4,
                                canonical: "float",
                                size: 4,
                                specifier: "Float32",
                                spelling: "float",
                                isSystem: false
                            })
                        })
                    }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        ; A field whose type is another record should extract as a NamedType reference (by USR), not
        ; recurse into the referenced struct's fields - that's a later resolution pass's job.
        Structs_WithNestedStructFields_ReferenceByName() {
            code := "
            (
                struct Inner {
                    int value;
                };
                struct Outer {
                    struct Inner inner;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Outer",
                fields: [
                    IR.Struct.StructField({
                        name: "inner",
                        offset: 0,
                        type: IR.NamedType({
                            spelling: "struct Inner",
                            canonical: "struct Inner",
                            size: 4,
                            alignment: 4,
                            usr: "c:@S@Inner",
                            name: "Inner",
                            isSystem: false
                        })
                    }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected, "Outer")
        }

        ; Bit fields carry their width and bit offset so an emitter can mask/shift; the byte `offset` is the byte
        ; the field starts in. All three named fields (and the anonymous padding) share one `unsigned` storage unit.
        Structs_WithBitFields_CaptureWidthAndBitOffset() {
            code := "
            (
                struct Bits {
                    unsigned a : 1;
                    unsigned b : 2;
                    unsigned   : 5;
                    unsigned c : 1;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Bits",
                fields: [
                    IR.Struct.StructField({ name: "a", type: _UInt(), offset: 0, bitWidth: 1, bitOffset: 0 }),
                    IR.Struct.StructField({ name: "b", type: _UInt(), offset: 0, bitWidth: 2, bitOffset: 1 }),
                    ; the anonymous 5-bit padding (bits 3-7) is dropped, so c lands at bit 8 (byte 1)
                    IR.Struct.StructField({ name: "c", type: _UInt(), offset: 1, bitWidth: 1, bitOffset: 8 }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        ; A regular field must not be misreported as a bit field: bitWidth/bitOffset stay at their -1 sentinel.
        Structs_NonBitFields_HaveNoBitWidth() {
            code := "
            (
                struct Plain {
                    int x;
                };
            )"

            expected := IR.Struct.Struct({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Plain",
                fields: [
                    IR.Struct.StructField({ name: "x", type: _Int(), offset: 0, bitWidth: -1, bitOffset: -1 }),
                ]
            })

            _AssertStructExtraction(A_ThisFunc, code, expected)
        }

        ; Unions use the exact same machinery as structs, so no need to stress test them
        ; specifically
        Unions_AreExtracted() {
            code := "
            (
                typedef union IntOrDouble {
                    long long intVal;
                    double doubleVal;
                } IntOrDouble;
            )"

            expected := IR.Struct.Union({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "IntOrDouble",
                fields: [
                    IR.Struct.StructField({
                        name: "intVal",
                        offset: 0,
                        type: IR.PrimitiveType({
                            alignment: 8,
                            canonical: "long long",
                            size: 8,
                            specifier: "Int64",
                            spelling: "long long",
                            isSystem: false
                        })
                    }),
                    IR.Struct.StructField({
                        name: "doubleVal",
                        offset: 0,
                        type: IR.PrimitiveType({
                            alignment: 8,
                            canonical: "double",
                            size: 8,
                            specifier: "Float64",
                            spelling: "double",
                            isSystem: false
                        })
                    })
                ]
            })

            _AssertUnionExtraction(A_ThisFunc, code, expected)
        }
    }

    class Enums {
        Enums_AreExtractedCorrectly() {
            code := "
            (
                typedef enum {
                    Pass,
                    Fail
                } Result;
            )"

            expected := IR.Enum.Enum({
                usr: "unknown",
                sourceFile: A_Temp "\" A_ThisFunc ".h",
                name: "Result",
                underlying: IR.PrimitiveType({
                    alignment: 4,
                    canonical: "int",
                    size: 4,
                    specifier: "Int32",
                    spelling: "int",
                    isSystem: false
                }),
                fields: [
                    IR.Enum.EnumField({ name: "Pass", value: 0 }),
                    IR.Enum.EnumField({ name: "Fail", value: 1 }),
                ]
            })

            _AssertEnumExtraction(A_ThisFunc, code, expected)
        }
    }
}