/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.object.infrastructure.configuration.settings;

@safe:

/// Type-safe service configuration. The field defaults apply when no source sets a value.
struct AppConfig {
  /// Name reported by /stats.
  string databaseName = "main";
  /// Bind address; use 0.0.0.0 on Cloud Foundry.
  string host = "127.0.0.1";
  ushort port = 8081;
  /// trace, debug, diagnostic, info, warn, error, critical, fatal or none.
  string logLevel = "info";
  /// Created at startup and protected from being dropped; empty for none.
  string defaultCollection = "default";
}

/// A configuration source holds an invalid value.
class ConfigurationException : Exception {
  this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(message, file, line);
  }
}
