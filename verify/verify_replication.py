import argparse, time
from kafka import KafkaConsumer, TopicPartition

def read_count(topic: str, bootstrap: str, timeout_s: int, expect: int | None):
    consumer = KafkaConsumer(
        bootstrap_servers=bootstrap,
        enable_auto_commit=False,
        auto_offset_reset="earliest",
        consumer_timeout_ms=int(timeout_s * 1000),
        group_id=f"verifier-{int(time.time()*1000)}",
    )
    # assessment spec: 1 partition
    tp = TopicPartition(topic, 0)
    consumer.assign([tp])
    consumer.seek_to_beginning(tp)

    target = expect
    if target is None:
        target = consumer.end_offsets([tp])[tp]

    count = 0
    start = time.time()
    while time.time() - start < timeout_s and count < target:
        batch = consumer.poll(timeout_ms=500)
        if not batch:
            if expect is None:
                target = consumer.end_offsets([tp])[tp]
            continue
        for _, records in batch.items():
            count += len(records)

    consumer.close()
    return count, target

if __name__ == "__main__":
    import os
    ap = argparse.ArgumentParser()
    ap.add_argument("--bootstrap", default="kafka-dr:9092")
    ap.add_argument("--topic", default="primary.commit-log")
    ap.add_argument("--timeout", type=int, default=int(os.getenv("TIMEOUT", "20")))
    ap.add_argument("--expect", type=int, default=int(os.getenv("EXPECT", "0")) if os.getenv("EXPECT") else None)
    args = ap.parse_args()

    count, target = read_count(args.topic, args.bootstrap, args.timeout, args.expect)
    print(f"{count}/{target}")
    if args.expect is not None and count < args.expect:
        raise SystemExit(1)
