module uim.hdb.presentation.odata.controller;

import uim.hdb.application.ports : ISqlUseCase;
import uim.hdb.domain.entities.user : AccessDenied, AuthenticationRequired;
import uim.hdb.domain.types.tablestats : ColumnStats, TableStats;
import uim.hdb.domain.value;
import uim.hdb.presentation.odata.errors;
import uim.hdb.presentation.odata.filter;
import uim.hdb.presentation.odata.model;
import uim.hdb.presentation.rest.services : jsonLiteral;
import std.algorithm : any, canFind, filter, map, min, startsWith;
import std.array : appender, array, join, split;
import std.conv : to;
import std.string : icmp, indexOf, strip, toLower;
import vibe.data.json : Json, parseJsonString;
import vibe.http.common : HTTPMethod, HTTPStatusException;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.stream.operations : readAllUTF8;
import vibe.textfilter.urlencode : urlEncode;

private enum jsonBase = "application/json;odata.metadata=minimal;odata.streaming=true;IEEE754Compatible=";
private enum size_t maxPageSize = 1000;

/// Zerlegter Ressourcenpfad: Set, Set(key), Set(key)/prop, Set/$count, ...
struct ResourcePath {
    string entitySet;
    bool hasKey;
    string key;
    string[] segments;
}

ResourcePath parseResourcePath(string path) {
    ResourcePath r;
    size_t i;
    while (i < path.length && path[i] != '(' && path[i] != '/')
        ++i;
    r.entitySet = path[0 .. i];
    if (i < path.length && path[i] == '(') {
        size_t j = i + 1;
        bool quoted;
        while (j < path.length && (path[j] != ')' || quoted)) {
            if (path[j] == '\'')
                quoted = !quoted;
            ++j;
        }
        if (j >= path.length)
            throw badRequest("Invalid key in path");
        r.hasKey = true;
        r.key = path[i + 1 .. j];
        i = j + 1;
    }
    if (i < path.length) {
        if (path[i] != '/')
            throw badRequest("Invalid path");
        r.segments = path[i + 1 .. $].split("/");
    }
    return r;
}

/// Schlüssel aus dem Pfad als SQL-Literal: 1, 'a''b' oder id=1.
string keyLiteral(ColumnStats column, string key) {
    auto text = key.strip;
    auto eq = text.indexOf('=');
    if (eq > 0 && text[0] != '\'') {
        if (text[0 .. eq].strip != column.name)
            throw badRequest("Unknown key property: " ~ text[0 .. eq].strip);
        text = text[eq + 1 .. $].strip;
    }
    if (column.type == ColumnType.text) {
        if (text.length < 2 || text[0] != '\'' || text[$ - 1] != '\'')
            throw badRequest("Key must be a quoted string");
        return toSqlLiteral(parseLiteral(ColumnType.text, text));
    }
    try
        return toSqlLiteral(valueFromInput(ColumnType.integer, text));
    catch (Exception)
        throw badRequest("Key must be an integer");
}

/// Mit IEEE754Compatible=true sind Int64-Werte Text, weil JavaScript sie als Zahl nicht exakt darstellen kann.
string propertyJson(Value v, bool ieee754 = false) {
    if (isNull(v))
        return "null";
    if (ieee754 && v.peek!long)
        return `"` ~ valueText(v) ~ `"`;
    if (auto s = v.peek!string)
        return Json(*s).toString;
    return valueText(v); // nicht Json: dessen Ausgabe hat nur 16 Stellen
}

/// Eingehender Adapter: OData-4.0-Dienst unter /odata/v4 über ISqlUseCase. Tabellen sind Entity Sets.
/// Anmeldung und Rollen gelten wie überall, weil der Controller nur die abgesicherte Sicht auf den Kern sieht.
/// Eigene Routen statt registerRestInterface, weil OData-Pfade wie orders(1)/$value keine festen Muster sind.
final class ODataController {
    enum root = "/odata/v4";
    private ISqlUseCase sql;

