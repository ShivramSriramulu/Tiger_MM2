#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "Building all images for caching..."
docker compose build --no-cache
echo "Images built and cached. Future runs will be faster!"
