/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module tsdb.tsdb-advanced-example;

import uim.databases.tsdb;
import std.datetime;
import std.stdio;
import std.format;

void main() {
  writeln("=== Time Series Database Advanced Example ===\n");

  auto db = new TimeSeriesDatabase("infra");
  auto now = Clock.currTime();

  // Setup: Create series for CPU usage on two hosts
  string[string] hostA = ["host": "api-01", "region": "eu-west"];
  string[string] hostB = ["host": "api-02", "region": "eu-west"];

  db.createSeries("cpu_usage", hostA);
  db.createSeries("cpu_usage", hostB);

  // Example 1: Batch insert
  writeln("Example 1: Batch insert CPU usage");
  writeln("------------------------------");
  TimePoint[] batchA;
  TimePoint[] batchB;
  foreach (i; 0 .. 12) {
    auto ts = now - dur!"minutes"(i * 5);
    batchA ~= TimePoint(ts, 30.0 + i * 1.2);
    batchB ~= TimePoint(ts, 25.0 + i * 0.9);
  }
  db.writePoints("cpu_usage", hostA, batchA);
  db.writePoints("cpu_usage", hostB, batchB);
  writeln("Inserted 12 points per host\n");

  // Example 2: Query per host
  writeln("Example 2: Query last 30 minutes per host");
  writeln("------------------------------");
  auto from = now - dur!"minutes"(30);
  auto to = now;
  auto pointsA = db.query("cpu_usage", hostA, from, to);
  auto pointsB = db.query("cpu_usage", hostB, from, to);
  writeln(format("api-01 points: %d", pointsA.length));
  writeln(format("api-02 points: %d", pointsB.length));
  writeln();

  // Example 3: Peak CPU usage
  writeln("Example 3: Peak CPU usage (last hour)");
  writeln("------------------------------");
  auto maxA = db.aggregate("cpu_usage", hostA, now - dur!"hours"(1), now, Aggregation.MAX);
  auto maxB = db.aggregate("cpu_usage", hostB, now - dur!"hours"(1), now, Aggregation.MAX);
  writeln(format("api-01 max: %.2f", maxA.value));
  writeln(format("api-02 max: %.2f", maxB.value));
  writeln();

  // Example 4: Downsample to 10-minute buckets
  writeln("Example 4: Downsample to 10-minute buckets");
  writeln("------------------------------");
  auto buckets = db.downsample("cpu_usage", hostA, now - dur!"hours"(1), now, dur!"minutes"(10), Aggregation.AVG);
  foreach (bucket; buckets) {
    writeln(format("  %s -> %.2f (count=%d)", bucket.timestamp.toISOExtString(), bucket.value, bucket.count));
  }
  writeln();

  // Example 5: Aggregate across a shorter window
  writeln("Example 5: Average CPU usage (last 15 minutes)");
  writeln("------------------------------");
  auto avgA = db.aggregate("cpu_usage", hostA, now - dur!"minutes"(15), now, Aggregation.AVG);
  writeln(format("api-01 avg: %.2f (count=%d)", avgA.value, avgA.count));
  writeln();

  // Example 6: Series inventory
  writeln("Example 6: List series keys");
  writeln("------------------------------");
  foreach (seriesKey; db.listSeries()) {
    writeln("  " ~ seriesKey);
  }

  writeln("\n=== Advanced Example Complete ===");
}