    this(ISqlUseCase sql) {
        this.sql = sql;
    }

    void register(URLRouter router) {
        router.any(root, &dispatch);
        router.any(root ~ "/*", &dispatch);
    }

    private void dispatch(HTTPServerRequest req, HTTPServerResponse res) {
        res.headers["OData-Version"] = "4.0";
        try {
            checkVersion(req);
            route(req, res);
        } catch (ODataError e)
            writeError(res, e.status, e.code, e.msg);
        catch (AuthenticationRequired e)
            writeError(res, 401, "Unauthorized", e.msg);
        catch (AccessDenied e)
            writeError(res, 403, "Forbidden", e.msg);
        catch (HTTPStatusException e)
            writeError(res, e.status, "Error", e.msg);
        catch (Exception e)
            writeError(res, 400, "BadRequest", e.msg); // Meldungen des Kerns, etwa eine gesperrte Datenbank
    }

    private void route(HTTPServerRequest req, HTTPServerResponse res) {
        auto path = req.path[root.length .. $];
        if (path.startsWith("/"))
            path = path[1 .. $];

        if (path.length == 0)
            return serviceDocument(req, res);
        if (path == "$metadata") {
            onlyGet(req);
            return res.writeBody(metadataXml(tables()), "application/xml");
        }
        if (path == "$batch")
            throw notImplemented("$batch is not supported");

        auto resource = parseResourcePath(path);
        auto table = find(resource.entitySet);
        if (resource.hasKey)
            return entityRequest(req, res, table, resource);
        if (resource.segments == ["$count"]) {
            onlyGet(req);
            checkOptions(req);
            return res.writeBody(matching(table, whereOf(req, table)).to!string, "text/plain");
        }
        if (resource.segments.length)
            throw notFound("Unknown path segment: " ~ resource.segments[0]);

        switch (req.method) {
        case HTTPMethod.GET:
            return collection(req, res, table);
        case HTTPMethod.POST:
            return create(req, res, table);
        default:
            throw methodNotAllowed();
        }
    }

    private void entityRequest(HTTPServerRequest req, HTTPServerResponse res, TableStats table, ResourcePath resource) {
        auto key = keyColumn(table);
        if (key.length == 0)
            throw notImplemented("Table " ~ table.table ~ " has no id column, so single rows can't be addressed");
        auto column = table.columns.filter!(c => c.name == key).front;
        auto predicate = key ~ " = " ~ keyLiteral(column, resource.key);

        if (resource.segments.length) {
            onlyGet(req);
            return propertyRequest(req, res, table, predicate, resource);
        }
        switch (req.method) {
        case HTTPMethod.GET:
            checkOptions(req);
            return writeEntity(req, res, table, single(table, predicate), 200);
        case HTTPMethod.PATCH:
            return update(req, res, table, predicate, false);
        case HTTPMethod.PUT:
            return update(req, res, table, predicate, true);
        case HTTPMethod.DELETE:
            single(table, predicate);
            sql.execute("DELETE FROM " ~ table.table ~ " WHERE " ~ predicate);
            return noContent(res);
        default:
            throw methodNotAllowed();
        }
    }

    private void propertyRequest(HTTPServerRequest req, HTTPServerResponse res, TableStats table, string predicate,
        ResourcePath resource) {
        auto name = resource.segments[0];
        size_t index = size_t.max;
        foreach (i, c; table.columns)
            if (c.name == name)
                index = i;
        if (index == size_t.max)
            throw notFound("Unknown property: " ~ name);
        immutable raw = resource.segments.length == 2 && resource.segments[1] == "$value";
        if (resource.segments.length > 1 && !raw)
            throw notFound("Unknown path segment: " ~ resource.segments[1]);

        auto value = single(table, predicate)[index];
        if (isNull(value))
            return noContent(res); // laut Spezifikation 204 für eine Eigenschaft ohne Wert
        if (raw)
            return res.writeBody(valueText(value), "text/plain");
        res.writeBody(`{"@odata.context":` ~ Json(contextBase(req) ~ "#" ~ table.table ~ "/" ~ name).toString
                ~ `,"value":` ~ propertyJson(value, ieee754(req)) ~ "}", jsonTypeOf(req));
    }

