/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Composition root: the only place where adapters and the application core are wired together.
/// Configuration: see uim.databases.relational.infrastructure.configuration.loader.
module app;

import uim.databases.relational;
import vibe.core.core : runApplication;
import vibe.core.log : logError, logInfo;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerSettings, listenHTTP;

@safe:

int main() {
  AppConfig config;
  try {
    config = loadConfiguration();
    configureLogging(config.logLevel);
  } catch (ConfigurationException e) {
    logError("Invalid configuration: %s", e.msg);
    return 1;
  }

  // Driven adapter (persistence)
  ITableRepository repository = new InMemoryTableRepository;

  // Application core behind the driving ports
  ITableCatalogUseCase catalog = new TableCatalogInteractor(repository);
  IRowUseCase rows = new RowInteractor(repository);
  IJoinUseCase joins = new JoinInteractor(repository);
  IDatabaseInfoService info = new DatabaseInfoService(repository, config.databaseName);

  // Driving adapter (presentation)
  auto router = new URLRouter;
  registerRoutes(router, new RelationalRestController(catalog, rows, joins, info));

  auto settings = new HTTPServerSettings;
  settings.port = config.port;
  settings.bindAddresses = [config.host];
  auto listener = listenHTTP(settings, router);
  scope (exit) listener.stopListening();

  logInfo("Relational database '%s' serving http://%s:%s", config.databaseName, config.host, config.port);
  return runApplication();
}
