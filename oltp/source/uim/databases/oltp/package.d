module uim.databases.oltp;

/// UIM OLTP (Online Transaction Processing) Database
/// 
/// A complete OLTP database system with:
/// - In-memory storage with persistence
/// - Transaction management with ACID properties
/// - Lock manager for concurrency control
/// - Write-Ahead Logging (WAL) for durability
/// - REST API for remote access
/// - Multiple isolation levels
/// 
/// Example usage:
/// ```d
/// import uim.databases.oltp;
/// 
/// // Create and start database
/// auto db = new OLTPDatabase("mydb");
/// 
/// // Create a table
/// db.createTable("users", ["id", "name", "email"]);
/// 
/// // Begin transaction
/// auto txn = db.beginTransaction();
/// 
/// try {
///     // Insert data
///     auto data = Json(["name": "John", "email": "john@example.com"]);
///     auto rowId = txn.insert("users", data);
///     
///     // Query data
///     auto rows = txn.query("users", "name", "John");
///     
///     // Commit transaction
///     txn.commit();
/// } catch (Exception e) {
///     txn.rollback();
/// }
/// 
/// // Checkpoint and shutdown
/// db.checkpoint();
/// db.shutdown();
/// ```

public import uim.databases.oltp.interfaces;
public import uim.databases.oltp.classes;
public import uim.databases.oltp.storage;
public import uim.databases.oltp.lock;
public import uim.databases.oltp.wal;
public import uim.databases.oltp.database;
public import uim.databases.oltp.api;
