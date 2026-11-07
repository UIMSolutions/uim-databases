module uim.hdb.domain.types.mergestatus;

import uim.hdb;

/// Zustand des Delta-Merges im Hintergrund.
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