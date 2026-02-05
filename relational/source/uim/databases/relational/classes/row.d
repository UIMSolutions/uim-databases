/// Row with metadata
struct Row {
    Json data;
    SysTime createdAt;
    SysTime updatedAt;
    
    this(Json data) {
        this.data = data;
        this.createdAt = Clock.currTime();
        this.updatedAt = Clock.currTime();
    }
    
    void update(Json newData) {
        this.data = newData;
        this.updatedAt = Clock.currTime();
    }
}