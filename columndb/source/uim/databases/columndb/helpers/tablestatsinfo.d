module uim.databases.columndb.helpers.tablestatsinfo;

/// Table info for stats
struct TableStatsInfo {
  string tableName;
  size_t rowCount;
  size_t columnCount;
}
