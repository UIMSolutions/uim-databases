/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.presentation.odata.errors;

/// Error with HTTP status and OData code; returned as {“error”: {...}}.
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

/// The specification requires an error to be raised if a service does not implement an option: never silently ignore it.
ODataError notImplemented(string msg) {
    return new ODataError(501, "NotImplemented", msg);
}