    private void serviceDocument(HTTPServerRequest req, HTTPServerResponse res) {
        onlyGet(req);
        auto sets = tables().map!(t => `{"name":` ~ Json(t.table).toString ~ `,"kind":"EntitySet","url":`
                ~ Json(t.table).toString ~ "}").join(",");
        res.writeBody(`{"@odata.context":` ~ Json(contextBase(req)).toString ~ `,"value":[` ~ sets ~ "]}", jsonTypeOf(req));
    }

    private void collection(HTTPServerRequest req, HTTPServerResponse res, TableStats table) {
        checkOptions(req);
        auto selected = selection(req, table);
        auto where = whereOf(req, table);
        immutable skip = numberOption(req, "$skip", 0);
        immutable top = numberOption(req, "$top", size_t.max);
        immutable pageSize = min(top, maxPageSize);

        auto statement = "SELECT * FROM " ~ table.table ~ (where.length ? " WHERE " ~ where : "");
        auto order = req.query.get("$orderby", "").strip;
        if (order.length)
            statement ~= " ORDER BY " ~ orderByToSql(order, table.columns);
        immutable total = matching(table, where);
        Value[][] rows;
        if (pageSize > 0)
            rows = sql.execute(statement ~ " LIMIT " ~ pageSize.to!string ~ " OFFSET " ~ skip.to!string).rows;

        auto body_ = appender!string;
        body_ ~= `{"@odata.context":` ~ Json(contextOf(req, table, selected)).toString;
        if (req.query.get("$count", "") == "true")
            body_ ~= `,"@odata.count":` ~ (ieee754(req) ? `"` ~ total.to!string ~ `"` : total.to!string);
        body_ ~= `,"value":[`;
        foreach (i, row; rows) {
            if (i)
                body_ ~= ",";
            body_ ~= entityJson(table, row, selected, skip + i + 1, ieee754(req));
        }
        body_ ~= "]";
        immutable served = skip + rows.length;
        immutable wanted = top == size_t.max ? total : min(total, skip + top);
        if (rows.length && served < wanted)
            body_ ~= `,"@odata.nextLink":` ~ Json(nextLink(req, table, served, top == size_t.max ? top : top - rows.length)).toString;
        body_ ~= "}";
        res.writeBody(body_[], jsonTypeOf(req));
    }

    private void create(HTTPServerRequest req, HTTPServerResponse res, TableStats table) {
        auto entity = readEntity(req, table);
        auto key = keyColumn(table);
        string[] literals;
        string predicate;
        foreach (c; table.columns) {
            auto literal = c.name in entity ? jsonLiteral(c, entity[c.name]) : "NULL";
            if (c.name == key) {
                if (literal == "NULL")
                    throw badRequest("Key property is required: " ~ key);
                predicate = key ~ " = " ~ literal;
                if (matching(table, predicate))
                    throw conflict("An entity with this key already exists");
            }
            literals ~= literal;
        }
        sql.execute("INSERT INTO " ~ table.table ~ " VALUES (" ~ literals.join(", ") ~ ")");
        res.statusCode = 201;
        if (key.length == 0) { // keine Adresse, aber Clients erwarten die Entität: sie ist die letzte Zeile
            immutable position = matching(table, "");
            auto last = sql.execute("SELECT * FROM " ~ table.table ~ " LIMIT 1 OFFSET " ~ (position - 1).to!string).rows[0];
            return writeEntity(req, res, table, last, 201, position);
        }
        auto location = entityUrl(req, table, predicate[key.length + 3 .. $]);
        res.headers["Location"] = location;
        if (prefersMinimal(req)) {
            res.headers["OData-EntityId"] = location;
            res.headers["Preference-Applied"] = "return=minimal";
            return noContent(res);
        }
        writeEntity(req, res, table, single(table, predicate), 201);
    }

