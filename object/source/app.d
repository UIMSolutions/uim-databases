/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Composition root: the only place where adapters and the application core are wired together.
/// Configuration: see uim.databases.object.infrastructure.configuration.loader.
module app;

import uim.databases.object;
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
  ICollectionRepository repository = new InMemoryCollectionRepository;

  // Application core behind the driving ports
  auto protectedNames = config.defaultCollection.length > 0 ? [config.defaultCollection] : null;
  ICollectionUseCase collections = new CollectionInteractor(repository, protectedNames);
  IDocumentUseCase documents = new DocumentInteractor(repository);
  IQueryUseCase queries = new QueryInteractor(repository);
  IIndexUseCase indexes = new IndexInteractor(repository);
  IDatabaseInfoService info = new DatabaseInfoService(repository, config.databaseName);

  if (config.defaultCollection.length > 0) {
    try {
      collections.createCollection(config.defaultCollection);
    } catch (ValidationException e) {
      logError("Invalid configuration: defaultCollection: %s", e.msg);
      return 1;
    }
    logInfo("Default collection: '%s'", config.defaultCollection);
  }

  // Driving adapter (presentation)
  auto router = new URLRouter;
  registerRoutes(router, new ObjectRestController(collections, documents, queries, indexes, info));

  auto settings = new HTTPServerSettings;
  settings.port = config.port;
  settings.bindAddresses = [config.host];
  auto listener = listenHTTP(settings, router);
  scope (exit) listener.stopListening();

  logInfo("Object database '%s' serving http://%s:%s", config.databaseName, config.host, config.port);
  return runApplication();
}
