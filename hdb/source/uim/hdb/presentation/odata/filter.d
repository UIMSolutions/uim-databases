module uim.hdb.presentation.odata.filter;

import uim.hdb;
import std.algorithm : all, canFind;
import std.array : array, join, replace, split;
import std.ascii : isDigit;
import std.conv : ConvException, to;
import std.regex : ctRegex, matchFirst;
import std.string : indexOf, strip;
import std.uni : isAlphaNum;

/// Translates an OData-$filter into a WHERE clause. The text is never passed through as-is: it is parsed into a tree
/// and regenerated, with properties checked against the schema and literals checked against the column type.
///
/// Unlike SQL, OData 4.0 uses two-valued comparisons here: `a ne 1` is true for NULL, `a gt 1` is false, and
/// `not (a gt 1)` is therefore true again. The renderer adds `OR a IS NULL` to account for this; a direct translation would
/// silently omit these lines.
string filterToWhere(string text, ColumnStats[] columns) {
    auto parser = Parser(tokenize(text), columns);
    auto node = parser.parseOr();
    if (parser.pos != parser.tokens.length)
        throw badRequest("Unexpected token in $filter: " ~ parser.tokens[parser.pos].text);
    return render(node, false);
}

/// Translates $orderby into an ORDER-BY list.
string orderByToSql(string text, ColumnStats[] columns) {
    string[] keys;
    foreach (raw; text.split(",")) {
        auto parts = raw.strip.split();
        if (parts.length == 0 || parts.length > 2 || (parts.length == 2 && parts[1] != "asc" && parts[1] != "desc"))
            throw badRequest("Invalid $orderby: " ~ raw.strip);
        findColumn(columns, parts[0]);
        keys ~= parts[0] ~ (parts.length == 2 && parts[1] == "desc" ? " DESC" : " ASC");
    }
    return keys.join(", ");
}

private ColumnStats findColumn(ColumnStats[] columns, string name) {
    foreach (c; columns)
        if (c.name == name)
            return c;
    throw badRequest("Unknown property: " ~ name);
}

private enum TokenKind {
    word,
    text,
    number,
    bare, /// Literal ohne Anführungszeichen: true, 2026-11-06, 12:30:00, GUIDs
    typed, /// Literal mit Präfix: duration'P1D', binary'AA', geometry'Point(1 2)'
    open,
    close,
    comma
}

private struct Token {
    TokenKind kind;
    string text;
    string prefix;
}

private Token[] tokenize(string s) {
    Token[] tokens;
    size_t i;
    while (i < s.length) {
        immutable c = s[i];
        if (c == ' ' || c == '\t') {
            ++i;
        } else if (c == '(') {
            tokens ~= Token(TokenKind.open, "(");
            ++i;
        } else if (c == ')') {
            tokens ~= Token(TokenKind.close, ")");
            ++i;
        } else if (c == ',') {
            tokens ~= Token(TokenKind.comma, ",");
            ++i;
        } else if (c == '\'') {
            string value;
            size_t j = i + 1;
            while (true) {
                if (j >= s.length)
                    throw badRequest("Unterminated string in $filter");
                if (s[j] == '\'') {
                    if (j + 1 < s.length && s[j + 1] == '\'') {
                        value ~= '\'';
                        j += 2;
                        continue;
                    }
                    break;
                }
                value ~= s[j++];
            }
            tokens ~= Token(TokenKind.text, value);
            i = j + 1;
        } else {
            size_t j = i;
            while (j < s.length && !" \t(),'".canFind(s[j]))
                ++j;
            auto word = s[i .. j];
            immutable numeric = !matchFirst(word, ctRegex!(`^-?\d+(\.\d+)?([eE][+-]?\d+)?$`)).empty;
            tokens ~= Token(numeric ? TokenKind.number : TokenKind.word, word);
            i = j;
        }
    }
    return tokens;
}

private enum NodeKind {
    and,
    or,
    not,
    compare,
    like
}

private final class Node {
    NodeKind kind;
    Node[] kids;
    string column, op, literal; // compare: literal ist ein SQL-Literal oder NULL; like: literal ist das Muster
}