    /// PATCH ändert nur die angegebenen Eigenschaften, PUT setzt fehlende auf NULL. Der Schlüssel bleibt unverändert:
    /// die Spezifikation verlangt, ihn im Rumpf zu ignorieren.
    private void update(HTTPServerRequest req, HTTPServerResponse res, TableStats table, string predicate, bool replace) {
        auto entity = readEntity(req, table);
        single(table, predicate);
        auto key = keyColumn(table);
        string[] assignments;
        foreach (c; table.columns) {
            if (c.name == key)
                continue;
            if (c.name in entity)
                assignments ~= c.name ~ " = " ~ jsonLiteral(c, entity[c.name]);
            else if (replace)
                assignments ~= c.name ~ " = NULL";
        }
        if (assignments.length)
            sql.execute("UPDATE " ~ table.table ~ " SET " ~ assignments.join(", ") ~ " WHERE " ~ predicate);
        if (req.headers.get("Prefer", "").toLower.indexOf("return=representation") >= 0) {
            res.headers["Preference-Applied"] = "return=representation";
            return writeEntity(req, res, table, single(table, predicate), 200);
        }
        noContent(res);
    }

    /// Der Kern erzwingt keine Eindeutigkeit: ein Schlüssel kann mehrfach vorkommen, dann ist die Adresse mehrdeutig
    /// und eine Änderung würde mehrere Zeilen treffen.
    private Value[] single(TableStats table, string predicate) {
        auto rows = sql.execute("SELECT * FROM " ~ table.table ~ " WHERE " ~ predicate ~ " LIMIT 2").rows;
        if (rows.length == 0)
            throw notFound("No entity with this key");
        if (rows.length > 1)
            throw conflict("The key is not unique in table " ~ table.table);
        return rows[0];
    }

    private size_t matching(TableStats table, string where) {
        auto statement = "SELECT COUNT(*) FROM " ~ table.table ~ (where.length ? " WHERE " ~ where : "");
        return sql.execute(statement).rows[0][0].get!long.to!size_t;
    }

    private TableStats[] tables() {
        return sql.stats().filter!(isExposable).array;
    }

    private TableStats find(string name) {
        foreach (t; tables())
            if (t.table == name)
                return t;
        throw notFound("Unknown entity set: " ~ name);
    }

    private void writeEntity(HTTPServerRequest req, HTTPServerResponse res, TableStats table, Value[] row, int status,
        size_t position = 1) {
        auto selected = selection(req, table);
        auto body_ = entityJson(table, row, selected, position, ieee754(req));
        res.statusCode = status;
        res.writeBody(`{"@odata.context":` ~ Json(contextOf(req, table, selected) ~ "/$entity").toString ~ "," ~ body_[1 .. $], jsonTypeOf(req));
    }
}

private ODataError methodNotAllowed() {
    return new ODataError(405, "MethodNotAllowed", "Method not allowed");
}

private void onlyGet(HTTPServerRequest req) {
    if (req.method != HTTPMethod.GET && req.method != HTTPMethod.HEAD)
        throw methodNotAllowed();
}

private void noContent(HTTPServerResponse res) {
    res.statusCode = 204;
    res.writeVoidBody();
}

private void writeError(HTTPServerResponse res, int status, string code, string message) {
    res.statusCode = status;
    res.writeBody(`{"error":{"code":` ~ Json(code).toString ~ `,"message":` ~ Json(message).toString ~ "}}", "application/json");
}

