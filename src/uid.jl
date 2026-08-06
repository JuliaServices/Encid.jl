# Helper functions to automatically wrap strings/symbols with their byte length
# recorded in the type domain (StringN{N} / SymbolN{N}), so values can be decoded later
wrap_string(s::StringN) = s
wrap_string(s::AbstractString) = StringN{ncodeunits(s)}(String(s))
wrap_string(x) = x  # Identity for non-strings

wrap_symbol(s::Symbol) = SymbolN{ncodeunits(String(s))}(s)
wrap_symbol(x) = x  # Identity for non-symbols

const PrimitiveUID = Union{UID2, UID4, UID8, UID16, UID24, UID32, UID64}

# Extract a uid's words as UInt128s (least-significant word first) with their bit sizes
function _uid_words(uid_type::Type{U}, uid) where {U <: PrimitiveUID}
    if uid_type == UID2
        return UInt128[UInt128(uid)], [16]
    elseif uid_type == UID4
        return UInt128[UInt128(uid)], [32]
    elseif uid_type == UID8
        return UInt128[UInt128(uid)], [64]
    elseif uid_type == UID16
        return UInt128[UInt128(uid)], [128]
    elseif uid_type == UID24
        t = Tuple(uid)
        return UInt128[t[1], UInt128(t[2])], [128, 64]
    elseif uid_type == UID32
        t = Tuple(uid)
        return UInt128[t[1], t[2]], [128, 128]
    else # UID64
        t = Tuple(uid)
        return UInt128[t[1], t[2], t[3], t[4]], [128, 128, 128, 128]
    end
end

# Rebuild a primitive uid from its words
function _uid_from_words(uid_type::Type{U}, words) where {U <: PrimitiveUID}
    if uid_type == UID2
        return UID2(UInt16(words[1]))
    elseif uid_type == UID4
        return UID4(UInt32(words[1]))
    elseif uid_type == UID8
        return UID8(UInt64(words[1]))
    elseif uid_type == UID16
        return UID16(words[1])
    elseif uid_type == UID24
        return UID24((words[1], UInt64(words[2])))
    elseif uid_type == UID32
        return UID32((words[1], words[2]))
    else # UID64
        return UID64((words[1], words[2], words[3], words[4]))
    end
end

# Helper function to encode values across multiple words
function encode_multi_word(args, types, uid_type)
    total_bits = sum(bits_required(T) for T in types)
    available_bits = bitsize(uid_type)

    if total_bits > available_bits
        throw(ArgumentError("Need $total_bits bits but only have $available_bits available in $uid_type"))
    end

    # Start from a random UID so unused bits stay random
    words, word_sizes = _uid_words(uid_type, uid_type())

    # Encode values across words, preserving random bits in unused portions
    bit_offset = 0
    for (arg, T) in zip(args, types)
        bits_needed = bits_required(T)
        encoded_value = encode_value(arg, bits_needed)

        # Distribute encoded value across words
        remaining_bits = bits_needed
        value_offset = 0

        while remaining_bits > 0
            # Find which word we're in
            word_idx = 1
            word_bit_offset = bit_offset
            for i in 1:length(word_sizes)
                if word_bit_offset < word_sizes[i]
                    word_idx = i
                    break
                end
                word_bit_offset -= word_sizes[i]
            end

            bits_in_word = min(remaining_bits, word_sizes[word_idx] - word_bit_offset)

            # Extract the relevant bits from encoded_value
            mask = _low_mask(bits_in_word)
            bits_to_write = (encoded_value >> value_offset) & mask

            # Clear the target bits and write the encoded value
            clear_mask = ~(mask << word_bit_offset)
            words[word_idx] = (words[word_idx] & clear_mask) | (bits_to_write << word_bit_offset)

            remaining_bits -= bits_in_word
            value_offset += bits_in_word
            bit_offset += bits_in_word
        end
    end

    return words
end

