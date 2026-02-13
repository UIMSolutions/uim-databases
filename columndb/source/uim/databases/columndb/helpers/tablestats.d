module uim.databases.columndb.helpers.tablestats;

/// Table statistics
struct TableStats {
  string tableName;
  size_t columnCount;
  size_t rowCount;
  size_t totalMemory;
}