#!/usr/bin/env dub
/+ dub.sdl:
    dependency "vibe-d" version="~>0.9.0"
+/
module example;

import std.stdio;
import std.net.curl;
import std.json;
import std.conv;
import std.random;
import core.thread;

void main() {
    writeln("Vector Database Example Client\n");
    
    string baseUrl = "http://localhost:8080";
    
    // Wait a bit for server to start if needed
    writeln("Checking server health...");
    try {
        auto healthResponse = get(baseUrl ~ "/health");























































































































































}    writeln("  curl http://localhost:8080/vectors");    writeln("  curl http://localhost:8080/stats");    writeln("\nTry running queries with curl:");    writeln("\n✓ Example completed!");        }        writeln("Note: Delete requires proper HTTP DELETE handling");    } catch (Exception e) {        writeln("✓ Deleted vec5");        auto deleteResponse = client.perform();        client.url = baseUrl ~ "/vectors/vec5";        client.method = HTTP.Method.del;        auto client = HTTP();    try {    writeln("\n--- Deleting a Vector ---");        }        writeln("✗ Failed to get stats: ", e.msg);    } catch (Exception e) {        writeln(statsResponse);        auto statsResponse = get(baseUrl ~ "/stats");    try {    writeln("\n--- Database Statistics ---");        }        writeln("Note: Update via PUT requires proper HTTP client handling");    } catch (Exception e) {        writeln("✓ Updated vec3 metadata");                                  ["Content-Type": "application/json"]);                                  updateRequest.toString(),        auto updateResponse = post(baseUrl ~ "/vectors/vec3",        client.addRequestHeader("Content-Type", "application/json");        client.method = HTTP.Method.put;        auto client = HTTP(baseUrl ~ "/vectors/vec3");                ];            ]                "status": "modified"                "category": "updated",            "metadata": [        JSONValue updateRequest = [    try {    writeln("\n--- Updating a Vector ---");        }        writeln("✗ Failed to search by ID: ", e.msg);    } catch (Exception e) {        }                   ", Distance: ", result["distance"].floating);            writeln("  - ID: ", result["id"].str,        foreach (result; searchJson["results"].array) {                writeln("Similar to vec2:");        auto searchJson = parseJSON(searchResponse);                                          ["Content-Type": "application/json"]);                                  searchByIdRequest.toString(),        auto searchResponse = post(baseUrl ~ "/search/vec2",                JSONValue searchByIdRequest = ["k": 3];    try {    writeln("\n--- Searching by Vector ID ---");        }        writeln("✗ Failed to search: ", e.msg);    } catch (Exception e) {        }                   ", Distance: ", result["distance"].floating);            writeln("  - ID: ", result["id"].str,         foreach (result; searchJson["results"].array) {                writeln("Found ", searchJson["count"].integer, " similar vectors:");        auto searchJson = parseJSON(searchResponse);                                          ["Content-Type": "application/json"]);                                  searchRequest.toString(),        auto searchResponse = post(baseUrl ~ "/search",                ];            "k": 3            "vector": queryVector,        JSONValue searchRequest = [                }            queryVector[j] = uniform(0.0, 1.0, rnd) + uniform(-0.1, 0.1);        foreach (j; 0 .. 128) {        auto rnd = Random(1);        queryVector.length = 128;        double[] queryVector;        // Create a query vector similar to vec1    try {    writeln("\n--- Searching for Similar Vectors ---");        }        writeln("✗ Failed to get vector: ", e.msg);    } catch (Exception e) {        writeln("Metadata: ", jsonResponse["metadata"]);        writeln("Dimension: ", jsonResponse["dimension"].integer);        writeln("Vector ID: ", jsonResponse["id"].str);        auto jsonResponse = parseJSON(getResponse);        auto getResponse = get(baseUrl ~ "/vectors/vec1");    try {    writeln("\n--- Getting a Specific Vector ---");        }        writeln("✗ Failed to list vectors: ", e.msg);    } catch (Exception e) {        writeln(listResponse);        auto listResponse = get(baseUrl ~ "/vectors");    try {    writeln("\n--- Listing All Vectors ---");        }        }            writeln("✗ Failed to add vector: ", e.msg);        } catch (Exception e) {            writeln("✓ Added vector vec", i);                               ["Content-Type": "application/json"]);                               request.toString(),            auto response = post(baseUrl ~ "/vectors",        try {                ];            ]                "index": to!string(i)                "category": i % 2 == 0 ? "even" : "odd",            "metadata": [            "vector": vector,            "id": "vec" ~ to!string(i),        JSONValue request = [                }            vector[j] = uniform(0.0, 1.0, rnd);        foreach (j; 0 .. 128) {        auto rnd = Random(i);        // Generate random vector                vector.length = 128;        double[] vector;    foreach (i; 1 .. 6) {    // Add some example vectors        writeln("\n--- Adding Vectors ---");        }        return;        writeln("✗ Server not responding. Make sure to run 'dub run' first.");    } catch (Exception e) {        writeln(healthResponse);        writeln("✓ Server is running");