private void checkVersion(HTTPServerRequest req) {
    auto version_ = req.headers.get("OData-MaxVersion", "").strip;
    if (version_.length && version_ != "4.0" && !version_.startsWith("4."))
        throw badRequest("This service speaks OData 4.0");
}

/// Prüft die Systemoptionen und das Format. Unbekanntes führt laut Spezifikation zu einem Fehler.
private void checkOptions(HTTPServerRequest req) {
    foreach (name, value; req.query.byKeyValue) {
        if (!name.startsWith("$"))
            continue; // eigene Optionen darf ein Dienst ignorieren
        if (["$expand", "$search", "$apply", "$compute", "$levels", "$index"].canFind(name))
            throw notImplemented(name ~ " is not supported");
        if (!["$filter", "$select", "$orderby", "$top", "$skip", "$count", "$format"].canFind(name))
            throw badRequest("Unknown system query option: " ~ name);
    }
    auto count = req.query.get("$count", "");
    if (count.length && count != "true" && count != "false")
        throw badRequest("$count must be true or false");
    auto format = req.query.get("$format", "");
    if (format.length && format != "json" && !format.startsWith("application/json"))
        throw new ODataError(406, "NotAcceptable", "Only JSON is available");
    auto accept = req.headers.get("Accept", "");
    if (format.length == 0 && accept.length && !["json", "*/*", "application/*"].any!(a => accept.indexOf(a) >= 0))
        throw new ODataError(406, "NotAcceptable", "Only JSON is available");
}

private string whereOf(HTTPServerRequest req, TableStats table) {
    auto text = req.query.get("$filter", "");
    return "$filter" in req.query ? filterToWhere(text, table.columns) : "";
}

private size_t numberOption(HTTPServerRequest req, string name, size_t fallback) {
    auto text = req.query.get(name, "");
    if (text.length == 0)
        return fallback;
    try
        return text.to!size_t;
    catch (Exception)
        throw badRequest(name ~ " must be a non-negative integer");
}

/// Ausgewählte Eigenschaften; leer bedeutet alle.
private string[] selection(HTTPServerRequest req, TableStats table) {
    auto text = req.query.get("$select", "").strip;
    if (text.length == 0 || text == "*")
        return null;
    string[] names;
    foreach (raw; text.split(",")) {
        auto name = raw.strip;
        if (!table.columns.any!(c => c.name == name))
            throw badRequest("Unknown property: " ~ name);
        names ~= name;
    }
    return names;
}

private string entityJson(TableStats table, Value[] row, string[] selected, size_t position, bool ieee) {
    string[] fields;
    if (keyColumn(table).length == 0 && selected.length == 0)
        fields ~= `"` ~ rowIdProperty ~ `":` ~ propertyJson(Value(cast(long) position), ieee);
    foreach (i, c; table.columns)
        if (selected.length == 0 || selected.canFind(c.name))
            fields ~= Json(c.name).toString ~ ":" ~ propertyJson(row[i], ieee);
    return "{" ~ fields.join(",") ~ "}";
}

/// Liest den Rumpf einer Entität. Annotationen wie @odata.type werden übersprungen.
private Json[string] readEntity(HTTPServerRequest req, TableStats table) {
    Json document;
    try
        document = parseJsonString(req.bodyReader.readAllUTF8());
    catch (Exception)
        throw badRequest("Request body must be JSON");
    if (document.type != Json.Type.object)
        throw badRequest("Request body must be a JSON object");
    Json[string] entity;
    foreach (string name, value; document) {
        if (name.indexOf('@') >= 0 || name == rowIdProperty)
            continue;
        auto column = table.columns.filter!(c => c.name == name);
        if (column.empty)
            throw badRequest("Unknown property: " ~ name);
        if (ieee754(req) && column.front.type == ColumnType.integer && value.type == Json.Type.string) {
            try
                value = Json(value.get!string.to!long);
            catch (Exception)
                throw badRequest("Property " ~ name ~ " expects an integer");
        }
        entity[name] = value;
    }
    return entity;
}

