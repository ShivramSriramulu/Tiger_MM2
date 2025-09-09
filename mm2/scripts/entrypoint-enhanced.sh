#!/usr/bin/env bash
set -euo pipefail
# Wait for brokers
/opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka-dr:9092 --list >/dev/null 2>&1 || true
sleep 3
exec /opt/kafka/bin/connect-mirror-maker.sh /opt/mm2/connect-mirror-maker.enhanced.properties
