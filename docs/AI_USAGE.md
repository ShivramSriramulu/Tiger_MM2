# AI Usage (Methodology & Attributions)

- **Tools**: ChatGPT + Cursor to scaffold Docker Compose, producer CLI, and the MM2 patch outline.
- **Approach**:
  - Verified Kafka 4.0 official images and KRaft‑only requirement.
  - Generated a minimal, focused patch to `MirrorSourceTask` (≤500 LOC) adding fail‑fast and reset‑recovery paths without changing public APIs or connector wiring.
  - Produced automation (`run_challenge.sh`) to demonstrate all scenarios deterministically.
- **Specific help**:
  - Drafted the `AdminClient`‑based TopicId check + `seekToBeginning` workflow.
  - Surfaced the recommended `consumer.auto.offset.reset=none` hardening.
- **Human validation**: I reviewed every line, pared down logic to avoid any behavior that could interfere with Kafka Connect offsets/checkpoints or ReplicationPolicy.
