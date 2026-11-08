/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.packed_vector;

@safe:
/// Bit-packed vector: each code occupies only as many bits as the dictionary requires.
struct PackedVector {
    private ulong[] words;
    private uint bits;
    private size_t len;

    size_t length() const {
        return len;
    }

    uint bitsPerValue() const {
        return bits;
    }

    size_t bytes() const {
        return words.length * ulong.sizeof;
    }

    PackedVector dup() const {
        PackedVector p;
        p.words = words.dup;
        p.bits = bits;
        p.len = len;
        return p;
    }

    static uint bitsFor(size_t distinct) {
        uint b = 1;
        while ((1UL << b) < distinct)
            ++b;
        return b;
    }

    static PackedVector pack(const(uint)[] codes, size_t distinct) {
        PackedVector p;
        p.bits = bitsFor(distinct);
        p.len = codes.length;
        p.words = new ulong[(codes.length * p.bits + 63) / 64];
        foreach (i, c; codes)
            p.set(i, c);
        return p;
    }

    private void set(size_t i, uint v) {
        immutable bitPos = i * bits;
        immutable w = bitPos / 64;
        immutable off = cast(uint)(bitPos % 64);
        words[w] |= cast(ulong)v << off;
        if (off + bits > 64)
            words[w + 1] |= cast(ulong)v >> (64 - off);
    }

    uint opIndex(size_t i) const {
        immutable bitPos = i * bits;
        immutable w = bitPos / 64;
        immutable off = cast(uint)(bitPos % 64);
        ulong x = words[w] >> off;
        if (off + bits > 64)
            x |= words[w + 1] << (64 - off);
        return cast(uint)(x & ((1UL << bits) - 1));
    }
}

unittest {
    uint[] codes;
    foreach (i; 0 .. 200)
        codes ~= i % 37;
    auto p = PackedVector.pack(codes, 37);
    assert(p.bitsPerValue == 6 && p.length == 200);
    foreach (i, c; codes)
        assert(p[i] == c);
    assert(p.bytes < codes.length * uint.sizeof);

    auto big = PackedVector.pack([uint.max, 0, 123_456_789, 7], 1UL << 32);
    assert(big.bitsPerValue == 32);
    assert(big[0] == uint.max && big[1] == 0 && big[2] == 123_456_789 && big[3] == 7);
}
