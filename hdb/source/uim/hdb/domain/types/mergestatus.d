/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.hdb.domain.types.mergestatus;

import uim.hdb;

mixin(ShowModule!());

@safe:
/// Status of the delta merge in the background.
struct MergeStatus {
    bool running;
    size_t completed;
    string lastError;

    Json toJson() const {
        return Json.emptyObject
            .set("running", running)
            .set("completed", completed)
            .set("lastError", lastError);
    }
}