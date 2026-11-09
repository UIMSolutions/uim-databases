/// Driven port: storage of collections. Implemented in persistence/repositories.
module uim.databases.object.ports.repositories.collections;

import uim.databases.object.domain.entities : DocumentCollection;

interface ICollectionRepository {
@safe:
  /// Inserts the collection or stores its new state. Interactors call it after every change.
  void save(DocumentCollection collection);

  /// null when there is no such collection.
  DocumentCollection find(string name);

  /// False if there was nothing to remove.
  bool remove(string name);

  bool exists(string name);

  /// All collections, ordered by name.
  DocumentCollection[] all();
}
