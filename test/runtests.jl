using Test, Aqua, Encid

@enum Color RED GREEN BLUE
@enum Temp::Int8 COLD = -5 MILD = 0 HOT = 42

@testset "Encid basics" begin
    uid = UID(123, "ab", :cd, 'x', 1.25; uid_type = UID32)
    @test uid[1] == 123
    @test uid[2] == "ab"
    @test uid[3] == :cd
    @test uid[4] == 'x'
    @test uid[5] ≈ 1.25
    @test length(uid) == 5
    @test Tuple(uid) == (123, "ab", :cd, 'x', 1.25)
    @test uid[begin] == 123
    @test uid[end] == 1.25
    @test collect(uid) == [123, "ab", :cd, 'x', 1.25]
    @test_throws BoundsError uid[0]
    @test_throws BoundsError uid[6]
    @test startswith(sprint(show, uid), "UID\"")

    # positional uid_type form
    uid2 = UID(UID16, 7, :ok)
    @test Tuple(uid2) == (7, :ok)
end

@testset "Encid empty" begin
    uid = UID()
    @test uid isa UID{Nothing, UID8}
    @test length(uid) == 0
    @test Tuple(uid) == ()
    @test iterate(uid) === nothing
    @test_throws BoundsError uid[1]
    for U in (UID2, UID4, UID8, UID16, UID24, UID32, UID64)
        r = UID(; uid_type = U)
        @test r isa UID{Nothing, U}
        @test length(string(r)) > 0
    end
end

@testset "All uid types round trip" begin
    for U in (UID2, UID4, UID8, UID16, UID24, UID32, UID64)
        uid = UID(UInt8(42); uid_type = U)
        @test uid[1] === UInt8(42)
        @test parse(typeof(uid), string(uid)) == uid
    end
    # multi-word boundary crossing: values straddle the 128-bit word boundary
    uid = UID(typemax(UInt64), typemax(UInt64), -1, 1.25; uid_type = UID32)
    @test Tuple(uid) == (typemax(UInt64), typemax(UInt64), -1, 1.25)
    uid = UID(1, 2, 3, 4, 5, 6, 7, 8; uid_type = UID64)
    @test Tuple(uid) == (1, 2, 3, 4, 5, 6, 7, 8)
    # UID24 (previously broken): word sizes 128 + 64
    uid = UID(typemax(UInt128), typemin(Int32); uid_type = UID24)
    @test uid[1] === typemax(UInt128)
    @test uid[2] === typemin(Int32)
end

@testset "Integer round trips" begin
    for x in (Int8(-5), Int8(127), Int8(-128),
              Int16(-300), typemin(Int16), typemax(Int16),
              Int32(-70000), typemin(Int32), typemax(Int32),
              -123456789, typemin(Int64), typemax(Int64),
              typemin(Int128), typemax(Int128), Int128(-7),
              UInt8(0xff), UInt16(0xffff), UInt32(0xffffffff),
              typemax(UInt64), typemax(UInt128), UInt128(0),
              true, false)
        uid = UID(x; uid_type = UID16)
        @test uid[1] === x
    end
end

@testset "Float round trips" begin
    for x in (1.25, -1.25, 0.0, -0.0, Inf, -Inf,
              1.5f0, -0.0f0, Inf32, Float16(2.5), Float16(-0.0))
        uid = UID(x)
        @test uid[1] === x
    end
    # NaN round-trips bit-exactly
    @test UID(NaN)[1] === NaN
    @test UID(NaN32)[1] === NaN32
end

@testset "Char round trips" begin
    for c in ('x', 'λ', '中', '🚀', '\0')
        uid = UID(c)
        @test uid[1] === c
    end
end

