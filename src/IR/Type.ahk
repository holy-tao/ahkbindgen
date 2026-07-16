#Requires AutoHotkey v2.1-alpha.30

#Import "Utils\Record" { Record }
#Import "Common" { Emittable }

/**
 * Transform for a field that holds any {@link Type} (polymorphically). Unlike using `Type` directly as a Record
 * transform - which would copy-construct the value into a *base* `Type` and drop any subclass fields (a
 * `PointerType`'s `pointee`, etc.) - this passes a `Type` instance through unchanged.
 * @param {Any} v the value to validate
 * @returns {Type} `v`, if it is a `Type`
 */
export IsType(v) {
    if v is Type
        return v
    throw TypeError("Expected a Type, got a(n) " Type(v), -1, v)
}

/**
 * Record transform that coerces any value to the literal integer 1 or 0
 * @param {Any} v value to coerce 
 * @returns {Integer} 1 or 0 
 */
export Boolean(v) {
    return !!v
}

/**
 * A top-level typedef that will be emitted during codegen.
 */
export class EmittableTypedef extends Emittable {
    /**
     * The type of the emittble
     * @type {Type}
     */
    underlying := IsType
}

/**
 * Base class for all type definitions.
 */
export class Type extends Record {
    /**
     * Pretty-printed type, e.g. "const char *".
     * @type {String}
     */
    spelling := String

    /**
     * The type with all sugar (e.g. typedefs) removed. For example, the canonical type of
     * `size_t` is typically `unsigned long long`.
     * @type {String}
     */
    canonical := String

    /**
     * The size of the type in bytes as would be reported by `sizeof`. Negative values indicate errors
     * @type {Integer}
     */
    size := Integer

    /**
     * The alignment of the type in bytes. Negative values indicate errors
     * @type {Integer}
     */
    alignment := Integer

    /**
     * Whether this type comes from a system header or not.
     * @type {Integer}
     */
    isSystem := Boolean

    /**
     * The AHK v2.1 type specifier that represents this type in a struct definition, e.g. "Int32", "RECT.Ptr",
     * "UInt8[64]", or a bare byte count for an opaque blob. Concrete subclasses override this.
     * @returns {String}
     */
    ToSpecifier() => Type.ThrowAbstract("ToSpecifier")

    static ThrowAbstract(member) {
        throw MethodError(Format("``{1}`` is abstract on ``Type``; use a concrete subclass", member), -2, member)
    }
}

/**
 * A primitive that maps directly onto one of AHK v2.1's numeric struct classes.
 */
export class PrimitiveType extends Type {
    /**
     * The AHK v2.1 type specifier to use for this in struct definitions and DllCalls: `IntPtr`, `UInt32`, etc.
     * @type {String}
     */
    specifier := String

    ToSpecifier() => this.specifier
}

/**
 * A type with no AHK-representable value, preserved only as a fixed-size run of bytes so the surrounding struct's
 * layout stays correct. No accessor is generated for it. Emitted as a bare integer (its size in bytes).
 */
export class OpaqueType extends Type {
    ToSpecifier() => String(this.size)
}

/**
 * Void - not representable, and we must never try to read it
 */
export class VoidType extends Type {
    ToSpecifier() => "void"
}

/**
 * A pointer to another type. Emitted as `<pointee>.Ptr`.
 */
export class PointerType extends Type {
    /**
     * The pointer's pointee
     * @type {Type}
     */
    pointee := IsType

    ToSpecifier() => this.pointee is PointerType 
        ? "IntPtr.Ptr"  ; Can't do double-indirection like this, pointer must be opaque
        : this.pointee.ToSpecifier() ".Ptr"
}

/**
 * An array of potentially unknown size. Emitted as `<element>[N]`.
 */
export class ArrayType extends Type {
    /**
     * The type of the array's elements
     * @type {Type}
     */
    elementType := IsType

    /**
     * The number of elements in the array if the array is constant, otherwise -1 (an incomplete / flexible array
     * member). Note this overrides `size`, so an `ArrayType`'s `size` is an element *count*, not a byte size.
     * @type {Integer}
     */
    length := [Integer, -1]

    ToSpecifier() => this.elementType.ToSpecifier() (this.length >= 0 ? "[" this.length "]" : "[]")
}

/**
 * A reference to a named declaration (struct, union, enum) identified by its USR.
 */
export class NamedType extends Type {
    /**
     * The declaration's Unified Symbol Resolution, stable and non-empty even for anonymous records.
     * @type {String}
     */
    usr := String

    /**
     * The declaration's source name (may be empty for anonymous records; a name is synthesized at emit time).
     * @type {String}
     */
    name := String

    ToSpecifier() => this.name
}

/**
 * A typedef. Preserves the alias `name` (so codegen can emit e.g. `HWND` rather than the underlying `IntPtr`)
 * alongside the type it aliases. `underlying` is resolved one typedef link at a time.
 */
export class TypedefType extends Type {
    /**
     * The declaration's Unified Symbol Resolution, stable and non-empty even for anonymous records.
     * @type {String}
     */
    usr := String

    /**
     * The typedef's name, e.g. "DWORD", "LPRECT".
     * @type {String}
     */
    name := String

    /**
     * The aliased type (one level down; itself possibly another {@link TypedefType}).
     * @type {Type}
     */
    underlying := IsType

    ; System-header typedefs (time_t, size_t, ...) resolve to their underlying primitive; typedefs from the
    ; library being generated keep their alias name so users can hang methods off them.
    ToSpecifier() => this.isSystem ? this.underlying.ToSpecifier() : this.name
}
