module uim.databases.relational.helpers.json;

import uim.databases.relational;

mixin(ShowModule!());

@safe:

size_t countJsonKeys(Json obj) {
  if (!obj.isObject)
    return 0;
  size_t count = 0;
  foreach (key, value; obj.object) {
    count++;
  }
  return count;
}

size_t countJsonArrayElements(Json arr) {
  if (!arr.isArray)
    return 0;
  return arr.array.length;
}

Json cloneJson(Json value) {
  if (value.isObject) {
    Json result = Json.object;
    foreach (key, val; value.object) {
      result[key] = cloneJson(val);
    }
    return result;
  } else if (value.isArray) {
    Json result = Json.array;
    foreach (element; value.array) {
      result.array ~= cloneJson(element);
    }
    return result;
  } else {
    return value; // For primitive types, return as is
  }
}

size_t totalJsonSize(Json value) {
  if (value.isObject) {
    size_t size = 0;
    foreach (key, val; value.object) {
      size += key.length + totalJsonSize(val);
    }
    return size;
  } else if (value.isArray) {
    size_t size = 0;
    foreach (element; value.array) {
      size += totalJsonSize(element);
    }
    return size;
  } else if (value.isString) {
    return value.string.length;
  } else {
    return 0; // For numbers, booleans, null, and undefined, we can consider size as 0
  }
}

size_t jsonDepth(Json value) {
  if (value.isObject) {
    size_t maxDepth = 0;
    foreach (key, val; value.object) {
      size_t depth = jsonDepth(val);
      if (depth > maxDepth)
        maxDepth = depth;
    }
    return maxDepth + 1;
  } else if (value.isArray) {
    size_t maxDepth = 0;
    foreach (element; value.array) {
      size_t depth = jsonDepth(element);
      if (depth > maxDepth)
        maxDepth = depth;
    }
    return maxDepth + 1;
  } else {
    return 1; // For primitive types, depth is 1
  }
}

size_t countJsonValues(Json value) {
  if (value.isObject) {
    size_t count = 0;
    foreach (key, val; value.object) {
      count += countJsonValues(val);
    }
    return count;
  } else if (value.isArray) {
    size_t count = 0;
    foreach (element; value.array) {
      count += countJsonValues(element);
    }
    return count;
  } else {
    return 1; // For primitive types, count as 1
  }
}

size_t countJsonKeysRecursive(Json value) {
  if (value.isObject) {
    size_t count = value.object.length;
    foreach (key, val; value.object) {
      count += countJsonKeysRecursive(val);
    }
    return count;
  } else if (value.isArray) {
    size_t count = 0;
    foreach (element; value.array) {
      count += countJsonKeysRecursive(element);
    }
    return count;
  } else {
    return 0; // For primitive types, no keys
  }
}

size_t countJsonArrayElementsRecursive(Json value) {
  if (value.isObject) {
    size_t count = 0;
    foreach (key, val; value.object) {
      count += countJsonArrayElementsRecursive(val);
    }
    return count;
  } else if (value.isArray) {
    size_t count = value.array.length;
    foreach (element; value.array) {
      count += countJsonArrayElementsRecursive(element);
    }
    return count;
  } else {
    return 0; // For primitive types, no array elements
  }
}

size_t toHash(Json value) {
  if (value.isObject) {
    size_t hash = 0;
    foreach (key, val; value.object) {
      hash ^= key.hash ^ toHash(val);
    }
    return hash;
  } else if (value.isArray) {
    size_t hash = 0;
    foreach (element; value.array) {
      hash ^= toHash(element);
    }
    return hash;
  } else if (value.isString) {
    return value.string.hash;
  } else if (value.isInteger) {
    return cast(size_t)value.integer;
  } else if (value.isBoolean) {
    return value.boolean ? 1 : 0;
  } else if (value.isNull) {
    return 0xDEADBEEF; // Arbitrary hash for null
  } else if (value.isUndefined) {
    return 0xBADF00D; // Arbitrary hash for undefined
  } else {
    return 0; // Should not reach here
  }
}

struct JsonKey {
    Json value;
    
    // Leitet Gleichheit an vibe.d Json weiter
    bool opEquals(ref const JsonKey other) const @safe pure nothrow {
        try { return this.value == other.value; } 
        catch (Exception) { return false; }
    }

    // Implementiert das vom Compiler geforderte Hashing
    extern (D) size_t toHash() const nothrow @safe {
        try {
            // Einfache Hash-Generierung über den String-Repräsentanten
            return typeid(string).getHash(value.toString());
        } catch (Exception) {
            return 0;
        }
    }
}