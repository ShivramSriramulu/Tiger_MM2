#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Helper to exec a Kafka CLI in a container
kexec() { docker exec "$1" bash -c "$2"; }

banner() { echo; echo "==================== $* ===================="; }

# 0) Clean up any existing containers and start fresh
banner "Cleaning up previous run"
docker compose down -v || true
docker system prune -f || true

# 1) Boot infra
banner "Starting clusters"
docker compose up -d kafka-primary kafka-dr
sleep 6

# 2) Create topic on primary with 1 partition/replica and 60s retention (assessment requirement)
TOPIC="commit-log"
banner "Creating $TOPIC on PRIMARY (retention=60s)"

# Clean up old topic if present
kexec kafka-primary "/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-primary:9092 --delete --topic $TOPIC || true"
sleep 2

# Create topic fresh
kexec kafka-primary "/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-primary:9092 --create --topic $TOPIC --partitions 1 --replication-factor 1"

# Set retention
kexec kafka-primary "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-primary:9092 --alter --topic $TOPIC --add-config retention.ms=60000"

# 3) Baseline: vanilla MM2 + produce + verify
banner "Baseline: vanilla MM2"
docker compose up -d mm2-vanilla
sleep 4
banner "Producing 1000 messages"
docker compose run --rm producer --count 1000
sleep 2
banner "Verify replication on DR"
docker compose run --rm -e EXPECT=1000 -e TIMEOUT=20 verifier || true

# 4) Truncation simulation (show vanilla may silently skip when reset!=none)
# Stop vanilla, wait past retention, then start enhanced which FAILS FAST
banner "Simulate truncation: pause >60s then start Enhanced MM2 to fail-fast"
docker compose stop mm2-vanilla || true
sleep 65
# Append new data after purge so position is now out-of-range
banner "Producing 10 messages after truncation"
docker compose run --rm producer --count 10
banner "Start Enhanced MM2 (should detect TRUNCATION and fail)"
set +e
(docker compose up -d --build mm2-enhanced && sleep 6 && docker logs mm2-enhanced --tail=200) || true
set -e

# 5) Topic reset simulation: delete & recreate; Enhanced MM2 auto-recovers
banner "Topic reset: delete + recreate $TOPIC on PRIMARY"
kexec kafka-primary "/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-primary:9092 --delete --topic $TOPIC || true"
sleep 3
kexec kafka-primary "/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-primary:9092 --create --topic $TOPIC --partitions 1 --replication-factor 1"
kexec kafka-primary "/opt/kafka/bin/kafka-configs.sh --bootstrap-server kafka-primary:9092 --alter --topic $TOPIC --add-config retention.ms=60000"

banner "Produce 50 messages post‑reset"
docker compose run --rm producer --count 50
sleep 5
banner "Check Enhanced MM2 logs for RESET_DETECTED and continued mirroring"
docker logs mm2-enhanced --tail=200 || true

banner "DONE"
