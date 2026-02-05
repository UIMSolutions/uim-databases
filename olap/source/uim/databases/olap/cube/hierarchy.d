module uim.databases.olap.cube.hierarchy;

import std.array;
import vibe.data.json;

/// Dimension hierarchy level
struct HierarchyLevel {
    string name;
    string column;
    int level;
}

/// Dimension hierarchy for drill-down/roll-up
class Hierarchy {
    private {
        string _name;
        HierarchyLevel[] _levels;
    }
    
    this(string name) {
        _name = name;
    }
    
    /// Get hierarchy name
    @property string name() {
        return _name;
    }
    
    /// Add level
    void addLevel(string name, string column, int level) {
        _levels ~= HierarchyLevel(name, column, level);
    }
    
    /// Get levels
    @property HierarchyLevel[] levels() {
        return _levels.dup;
    }
    
    /// Get level count
    @property size_t levelCount() {
        return _levels.length;
    }
    
    /// Get level by index
    HierarchyLevel getLevel(size_t index) {
        return _levels[index];
    }
    
    /// To JSON
    Json toJson() {
        auto result = Json.emptyObject;
        result["name"] = _name;
        
        auto levelsJson = Json.emptyArray;
        foreach (lvl; _levels) {
            auto levelJson = Json.emptyObject;
            levelJson["name"] = lvl.name;
            levelJson["column"] = lvl.column;
            levelJson["level"] = lvl.level;
            levelsJson ~= levelJson;
        }
        result["levels"] = levelsJson;
        
        return result;
    }
}
