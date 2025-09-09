# Architecture Flow Diagram

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Kafka MM2 DR Demo Architecture                        │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PRIMARY       │    │   MIRRORMAKER   │    │   DR CLUSTER    │
│   CLUSTER       │    │       2         │    │                 │
│                 │    │                 │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ Kafka 4.0   │ │    │ │ Vanilla MM2 │ │    │ │ Kafka 4.0   │ │
│ │ (KRaft)     │ │    │ │             │ │    │ │ (KRaft)     │ │
│ │ Port: 19092 │ │    │ │ Enhanced MM2│ │    │ │ Port: 29092 │ │
│ └─────────────┘ │    │ │ (Patched)   │ │    │ └─────────────┘ │
│                 │    │ └─────────────┘ │    │                 │
│ ┌─────────────┐ │    │                 │    │ ┌─────────────┐ │
│ │ commit-log  │ │    │                 │    │ │primary.     │ │
│ │ topic       │ │    │                 │    │ │commit-log   │ │
│ │ (1 partition)│ │    │                 │    │ │topic        │ │
│ └─────────────┘ │    │                 │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PRODUCER      │    │   FAULT         │    │   VERIFIER      │
│   (CLI)         │    │   TOLERANCE     │    │   (Bounded)     │
│                 │    │   FEATURES      │    │                 │
│ • --count N     │    │                 │    │ • --expect 1000 │
│ • JSON events   │    │ • Fail-fast on  │    │ • --timeout 20s │
│ • CREATE/UPDATE │    │   truncation    │    │ • Exit on count │
│   /DELETE       │    │                 │    │   or timeout    │
│                 │    │ • Auto-recover  │    │                 │
│                 │    │   on reset      │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Data Flow

```
1. PRODUCTION PHASE
   Producer → commit-log (Primary) → Vanilla MM2 → primary.commit-log (DR)

2. TRUNCATION TEST
   Stop MM2 → Wait 65s (retention=60s) → Produce 10 msgs → Enhanced MM2
   Enhanced MM2 → TRUNCATION_DETECTED → Fail-fast with ConnectException

3. TOPIC RESET TEST
   Delete commit-log → Recreate commit-log → Produce 50 msgs → Enhanced MM2
   Enhanced MM2 → RESET_DETECTED → seekToBeginning → Continue mirroring

4. VERIFICATION
   Verifier → primary.commit-log (DR) → Count messages → Exit (1000/1000)
```

## Fault-Tolerance Enhancements

### Enhanced MM2 Patch (≤500 LOC)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MirrorSourceTask Enhancements               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐                    │
│  │  TRUNCATION     │    │  TOPIC RESET    │                    │
│  │  DETECTION      │    │  HANDLING       │                    │
│  │                 │    │                 │                    │
│  │ • Catch         │    │ • Cache TopicId │                    │
│  │   OffsetOutOf   │    │   per topic     │                    │
│  │   RangeException│    │                 │                    │
│  │                 │    │ • Detect ID     │                    │
│  │ • Log           │    │   change        │                    │
│  │   TRUNCATION_   │    │                 │                    │
│  │   DETECTED      │    │ • Log RESET_    │                    │
│  │                 │    │   DETECTED      │                    │
│  │ • Throw         │    │                 │                    │
│  │   ConnectException│  │ • seekToBeginning│                   │
│  │                 │    │                 │                    │
│  └─────────────────┘    └─────────────────┘                    │
│                                                                 │
│  Configuration Properties:                                      │
│  • mirrorsource.fail.on.truncation=true                        │
│  • mirrorsource.auto.recover.on.reset=true                     │
│  • mirrorsource.topic.reset.retry.ms=5000                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Mac M1 Optimizations

```
┌─────────────────────────────────────────────────────────────────┐
│                      Performance Optimizations                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  • retention.ms=60000 (60s) for proper truncation testing      │
│  • sleep 65s for truncation test (wait past retention)         │
│  • Bounded verifier (--expect 1000 --timeout 20)               │
│  • platform: linux/arm64 for all containers                    │
│  • Multi-stage Docker builds with layer caching                │
│  • Idempotent run_challenge.sh with cleanup                    │
│                                                                 │
│  Result: Efficient execution with proper assessment timing     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## RPO/RTO Alignment

```
┌─────────────────────────────────────────────────────────────────┐
│                    TigerGraph-Style DR Goals                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  RPO (Recovery Point Objective):                               │
│  • Bound by MM2 lag + source retention                         │
│  • Fail-fast truncation makes data loss visible                │
│  • No silent gaps in replication                               │
│                                                                 │
│  RTO (Recovery Time Objective):                                │
│  • Auto-recovery on topic reset reduces manual ops             │
│  • Fast detection and response to failures                     │
│  • Cross-region event replication (Primary → DR)               │
│                                                                 │
│  HA + DR Pattern:                                               │
│  • In-cluster ISR for HA within region                         │
│  • Cross-cluster MM2 for DR across regions                     │
│  • Durable, auditable event movement to DR region              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```
