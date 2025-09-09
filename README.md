# Kafka MirrorMaker 2 — Fault-Tolerant DR Demo 

## Project Overview

This project enhances Apache Kafka MirrorMaker 2 (MM2) for mission-critical data replication between a Primary cluster and a Disaster Recovery (DR) cluster. It includes:

- A synthetic data replication pipeline (producer → MM2 → DR)
- Code changes to MM2 to improve fault tolerance:
  - **Fail-fast on truncation** (no silent data loss)
  - **Graceful recovery on topic reset** (auto-resubscribe from beginning)
- Kafka version: v4.0.0 (KRaft)


## Background & Motivation

We simulate a real commit-log/WAL setup:

- **Primary**: Services produce ordered events to `commit-log` and read from it to maintain state
- **Cross-Cluster Replication**: MirrorMaker 2 mirrors `commit-log` → `primary.commit-log` in the DR cluster
- **DR**: Standby services consume `primary.commit-log` to keep a synchronized shadow state

### Gaps in vanilla MM2 addressed

- **Silent Data Loss**: Retention may purge messages before replication catches up; vanilla setups can continue from later offsets without surfacing the gap
- **Service Disruption**: Topic delete/recreate (maintenance) may break replication or stall until manual intervention

**Goal**: Detect these scenarios and respond in a way that is obvious, safe, and automated.

## Architecture

### Cluster Setup

- **Primary**: Single-node Kafka 4.0 (KRaft)
- **DR**: Single-node Kafka 4.0 (KRaft)
- **MM2**:
  - Vanilla to prove baseline replication
  - Enhanced MM2 (≤500 LOC patch) for fault tolerance
- **Producer**: CLI emitting JSON events to `commit-log`
- **Topic config**: `commit-log` (Primary) and `primary.commit-log` (DR), 1 partition, 1 replica (per assessment)

### Components

#### Commit Log Producer (CLI)

- `--count N` → produces exactly N messages then exits
- JSON schema:
```json
{
  "event_id": "uuid",
  "timestamp": 1724684407,
  "op_type": "CREATE|UPDATE|DELETE",
  "key": "doc:8f7b",
  "value": {"status":"archived"}
}
```

#### MirrorMaker 2 (Enhanced)

- **Truncation detection (fail-fast)**: On `OffsetOutOfRangeException`, log `TRUNCATION_DETECTED` and throw (no silent skip)
- **Topic reset auto-recovery**: Detect TopicId change (delete/recreate), log `RESET_DETECTED`, `seekToBeginning` for that topic's partitions, and continue

## What I Built (Summary)

1. Two single-node KRaft clusters via Docker Compose 
2. Vanilla MM2 to prove baseline replication works
3. Enhanced MM2 with a surgical patch (≈230 LOC in `MirrorSourceTask`):
   - AdminClient-based TopicId cache to detect reset
   - Catch `OffsetOutOfRangeException` → fail-fast with diagnostics
   - Resubscribe/seek behavior controlled via properties:
     - `mirrorsource.fail.on.truncation=true`
     - `mirrorsource.auto.recover.on.reset=true`
     - `mirrorsource.topic.reset.retry.ms=5000`
4. Bounded Verifier that exits after seeing N messages or on timeout (prevents hangs)
5. Automation script `run_challenge.sh` to run:
   - Baseline replication (1000 messages)
   - Truncation simulation (60s retention; fail-fast logs)
   - Topic reset simulation (delete/recreate; auto-recover logs)

## How to Run 

**Requires**: Docker Desktop, Git, Bash

```bash
# fresh start
docker compose down -v

# run all scenarios (≈2–3 minutes)
./run_challenge.sh
```

### You should see:

- **Baseline**: `1000/1000` in the verifier output
- **Truncation test**: Enhanced MM2 logs `TRUNCATION_DETECTED` and exits (by design)
- **Topic reset test**: Enhanced MM2 logs `RESET_DETECTED` and continues mirroring

### Test Configuration

- `retention.ms=60000` (60s) for truncation testing
- `sleep 65` for truncation scenario (wait past retention)
- Bounded verifier (`--expect 1000 --timeout 20`) to avoid infinite loops
- Official Kafka multi-arch images (`platform: linux/arm64`)

## Fault-Tolerance Enhancements (Design Details)

### Fail-Fast on Truncation

- **Trigger**: Consumer hits `OffsetOutOfRangeException` (retention purged the expected offset)
- **Action**: Log `TRUNCATION_DETECTED` with:
  - partition → earliest offsets
  - consumer assignment
- **Outcome**: Throw `ConnectException`. Operators immediately see data loss

### Graceful Topic Reset Handling

- **Signal**: Source topic's TopicId changed (delete/recreate)
- **Action**: Log `RESET_DETECTED` with old/new IDs; `seekToBeginning` for the topic's assigned partitions; continue
- **Also handles**: `UnknownTopicOrPartitionException` with backoff/retry until topic reappears

All toggles are in the enhanced MM2 properties file. The patch is self-contained and under the 500 LOC requirement.

## Cross-Cluster Replication

This solution uses **asynchronous cross-cluster replication** via MM2, hardened with:
- **Fail-fast truncation detection** - Makes data loss immediately visible
- **Topic reset auto-recovery** - Reduces manual intervention during maintenance
- **RPO/RTO transparency** - Clear visibility into recovery point and time objectives

## Key Features

- **Mac M1 optimized**: Multi-arch Docker images with `platform: linux/arm64`
- **Bounded verifier**: Exits after expected count or timeout (no hangs)
- **MM2 patch (≤500 LOC)**: AdminClient + TopicId cache for reset detection
- **Clear logging**: `TRUNCATION_DETECTED` and `RESET_DETECTED` markers
- **Complete automation**: `run_challenge.sh` orchestrates all scenarios