private bool ieee754(HTTPServerRequest req) {
    return [req.headers.get("Accept", ""), req.headers.get("Content-Type", ""), req.query.get("$format", "")]
        .any!(h => h.toLower.indexOf("ieee754compatible=true") >= 0);
}

private string jsonTypeOf(HTTPServerRequest req) {
    return jsonBase ~ (ieee754(req) ? "true" : "false");
}

private bool prefersMinimal(HTTPServerRequest req) {
    return req.headers.get("Prefer", "").toLower.indexOf("return=minimal") >= 0;
}

private string serviceRoot(HTTPServerRequest req) {
    immutable https = req.tls || req.headers.get("X-Forwarded-Proto", "") == "https";
    return (https ? "https://" : "http://") ~ req.host ~ ODataController.root ~ "/";
}

private string contextBase(HTTPServerRequest req) {
    return serviceRoot(req) ~ "$metadata";
}

private string contextOf(HTTPServerRequest req, TableStats table, string[] selected) {
    return contextBase(req) ~ "#" ~ table.table ~ (selected.length ? "(" ~ selected.join(",") ~ ")" : "");
}

private string entityUrl(HTTPServerRequest req, TableStats table, string keyLiteralText) {
    return serviceRoot(req) ~ table.table ~ "(" ~ keyLiteralText ~ ")";
}

/// Link auf die nächste Seite: alle Optionen bleiben, $skip und $top werden fortgeschrieben.
private string nextLink(HTTPServerRequest req, TableStats table, size_t skip, size_t top) {
    string[] parts;
    foreach (name, value; req.query.byKeyValue)
        if (name != "$skip" && name != "$top")
            parts ~= name ~ "=" ~ urlEncode(value);
    parts ~= "$skip=" ~ skip.to!string;
    if (top != size_t.max)
        parts ~= "$top=" ~ top.to!string;
    return serviceRoot(req) ~ table.table ~ "?" ~ parts.join("&");
}

unittest {
    import std.exception : assertThrown;

    auto r = parseResourcePath("orders");
    assert(r.entitySet == "orders" && !r.hasKey && r.segments.length == 0);
    r = parseResourcePath("orders/$count");
    assert(r.segments == ["$count"]);
    r = parseResourcePath("orders(1)");
    assert(r.hasKey && r.key == "1");
    r = parseResourcePath("orders('a/b)c''d')/name/$value");
    assert(r.key == "'a/b)c''d'" && r.segments == ["name", "$value"]);
    assertThrown(parseResourcePath("orders(1"));
    assertThrown(parseResourcePath("orders(1)x"));

    ColumnStats id, code;
    id.name = "id";
    id.type = ColumnType.integer;
    code.name = "id";
    code.type = ColumnType.text;
    assert(keyLiteral(id, "5") == "5" && keyLiteral(id, "id=5") == "5" && keyLiteral(id, " -5 ") == "-5");
    assert(keyLiteral(code, "'a''b'") == "'a''b'");
    assert(keyLiteral(code, "id='a=b'") == "'a=b'");
    assert(keyLiteral(code, "'a=b'") == "'a=b'");
    assertThrown(keyLiteral(id, "1 OR 1=1"));
    assertThrown(keyLiteral(id, "x=1"));
    assertThrown(keyLiteral(code, "a"));

    assert(propertyJson(Value(123456789012345678.0)) == "1.2345678901234568e+17");
    assert(propertyJson(nullValue) == "null" && propertyJson(Value("a\"b")) == `"a\"b"`);
    assert(propertyJson(Value(long.max)) == "9223372036854775807");
    assert(propertyJson(Value(long.max), true) == `"9223372036854775807"`);
    assert(propertyJson(Value(1.5), true) == "1.5"); // Edm.Double bleibt eine Zahl
}