@testset "String and Symbol round trips" begin
    for s in ("", "a", "ab", "a\0b", "héllo", "日本語", "12345678")
        uid = UID(s; uid_type = UID16)
        @test uid[1] == s
    end
    for s in (:a, :ab, :héllo, Symbol("日本語"))
        uid = UID(s; uid_type = UID16)
        @test uid[1] === s
    end
    # too large for the uid type
    @test_throws ArgumentError UID("123456789")            # 72 bits > 64
    @test_throws ArgumentError UID(UID2, 1, 2)             # 128 bits > 16

    # 16 bytes is the per-value maximum (128 bits); longer values error instead of
    # silently truncating, even when the uid type has room
    s16 = "abcdefghijklmnop"
    @test UID(s16; uid_type = UID16)[1] == s16
    @test UID(s16, s16; uid_type = UID32) |> Tuple == (s16, s16)
    @test_throws ArgumentError UID(s16 * "q"; uid_type = UID32)
    @test_throws ArgumentError UID(Symbol(s16 * "q"); uid_type = UID32)
    @test_throws ArgumentError StringN{17}(s16 * "q")
    @test_throws ArgumentError SymbolN{17}(Symbol(s16 * "q"))
    @test_throws ArgumentError decode_value(StringN{17}, UInt128(0), 136)
    @test_throws ArgumentError decode_value(SymbolN{17}, UInt128(0), 136)
end

@testset "Enum round trips" begin
    @test UID(GREEN)[1] === GREEN
    @test UID(COLD)[1] === COLD
    @test UID(HOT)[1] === HOT
    uid = UID(RED, HOT, BLUE; uid_type = UID16)
    @test Tuple(uid) == (RED, HOT, BLUE)
end

@testset "Encid helpers" begin
    @test bitsize(UID2) == 16
    @test bitsize(UID16) == 128
    @test bitsize(UID64) == 512
    @test bits_required("abc") == 24
    @test bits_required("héllo") == 48      # byte count, not char count
    @test bits_required(String) == 128
    @test bits_required(Symbol) == 128
    @test bits_required(0) == 1
    @test bits_required(1) == 1
    @test bits_required(2) == 2
    @test bits_required(1000) == 10
    @test bits_required(2^53) == 54         # exact (no float rounding)
    @test bits_required(typemax(Int64)) == 63
    @test bits_required(Int8(-1)) == 8      # negative: full type width
    @test bits_required(-1) == 64
    @test bits_required(Int32) == 32
    @test bits_required(Float32) == 32
    @test bits_required(Float64) == 64
    @test bits_required(Char) == 32
    @test bits_required('x') == 32
    @test bits_required(:ab) == 16
    @test bits_required(Color) == 32
    @test bits_required(Temp) == 8
    @test bits_required(StringN{5}) == 40
    @test bits_required(SymbolN{3}) == 24
    # unsupported types get a descriptive error, not a MethodError
    @test_throws ArgumentError bits_required(Vector{Int})
    @test_throws ArgumentError bits_required([1, 2])
    @test_throws ArgumentError UID([1, 2])
end

@testset "StringN and SymbolN" begin
    s = StringN{2}("ab")
    @test s == "ab"
    @test String(s) == "ab"
    @test length(s) == 2
    @test ncodeunits(s) == 2
    @test collect(s) == ['a', 'b']
    @test s == StringN{2}("ab")
    @test "ab" == s                          # generic AbstractString ==
    @test sprint(show, s) == "StringN{2}(\"ab\")"
    @test_throws ArgumentError StringN{2}("abc")
    # N counts bytes, so multi-byte strings use their codeunit count
    h = StringN{6}("héllo")
    @test h == "héllo"
    @test length(h) == 5
    @test_throws ArgumentError StringN{5}("héllo")

    y = SymbolN{2}(:ab)
    @test y == :ab
    @test :ab == y                           # symmetric
    @test Symbol(y) === :ab
    @test String(y) == "ab"
    @test y == SymbolN{2}(:ab)
    @test sprint(show, y) == "SymbolN{2}(:ab)"
    @test_throws ArgumentError SymbolN{3}(:ab)

    # explicit StringN/SymbolN args pass through unwrapped on decode
    uid = UID(StringN{2}("ab"), SymbolN{2}(:cd); uid_type = UID8)
    @test uid[1] == "ab"
    @test uid[2] === :cd
end

