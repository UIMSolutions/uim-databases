/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.network;

import std.algorithm : all, canFind, count, findSplit;
import std.ascii : isDigit;
import std.conv : to;
import std.exception : enforce;
import std.string : indexOf, split, strip, toLower;

/// IP-Adresse als 16 Byte. IPv4 liegt im IPv6-Raum als ::ffff:a.b.c.d, so vergleicht eine Regel beide Familien.
alias IpBytes = ubyte[16];

/// Ein Netz wie 192.168.0.0/24, 2001:db8::/32 oder eine einzelne Adresse.
struct IpNetwork {
    IpBytes address; // auf die Präfixlänge gekürzt
    int prefix; // im IPv6-Raum, 0 bis 128
    bool v4; // nur für die Ausgabe

    /// Liest eine Adresse oder ein Netz in CIDR-Schreibweise. Bits hinter dem Präfix müssen 0 sein,
    /// damit 10.0.0.1/8 nicht unbemerkt als 10.0.0.0/8 gilt.
    static IpNetwork parse(string text) {
        auto t = text.strip;
        auto parts = t.findSplit("/");
        IpNetwork n;
        n.v4 = !parts[0].canFind(':');
        n.address = parseIpAddress(parts[0]);
        immutable maxPrefix = n.v4 ? 32 : 128;
        int given = maxPrefix;
        if (parts[1].length) {
            enforce(parts[2].length && parts[2].length <= 3 && parts[2].all!isDigit, "Invalid prefix length in " ~ t);
            given = parts[2].to!int;
            enforce(given <= maxPrefix, "Prefix length too large in " ~ t);
        }
        n.prefix = n.v4 ? given + 96 : given;
        enforce(masked(n.address, n.prefix) == n.address,
            "Address has bits set after the prefix: " ~ t ~ " (did you mean " ~ IpNetwork(masked(n.address, n.prefix), n.prefix, n.v4).toString ~ "?)");
        return n;
    }

    bool contains(IpBytes ip) const {
        return masked(ip, prefix) == address;
    }

    /// Kanonische Schreibweise, einzelne Adressen ohne Präfix.
    string toString() const {
        auto own = v4 ? prefix - 96 : prefix;
        auto full = v4 ? 32 : 128;
        auto text = v4 ? formatV4(address) : formatV6(address);
        return own == full ? text : text ~ "/" ~ own.to!string;
    }
}

/// Liest eine IPv4- oder IPv6-Adresse (auch ::ffff:1.2.3.4); wirft bei allem anderen.
IpBytes parseIpAddress(string text) {
    auto t = text.strip.toLower;
    enforce(t.length, "Empty IP address");
    if (!t.canFind(':'))
        return v4Mapped(parseV4(t));

    // IPv6: höchstens ein "::", am Ende darf eine IPv4-Adresse stehen
    if (t.length >= 2 && t[0] == '[' && t[$ - 1] == ']')
        t = t[1 .. $ - 1];
    ubyte[] tail;
    auto lastColon = t.lastIndexOfChar(':');
    if (t[lastColon + 1 .. $].canFind('.')) {
        auto v4 = parseV4(t[lastColon + 1 .. $]);
        tail = v4[];
        t = t[0 .. lastColon + 1] ~ "0:0"; // Platzhalter für die letzten 32 Bit
    }
    enforce(t.count("::") <= 1, "Invalid IPv6 address: " ~ text);
    string[] head, rest;
    auto halves = t.findSplit("::");
    head = halves[0].length ? halves[0].split(":") : null;
    if (halves[1].length)
        rest = halves[2].length ? halves[2].split(":") : null;
    immutable groups = head.length + rest.length;
    enforce(halves[1].length ? groups <= 7 : groups == 8, "Invalid IPv6 address: " ~ text);
    IpBytes result;
    void put(string[] parts, size_t start) {
        foreach (i, p; parts) {
            enforce(p.length >= 1 && p.length <= 4 && p.all!(c => isDigit(c) || (c >= 'a' && c <= 'f')),
                "Invalid IPv6 address: " ~ text);
            auto v = p.to!ushort(16);
            result[(start + i) * 2] = cast(ubyte)(v >> 8);
            result[(start + i) * 2 + 1] = cast(ubyte)(v & 0xff);
        }
    }

    put(head, 0);
    put(rest, 8 - rest.length);
    if (tail.length)
        result[12 .. 16] = tail[];
    return result;
}

/// Ob eine Adresse in einer der Listen liegt. Eine leere Liste erlaubt alles; eine unbekannte oder ungültige
/// Adresse ist bei einer nicht leeren Liste nicht erlaubt.
bool isAllowed(const IpNetwork[] networks, string address) {
    if (networks.length == 0)
        return true;
    IpBytes ip;
    try
        ip = parseIpAddress(address);
    catch (Exception)
        return false;
    foreach (n; networks)
        if (n.contains(ip))
            return true;
    return false;
}

