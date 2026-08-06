# Primitive UID types with different bit sizes.
# The name suffix is the size in bytes: UID2 = 2 bytes = 16 bits, ..., UID64 = 64 bytes = 512 bits.
primitive type UID2 <: Integer 16 end
primitive type UID4 <: Integer 32 end
primitive type UID8 <: Integer 64 end
primitive type UID16 <: Integer 128 end
primitive type UID24 <: Integer 192 end
primitive type UID32 <: Integer 256 end
primitive type UID64 <: Integer 512 end

"""
    UID2, UID4, UID8, UID16, UID24, UID32, UID64

Primitive identifier types of 16, 32, 64, 128, 192, 256, and 512 bits respectively
(the name suffix is the size in bytes). Calling a type with no arguments produces a
random identifier, e.g. `UID8()`. Use [`string`](@ref Base.string) to render one as a
Base58 string and [`parse`](@ref Base.parse) to read it back.
"""
UID2, UID4, UID8, UID16, UID24, UID32, UID64

# Constructor functions for each primitive type: random identifiers
UID2() = reinterpret(UID2, rand(UInt16))
UID4() = reinterpret(UID4, rand(UInt32))
UID8() = reinterpret(UID8, rand(UInt64))
UID16() = reinterpret(UID16, rand(UInt128))
UID24() = reinterpret(UID24, (rand(UInt64), rand(UInt64), rand(UInt64)))
UID32() = reinterpret(UID32, (rand(UInt128), rand(UInt128)))
UID64() = reinterpret(UID64, (rand(UInt128), rand(UInt128), rand(UInt128), rand(UInt128)))

# Convert from integers
UID2(x::UInt16) = reinterpret(UID2, x)
UID4(x::UInt32) = reinterpret(UID4, x)
UID8(x::UInt64) = reinterpret(UID8, x)
UID16(x::UInt128) = reinterpret(UID16, x)
# NTuple{3, UInt64} is the reinterpret carrier for UID24: Tuple{UInt128, UInt64} has
# 8 bytes of alignment padding (sizeof 32 != 24), so it cannot represent the raw bits.
function UID24(x::Tuple{UInt128, UInt64})
    lo, hi = x
    return reinterpret(UID24, (UInt64(lo & typemax(UInt64)), UInt64(lo >> 64), hi))
end
UID32(x::Tuple{UInt128, UInt128}) = reinterpret(UID32, x)
UID64(x::Tuple{UInt128, UInt128, UInt128, UInt128}) = reinterpret(UID64, x)

# Convert to integers
Base.UInt16(x::UID2) = reinterpret(UInt16, x)
Base.UInt32(x::UID4) = reinterpret(UInt32, x)
Base.UInt64(x::UID8) = reinterpret(UInt64, x)
Base.UInt128(x::UID16) = reinterpret(UInt128, x)

# Convert to tuples for larger types (words ordered least-significant first)
function Base.Tuple(x::UID24)
    nt = reinterpret(NTuple{3, UInt64}, x)
    return (UInt128(nt[1]) | (UInt128(nt[2]) << 64), nt[3])
end
Base.Tuple(x::UID32) = reinterpret(Tuple{UInt128, UInt128}, x)
Base.Tuple(x::UID64) = reinterpret(Tuple{UInt128, UInt128, UInt128, UInt128}, x)

# Widen single-word UIDs to UInt128 for encoding/decoding
Base.UInt128(x::UID2) = UInt128(UInt16(x))
Base.UInt128(x::UID4) = UInt128(UInt32(x))
Base.UInt128(x::UID8) = UInt128(UInt64(x))

# Hashing: hash the full underlying bits (multi-word types hash their word tuple)
Base.hash(x::UID2, h::UInt) = hash(UInt16(x), h)
Base.hash(x::UID4, h::UInt) = hash(UInt32(x), h)
Base.hash(x::UID8, h::UInt) = hash(UInt64(x), h)
Base.hash(x::UID16, h::UInt) = hash(UInt128(x), h)
Base.hash(x::UID24, h::UInt) = hash(Tuple(x), h)
Base.hash(x::UID32, h::UInt) = hash(Tuple(x), h)
Base.hash(x::UID64, h::UInt) = hash(Tuple(x), h)

"""
    string(x::UID2)  ->  String

Render a primitive UID as a Base58 string encoding exactly `bitsize(typeof(x)) ÷ 8`
bytes. The inverse operation is `parse(typeof(x), str)`.
"""
function Base.string(x::UID2)
    bytes = reinterpret(UInt8, [UInt16(x)])
    return Base58.encode(bytes)
