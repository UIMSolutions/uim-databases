/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.gui.transport;

import uim.hdb.presentation.gui.api : HttpReply, IHttpTransport;
import core.time : seconds;
import std.exception : enforce;
import etc.c.curl : CurlOption;
import std.net.curl : HTTP;

@safe:

/// HTTP über libcurl (Phobos). Die Anfragen laufen synchron; der Admin-Client wartet kurz darauf, für die meist
/// kleinen Antworten eines Admin-Werkzeugs genügt das.
final class CurlTransport : IHttpTransport {
    /// @trusted: std.net.curl ist @system, weil es C-Zeiger an libcurl gibt. Hier gehen nur Kopien von D-Strings
    /// hinein, und die empfangenen Bytes werden in einen eigenen Puffer kopiert.
    HttpReply send(string method, string url, string[string] headers, string body) @trusted {
        auto http = HTTP(url);
        http.connectTimeout = 5.seconds;
        http.operationTimeout = 120.seconds; // Sicherungen können dauern
        foreach (name, value; headers)
            if (name != "Content-Type")
                http.addRequestHeader(name, value);
        // Mit Rumpf immer als POST senden und das Verb ersetzen: Phobos schickt PUT sonst über CURLOPT_UPLOAD und
        // ignoriert die mit setPostData gesetzten Daten. `body` lebt bis nach perform, libcurl liest direkt daraus.
        switch (method) {
        case "GET":
            enforce(body.length == 0, "GET requests have no body");
            http.method = HTTP.Method.get;
            break;
        case "POST":
        case "PUT":
        case "DELETE":
            http.setPostData(body, headers.get("Content-Type", "application/json"));
            http.method = HTTP.Method.post;
            if (method != "POST")
                http.handle.set(CurlOption.customrequest, method);
            break;
        default:
            throw new Exception("Unsupported HTTP method: " ~ method);
        }
        ubyte[] received;
        http.onReceive = (ubyte[] data) { received ~= data; return data.length; };
        http.perform();
        return HttpReply(http.statusLine.code, cast(string) received.idup);
    }
}
