module uim.hdb.presentation.odata.model;

import uim.hdb;

enum schemaNamespace = "hdb";

/// Alternative key for tables without an `id`: the position in the result set. An entity requires a key in OData,
/// but this key is not stable and therefore cannot be used to address the entity.
enum rowIdProperty = "__rowid";

/// The column `id` is the key, otherwise there is none; empty if the table has no such column.
/// Only integers, text, and GUIDs are suitable as keys; decimals, for example, are not due to rounding.
string keyColumn(TableStats table) {
    foreach (c; table.columns)
        if (icmp(c.name, "id") == 0 && (isIntegerType(c.type) || c.type == ColumnType.text || c.type == ColumnType.guid))
            return c.name;
    return "";
}

/// Facets of a type. Without them, the default would apply: Scale 0 would be an integer, Precision 0 whole seconds.
private string facets(ColumnType type) {
    if (type == ColumnType.exact)
        return ` Scale="variable"`;
    if (type == ColumnType.dateTime || type == ColumnType.time || type == ColumnType.duration)
        return ` Precision="7"`;
    return "";
}

/// Tabellen, die sich als gültige CSDL darstellen lassen. Der Kern erlaubt Namen wie `1a`, OData nicht;
/// eine einzige solche Tabelle würde sonst das gesamte $metadata-Dokument ungültig machen.
bool isExposable(TableStats table) {
    return isSimpleIdentifier(table.table)
        && table.columns.all!(c => isSimpleIdentifier(c.name) && c.name != rowIdProperty);
}

bool isSimpleIdentifier(string name) {
    if (name.length == 0)
        return false;
    bool first = true;
    foreach (dchar c; name) {
        if (!(c == '_' || (first ? isAlpha(c) : isAlphaNum(c))))
            return false;
        first = false;
    }
    return true;
}

/// CSDL-Dokument für $metadata. Namen sind geprüfte Bezeichner, sie brauchen keine XML-Maskierung.
string metadataXml(TableStats[] tables) {
    auto x = appender!string;
    x ~= `<?xml version="1.0" encoding="utf-8"?>` ~ "\n";
    x ~= `<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx">` ~ "\n";
    x ~= "<edmx:DataServices>\n";
    x ~= `<Schema Namespace="` ~ schemaNamespace ~ `" xmlns="http://docs.oasis-open.org/odata/ns/edm">` ~ "\n";
    foreach (t; tables) {
        auto key = keyColumn(t);
        x ~= `<EntityType Name="` ~ t.table ~ `"><Key><PropertyRef Name="`
            ~ (key.length ? key : rowIdProperty) ~ `"/></Key>` ~ "\n";
        if (key.length == 0)
            x ~= `<Property Name="` ~ rowIdProperty ~ `" Type="Edm.Int64" Nullable="false"/>` ~ "\n";
        foreach (c; t.columns)
            x ~= `<Property Name="` ~ c.name ~ `" Type="` ~ edmType(c.type) ~ `"` ~ facets(c.type)
                ~ (c.name == key ? ` Nullable="false"` : "") ~ "/>\n";
        x ~= "</EntityType>\n";
    }
    x ~= "<EntityContainer Name=\"Container\">\n";
    foreach (t; tables)
        x ~= `<EntitySet Name="` ~ t.table ~ `" EntityType="` ~ schemaNamespace ~ "." ~ t.table ~ `"/>` ~ "\n";
    x ~= "</EntityContainer>\n</Schema>\n</edmx:DataServices>\n</edmx:Edmx>\n";
    return x[];
}

unittest {
    import std.string : indexOf;

    ColumnStats id, name;
    id.name = "ID";
    id.type = ColumnType.integer;
    name.name = "name";
    name.type = ColumnType.text;
    auto keyed = TableStats("orders", 0, 0, [id, name]);
    auto keyless = TableStats("logs", 0, 0, [name]);

    assert(keyColumn(keyed) == "ID" && keyColumn(keyless) == "");
    foreach (type; [ColumnType.decimal, ColumnType.blob, ColumnType.geo, ColumnType.link]) {
        id.type = type;
        assert(keyColumn(TableStats("d", 0, 0, [id])) == "");
    }
    foreach (type; [ColumnType.int32, ColumnType.guid, ColumnType.text]) {
        id.type = type;
        assert(keyColumn(TableStats("d", 0, 0, [id])) == "ID");
    }
    id.type = ColumnType.exact;
    assert(metadataXml([TableStats("d", 0, 0, [id])]).indexOf(`Type="Edm.Decimal" Scale="variable"`) > 0);
    id.type = ColumnType.dateTime;
    assert(metadataXml([TableStats("d", 0, 0, [id])]).indexOf(`Type="Edm.DateTimeOffset" Precision="7"`) > 0);
    id.type = ColumnType.integer;

    auto xml = metadataXml([keyed, keyless]);
    assert(xml.indexOf(`<EntityType Name="orders"><Key><PropertyRef Name="ID"/></Key>`) > 0);
    assert(xml.indexOf(`<Property Name="ID" Type="Edm.Int64" Nullable="false"/>`) > 0);
    assert(xml.indexOf(`<PropertyRef Name="__rowid"/>`) > 0);
    assert(xml.indexOf(`<EntitySet Name="logs" EntityType="hdb.logs"/>`) > 0);

    assert(isSimpleIdentifier("a_1") && isSimpleIdentifier("_a") && isSimpleIdentifier("größe"));
    assert(!isSimpleIdentifier("1a") && !isSimpleIdentifier("") && !isSimpleIdentifier("a-b"));
    assert(!isExposable(TableStats("1a", 0, 0, [name])));
}
