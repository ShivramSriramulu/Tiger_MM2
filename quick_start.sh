#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "🚀 Kafka MM2 DR Demo - Quick Start"
echo "=================================="
echo
echo "This will:"
echo "1. Build all Docker images (cached for future runs)"
echo "2. Run the complete fault-tolerant replication demo"
echo "3. Show vanilla vs enhanced MM2 behavior"
echo

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

echo "Building images..."
docker compose build

echo "Running demo..."
./run_challenge.sh

echo
echo "✅ Demo complete! Check the logs above for:"
echo "   - Baseline replication (vanilla MM2)"
echo "   - Truncation detection (enhanced MM2 fail-fast)"
echo "   - Topic reset recovery (enhanced MM2 auto-recover)"