private struct Operand {
    bool isColumn;
    ColumnStats column;
    Token token;
    bool isNull;
}

private struct Parser {
    Token[] tokens;
    ColumnStats[] columns;
    size_t pos;

    private bool atWord(string word) {
        return pos < tokens.length && tokens[pos].kind == TokenKind.word && tokens[pos].text == word;
    }

    Node parseOr() {
        Node[] kids = [parseAnd()];
        while (atWord("or")) {
            ++pos;
            kids ~= parseAnd();
        }
        return kids.length == 1 ? kids[0] : group(NodeKind.or, kids);
    }

    private Node parseAnd() {
        Node[] kids = [parseUnary()];
        while (atWord("and")) {
            ++pos;
            kids ~= parseUnary();
        }
        return kids.length == 1 ? kids[0] : group(NodeKind.and, kids);
    }

    private Node parseUnary() {
        if (atWord("not")) {
            ++pos;
            return group(NodeKind.not, [parseUnary()]);
        }
        return parsePrimary();
    }

    private Node parsePrimary() {
        if (pos >= tokens.length)
            throw badRequest("Incomplete $filter");
        if (tokens[pos].kind == TokenKind.open) {
            ++pos;
            auto node = parseOr();
            expect(TokenKind.close, ")");
            return node;
        }
        if (tokens[pos].kind == TokenKind.word && pos + 1 < tokens.length && tokens[pos + 1].kind == TokenKind
            .open)
            return parseFunction();

        auto left = parseOperand();
        if (pos >= tokens.length || tokens[pos].kind != TokenKind.word)
            throw badRequest("Comparison operator expected in $filter");
        auto op = tokens[pos++].text;
        if (!["eq", "ne", "gt", "ge", "lt", "le"].canFind(op))
            throw notImplemented("Operator not supported in $filter: " ~ op);
        auto right = parseOperand();
        return compare(left, op, right);
    }

    private Operand parseOperand() {
        if (pos >= tokens.length)
            throw badRequest("Incomplete $filter");
        auto t = tokens[pos++];
        final switch (t.kind) {
        case TokenKind.text:
        case TokenKind.number:
        case TokenKind.bare:
        case TokenKind.typed:
            return Operand(false, ColumnStats.init, t, false);
        case TokenKind.word:
            if (t.text == "null")
                return Operand(false, ColumnStats.init, t, true);
            if (literalPrefixes.canFind(t.text) && pos < tokens.length && tokens[pos].kind == TokenKind
                .text)
                return Operand(false, ColumnStats.init, Token(TokenKind.typed, tokens[pos++].text, t
                        .text), false);
            if (isBareLiteral(t.text))
                return Operand(false, ColumnStats.init, Token(TokenKind.bare, t.text), false);
            return Operand(true, findColumn(columns, t.text), t, false);
        case TokenKind.open:
        case TokenKind.close:
        case TokenKind.comma:
            throw badRequest("Operand expected in $filter, found " ~ t.text);
        }
    }

    private Node compare(Operand left, string op, Operand right) {
        if (left.isColumn == right.isColumn)
            throw notImplemented("$filter compares a property with a literal");
        if (!left.isColumn) { // 5 lt a  ==  a gt 5
            auto swapped = [
                "lt": "gt", "gt": "lt", "le": "ge", "ge": "le", "eq": "eq",
                "ne": "ne"
            ];
            return compare(right, swapped[op], left);
        }
        auto node = new Node;
        node.kind = NodeKind.compare;
        node.column = left.column.name;
        node.op = op;
        if (right.isNull) {
            if (op != "eq" && op != "ne")
                throw badRequest("null can only be compared with eq or ne");
            node.literal = "NULL";
        } else
            node.literal = typedLiteral(left.column, right.token);
        return node;
    }

