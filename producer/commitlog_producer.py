import argparse, json, os, random, time, uuid
from datetime import datetime
from kafka import KafkaProducer

OPS = ["CREATE", "UPDATE", "DELETE"]

parser = argparse.ArgumentParser()
parser.add_argument("--count", type=int, required=True)
parser.add_argument("--bootstrap", default=os.getenv("BOOTSTRAP", "kafka-primary:9092"))
parser.add_argument("--topic", default=os.getenv("TOPIC", "commit-log"))
args = parser.parse_args()

prod = KafkaProducer(bootstrap_servers=args.bootstrap, value_serializer=lambda v: json.dumps(v).encode("utf-8"))

for i in range(args.count):
    evt = {
        "event_id": str(uuid.uuid4()),
        "timestamp": int(time.time()),
        "op_type": random.choice(OPS),
        "key": f"doc:{random.randint(0, 65535):04x}",
        "value": {"status": random.choice(["active","archived","deleted"])},
    }
    prod.send(args.topic, value=evt)
    if i % 100 == 0:
        print(f"produced {i}")
prod.flush()
print(f"done: produced {args.count} events to {args.topic}")
