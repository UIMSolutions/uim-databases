module uim.databases.oltp;

/// UIM OLTP (Online Transaction Processing) Library
/// 
/// This module provides comprehensive OLTP functionality including:
/// - Transaction management with ACID properties
/// - Connection pooling for efficient resource management
/// - Query builder for safe SQL construction
/// - Support for multiple isolation levels
/// 
/// Example usage:
/// ```d
/// import uim.databases.oltp;
/// 
/// // Create connection pool
/// auto pool = new ConnectionPool("host=localhost;db=mydb", 10);
/// 
/// // Acquire connection
/// auto conn = pool.acquire();
/// 
/// // Begin transaction
/// auto txn = conn.beginTransaction(IsolationLevel.serializable);
/// 
/// try {
///     // Execute queries within transaction
///     txn.execute("INSERT INTO users (name, email) VALUES ('John', 'john@example.com')");
///     txn.execute("UPDATE accounts SET balance = balance - 100 WHERE user_id = 1");
///     
///     // Commit transaction
///     txn.commit();
/// } catch (Exception e) {
///     // Rollback on error
///     txn.rollback();
/// } finally {
///     // Release connection back to pool
///     pool.release(conn);
/// }
/// ```

public import uim.databases.oltp.interfaces;
public import uim.databases.oltp.classes;
