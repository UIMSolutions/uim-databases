/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Betriebsart „gateway“: ein Zugang vor mehreren hdb-Servern, Weiterleitung nach Mandant.
module uim.hdb.infrastructure.gateway;

public:
    import uim.hdb.infrastructure.gateway.proxy;
    import uim.hdb.infrastructure.gateway.routes;
