/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
/// Driving port: database-wide information for monitoring.
module uim.databases.object.ports.services.databaseinfo;

import uim.databases.object.application.dtos;

interface IDatabaseInfoService {
@safe:
  HealthStatus health();

  DatabaseStatistics statistics();
}
