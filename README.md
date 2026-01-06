# Encid.jl

Encid generates compact, fixed-width identifiers that can encode a small set of values while
preserving random bits. It supports multiple UID sizes (16 to 512 bits) and can pack integers,
floats, symbols, strings, chars, and enums into a single ID that can be decoded later.

## How it works

- Pick a UID size (UID2/4/8/16/24/32/64 -> 16/32/64/128/192/256/512 bits).
- Each input value is encoded into the next available bits.
- Any unused bits remain random to keep IDs unpredictable.

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

## Helpers

- `bits_required(x)` and `bits_required(T)` estimate how many bits a value or type needs.
- `bitsize(UID16)` returns the bit width of a UID type.
- `StringN{N}` and `SymbolN{N}` let you enforce fixed-size string/symbol encoding.

## Notes

- `UID()` with no arguments returns a random UID of the requested type.
- Decode uses the original types, so keep your input ordering and types consistent.
