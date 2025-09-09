# Design Notes

## Why Kafka 4.0 official images?
- Multi‑arch (arm64) + KRaft only. One container per cluster is enough for the assessment.

## Enhanced MM2 changes
We extend `MirrorSourceTask` to:
1. **Fail‑fast on truncation**: When the source consumer throws `OffsetOutOfRangeException` (because retention removed messages older than our position), we log `TRUNCATION_DETECTED` with earliest offsets and **throw `ConnectException`**. Vanilla MM2 can reset silently depending on `auto.offset.reset`; failing fast surfaces the data loss immediately.
2. **Auto‑recover on topic reset**: We cache source **TopicId** per topic using `Admin.describeTopics`. If the TopicId changes (delete/recreate) we log `RESET_DETECTED` and `seekToBeginning` for assigned partitions of that topic so mirroring resumes cleanly. If `UnknownTopicOrPartitionException` occurs, we backoff and retry until the topic reappears.

### LOC budget
~230 LOC added, well under 500 LOC requirement.

### Integration
No changes to external APIs. Controlled via properties:
- `mirrorsource.fail.on.truncation=true|false`
- `mirrorsource.auto.recover.on.reset=true|false`
- `mirrorsource.topic.reset.retry.ms=5000`

### Test scenarios
- **Normal flow**: vanilla → 1000 msgs → DR sees ~1000
- **Truncation**: stop MM2, wait > retention, produce → Enhanced MM2 logs `TRUNCATION_DETECTED` and fails
- **Reset**: delete+recreate topic, produce → Enhanced MM2 logs `RESET_DETECTED` and continues mirroring
