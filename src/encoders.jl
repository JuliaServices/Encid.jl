# Encoders for different data types
# These functions encode values into the first N bits of a UID

# Mask with the low `bits` bits set (bits must be in 1:128)
_low_mask(bits::Int) = bits >= 128 ? typemax(UInt128) : (UInt128(1) << bits) - UInt128(1)

"""
    StringN{N}(s::String)

Fixed-size string wrapper enforcing that `s` occupies exactly `N` bytes (codeunits).
Used by [`UID`](@ref) to record a string's byte length in the type domain so it can be
decoded later. Multi-byte UTF-8 strings are supported; `N` counts bytes, not characters.
"""
struct StringN{N} <: AbstractString
    value::String
    function StringN{N}(s::String) where {N}
        if ncodeunits(s) != N
            throw(ArgumentError("StringN{$N} must have $N bytes (codeunits), got $(ncodeunits(s))"))
        end
        new{N}(s)
    end
end

Base.String(s::StringN) = s.value
Base.show(io::IO, s::StringN{N}) where {N} = print(io, "StringN{$N}(", repr(s.value), ")")

# AbstractString interface: delegate to the wrapped String
Base.ncodeunits(s::StringN) = ncodeunits(s.value)
Base.codeunit(s::StringN) = codeunit(s.value)
Base.codeunit(s::StringN, i::Integer) = codeunit(s.value, i)
Base.isvalid(s::StringN, i::Integer) = isvalid(s.value, i)
Base.iterate(s::StringN) = iterate(s.value)
Base.iterate(s::StringN, state::Integer) = iterate(s.value, state)
Base.length(s::StringN) = length(s.value)

# Equality
Base.:(==)(a::StringN{N}, b::StringN{N}) where {N} = a.value == b.value
Base.:(==)(a::StringN, b::String) = a.value == b

"""
    SymbolN{N}(s::Symbol)

Fixed-size symbol wrapper enforcing that `s`'s name occupies exactly `N` bytes
(codeunits). Used by [`UID`](@ref) to record a symbol's byte length in the type domain
so it can be decoded later.
"""
struct SymbolN{N}
    value::Symbol
    function SymbolN{N}(s::Symbol) where {N}
        nb = ncodeunits(String(s))
        if nb != N
            throw(ArgumentError("SymbolN{$N} must have $N bytes (codeunits), got $nb"))
        end
        new{N}(s)
    end
end

Base.Symbol(s::SymbolN) = s.value
Base.String(s::SymbolN) = String(s.value)
Base.show(io::IO, s::SymbolN{N}) where {N} = print(io, "SymbolN{$N}(:$(s.value))")

# Iteration support for SymbolN
Base.iterate(s::SymbolN) = iterate(String(s))
Base.iterate(s::SymbolN, state::Integer) = iterate(String(s), state)

# Equality (symmetric; StringN gets its Symbol-free analog via generic AbstractString ==)
Base.:(==)(a::SymbolN{N}, b::SymbolN{N}) where {N} = a.value == b.value
Base.:(==)(a::SymbolN, b::Symbol) = a.value == b
Base.:(==)(a::Symbol, b::SymbolN) = b == a

"""
    bits_required(x)  ->  Int
    bits_required(T::Type)  ->  Int

Number of bits needed to encode a value or a type.

The type form is what [`UID`](@ref) uses to lay out its arguments: full type width for
integers, floats, chars, and enums; `N * 8` for `StringN{N}` and `SymbolN{N}`; 128 for
plain `String`/`Symbol` (up to 16 bytes, NUL-padded).

The value form is an exact measurement for a specific value: the position of the
highest set bit for non-negative integers (`bits_required(0) == 1`), the full type
width for negative integers, and the type width for other supported values.
"""
function bits_required(x::Integer)
    if x < 0
        return 8 * sizeof(typeof(x))  # full width, two's complement
    elseif x == 0
        return 1
    else
        return ndigits(x, base = 2)
    end
end

function bits_required(::Type{T}) where {T<:Integer}
    return 8 * sizeof(T)
end