end

function Base.string(x::UID4)
    bytes = reinterpret(UInt8, [UInt32(x)])
    return Base58.encode(bytes)
end

function Base.string(x::UID8)
    bytes = reinterpret(UInt8, [UInt64(x)])
    return Base58.encode(bytes)
end

function Base.string(x::UID16)
    bytes = reinterpret(UInt8, [UInt128(x)])
    return Base58.encode(bytes)
end

function Base.string(x::UID24)
    t = Tuple(x)
    # exactly 24 bytes: 16 for the low word, 8 for the high word (no padding)
    bytes = vcat(reinterpret(UInt8, [t[1]]), reinterpret(UInt8, [t[2]]))
    return Base58.encode(bytes)
end

function Base.string(x::UID32)
    t = Tuple(x)
    bytes = reinterpret(UInt8, [t[1], t[2]])
    return Base58.encode(bytes)
end

function Base.string(x::UID64)
    t = Tuple(x)
    bytes = reinterpret(UInt8, [t[1], t[2], t[3], t[4]])
    return Base58.encode(bytes)
end

"""
    parse(::Type{U}, s::AbstractString)  ->  U

Parse a Base58 string produced by `string(::U)` back into the primitive UID type `U`
(one of `UID2`, `UID4`, `UID8`, `UID16`, `UID24`, `UID32`, `UID64`). Throws an
`ArgumentError` if `s` contains invalid Base58 characters or decodes to the wrong
number of bytes.
"""
function _uid_parse_bytes(::Type{U}, s::AbstractString) where {U}
    bytes = Base58.decode(s)
    nbytes = bitsize(U) ÷ 8
    if length(bytes) != nbytes
        throw(ArgumentError("Base58 string \"$s\" decodes to $(length(bytes)) bytes, expected $nbytes for $U"))
    end
    return bytes
end

Base.parse(::Type{UID2}, s::AbstractString) = UID2(reinterpret(UInt16, _uid_parse_bytes(UID2, s))[1])
Base.parse(::Type{UID4}, s::AbstractString) = UID4(reinterpret(UInt32, _uid_parse_bytes(UID4, s))[1])
Base.parse(::Type{UID8}, s::AbstractString) = UID8(reinterpret(UInt64, _uid_parse_bytes(UID8, s))[1])
Base.parse(::Type{UID16}, s::AbstractString) = UID16(reinterpret(UInt128, _uid_parse_bytes(UID16, s))[1])

function Base.parse(::Type{UID24}, s::AbstractString)
    bytes = _uid_parse_bytes(UID24, s)
    lo = reinterpret(UInt128, bytes[1:16])[1]
    hi = reinterpret(UInt64, bytes[17:24])[1]
    return UID24((lo, hi))
end

function Base.parse(::Type{UID32}, s::AbstractString)
    bytes = _uid_parse_bytes(UID32, s)
    words = reinterpret(UInt128, bytes)
    return UID32((words[1], words[2]))
end

function Base.parse(::Type{UID64}, s::AbstractString)
    bytes = _uid_parse_bytes(UID64, s)
    words = reinterpret(UInt128, bytes)
    return UID64((words[1], words[2], words[3], words[4]))
end

# Show methods
Base.show(io::IO, x::UID2) = print(io, "UID2\"$(string(x))\"")
Base.show(io::IO, x::UID4) = print(io, "UID4\"$(string(x))\"")
Base.show(io::IO, x::UID8) = print(io, "UID8\"$(string(x))\"")
Base.show(io::IO, x::UID16) = print(io, "UID16\"$(string(x))\"")
Base.show(io::IO, x::UID24) = print(io, "UID24\"$(string(x))\"")
Base.show(io::IO, x::UID32) = print(io, "UID32\"$(string(x))\"")
Base.show(io::IO, x::UID64) = print(io, "UID64\"$(string(x))\"")

"""
    bitsize(U)  ->  Int

Return the bit width of a primitive UID type: `bitsize(UID2) == 16` up through
`bitsize(UID64) == 512`.
"""
bitsize(::Type{UID2}) = 16
bitsize(::Type{UID4}) = 32
bitsize(::Type{UID8}) = 64
bitsize(::Type{UID16}) = 128
bitsize(::Type{UID24}) = 192
bitsize(::Type{UID32}) = 256
bitsize(::Type{UID64}) = 512
