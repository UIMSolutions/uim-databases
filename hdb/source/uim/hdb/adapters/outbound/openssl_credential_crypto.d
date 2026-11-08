module uim.hdb.adapters.outbound.openssl_credential_crypto;

import uim.hdb.application.ports;
import std.algorithm : min;
import std.array : split;
import std.base64 : Base64, Base64URLNoPadding;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.string : toStringz;
import vibe.core.concurrency : async;
import vibe.core.task : Task;

@safe:

// libcrypto ist über vibe.d bereits gelinkt.
private extern (C) nothrow @nogc {
    const(void)* EVP_sha256();
    int PKCS5_PBKDF2_HMAC(const(char)* pass, int passlen, const(ubyte)* salt, int saltlen, int iter,
        const(void)* digest, int keylen, ubyte* output);
    int RAND_bytes(ubyte* buffer, int num);
}

/// Ausgehender Adapter: PBKDF2-HMAC-SHA256 (600 000 Runden, OWASP-Empfehlung) und Zufall aus OpenSSL.
/// Format: pbkdf2-sha256$runden$salz$hash. Die Runden stehen im Hash, sie lassen sich später erhöhen.
final class OpensslCredentialCrypto : ICredentialCrypto {
    private enum scheme = "pbkdf2-sha256";
    private enum iterations = 600_000;
    private enum maxIterations = 100_000_000;
    private enum keyLength = 32;

    string hashPassword(string password) {
        auto salt = randomBytes(16);
        auto hash = derive(password, salt, iterations);
        return format("%s$%s$%s$%s", scheme, iterations, Base64.encode(salt), Base64.encode(hash));
    }

    bool verifyPassword(string password, string stored) {
        auto parts = stored.split("$");
        if (parts.length != 4 || parts[0] != scheme)
            return false;
        immutable rounds = parts[1].to!int;
        enforce(rounds > 0 && rounds <= maxIterations, "Invalid password hash");
        auto expected = Base64.decode(parts[3]);
        return sameBytes(derive(password, Base64.decode(parts[2]).idup, rounds), expected);
    }

    string randomSecret() {
        return Base64URLNoPadding.encode(randomBytes(32)).idup;
    }
}

private immutable(ubyte)[] randomBytes(int count) {
    enforce(count > 0, "Invalid length");
    auto buffer = new ubyte[count];
    enforce(RAND_bytes(&buffer[0], count) == 1, "No secure random numbers available");
    return buffer.idup;
}

/// In einer Anfrage läuft die Ableitung auf einem Worker-Thread, sonst stünde der Server währenddessen still.
private ubyte[] derive(string password, immutable(ubyte)[] salt, int rounds) {
    if (Task.getThis() == Task.init)
        return pbkdf2(password, salt, rounds).dup;
    return async(&pbkdf2, password, salt, rounds).getResult().dup;
}

private immutable(ubyte)[] pbkdf2(string password, immutable(ubyte)[] salt, int rounds) {
    enum keyLength = 32;
    auto key = new ubyte[keyLength];
    // Das Passwort darf leer sein; ptr wäre dann null und OpenSSL würde daran scheitern.
    enforce(salt.length > 0, "Empty salt");
    enforce(PKCS5_PBKDF2_HMAC(password.toStringz, password.length.to!int, &salt[0], salt.length.to!int,
            rounds, EVP_sha256(), keyLength, &key[0]) == 1, "Password hashing failed");
    return key.idup;
}

/// Vergleich ohne frühen Abbruch, damit die Laufzeit nichts über den Hash verrät.
private bool sameBytes(const(ubyte)[] a, const(ubyte)[] b) {
    uint diff = a.length != b.length;
    foreach (i; 0 .. min(a.length, b.length))
        diff |= a[i] ^ b[i];
    return diff == 0;
}

unittest {
    auto crypto = new OpensslCredentialCrypto;
    auto hash = crypto.hashPassword("correct horse ümläut");
    assert(hash.split("$")[1] == "600000");
    assert(crypto.verifyPassword("correct horse ümläut", hash));
    assert(!crypto.verifyPassword("correct horse umlaut", hash));
    assert(!crypto.verifyPassword("", hash));
    assert(crypto.hashPassword("x") != crypto.hashPassword("x")); // eigenes Salz je Hash
    assert(!crypto.verifyPassword("x", "plaintext"));
    assert(crypto.randomSecret() != crypto.randomSecret());
    assert(crypto.randomSecret().length == 43);

    // Bekannter Testvektor: PBKDF2-HMAC-SHA256("password", "salt", 1, 32)
    import std.digest : toHexString, LetterCase;

    assert(pbkdf2("password", cast(immutable(ubyte)[]) "salt", 1).toHexString!(LetterCase.lower)
        == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"[0 .. 64]);
}
