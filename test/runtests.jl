using Test, Encid

@testset "Encid basics" begin
    uid = UID(123, "ab", :cd, 'x', 1.25; uid_type=UID32)
    @test uid[1] == 123
    @test uid[2] == "ab"
    @test uid[3] == :cd
    @test uid[4] == 'x'
    @test uid[5] ≈ 1.25
    @test length(uid) == 5
    @test Tuple(uid) == (123, "ab", :cd, 'x', 1.25)
end

@testset "Encid empty" begin
    uid = UID()
    @test length(uid) == 0
    @test Tuple(uid) == ()
end

@testset "Encid helpers" begin
    @test bitsize(UID16) == 128
    @test bits_required("abc") == 24
    @test bits_required(String) == 128
end

@testset "Encid Base58" begin
    bytes = UInt8[0x00, 0x01, 0x02, 0x03]
    encoded = Encid.Base58.encode(bytes)
    @test Encid.Base58.decode(encoded) == bytes
end

include("trim_compile_tests.jl")
