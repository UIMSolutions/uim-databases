#!/usr/bin/env dub
/+ dub.sdl:
    name "oltp-example"
    dependency "uim-databases-oltp" path="."
+/

module oltpexample;

import std.stdio;
import uim.databases.oltp;

void main() {
    writeln("=== UIM OLTP Library Example ===\n");
    
    // Example 1: Basic Connection Pool
    writeln("1. Creating Connection Pool...");
    auto pool = new ConnectionPool("host=localhost;database=testdb;user=admin;password=secret", 5, 2);
    writeln("Pool Statistics:");
    writeln(pool.getStatistics());
    writeln();
    
    // Example 2: Acquire and Release Connection
    writeln("2. Acquiring Connection...");
    try {
        auto conn = pool.acquire();
        writeln("Connection acquired: ", conn.connectionString);
        writeln("Connection is open: ", conn.isOpen);
        
        // Example 3: Transaction Management
        writeln("\n3. Creating Transaction...");
        auto txn = conn.beginTransaction(IsolationLevel.readCommitted);
        writeln("Transaction ID: ", txn.id);
        writeln("Isolation Level: ", txn.isolationLevel);
        writeln("Transaction is active: ", txn.isActive);
        
        // Example 4: Query Builder
        writeln("\n4. Building Queries...");
        
        // SELECT query
        auto selectQuery = new Query()
            .table("users")
            .select("id", "name", "email")
            .where("status", "active")
            .limit(10)
            .offset(0);
        writeln("SELECT: ", selectQuery.build());
        
        // INSERT query
        auto insertQuery = new Query()
            .table("users")
            .insert(["name": "John Doe", "email": "john@example.com", "status": "active"]);
        writeln("INSERT: ", insertQuery.build());
        
        // UPDATE query
        auto updateQuery = new Query()
            .table("users")
            .update(["status": "inactive"])
            .where("id", "123");
        writeln("UPDATE: ", updateQuery.build());
        
        // DELETE query
        auto deleteQuery = new Query()
            .table("users")
            .deleteFrom()
            .where("id", "456");
        writeln("DELETE: ", deleteQuery.build());
        
        // Example 5: Simulate Transaction Operations
        writeln("\n5. Simulating Transaction Operations...");
        try {
            writeln("Executing INSERT...");
            txn.execute(insertQuery.build());
            
            writeln("Executing UPDATE...");
            txn.execute(updateQuery.build());
            
            writeln("Committing transaction...");
            txn.commit();
            writeln("Transaction committed successfully!");
        } catch (Exception e) {
            writeln("Error occurred, rolling back transaction...");
            txn.rollback();
            writeln("Transaction rolled back: ", e.msg);
        }
        
        // Release connection
        writeln("\n6. Releasing Connection...");
        pool.release(conn);
        writeln("Connection released back to pool");
        
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    
    // Show final pool statistics
    writeln("\n7. Final Pool Statistics:");
    writeln(pool.getStatistics());
    
    // Example 6: Multiple Concurrent Connections
    writeln("\n8. Testing Multiple Connections...");
    try {
        auto conn1 = pool.acquire();
        auto conn2 = pool.acquire();
        auto conn3 = pool.acquire();
        
        writeln("Acquired 3 connections");
        writeln(pool.getStatistics());
        
        pool.release(conn1);
        pool.release(conn2);
        pool.release(conn3);
        
        writeln("\nReleased all connections");
        writeln(pool.getStatistics());
        
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    
    // Clean up
    writeln("\n9. Cleaning up...");
    pool.clear();
    writeln("Pool cleared");
    
    writeln("\n=== Example Complete ===");
}