@testset "encode_value / decode_value" begin
    @test decode_value(Int, encode_value(42, 16), 16) === 42
    @test decode_value(Int, encode_value(-42, 16), 16) === -42
    @test decode_value(Int8, encode_value(Int8(-5), 8), 8) === Int8(-5)
    @test decode_value(UInt64, encode_value(typemax(UInt64), 64), 64) === typemax(UInt64)
    @test decode_value(Int64, encode_value(typemin(Int64), 64), 64) === typemin(Int64)
    @test decode_value(Int128, encode_value(typemin(Int128), 128), 128) === typemin(Int128)
    @test decode_value(UInt128, encode_value(typemax(UInt128), 128), 128) === typemax(UInt128)
    @test decode_value(Float64, encode_value(1.25, 64), 64) === 1.25
    @test decode_value(Float32, encode_value(1.5f0, 32), 32) === 1.5f0
    @test decode_value(Char, encode_value('λ', 32), 32) === 'λ'
    @test decode_value(String, encode_value("hi", 32), 32) == "hi"
    @test decode_value(Symbol, encode_value(:hi, 32), 32) === :hi

    # range/argument validation
    @test_throws ArgumentError encode_value(1, 0)
    @test_throws ArgumentError encode_value(1, 129)
    @test_throws ArgumentError encode_value(256, 8)          # too large
    @test_throws ArgumentError encode_value(-129, 8)         # too small
    @test_throws ArgumentError encode_value(1.25, 32)        # Float64 is 64 bits
    @test_throws ArgumentError encode_value(1.5f0, 64)       # Float32 is 32 bits
    @test_throws ArgumentError encode_value('λ', 8)          # doesn't fit
    @test_throws ArgumentError encode_value("abc", 16)       # 24 bits > 16
    @test_throws ArgumentError decode_value(Int, UInt128(0), 129)
    @test_throws ArgumentError decode_value(Float64, UInt128(0), 32)
    @test_throws ArgumentError encode_value(StringN{2}("ab"), 8)
    @test_throws ArgumentError decode_value(StringN{2}, UInt128(0), 8)
    @test_throws ArgumentError encode_value(SymbolN{2}(:ab), 8)
    @test_throws ArgumentError decode_value(SymbolN{2}, UInt128(0), 8)
end

@testset "Encid Base58" begin
    bytes = UInt8[0x00, 0x01, 0x02, 0x03]
    encoded = Encid.Base58.encode(bytes)
    @test Encid.Base58.decode(encoded) == bytes

    @test Encid.Base58.encode(UInt8[]) == ""
    @test Encid.Base58.decode("") == UInt8[]
    @test Encid.Base58.encode(UInt8[0x00, 0x00, 0x01]) == "112"
    @test Encid.Base58.decode("112") == UInt8[0x00, 0x00, 0x01]
    @test Encid.Base58.encode(UInt8[0x00, 0x00, 0x00]) == "111"
    @test Encid.Base58.decode("111") == UInt8[0x00, 0x00, 0x00]
    @test_throws ArgumentError Encid.Base58.decode("0")      # not in alphabet
    @test_throws ArgumentError Encid.Base58.decode("I0Ol")

    # exhaustive byte-level round trips incl. leading/trailing zeros
    for bytes in (UInt8[0x00], UInt8[0xff], UInt8[0x00, 0xff, 0x00, 0x2a],
                  UInt8[0x2a], zeros(UInt8, 8), rand(UInt8, 64))
        @test Encid.Base58.decode(Encid.Base58.encode(bytes)) == bytes
    end
end

