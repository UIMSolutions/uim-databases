module uim.hdb.presentation.unix.interfaces;

import vibe.data.json : Json;

/// Anfrage über eine Unix-Domain-Socket-Verbindung.
interface IUnixRequest {
    /// Methode in Großbuchstaben, z.B. "GET".
    string method() const;
    /// Pfad ohne Query-String, z.B. "/api/v1/sql".
    string path() const;
    string[string] headers() const;
    /// Wert eines Headers ohne Rücksicht auf die Schreibweise; null, wenn er fehlt.
    string header(string name) const;
    string body() const;
    /// Der Body als Json; Json(null), wenn er leer oder ungültig ist.
    Json json() const;
}

/// Antwort über eine Unix-Domain-Socket-Verbindung.
interface IUnixResponse {
    int status() const;
    string[string] headers() const;
    string body() const;

    IUnixResponse status(int value);
    IUnixResponse header(string name, string value);
    IUnixResponse body(string value);
    /// Setzt den Body und den Content-Type.
    IUnixResponse json(Json value);
}

/// Bearbeitet die Anfragen eines Unix-Socket-Servers.
interface IUnixController {
    /// Präfix der Routen, z.B. "/api/v1".
    string routePrefix() const;
    bool canHandle(IUnixRequest request);
    IUnixResponse handle(IUnixRequest request);
}

/// Einzelne Client-Verbindung eines Unix-Socket-Servers.
interface IUnixConnection {
    /// Liest die nächste Nachricht; null, wenn der Client die Verbindung geschlossen hat.
    string readMessage();
    void writeMessage(string message);
    void close();
}

/// Server auf einem Unix Domain Socket.
interface IUnixServer {
    string socketPath() const;
    bool running() const;
    void start();
    void stop();
}