bits_required(x::AbstractFloat) = bits_required(typeof(x))

function bits_required(::Type{T}) where {T<:Base.IEEEFloat}
    return 8 * sizeof(T)
end

function bits_required(x::Symbol)
    return ncodeunits(String(x)) * 8
end

function bits_required(::Type{Symbol})
    return 128  # plain Symbol type: up to 16 bytes, NUL-padded
end

function bits_required(x::AbstractString)
    return ncodeunits(x) * 8
end

function bits_required(::Type{String})
    return 128  # plain String type: up to 16 bytes, NUL-padded
end

bits_required(x::Char) = 32
bits_required(::Type{Char}) = 32

"""
    encode_value(x, bits::Int)  ->  UInt128

Encode `x` into the low `bits` bits of a `UInt128`. Supported types: integers up to
128 bits (two's complement for negatives), IEEE floats (`bits` must equal the float's
width), `Char` (32 bits), `String`/`Symbol` (one byte per codeunit, low byte first),
and [`StringN`](@ref)/[`SymbolN`](@ref) (exactly `N * 8` bits). Values that cannot be
represented in `bits` bits throw an `ArgumentError`.

The inverse operation is [`decode_value`](@ref).
"""
function encode_value(x::Integer, bits::Int)
    if bits < 1 || bits > 128
        throw(ArgumentError("Cannot encode $bits bits into UInt128"))
    end

    mask = _low_mask(bits)
    if x >= 0
        if bits < 128 && !(UInt128(x) <= mask)
            throw(ArgumentError("Value $x too large for $bits bits"))
        end
    else
        # smallest representable two's-complement value in `bits` bits is -2^(bits-1)
        if bits < 128 && !(Int128(x) >= -(Int128(1) << (bits - 1)))
            throw(ArgumentError("Value $x too small for $bits bits"))
        end
    end
    # `% UInt128` sign-extends negative values (two's complement), zero-extends otherwise
    return (x % UInt128) & mask
end

# Unsigned reinterpret carriers for IEEE floats
_float_uint(::Type{Float16}) = UInt16
_float_uint(::Type{Float32}) = UInt32
_float_uint(::Type{Float64}) = UInt64

function encode_value(x::T, bits::Int) where {T<:Base.IEEEFloat}
    nbits = 8 * sizeof(T)
    if bits != nbits
        throw(ArgumentError("$T is encoded as $nbits bits, got $bits"))
    end
    return UInt128(reinterpret(_float_uint(T), x))
end

function encode_value(x::Symbol, bits::Int)
    return encode_value(String(x), bits)
end

function encode_value(x::String, bits::Int)
    if bits > 128
        throw(ArgumentError("Cannot encode $bits bits into UInt128"))
    end
    nb = ncodeunits(x)
    if nb * 8 > bits
        throw(ArgumentError("String of $nb bytes needs $(nb * 8) bits, got $bits"))
    end

    result = UInt128(0)
    for i in 1:nb
        result |= UInt128(codeunit(x, i)) << ((i - 1) * 8)
    end
    return result
end

function encode_value(x::Char, bits::Int)
    if bits < 1 || bits > 32
        throw(ArgumentError("Cannot encode $bits bits for char"))
    end
    value = UInt128(UInt32(x))
    if value > _low_mask(bits)
        throw(ArgumentError("Char $(repr(x)) does not fit in $bits bits"))
    end
    return value
end

"""
    decode_value(T::Type, encoded::UInt128, bits::Int)

Decode a value of type `T` from the low `bits` bits of `encoded`, inverting
[`encode_value`](@ref). Integer types are sign-extended and returned as `T`;
`String`/`Symbol` decoding stops at the first zero byte (or after `min(bits ÷ 8, 16)`
bytes); `StringN{N}`/`SymbolN{N}` decode exactly `N` bytes.
"""
function decode_value(::Type{T}, encoded::UInt128, bits::Int) where {T<:Integer}
    if bits < 1 || bits > 128
        throw(ArgumentError("Cannot decode $bits bits for integer"))
    end

    value = encoded & _low_mask(bits)
    if T <: Signed && bits < 128 && (value >> (bits - 1)) % Bool
        value |= ~_low_mask(bits)  # sign-extend
    end
    # `% T` truncates to T's width, preserving two's-complement bit patterns
    return value % T
