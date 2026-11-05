module uim.hdb.presentation.odata.errors;

/// Fehler mit HTTP-Status und OData-Code, wird als {"error": {...}} ausgeliefert.
class ODataError : Exception {
    int status;
    string code;

    this(int status, string code, string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
        this.status = status;
        this.code = code;
    }
}

ODataError badRequest(string msg) {
    return new ODataError(400, "BadRequest", msg);
}

ODataError notFound(string msg) {
    return new ODataError(404, "NotFound", msg);
}

ODataError conflict(string msg) {
    return new ODataError(409, "Conflict", msg);
}

/// Die Spezifikation verlangt einen Fehler, wenn ein Dienst eine Option nicht umsetzt: nie stillschweigend ignorieren.
ODataError notImplemented(string msg) {
    return new ODataError(501, "NotImplemented", msg);
}