    private Node parseFunction() {
        auto name = tokens[pos].text;
        if (!["contains", "startswith", "endswith"].canFind(name))
            throw notImplemented("Function not supported in $filter: " ~ name);
        pos += 2;
        if (pos >= tokens.length || tokens[pos].kind != TokenKind.word)
            throw badRequest(name ~ " expects a property");
        auto column = findColumn(columns, tokens[pos++].text);
        if (edmType(column.type) != "Edm.String")
            throw badRequest(name ~ " needs a text property: " ~ column.name);
        expect(TokenKind.comma, ",");
        if (pos >= tokens.length || tokens[pos].kind != TokenKind.text)
            throw badRequest(name ~ " expects a string");
        auto needle = escapeLike(tokens[pos++].text);
        expect(TokenKind.close, ")");

        auto node = new Node;
        node.kind = NodeKind.like;
        node.column = column.name;
        node.literal = name == "contains" ? "%" ~ needle ~ "%" : name == "startswith" ? needle ~ "%" : "%" ~ needle;
        return node;
    }

    private void expect(TokenKind kind, string text) {
        if (pos >= tokens.length || tokens[pos].kind != kind)
            throw badRequest("Expected " ~ text ~ " in $filter");
        ++pos;
    }
}

private Node group(NodeKind kind, Node[] kids) {
    auto node = new Node;
    node.kind = kind;
    node.kids = kids;
    return node;
}

private enum literalPrefixes = ["duration", "binary", "geometry", "geography"];

/// Bezeichner beginnen nie mit einer Ziffer und enthalten kein -, Spalten sind also nicht zu verwechseln.
private bool isBareLiteral(string word) {
    return word == "true" || word == "false" || isDigit(word[0]) || word.indexOf('-') >= 0;
}

/// Prüft die Form eines Literals gegen den Spaltentyp; der Text selbst ist noch ungeprüft.
private string typedLiteral(ColumnStats column, Token token) {
    void expect(TokenKind kind, string what, string prefix = "") {
        if (token.kind != kind || token.prefix != prefix)
            throw badRequest("Property " ~ column.name ~ " expects " ~ what);
    }

    auto text = token.text;
    try {
        switch (column.type) {
        case ColumnType.text:
        case ColumnType.link:
            expect(TokenKind.text, "a string");
            break;
        case ColumnType.blob:
            expect(TokenKind.typed, "binary'...'", "binary");
            text = base64UrlToHex(text);
            break;
        case ColumnType.duration:
            expect(TokenKind.typed, "duration'...'", "duration");
            break;
        case ColumnType.geo:
        case ColumnType.geography:
            immutable prefix = column.type == ColumnType.geo ? "geometry" : "geography";
            expect(TokenKind.typed, prefix ~ "'...'", prefix);
            auto srid = matchFirst(text, ctRegex!(`^SRID=\d+;`, "i"));
            if (!srid.empty)
                text = srid.post;
            break;
        case ColumnType.boolean:
        case ColumnType.date:
        case ColumnType.dateTime:
        case ColumnType.time:
        case ColumnType.guid:
            expect(TokenKind.bare, "an unquoted " ~ edmType(column.type));
            break;
        default:
            expect(TokenKind.number, "a number");
            if (isIntegerType(column.type) && !text.all!(c => isDigit(c) || c == '-'))
                throw badRequest("Property " ~ column.name ~ " expects an integer");
            break;
        }
        return toSqlLiteral(valueFromInput(column.type, text));
    } catch (ODataError e)
        throw e;
    catch (Exception e)
        throw badRequest(e.msg);
}

private string escapeLike(string text) {
    return text.replace(`\`, `\\`).replace("%", `\%`).replace("_", `\_`);
}

private string render(Node node, bool negated) {
    final switch (node.kind) {
    case NodeKind.not:
        return render(node.kids[0], !negated);
    case NodeKind.and:
    case NodeKind.or:
        // De Morgan: der Kern kennt kein allgemeines NOT
        immutable conjunction = (node.kind == NodeKind.and) != negated;
        string[] parts;
        foreach (kid; node.kids)
            parts ~= render(kid, negated);
        return "(" ~ parts.join(conjunction ? " AND " : " OR ") ~ ")";
    case NodeKind.like:
        auto pattern = toSqlLiteral(Value(node.literal));
        return negated ? "(" ~ node.column ~ " NOT LIKE " ~ pattern ~ ` ESCAPE '\' OR ` ~ node.column ~ " IS NULL)"
            : node.column ~ " LIKE " ~ pattern ~ ` ESCAPE '\'`;
    case NodeKind.compare:
        return renderCompare(node, negated);
    }
}

