module uim.databases.columndb.helpers.databasestats;

/// Database statistics
struct DatabaseStats {
  string databaseName;
  size_t tableCount;
  size_t totalMemory;
  TableStatsInfo[] tables;
}
