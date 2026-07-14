# Trim-compile workload: exercises the code paths the trim-verifier fixes
# cover, with value-level assertions so the compiled executable proves runtime
# behavior too. Compiled by test/trim_compile_tests.jl with `juliac --trim=safe`
# and an error budget of zero, then executed.
using Encid

# base58 leading-zero padding (the repeat(::String, n) fix): leading zero bytes
# must become leading '1's, and the round trip must be exact
function _assert_base58()::Nothing
    Encid.Base58.encode(UInt8[0x00, 0x00, 0x01]) == "112" || error("base58 leading zeros")
    Encid.Base58.encode(UInt8[0x00, 0x00, 0x00]) == "111" || error("base58 all zeros")
    for bytes in (UInt8[0x00, 0x00, 0x01], UInt8[0x00, 0xff, 0x00, 0x2a], UInt8[0x2a])
        Encid.Base58.decode(Encid.Base58.encode(bytes)) == bytes || error("base58 roundtrip")
    end
    return nothing
end

# primitive uid construction, string rendering, and value conversions
function _assert_primitive_uids()::Nothing
    string(UID8(UInt64(1))) == "Ahg1opVcGX" || error("UID8 string")
    UInt64(UID8(UInt64(42))) == UInt64(42) || error("UID8 word roundtrip")
    r = UID8()
    length(string(r)) > 0 || error("UID8 random string")
    bits_required(1000) == 10 || error("bits_required")
    bitsize(UID8) == 64 || error("bitsize")
    Encid.decode_value(Int, Encid.encode_value(42, 16), 16) == 42 || error("encode/decode_value")
    return nothing
end

# the single-word String fast path (value-level, no StringN{N} runtime type
# parameter): result is tagged UID{String, U} and packs characters into the
# low bits exactly like the generic path
function _assert_string_fast_path()::Nothing
    u = UID(UID8, "EVT")
    u isa UID{String, UID8} || error("fast path type")
    expected = (UInt64('T') << 16) | (UInt64('V') << 8) | UInt64('E')
    (UInt64(u.uid) & 0x0000000000ffffff) == expected || error("fast path packing")
    length(string(u)) > 0 || error("fast path string")
    u == u || error("fast path equality")
    hash(u) isa UInt || error("fast path hash")
    io = IOBuffer()
    show(io, u)
    startswith(String(take!(io)), "UID\"") || error("fast path show")
    return nothing
end

# the value-level String fast path across all single-word uid types.
# NOTE: this is the trim-safe constructor surface. The generic `args...`
# machinery (including the kwarg form) wraps strings as StringN{length(s)} —
# a runtime type parameter — and decode-by-index walks runtime type
# parameters; both remain dynamic and are exercised by the regular test
# suite instead.
function _check_fast_path(u::UID{String, U})::Nothing where {U}
    length(string(u)) > 0 || error("ctor string")
    u == u || error("ctor equality")
    hash(u) isa UInt || error("ctor hash")
    return nothing
end

function _assert_fast_path_ctors()::Nothing
    _check_fast_path(UID(UID2, "a"))
    _check_fast_path(UID(UID4, "ab"))
    _check_fast_path(UID(UID8, "PAY"))
    u16 = UID(UID16, "EVENT")
    u16 isa UID{String, UID16} || error("UID16 fast path type")
    _check_fast_path(u16)
    return nothing
end

function run_encid_trim_workload()::Nothing
    _assert_base58()
    _assert_primitive_uids()
    _assert_string_fast_path()
    _assert_fast_path_ctors()
    return nothing
end

function @main(args::Vector{String})::Cint
    _ = args
    run_encid_trim_workload()
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