# Helper function to decode values from multiple words
function decode_multi_word(uid, types, uid_type)
    words, word_sizes = _uid_words(uid_type, uid)

    # Decode values from words
    decoded = []
    bit_offset = 0

    for T in types
        bits_needed = bits_required(T)
        encoded_value = UInt128(0)

        # Collect bits from words
        remaining_bits = bits_needed
        value_offset = 0

        while remaining_bits > 0
            # Find which word we're in
            word_idx = 1
            word_bit_offset = bit_offset
            for i in 1:length(word_sizes)
                if word_bit_offset < word_sizes[i]
                    word_idx = i
                    break
                end
                word_bit_offset -= word_sizes[i]
            end

            bits_in_word = min(remaining_bits, word_sizes[word_idx] - word_bit_offset)

            # Extract bits from the word
            mask = _low_mask(bits_in_word)
            bits_from_word = (words[word_idx] >> word_bit_offset) & mask

            # Add to encoded_value
            encoded_value |= bits_from_word << value_offset

            remaining_bits -= bits_in_word
            value_offset += bits_in_word
            bit_offset += bits_in_word
        end

        # Decode the value
        push!(decoded, decode_value(T, encoded_value, bits_needed))
    end

    return decoded
end

"""
    UID(args...; uid_type = UID8)
    UID(uid_type, args...)

Generate an identifier of `uid_type` (one of `UID2`, `UID4`, `UID8`, `UID16`, `UID24`,
`UID32`, `UID64`) with `args` encoded into its low bits; any remaining bits are filled
with random bits. Supported argument types: integers, IEEE floats, `Char`, `String`,
`Symbol`, enums, and [`StringN`](@ref)/[`SymbolN`](@ref).

With no `args`, returns a fully random identifier.

The encoded values can be recovered from the `UID` object by index (`uid[1]`), by
iteration, or all at once with `Tuple(uid)`. Use `string(uid)` for the Base58 string
form and `parse(typeof(uid), str)` to reconstruct the `UID` from that string — the
argument types are carried in the `UID`'s type parameters, so decoding a parsed string
requires the same concrete `UID{T, U}` type.

```jldoctest
julia> uid = UID(123, "ab", :cd, 'x', 1.25; uid_type = UID32);

julia> Tuple(uid)
(123, "ab", :cd, 'x', 1.25)

julia> parse(typeof(uid), string(uid)) == uid
true
```

!!! note
    `UID(uid_type, s::String)` for single-word uid types (`UID2`–`UID16`) is a
    value-level fast path that returns a `UID{String, U}`: generation and printing are
    identical to the generic path, but the string's length is not recorded in the type,
    so the value cannot be decoded back out by index. Use the keyword form
    (`UID(s; uid_type)`) when you need to decode.
"""
struct UID{T, U <: PrimitiveUID}
    uid::U
end

# Constructor that takes any number of arguments and encodes them.
# Both entry points forward to _uid_impl with the uid type as a positional where-param:
# julia doesn't specialize methods on unparameterized Type arguments, and kwarg
# NamedTuples type a Type value as a bare DataType — either way every call funneled
# into one instance where `uid_type` is a runtime DataType: type-unstable, and
# unresolvable dynamic dispatch under `juliac --trim`.
UID(args...; uid_type::Type{U} = UID8) where {U <: PrimitiveUID} =
    _uid_impl(U, args...)

# Constructor with specific UID type
UID(uid_type::Type{U}, args...) where {U <: PrimitiveUID} =
    _uid_impl(U, args...)

# Value-level fast path for the common "encode one string into a single-word uid"
# case (e.g. prefixed ids). The generic path wraps the string as StringN{ncodeunits(s)} —
# a runtime type parameter — which makes the whole encode machinery runtime dispatch:
# type-unstable, and unresolvable under `juliac --trim`. This produces bit-identical
# results (verified against the generic path) using the length's value instead of its
# type. Multi-word uid types fall through to the generic `args...` method.
# NOTE: the result is tagged UID{String, U} (not UID{Tuple{StringN{N}}, U});
# generation/printing is identical, but callers that decode by type should use the
# generic constructor.
function UID(uid_type::Type{U}, s::String) where {U <: Union{UID2, UID4, UID8, UID16}}
    n = ncodeunits(s)
    total_bits = n * 8
    available_bits = bitsize(U)
    if total_bits > available_bits
        throw(ArgumentError("Need $total_bits bits but only have $available_bits available in $U"))
    end
    # random init, then overwrite the low n*8 bits with the packed bytes —
    # the same layout encode_multi_word produces for a single StringN argument
    w = _uid_word(U())
    for i in 1:n
        off = (i - 1) * 8
        w = (w & ~(UInt128(0xff) << off)) | (UInt128(codeunit(s, i)) << off)
    end
    return UID{String, U}(_uid_from_word(U, w))
