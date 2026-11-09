/// Driving port: database-wide information for monitoring.
module uim.databases.object.ports.services.databaseinfo;

import uim.databases.object.application.dtos;

interface IDatabaseInfoService {
@safe:
  HealthStatus health();

  DatabaseStatistics statistics();
}
