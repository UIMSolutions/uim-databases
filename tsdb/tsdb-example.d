/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Suel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Suel (aka UIManufaktur)
*****************************************************************************************************************/
module tsdb_example;

import uim.databases.tsdb;
import std.datetime;
import std.stdio;
import std.format;

void main() {
  writeln("=== Time Series Database Example ===\n");

  auto db = new TimeSeriesDatabase("sensors");

  // Example 1: Create series
  writeln("Example 1: Create a time series");
  writeln("------------------------------");
  string[string] tags = ["city": "Berlin", "unit": "C"];
  db.createSeries("temperature", tags);
  writeln("Created series: temperature with tags city=Berlin, unit=C\n");

  // Example 2: Add points
  writeln("Example 2: Add points");
  writeln("------------------------------");
  auto now = Clock.currTime();
  foreach (i; 0 .. 6) {
    auto ts = now - dur!"minutes"(i * 10);
    double value = 20.0 + i * 0.5;
    db.writePoint("temperature", tags, TimePoint(ts, value));
  }
  writeln("Added 6 points over the last hour\n");

  // Example 3: Query a range
  writeln("Example 3: Query last 30 minutes");
  writeln("------------------------------");
  auto from = now - dur!"minutes"(30);
  auto to = now;
  auto points = db.query("temperature", tags, from, to);
  writeln(format("Found %d points", points.length));
  foreach (point; points) {
    writeln(format("  %s -> %.2f", point.timestamp.toISOExtString(), point.value));
  }
  writeln();

  // Example 4: Aggregate average
  writeln("Example 4: Average temperature (last hour)");
  writeln("------------------------------");
  auto agg = db.aggregate("temperature", tags, now - dur!"hours"(1), now, Aggregation.AVG);
  writeln(format("Average: %.2f (count=%d)", agg.value, agg.count));
  writeln();

  // Example 5: Downsample to 15-minute buckets
  writeln("Example 5: Downsample to 15-minute buckets");
  writeln("------------------------------");
  auto buckets = db.downsample("temperature", tags, now - dur!"hours"(1), now, dur!"minutes"(15), Aggregation.AVG);
  foreach (bucket; buckets) {
    writeln(format("  %s -> %.2f (count=%d)", bucket.timestamp.toISOExtString(), bucket.value, bucket.count));
  }
  writeln();

  // Example 6: List series
  writeln("Example 6: List series");
  writeln("------------------------------");
  foreach (seriesKey; db.listSeries()) {
    writeln("  " ~ seriesKey);
  }
  writeln();

  // Example 7: Database stats
  writeln("Example 7: Database stats");
  writeln("------------------------------");
  writeln(format("Series: %d", db.seriesCount()));
  writeln(format("Total points: %d", db.totalPoints()));

  writeln("\n=== Example Complete ===");
}
