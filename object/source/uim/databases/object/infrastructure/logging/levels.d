module uim.databases.object.infrastructure.logging.levels;

import uim.databases.object.infrastructure.configuration.settings : ConfigurationException;
import std.string : strip, toLower;
import vibe.core.log : LogLevel, setLogLevel;

@safe:

/// Throws: ConfigurationException for unknown names.
LogLevel parseLogLevel(string name) {
  switch (name.strip.toLower) {
    case "trace":
      return LogLevel.trace;
    case "debug":
      return LogLevel.debug_;
    case "diagnostic":
      return LogLevel.diagnostic;
    case "info":
      return LogLevel.info;
    case "warn", "warning":
      return LogLevel.warn;
    case "error":
      return LogLevel.error;
    case "critical":
      return LogLevel.critical;
    case "fatal":
      return LogLevel.fatal;
    case "none":
      return LogLevel.none;
    default:
      throw new ConfigurationException("Unknown log level '" ~ name ~ "'");
  }
}

/// Sets the minimum level of vibe.d's console logger.
void configureLogging(string level) {
  setLogLevel(parseLogLevel(level));
}

unittest {
  import std.exception : assertThrown;

  assert(parseLogLevel("DEBUG") == LogLevel.debug_);
  assertThrown!ConfigurationException(parseLogLevel("loud"));
}