private string renderCompare(Node node, bool negated) {
    auto c = node.column;
    if (node.literal == "NULL")
        return c ~ ((node.op == "eq") != negated ? " IS NULL" : " IS NOT NULL");
    auto op = negated ? [
        "eq": "ne",
        "ne": "eq",
        "gt": "le",
        "ge": "lt",
        "lt": "ge",
        "le": "gt"
    ][node.op] : node.op;
    immutable sqlOp = [
        "eq": "=",
        "ne": "!=",
        "gt": ">",
        "ge": ">=",
        "lt": "<",
        "le": "<="
    ][op];
    auto comparison = c ~ " " ~ sqlOp ~ " " ~ node.literal;
    immutable matchesNull = op == "ne" || (negated && node.op != "ne");
    return matchesNull ? "(" ~ comparison ~ " OR " ~ c ~ " IS NULL)" : comparison;
}

unittest {
    import uim.hdb;
    import std.algorithm : map, sort;
    import std.exception : collectException;

    auto sql = new SqlService(new MemoryTableRepository);
    sql.execute("CREATE TABLE t (id INTEGER, n VARCHAR, w DECIMAL)");
    sql.execute("INSERT INTO t VALUES (1, 'apple', 1.5)");
    sql.execute("INSERT INTO t VALUES (2, 'a_b', 2)");
    sql.execute("INSERT INTO t VALUES (3, 'axb', 3)");
    sql.execute("INSERT INTO t VALUES (4, '100%', NULL)");
    sql.execute("INSERT INTO t VALUES (5, NULL, 5)");
    sql.execute("INSERT INTO t VALUES (6, 'it''s AND x', 6)");
    sql.execute("INSERT INTO t VALUES (7, 'back\\slash', 7)");
    auto columns = sql.stats()[0].columns;

    long[] ids(string filter) {
        auto rows = sql.execute("SELECT id FROM t WHERE " ~ filterToWhere(filter, columns) ~ " ORDER BY id")
            .rows;
        return rows.map!(r => r[0].get!long).array;
    }

    int status(string filter) {
        auto e = collectException!ODataError(filterToWhere(filter, columns));
        return e is null ? 0 : e.status;
    }

    // Vergleiche, auch mit vertauschten Operanden
    assert(ids("id eq 2") == [2]);
    assert(ids("id gt 5") == [6, 7]);
    assert(ids("5 lt id") == [6, 7]);
    assert(ids("w le 2") == [1, 2]);
    assert(ids("n eq 'apple'") == [1]);
    assert(ids("n eq 'it''s AND x'") == [6]);
    assert(ids("id eq 1 or id eq 3 and n eq 'axb'") == [1, 3]);
    assert(ids("(id eq 1 or id eq 3) and n eq 'axb'") == [3]);

    // NULL nach OData 4.0: ne und not treffen NULL, gt nicht
    assert(ids("n eq null") == [5]);
    assert(ids("null eq n") == [5]);
    assert(ids("n ne null") == [1, 2, 3, 4, 6, 7]);
    assert(ids("w ne 2") == [1, 3, 4, 5, 6, 7]);
    assert(ids("w gt 4") == [5, 6, 7]);
    assert(ids("not (w gt 4)") == [1, 2, 3, 4]);
    assert(ids("not (w eq 2)") == ids("w ne 2"));
    assert(ids("not (w ne 2)") == [2]);
    assert(ids("not (n eq null)") == ids("n ne null"));

    // De Morgan
    assert(ids("not (id lt 3 or id gt 5)") == [3, 4, 5]);
    assert(ids("not (id ge 3 and id le 5)") == [1, 2, 6, 7]);
    assert(ids("not not (id eq 1)") == [1]);

    // Funktionen: % und _ sind Zeichen, keine Platzhalter
    assert(ids("startswith(n,'a')") == [1, 2, 3]);
    assert(ids("endswith(n,'b')") == [2, 3]);
    assert(ids("contains(n,'a_b')") == [2]);
    assert(ids("contains(n,'%')") == [4]);
    assert(ids("contains(n,'\\')") == [7]);
    assert(ids("contains(n,'''')") == [6]);
    assert(ids("not contains(n,'a')") == [4, 5, 6]);

    // Injektion: der Text bleibt Literal oder wird abgelehnt
    assert(ids("n eq 'x'' OR ''1''=''1'") == []);
    assert(status("id eq 1 OR 1 eq 1") == 400);
    assert(status("id eq 1; DROP TABLE t") == 400);
    assert(status("id eq 1) OR (id ne 1") == 400);
    assert(status("nope eq 1") == 400);
    assert(status("id eq 'x'") == 400);
    assert(status("n eq 1") == 400);
    assert(status("id eq 1.5") == 400);
    assert(status("id gt null") == 400);
    assert(status("id eq true") == 400);
    assert(status("id eq") == 400);
    assert(status("") == 400);
    assert(status("n eq 'open") == 400);
    assert(status("contains(id,'1')") == 400);

    // Was fehlt, meldet 501
    assert(status("tolower(n) eq 'a'") == 501);
    assert(status("id add 1 eq 2") == 501);
    assert(status("id eq w") == 501);
    assert(status("1 eq 1") == 501);

    assert(orderByToSql("n desc, id", columns) == "n DESC, id ASC");
    assert(collectException!ODataError(orderByToSql("nope", columns)).status == 400);
    assert(collectException!ODataError(orderByToSql("n up", columns)).status == 400);
    assert(collectException!ODataError(orderByToSql("n; DROP", columns)).status == 400);
}