/// Prüft und normalisiert eine Liste; doppelte Einträge fallen weg.
IpNetwork[] parseNetworks(string[] entries) {
    IpNetwork[] result;
    foreach (e; entries) {
        if (e.strip.length == 0)
            continue;
        auto n = IpNetwork.parse(e);
        if (!result.canFind(n))
            result ~= n;
    }
    enforce(result.length <= 256, "At most 256 networks per list");
    return result;
}

private ubyte[4] parseV4(string t) {
    auto parts = t.split(".");
    enforce(parts.length == 4, "Invalid IPv4 address: " ~ t);
    ubyte[4] b;
    foreach (i, p; parts) {
        enforce(p.length >= 1 && p.length <= 3 && p.all!isDigit && (p.length == 1 || p[0] != '0'),
            "Invalid IPv4 address: " ~ t);
        auto v = p.to!int;
        enforce(v <= 255, "Invalid IPv4 address: " ~ t);
        b[i] = cast(ubyte) v;
    }
    return b;
}

private IpBytes v4Mapped(ubyte[4] b) {
    IpBytes r;
    r[10] = 0xff;
    r[11] = 0xff;
    r[12 .. 16] = b[];
    return r;
}

private IpBytes masked(IpBytes ip, int prefix) {
    IpBytes r;
    foreach (i; 0 .. 16) {
        immutable bits = prefix - cast(int) i * 8;
        r[i] = bits >= 8 ? ip[i] : bits <= 0 ? 0 : cast(ubyte)(ip[i] & (0xff << (8 - bits)));
    }
    return r;
}

private string formatV4(IpBytes b) {
    return b[12].to!string ~ "." ~ b[13].to!string ~ "." ~ b[14].to!string ~ "." ~ b[15].to!string;
}

/// Einfache Ausgabe ohne Verkürzung der längsten Nullfolge außer am Stück, genug für Anzeige und Vergleich.
private string formatV6(IpBytes b) {
    import std.format : format;

    ushort[8] g;
    foreach (i; 0 .. 8)
        g[i] = cast(ushort)(b[i * 2] << 8 | b[i * 2 + 1]);
    // längste Folge von Nullgruppen (mindestens 2) durch :: ersetzen
    int bestStart = -1, bestLength = 0;
    for (int i = 0; i < 8;) {
        if (g[i] != 0) {
            ++i;
            continue;
        }
        int j = i;
        while (j < 8 && g[j] == 0)
            ++j;
        if (j - i > bestLength && j - i >= 2) {
            bestStart = i;
            bestLength = j - i;
        }
        i = j;
    }
    string result;
    for (int i = 0; i < 8; ++i) {
        if (i == bestStart) {
            result ~= "::";
            i += bestLength - 1;
            continue;
        }
        if (result.length && result[$ - 1] != ':')
            result ~= ":";
        result ~= format("%x", g[i]);
    }
    return result;
}

private size_t lastIndexOfChar(string s, char c) {
    foreach_reverse (i, ch; s)
        if (ch == c)
            return i;
    return size_t.max;
}

unittest {
    import std.exception : assertThrown;

    auto office = IpNetwork.parse("192.168.10.0/24");
    assert(office.toString == "192.168.10.0/24");
    assert(isAllowed([office], "192.168.10.77") && !isAllowed([office], "192.168.11.1"));
    assert(isAllowed([office], "::ffff:192.168.10.5")); // IPv4 über IPv6 angebunden
    assert(isAllowed([IpNetwork.parse("10.1.2.3")], "10.1.2.3") && !isAllowed([IpNetwork.parse("10.1.2.3")], "10.1.2.4"));
    assert(isAllowed([IpNetwork.parse("0.0.0.0/0")], "8.8.8.8") && !isAllowed([IpNetwork.parse("0.0.0.0/0")], "2001:db8::1"));

    auto v6 = IpNetwork.parse("2001:DB8::/32");
    assert(v6.toString == "2001:db8::/32");
    assert(isAllowed([v6], "2001:db8:1234::1") && !isAllowed([v6], "2001:db9::1"));
    assert(isAllowed([IpNetwork.parse("::1")], "::1") && !isAllowed([IpNetwork.parse("::1")], "127.0.0.1"));
    assert(parseIpAddress("::ffff:1.2.3.4") == parseIpAddress("1.2.3.4"));
    assert(parseIpAddress("[fe80::1]") == parseIpAddress("fe80:0:0:0:0:0:0:1"));
    assert(IpNetwork.parse("fe80:0:0:0:0:0:0:1").toString == "fe80::1");

    // Leere Liste erlaubt alles, sonst gelten unbekannte Adressen als nicht erlaubt
    assert(isAllowed([], "anything") && !isAllowed([office], "") && !isAllowed([office], "unix"));

    foreach (bad; ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1.2.3.4/33", "1.2.3.4/x", "1.2.3.4/",
            "10.0.0.1/8", "1:2:3:4:5:6:7:8:9", "1::2::3", "12345::", "g::1", "2001:db8::/129"])
        assertThrown(IpNetwork.parse(bad), bad);

    assert(parseNetworks(["10.0.0.0/8", " ", "10.0.0.0/8", "::1"]).length == 2);
}
