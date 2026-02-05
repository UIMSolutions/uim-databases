#!/usr/bin/env dub
/+ dub.sdl:
    name "oltp-database-example"
    dependency "uim-databases-oltp" path="./oltp" configuration="library"
+/

module oltpdbexample;

import std.stdio;
import vibe.data.json;
import uim.databases.oltp;

void main() {
    writeln("=== UIM OLTP Database Example ===\n");
    
    // 1. Create OLTP Database
    writeln("1. Creating OLTP Database...");
    auto db = new OLTPDatabase("testdb", "./test_data", "./test_wal");
    writeln("Database created: ", db.name);
    writeln();
    
    // 2. Create Tables
    writeln("2. Creating Tables...");
    db.createTable("users", ["id", "name", "email", "status"]);
    db.createTable("accounts", ["id", "user_id", "balance"]);
    writeln("Tables created: users, accounts");
    writeln();
    
    // 3. Insert Data with Transactions
    writeln("3. Inserting Data...");
    try {
        auto txn1 = db.beginTransaction();
        writeln("Transaction started: ", txn1.id);
        
        // Insert users
        auto user1 = Json.emptyObject;
        user1["name"] = "Alice";
        user1["email"] = "alice@example.com";
        user1["status"] = "active";
        auto userId1 = txn1.insert("users", user1);
        writeln("  Inserted user: ", userId1);
        
        auto user2 = Json.emptyObject;
        user2["name"] = "Bob";
        user2["email"] = "bob@example.com";
        user2["status"] = "active";
        auto userId2 = txn1.insert("users", user2);
        writeln("  Inserted user: ", userId2);
        
        // Insert accounts
        auto account1 = Json.emptyObject;
        account1["user_id"] = userId1;
        account1["balance"] = "1000.00";
        txn1.insert("accounts", account1);
        
        auto account2 = Json.emptyObject;
        account2["user_id"] = userId2;
        account2["balance"] = "500.00";
        txn1.insert("accounts", account2);
        
        txn1.commit();
        writeln("Transaction committed successfully!");
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    writeln();
    
    // 4. Query Data
    writeln("4. Querying Data...");
    try {
        auto txn2 = db.beginTransaction();
        
        auto users = txn2.query("users");
        writeln("Total users: ", users.length);
        foreach (i, user; users) {
            writeln("  User ", i + 1, ": ", user["data"]["name"].get!string);
        }
        
        auto activeUsers = txn2.query("users", "status", "active");
        writeln("Active users: ", activeUsers.length);
        
        txn2.commit();
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    writeln();
    
    // 5. Update Data
    writeln("5. Updating Data...");
    try {
        auto txn3 = db.beginTransaction();
        
        auto users = txn3.query("users");
        if (users.length > 0) {
            auto userId = users[0]["_id"].get!string;
            
            auto updateData = Json.emptyObject;
            updateData["status"] = "inactive";
            
            txn3.update("users", userId, updateData);
            writeln("  Updated user ", userId, " to inactive");
        }
        
        txn3.commit();
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    writeln();
    
    // 6. Transaction Rollback Example
    writeln("6. Testing Transaction Rollback...");
    try {
        auto txn4 = db.beginTransaction();
        
        auto user3 = Json.emptyObject;
        user3["name"] = "Charlie";
        user3["email"] = "charlie@example.com";
        user3["status"] = "active";
        auto userId3 = txn4.insert("users", user3);
        writeln("  Inserted user: ", userId3);
        
        // Simulate error and rollback
        writeln("  Simulating error...");
        txn4.rollback();
        writeln("  Transaction rolled back!");
        
        // Verify the user was not inserted
        auto txn5 = db.beginTransaction();
        auto users = txn5.query("users");
        writeln("  Total users after rollback: ", users.length);
        txn5.commit();
    } catch (Exception e) {
        writeln("Error: ", e.msg);
    }
    writeln();
    
    // 7. Database Statistics
    writeln("7. Database Statistics:");
    auto stats = db.getStatistics();
    writeln(stats.toPrettyString());
    writeln();
    
    // 8. Checkpoint
    writeln("8. Performing Checkpoint...");
    db.checkpoint();
    writeln("Checkpoint completed");
    writeln();
    
    // 9. Shutdown
    writeln("9. Shutting Down Database...");
    db.shutdown();
    writeln("Database shut down successfully");
    
    writeln("\n=== Example Complete ===");
}