end

function decode_value(::Type{T}, encoded::UInt128, bits::Int) where {T<:Base.IEEEFloat}
    nbits = 8 * sizeof(T)
    if bits != nbits
        throw(ArgumentError("$T is decoded from $nbits bits, got $bits"))
    end
    U = _float_uint(T)
    return reinterpret(T, (encoded & _low_mask(bits)) % U)
end

function decode_value(::Type{Symbol}, encoded::UInt128, bits::Int)
    return Symbol(decode_value(String, encoded, bits))
end

function decode_value(::Type{String}, encoded::UInt128, bits::Int)
    if bits > 128
        throw(ArgumentError("Cannot decode $bits bits for string"))
    end

    # Extract bytes until a zero byte (NUL padding) or the bit budget runs out
    bytes = UInt8[]
    for i in 1:min(bits ÷ 8, 16)
        byte = UInt8((encoded >> ((i - 1) * 8)) & 0xFF)
        if byte == 0x00
            break
        end
        push!(bytes, byte)
    end

    return String(bytes)
end

function decode_value(::Type{Char}, encoded::UInt128, bits::Int)
    if bits < 1 || bits > 32
        throw(ArgumentError("Cannot decode $bits bits for char"))
    end

    value = encoded & _low_mask(bits)
    return Char(UInt32(value))
end

# bits_required for StringN{N} / SymbolN{N}: exactly N bytes
bits_required(::Type{StringN{N}}) where {N} = N * 8
bits_required(x::StringN{N}) where {N} = N * 8
bits_required(::Type{SymbolN{N}}) where {N} = N * 8
bits_required(x::SymbolN{N}) where {N} = N * 8

function encode_value(x::StringN{N}, bits::Int) where {N}
    if bits != N * 8
        throw(ArgumentError("bits for StringN{$N} must be N*8, got $bits"))
    end
    result = UInt128(0)
    for i in 1:N
        result |= UInt128(codeunit(x.value, i)) << ((i - 1) * 8)
    end
    return result
end

function decode_value(::Type{StringN{N}}, encoded::UInt128, bits::Int) where {N}
    if bits != N * 8
        throw(ArgumentError("bits for StringN{$N} must be N*8, got $bits"))
    end
    bytes = Vector{UInt8}(undef, N)
    for i in 1:N
        bytes[i] = UInt8((encoded >> ((i - 1) * 8)) & 0xFF)
    end
    return StringN{N}(String(bytes))
end

function encode_value(x::SymbolN{N}, bits::Int) where {N}
    if bits != N * 8
        throw(ArgumentError("bits for SymbolN{$N} must be N*8, got $bits"))
    end
    str = String(x.value)
    result = UInt128(0)
    for i in 1:N
        result |= UInt128(codeunit(str, i)) << ((i - 1) * 8)
    end
    return result
end

function decode_value(::Type{SymbolN{N}}, encoded::UInt128, bits::Int) where {N}
    if bits != N * 8
        throw(ArgumentError("bits for SymbolN{$N} must be N*8, got $bits"))
    end
    bytes = Vector{UInt8}(undef, N)
    for i in 1:N
        bytes[i] = UInt8((encoded >> ((i - 1) * 8)) & 0xFF)
    end
    return SymbolN{N}(Symbol(String(bytes)))
end

# Enum support: encode/decode via the enum's base integer type
function bits_required(::Type{T}) where {T<:Enum}
    return 8 * sizeof(Base.Enums.basetype(T))
end
function bits_required(x::Enum)
    return bits_required(typeof(x))
end

function encode_value(x::T, bits::Int) where {T<:Enum}
    B = Base.Enums.basetype(T)
    return encode_value(B(x), bits)
end

function decode_value(::Type{T}, encoded::UInt128, bits::Int) where {T<:Enum}
    int_val = decode_value(Base.Enums.basetype(T), encoded, bits)
    return T(int_val)
end
