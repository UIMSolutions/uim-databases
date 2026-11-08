/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.unix.connection;

import uim.hdb.presentation.unix.interfaces;
import uim.hdb.presentation.unix.message;
import std.array : appender;
import std.conv : ConvException, to;
import std.string : icmp, indexOf, representation, strip;
import std.utf : UTFException, validate;
import vibe.core.net : TCPConnection;

@safe:

/// Liest und schreibt Nachrichten auf einem Socket. vibe nennt jede Stream-Verbindung TCPConnection, auch AF_UNIX.
final class UnixConnection : IUnixConnection {
    enum size_t maxHeaderBytes = 64 * 1024;

    private TCPConnection socket;
    private size_t maxBodyBytes;

    this(TCPConnection socket, size_t maxBodyBytes) {
        this.socket = socket;
        this.maxBodyBytes = maxBodyBytes;
    }

    string readMessage() {
        if (socket.empty)
            return null;

        auto header = appender!string;
        size_t bodyLength, headerBytes;
        bool first = true;
        while (true) {
            auto line = readLine(headerBytes);
            header.put(line);
            if (line == "\n" || line == "\r\n")
                break;
            if (!first)
                bodyLength = contentLength(line, bodyLength);
            first = false;
        }

        auto content = new ubyte[bodyLength];
        if (bodyLength)
            socket.read(content);
        auto message = header.data ~ cast(string)content;
        try
            validate(message);
        catch (UTFException)
            throw new UnixProtocolError(400, "Message is not valid UTF-8");
        return message;
    }

    /// Zeile mit Zeilenende. Das Limit gilt für alle Header zusammen, sonst wäre der Speicher pro Nachricht unbegrenzt.
    private string readLine(ref size_t headerBytes) {
        auto line = appender!string;
        ubyte[1] next;
        do {
            if (++headerBytes > maxHeaderBytes)
                throw new UnixProtocolError(413, "Headers too large");
            socket.read(next[]);
            line.put(cast(char)next[0]);
        } while (next[0] != '\n');
        return line.data;
    }

    private size_t contentLength(string line, size_t current) {
        auto colon = line.indexOf(':');
        if (colon <= 0 || icmp(line[0 .. colon].strip, "Content-Length") != 0)
            return current;
        size_t length;
        try
            length = line[colon + 1 .. $].strip.to!size_t;
        catch (ConvException)
            throw new UnixProtocolError(400, "Invalid Content-Length");
        if (length > maxBodyBytes)
            throw new UnixProtocolError(413, "Body too large");
        return length;
    }

    void writeMessage(string message) {
        socket.write(message.representation);
        socket.flush();
    }

    void close() {
        socket.close();
    }
}
