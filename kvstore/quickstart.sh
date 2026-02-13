#!/bin/bash
# Quick Start Guide - Key-Value Store REST API

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Key-Value Store - Quick Start Guide                  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Navigate to kvstore directory
cd "$(dirname "$0")"

echo "📦 Building Key-Value Store..."
dub build --config=executable

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Please check dependencies and try again."
    exit 1
fi

echo ""
echo "✅ Build successful!"
echo ""
echo "🚀 Starting REST API Server..."
echo ""
echo "Server will run on: http://127.0.0.1:8080"
echo ""
echo "📝 Example commands:"
echo ""
echo "1️⃣  Set a value:"
echo "    curl -X POST http://localhost:8080/kvstore \\"
echo "      -H \"Content-Type: application/json\" \\"
echo "      -d '{\"key\": \"name\", \"value\": \"John Doe\"}'"
echo ""
echo "2️⃣  Get a value:"
echo "    curl http://localhost:8080/kvstore/name"
echo ""
echo "3️⃣  Get all keys:"
echo "    curl http://localhost:8080/kvstore/keys"
echo ""
echo "4️⃣  Delete a value:"
echo "    curl -X DELETE http://localhost:8080/kvstore/name"
echo ""
echo "5️⃣  Get store stats:"
echo "    curl http://localhost:8080/kvstore/stats"
echo ""
echo "6️⃣  Set multiple values:"
echo "    curl -X POST http://localhost:8080/kvstore/multi \\"
echo "      -H \"Content-Type: application/json\" \\"
echo "      -d '{\"pairs\": {\"key1\": \"val1\", \"key2\": \"val2\"}}'"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Run the application
dub run --config=executable