@testset "string / parse round trips" begin
    for U in (UID2, UID4, UID8, UID16, UID24, UID32, UID64)
        for _ in 1:10
            u = U()
            @test parse(U, string(u)) == u
        end
    end
    # zero-valued and edge-pattern uids
    @test parse(UID2, string(UID2(0x0000))) == UID2(0x0000)
    @test parse(UID8, string(UID8(UInt64(1)))) == UID8(UInt64(1))
    @test parse(UID8, string(UID8(UInt64(1) << 63))) == UID8(UInt64(1) << 63)
    @test parse(UID16, string(UID16(UInt128(0)))) == UID16(UInt128(0))
    @test parse(UID24, string(UID24((UInt128(0), UInt64(0))))) == UID24((UInt128(0), UInt64(0)))
    @test string(UID8(UInt64(1))) == "Ahg1opVcGX"

    # UID24 and UID32 strings are distinct (UID24 encodes exactly 24 bytes)
    a = UID24((UInt128(1), UInt64(2)))
    b = UID32((UInt128(1), UInt128(2)))
    @test string(a) != string(b)

    # full UID{T, U} parse
    uid = UID(123, "ab", :cd, 'x', 1.25; uid_type = UID32)
    back = parse(typeof(uid), string(uid))
    @test back == uid
    @test Tuple(back) == (123, "ab", :cd, 'x', 1.25)

    # parse validation
    @test_throws ArgumentError parse(UID8, "!!!not-base58!!!")
    @test_throws ArgumentError parse(UID8, string(UID16()))  # wrong byte count

    # tryparse: nothing on bad input, value on good input
    @test tryparse(UID8, "!!!not-base58!!!") === nothing
    @test tryparse(UID8, string(UID16())) === nothing
    r8 = UID8()
    @test tryparse(UID8, string(r8)) === r8
    tu = UID(7, :ab; uid_type = UID16)
    @test tryparse(typeof(tu), string(tu)) == tu
    @test tryparse(typeof(tu), "***") === nothing

    # string macros: the show form of a primitive uid is pasteable syntax
    @test UID8"Ahg1opVcGX" === UID8(UInt64(1))
    @test parse(UID2, string(UID2"11")) === UID2"11"

    # print/interpolation matches string(); show is the pasteable literal form
    @test "id: $r8" == "id: $(string(r8))"
    @test sprint(show, r8) == "UID8\"$(string(r8))\""
    @test "id: $tu" == "id: $(string(tu))"
    @test sprint(print, r8) == string(r8)
end

@testset "Equality, ordering, and hashing" begin
    u = UID(7, :ab; uid_type = UID16)
    same = parse(typeof(u), string(u))
    @test u == same
    @test hash(u) == hash(same)
    @test isequal(u, same)
    other = UID(8, :ab; uid_type = UID16)
    @test u != other

    # cross-type and cross-domain == is false, never an error
    @test UID8(UInt64(1)) != UID2(0x0001)
    @test UID8(UInt64(1)) != UInt64(1)
    @test UID8(UInt64(1)) != 1

    # ordering compares as unsigned values, most-significant word first
    @test UID8(UInt64(1)) < UID8(UInt64(2))
    @test UID24((UInt128(9), UInt64(0))) < UID24((UInt128(0), UInt64(1)))
    @test sort([UID8(UInt64(3)), UID8(UInt64(1)), UID8(UInt64(2))]) ==
          [UID8(UInt64(1)), UID8(UInt64(2)), UID8(UInt64(3))]
    xs = sort([UID32() for _ in 1:10])
    @test issorted(xs)
    ws = sort([UID(i; uid_type = UID16) for i in (3, 1, 2)])
    @test issorted(ws)

    # same bits under different type params compare unequal
    @test UID(UID8, "EVT") != UID("EVT"; uid_type = UID8)

    # multi-word uids hash all their bits (regression: UInt128 word overlap)
    c = UID24((UInt128(0), UInt64(1)))
    d = UID24((UInt128(1) << 64, UInt64(0)))
    @test hash(c) != hash(d)
    e = UID64((UInt128(0), UInt128(1), UInt128(0), UInt128(0)))
    f = UID64((UInt128(0), UInt128(0), UInt128(1), UInt128(0)))
    @test hash(e) != hash(f)
end

@testset "String fast path" begin
    u = UID(UID8, "EVT")
    @test u isa UID{String, UID8}
    expected = (UInt64('T') << 16) | (UInt64('V') << 8) | UInt64('E')
    @test (UInt64(u.uid) & 0x0000000000ffffff) == expected
    @test length(string(u)) > 0
    @test u == u
    @test hash(u) isa UInt
    # fast-path uids don't record the string's length, so they can't be decoded
    @test length(u) == 0
    @test Tuple(u) == ()
    @test_throws BoundsError u[1]
    # utf-8 strings pack byte-for-byte, same as the generic path
    v = UID(UID8, "hél")
    @test v isa UID{String, UID8}
    g = UID("hél"; uid_type = UID8)
    @test (UInt64(v.uid) & 0x00000000ffffffff) == (UInt64(g.uid) & 0x00000000ffffffff)
    @test_throws ArgumentError UID(UID2, "abc")
    # multi-word uid types fall through to the generic constructor
    w = UID(UID24, "abc")
    @test w[1] == "abc"
end

@testset "Aqua" begin
    Aqua.test_all(Encid)
end

include("trim_compile_tests.jl")