unittest {
    import uim.hdb;
    import std.exception : collectException;

    auto sql = new SqlService(new MemoryTableRepository);
    sql.execute(
        "CREATE TABLE t (id INT32, f BOOLEAN, x NUMERIC, r REAL, d DATE, ts TIMESTAMP, tm TIME, du DURATION, u GUID,
        b BLOB, g GEO, w GEOGRAPHY, l LINK)".replace("\n", " "));
    sql.execute(
        "INSERT INTO t VALUES (1, true, 1.50, 0.5, '2026-11-06', '2026-11-06T12:00:00+01:00', '12:30:00', 'PT36H',
        '01234567-89AB-CDEF-0123-456789ABCDEF', X'FBFF', 'POINT(1 2)', 'POINT(13.4 52.5)', 'https://example.org/x')"
            .replace("\n", " "));
    auto columns = sql.stats()[0].columns;

    bool hit(string filter) {
        return sql.execute("SELECT id FROM t WHERE " ~ filterToWhere(filter, columns)).rows.length == 1;
    }

    foreach (filter; [
            "f eq true", "not (f eq false)", "x eq 1.5",
            "x gt 1.49999999999999999999", "r eq 0.5", "d eq 2026-11-06",
            "d lt 2026-11-07", "ts eq 2026-11-06T11:00:00Z",
            "ts lt 2026-11-06T12:00:00Z", "tm ge 12:30:00",
            "du eq duration'P1DT12H'", "du gt duration'PT1H'",
            "u eq 01234567-89ab-cdef-0123-456789abcdef",
            "b eq binary'-_8'", "g eq geometry'SRID=0;Point(1 2)'",
            "w eq geography'SRID=4326;Point(13.4 52.5)'",
            "l eq 'https://example.org/x'", "contains(l,'example')",
            "2026-11-05 lt d"
        ])
        assert(hit(filter), filter);
    assert(!hit("f eq false") && !hit("d gt 2026-11-06"));

    foreach (bad; [
            "f eq 'true'", "f eq 1", "x eq 'a'", "d eq '2026-11-06'",
            "d eq 2026-13-01", "ts eq 2026-11-06",
            "du eq 'P1D'", "du eq duration'P1Y'", "u eq 'x'", "u eq 1-2",
            "b eq 'FBFF'", "b eq binary'a+'",
            "g eq 'POINT(1 2)'", "g eq geography'Point(1 2)'",
            "w eq geography'Point(200 0)'",
            "l eq 'javascript:alert(1)'", "contains(b,'FB')",
            "contains(g,'POINT')", "contains(d,'2026')"
        ]) {
        auto e = collectException!ODataError(filterToWhere(bad, columns));
        assert(e !is null && e.status == 400, bad);
    }
}