end

_uid_word(u::UID2) = UInt128(UInt16(u))
_uid_word(u::UID4) = UInt128(UInt32(u))
_uid_word(u::UID8) = UInt128(UInt64(u))
_uid_word(u::UID16) = UInt128(u)

_uid_from_word(::Type{UID2}, w::UInt128) = UID2(UInt16(w))
_uid_from_word(::Type{UID4}, w::UInt128) = UID4(UInt32(w))
_uid_from_word(::Type{UID8}, w::UInt128) = UID8(UInt64(w))
_uid_from_word(::Type{UID16}, w::UInt128) = UID16(w)

function _uid_impl(uid_type::Type{U}, args...) where {U <: PrimitiveUID}
    if isempty(args)
        return UID{Nothing, uid_type}(uid_type())
    end

    # Wrap strings with StringN{N} and symbols with SymbolN{N} automatically
    wrapped_args = map(wrap_string ∘ wrap_symbol, args)
    types = map(typeof, wrapped_args)

    # Encode values across multiple words (throws if they don't fit in uid_type)
    words = encode_multi_word(wrapped_args, types, uid_type)

    return UID{Tuple{types...}, uid_type}(_uid_from_words(uid_type, words))
end

# String representation
function Base.string(uid::UID)
    return string(uid.uid)
end

"""
    parse(::Type{UID{T, U}}, s::AbstractString)  ->  UID{T, U}

Reconstruct a [`UID`](@ref) from its Base58 string form (as produced by
`string(uid)`). The encoded argument types `T` are not stored in the string, so the
full concrete `UID{T, U}` type must be supplied — typically as `typeof(uid)` from a
`UID` built with the same argument types.
"""
Base.parse(::Type{UID{T, U}}, s::AbstractString) where {T, U <: PrimitiveUID} =
    UID{T, U}(parse(U, s))

# Show method
function Base.show(io::IO, uid::UID)
    print(io, "UID\"$(string(uid))\"")
end

# Helper function to unwrap StringN and SymbolN values
function unwrap_value(value)
    if value isa StringN
        return String(value)
    elseif value isa SymbolN
        return Symbol(value)
    else
        return value
    end
end

# Indexing to extract original values
function Base.getindex(uid::UID{T, U}, i::Integer) where {T, U}
    if !(T <: Tuple)
        throw(BoundsError(uid, i))
    end

    args = T.parameters
    if i < 1 || i > length(args)
        throw(BoundsError(uid, i))
    end

    # Use multi-word decoding to get all values
    decoded_values = decode_multi_word(uid.uid, args, U)
    # Automatically unwrap StringN and SymbolN values
    return unwrap_value(decoded_values[i])
end

# Number of encoded values
function Base.length(uid::UID{T}) where T
    return T <: Tuple ? length(T.parameters) : 0
end

Base.firstindex(uid::UID) = 1
Base.lastindex(uid::UID) = length(uid)

# Iterator support
function Base.iterate(uid::UID, state::Integer = 0)
    if state >= length(uid)
        return nothing
    end
    return (uid[state + 1], state + 1)
end

# Convert to tuple (decodes all values in a single pass)
function Base.Tuple(uid::UID{T, U}) where {T, U}
    if !(T <: Tuple)
        return ()
    end
    decoded_values = decode_multi_word(uid.uid, T.parameters, U)
    return Tuple(map(unwrap_value, decoded_values))
end

# Equality
function Base.:(==)(a::UID, b::UID)
    if typeof(a) !== typeof(b)
        return false
    end
    return a.uid == b.uid
end

# Hash
function Base.hash(uid::UID, h::UInt)
    return hash(uid.uid, h)
end
