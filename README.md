# Encid.jl

[![CI](https://github.com/JuliaServices/Encid.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/JuliaServices/Encid.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/JuliaServices/Encid.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaServices/Encid.jl)

Encid generates compact, fixed-width identifiers that can encode a small set of values
while preserving random bits. It supports multiple UID sizes (16 to 512 bits) and can
pack integers, floats, symbols, strings, chars, and enums into a single ID that can be
decoded later.

## How it works

- Pick a UID size: `UID2`/`UID4`/`UID8`/`UID16`/`UID24`/`UID32`/`UID64`, named by byte
  count (16/32/64/128/192/256/512 bits).
- Each input value is encoded into the next available bits, using its type's full width.
- Any unused bits are filled with random bits.

## Installation

```julia
using Pkg
Pkg.add("Encid")
```

## Usage

```julia
using Encid

uid = UID(123, "ab", :cd, 'x', 1.25; uid_type=UID32)
string(uid)      # Base58-encoded identifier
uid[1]           # 123
uid[2]           # "ab"
uid[3]           # :cd
uid[4]           # 'x'
uid[5]           # 1.25
Tuple(uid)       # (123, "ab", :cd, 'x', 1.25)
```

Identifiers round-trip through their string form. The encoded argument types are carried
in the `UID`'s type parameters (not in the string), so parsing requires the concrete
type:

```julia
s = string(uid)                 # e.g. "yvQZFZ9NoRBEnbLmLWL9D8AMdNsxc3f4V1sqiJmZWLBc"
uid2 = parse(typeof(uid), s)
uid2 == uid                     # true
Tuple(uid2)                     # (123, "ab", :cd, 'x', 1.25)
```

Plain random identifiers work too, at any size:

```julia
r = UID8()                      # random 64-bit identifier
s = string(r)                   # e.g. "4jyPvXqoLXYN"
parse(UID8, s) == r             # true
```

## Helpers

- `bits_required(x)` and `bits_required(T)` return how many bits a value or type needs.
- `bitsize(UID16)` returns the bit width of a UID type.
- `StringN{N}` and `SymbolN{N}` let you enforce fixed-size string/symbol encoding
  (`N` counts bytes/codeunits).

## Notes

- `UID()` with no arguments returns a random UID of the requested type.
- Decoding uses the types recorded in the `UID`'s type parameters, so keep your input
  ordering and types consistent.
- Strings and symbols are encoded byte-for-byte (UTF-8), one byte per codeunit;
  `StringN{N}`/`SymbolN{N}` sizes are byte counts.
- `UID(uid_type, s::String)` for single-word uid types (`UID2`–`UID16`) is a
  value-level fast path returning `UID{String, U}`: generation and printing are
  identical to the generic path, but the value cannot be decoded back out by index
  (the string's length is not recorded in the type). Use the keyword form
  (`UID(s; uid_type=...)`) when you need to decode. The fast path (and the constructor
  surface generally) is kept compatible with `juliac --trim=safe` static compilation,
  which the test suite verifies.
- Random bits come from Julia's default random number generator, which is **not** a
  cryptographically secure source: don't treat these identifiers as unguessable
  secrets or capability tokens.
