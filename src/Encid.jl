"""
    Encid

Generate compact, fixed-width identifiers that can encode a small set of values while
preserving random bits. Pick a size ([`UID2`](@ref) through [`UID64`](@ref), 16–512
bits), pack integers, floats, chars, strings, symbols, and enums into the low bits with
[`UID`](@ref), and decode them back out later by index or via `Tuple(uid)`. Identifiers
render as Base58 strings with `string(uid)` and round-trip with `parse`.
"""
module Encid

using Random

export UID, UID2, UID4, UID8, UID16, UID24, UID32, UID64
export @UID2_str, @UID4_str, @UID8_str, @UID16_str, @UID24_str, @UID32_str, @UID64_str
export encode_value, decode_value, bits_required, bitsize, StringN, SymbolN

include("base58.jl")
include("primitive_uids.jl")
include("encoders.jl")
include("uid.jl")

end # module
