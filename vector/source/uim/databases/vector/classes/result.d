/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UIManufaktur) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UIManufaktur)
*****************************************************************************************************************/
module uim.databases.vector.classes.result;

import uim.databases.vector;

@safe:
/// Search result containing vector and its distance
struct SearchResult {
    Vector vector;
    double distance;
    
    int opCmp(ref const SearchResult other) const {
        if (distance < other.distance) return -1;
        if (distance > other.distance) return 1;
        return 0;
    }
}
