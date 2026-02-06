/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.oltp.enumerations.state;

import uim.databases.oltp;
@safe:

/// Transaction state
enum TransactionState {
    active,
    committed,
    aborted,
    failed
}