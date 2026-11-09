/// Loads AppConfig. Precedence, lowest to highest:
///   1. built-in defaults (AppConfig field initialisers)
///   2. config file, `config/default.json` or the path in OBJECT_CONFIG_FILE
///   3. environment: PORT (set by Cloud Foundry), OBJECT_DATABASE_NAME, OBJECT_HOST,
///      OBJECT_PORT, OBJECT_LOG_LEVEL, OBJECT_DEFAULT_COLLECTION
///   4. VCAP_SERVICES: `credentials` of the service instance named or tagged "object-config"
/// Every source uses the keys databaseName, host, port, logLevel and defaultCollection.
module uim.databases.object.infrastructure.configuration.loader;

import uim.databases.object.infrastructure.configuration.settings;
import std.algorithm : canFind;
import std.conv : ConvException, to;
import std.file : exists, readText;
import std.process : environment;
import vibe.data.json : Json, JSONException, parseJsonString;

@safe:

enum string defaultConfigFile = "config/default.json";
enum string vcapServiceName = "object-config";

/// Reads the config file and the process environment.
/// Throws: ConfigurationException for unreadable or invalid values.
AppConfig loadConfiguration() {
  auto env = environment.toAA();
  immutable path = env.get("OBJECT_CONFIG_FILE", defaultConfigFile);
  string fileContent;
  if (exists(path)) {
    fileContent = readText(path);
  } else if ("OBJECT_CONFIG_FILE" in env) {
    throw new ConfigurationException("Config file not found: " ~ path);
  }
  return resolveConfiguration(fileContent, env, path);
}

/// Pure resolution from already-read sources (used by loadConfiguration and the tests).
AppConfig resolveConfiguration(string fileContent, const string[string] env, string fileName = defaultConfigFile) {
  AppConfig config;
  if (fileContent.length > 0) {
    apply(config, parse(fileContent, fileName), fileName);
  }

  if (auto port = "PORT" in env) {
    config.port = toPort(*port, "PORT");
  }
  if (auto value = "OBJECT_DATABASE_NAME" in env) {
    config.databaseName = *value;
  }
  if (auto value = "OBJECT_HOST" in env) {
    config.host = *value;
  }
  if (auto value = "OBJECT_PORT" in env) {
    config.port = toPort(*value, "OBJECT_PORT");
  }
  if (auto value = "OBJECT_LOG_LEVEL" in env) {
    config.logLevel = *value;
  }
  if (auto value = "OBJECT_DEFAULT_COLLECTION" in env) {
    config.defaultCollection = *value;
  }

  if (auto vcap = "VCAP_SERVICES" in env) {
    applyVcapServices(config, parse(*vcap, "VCAP_SERVICES"));
  }
  return config;
}

private Json parse(string content, string source) {
  try {
    auto json = parseJsonString(content, source);
    if (json.type != Json.Type.object) {
      throw new ConfigurationException(source ~ " must contain a JSON object");
    }
    return json;
  } catch (JSONException e) {
    throw new ConfigurationException("Invalid JSON in " ~ source ~ ": " ~ e.msg);
  }
}

private void applyVcapServices(ref AppConfig config, Json services) {
  foreach (label, instances; services.byKeyValue) {
    if (instances.type != Json.Type.array) {
      continue;
    }
    foreach (instance; instances.byValue) {
      if (instance.type == Json.Type.object && isConfigService(instance)) {
        auto credentials = member(instance, "credentials");
        if (credentials.type == Json.Type.object) {
          apply(config, credentials, "VCAP_SERVICES (" ~ label ~ ")");
        }
        return;
      }
    }
  }
}

private bool isConfigService(Json instance) {
  auto name = member(instance, "name");
  if (name.type == Json.Type.string && name.get!string == vcapServiceName) {
    return true;
  }
  auto tags = member(instance, "tags");
  if (tags.type == Json.Type.array) {
    foreach (tag; tags.byValue) {
      if (tag.type == Json.Type.string && tag.get!string == vcapServiceName) {
        return true;
      }
    }
  }
  return false;
}

/// Member of a JSON object, or undefined. (Indexing a mutable Json object would add the missing key.)
private Json member(Json object, string key) {
  auto found = key in object;
  return found is null ? Json.undefined : *found;
}

private void apply(ref AppConfig config, Json values, string source) {
  foreach (key, value; values.byKeyValue) {
    switch (key) {
      case "databaseName":
        config.databaseName = text(value, key, source);
        break;
      case "host":
        config.host = text(value, key, source);
        break;
      case "logLevel":
        config.logLevel = text(value, key, source);
        break;
      case "defaultCollection":
        config.defaultCollection = text(value, key, source);
        break;
      case "port":
        config.port = value.type == Json.Type.int_
          ? toPort(value.get!long.to!string, source ~ ".port")
          : toPort(text(value, key, source), source ~ ".port");
        break;
      default:
        break; // unknown keys are ignored so one file can serve several services
    }
  }
}

private string text(Json value, string key, string source) {
  if (value.type != Json.Type.string) {
    throw new ConfigurationException(source ~ "." ~ key ~ " must be a string");
  }
  return value.get!string;
}

private ushort toPort(string value, string source) {
  try {
    immutable port = value.to!ushort;
    if (port == 0) {
      throw new ConfigurationException(source ~ " must be between 1 and 65535");
    }
    return port;
  } catch (ConvException) {
    throw new ConfigurationException(source ~ " is not a port number: '" ~ value ~ "'");
  }
}

unittest {
  import std.exception : assertThrown;

  assert(resolveConfiguration("", null) == AppConfig.init);

  auto fromFile = resolveConfiguration(`{"databaseName":"file","port":9000,"comment":"ignored"}`, null);
  assert(fromFile.databaseName == "file" && fromFile.port == 9000 && fromFile.host == "127.0.0.1");

  // Environment beats the file; OBJECT_PORT beats Cloud Foundry's PORT.
  auto fromEnv = resolveConfiguration(`{"port":9000,"logLevel":"warn","defaultCollection":"file"}`,
    ["PORT": "8080", "OBJECT_LOG_LEVEL": "debug", "OBJECT_DEFAULT_COLLECTION": ""]);
  assert(fromEnv.port == 8080 && fromEnv.logLevel == "debug" && fromEnv.defaultCollection == "");
  assert(resolveConfiguration("", ["PORT": "8080", "OBJECT_PORT": "7000"]).port == 7000);

  // VCAP_SERVICES beats everything; matched by name or tag.
  enum vcap = `{"user-provided":[
      {"name":"other","credentials":{"databaseName":"wrong"}},
      {"name":"cfg","tags":["object-config"],"credentials":{"databaseName":"cf","port":"8443"}}]}`;
  auto fromVcap = resolveConfiguration(`{"databaseName":"file"}`, ["OBJECT_DATABASE_NAME": "env", "VCAP_SERVICES": vcap]);
  assert(fromVcap.databaseName == "cf" && fromVcap.port == 8443);

  assertThrown!ConfigurationException(resolveConfiguration(`{"port":"x"}`, null));
  assertThrown!ConfigurationException(resolveConfiguration(`{"port":0}`, null));
  assertThrown!ConfigurationException(resolveConfiguration(`{"host":1}`, null));
  assertThrown!ConfigurationException(resolveConfiguration(`not json`, null));
  assertThrown!ConfigurationException(resolveConfiguration("", ["PORT": "70000"]));
}