## Key Optimizations

- **Bounded verifier**: Exits after expected count or timeout (prevents hangs)
- **60s retention**: Proper truncation testing as required for assessment
- **Idempotent scripts**: Clean runs with `docker compose down -v`
- **Mac M1 ready**: Multi-arch images with `platform: linux/arm64`
- **Efficient builds**: Multi-stage Dockerfile with layer caching

## How to Prove It Works (What Reviewers Should See)

### Baseline:
```
produced 1000 ...
verifier → 1000/1000
```

### Truncation (fail-fast):
```
TRUNCATION_DETECTED: Source offsets are out of range ...
```
(MM2 task exits with `ConnectException` by design.)

### Topic reset (auto-recover):
```
RESET_DETECTED: Topic commit-log recreated (oldId=... newId=...). Seeking to beginning.
```
(MM2 continues replicating new events.)



## Sync vs. Async Replication (and what we used)

| Aspect | Synchronous (ISR, in-cluster) | Asynchronous (MM2, cross-cluster) |
|--------|-------------------------------|-----------------------------------|
| Where | Same cluster replicas | Separate DR cluster |
| Producer latency | Higher (wait for replicas) | Lower (mirror later) |
| Consistency | Stronger within cluster | Eventual across clusters |
| RPO | ~0 in-cluster | >0 (depends on lag/retention) |
| RTO | Fast in-cluster | Depends on DR state/lag |
| Used here | Not applicable | Yes (MM2) |

**Why async MM2**: best fit for cross-region DR. The fail-fast and auto-recover features make RPO/RTO transparent and operations predictable.

## Deliverables

### Repository Links
- **GitHub Repository**: [https://github.com/ShivramSriramulu/Tiger_MM2](https://github.com/ShivramSriramulu/Tiger_MM2)
- **Kafka Fork**: [https://github.com/ShivramSriramulu/kafka](https://github.com/ShivramSriramulu/kafka) (Fork of [Apache Kafka](https://github.com/apache/kafka))
- **Pull Request Title**: `MM2: fail-fast on truncation + auto-recover on topic reset (MirrorSourceTask)`
- **Patch Location**: `mm2/patches/mm2-fault-tolerance.patch` (≤500 LOC)

### Docker Hub Images
- **Enhanced MM2**: [shivramsriramulu/enhanced-mm2:latest](https://hub.docker.com/r/shivramsriramulu/enhanced-mm2) (Pre-built Kafka with fault-tolerance modifications)
- **Commit Log Producer**: [shivramsriramulu/commitlog-producer:latest](https://hub.docker.com/r/shivramsriramulu/commitlog-producer) (CLI for generating test events)

### Setup Instructions
```bash
# Clone repository
git clone https://github.com/ShivramSriramulu/Tiger_MM2.git
cd mm2-dr-demo

# Start environment
docker compose up -d

# Run complete test suite
./run_challenge.sh
```

### Test Execution
```bash
# Quick start (builds images + runs demo)
./quick_start.sh

# Or direct execution
./run_challenge.sh
```

**Expected Results**:
- Baseline: `1000/1000` messages replicated
- Truncation: `TRUNCATION_DETECTED` error (fail-fast)
- Reset: `RESET_DETECTED` recovery (auto-continue)

### Log Analysis
**Key log messages to monitor**:

```bash
# Check Enhanced MM2 logs
docker logs mm2-enhanced

# Look for these patterns:
# TRUNCATION_DETECTED: Source offsets are out of range
# RESET_DETECTED: Topic commit-log recreated (oldId=... newId=...)
# Enhanced MM2: Starting with fault-tolerance features...
```

**Container logs**:
```bash
# All containers
docker compose logs

# Specific services
docker compose logs kafka-primary
docker compose logs kafka-dr
docker compose logs mm2-enhanced
docker compose logs producer
docker compose logs verifier
```

### Design Rationale

**MirrorMaker 2 Modifications**:
- **Surgical approach**: Only modified `MirrorSourceTask.java` (≤500 LOC)
- **No API changes**: All enhancements via configuration properties
- **Minimal disruption**: Preserves existing Kafka Connect behavior
- **Production-ready**: Uses standard Kafka patterns (AdminClient, SLF4J logging)

**Integration Approach**:
- **Fail-fast truncation**: Catches `OffsetOutOfRangeException` → logs diagnostics → throws `ConnectException`
- **Topic reset recovery**: Caches TopicId → detects changes → seeks to beginning → continues
- **Configurable behavior**: Toggle features via properties for different environments
- **Operator-friendly**: Clear log markers (`TRUNCATION_DETECTED`, `RESET_DETECTED`)

**Why this approach**:
- **Data integrity**: Prevents silent data loss in retention gaps
- **Operational efficiency**: Reduces manual intervention during maintenance
- **Observability**: Clear error messages for troubleshooting
- **Backward compatibility**: Existing MM2 deployments unaffected

### Repo Files
- `docker-compose.yml` (Primary, DR, vanilla MM2, enhanced MM2, producer, verifier)
- `mm2/patches/mm2-fault-tolerance.patch`
- `mm2/connect-mirror-maker.enhanced.properties`
- `producer/commitlog_producer.py`
- `verify/verify_replication.py` (bounded)
- `run_challenge.sh` (end-to-end automation)
- `docs/AI_USAGE.md` (AI methodology per policy)

## AI Usage (per Policy)

Used for scaffolding Docker Compose, producer/verifier scripts, and drafting the MM2 patch approach.

**Human review**: I validated every line, reduced code to <500 LOC changes, and ensured no public API changes.

**Value**: Faster iteration, clearer error messages, and automation for reproducible grading.
