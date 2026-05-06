# Kafka Replication & Fault Tolerance – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Kafka Replication

**Replication** là cơ chế Kafka đảm bảo durability và availability: mỗi partition có 1 Leader và N-1 Follower replicas. Data được replicate từ Leader sang Followers trước khi ACK producer.

```
Replication factor (RF):
  RF=1: no redundancy (single point of failure)
  RF=3: standard production (tolerate 1 broker failure)
  RF=5: tolerate 2 broker failures (financial/critical systems)

Data flow:
  Producer → Leader (write) → ISR Followers (replicate) → ACK producer
  Consumer ← Leader (read by default, can read from follower in KIP-392)
```

---

## Components – ISR (In-Sync Replicas)

```
ISR: set of replicas that are "in sync" with the leader
  Leader: always in ISR
  Follower: joins ISR when caught up within replica.lag.time.max.ms

A follower falls OUT of ISR when:
  - No heartbeat to leader for replica.lag.time.max.ms (default 30s)
  - Fetch lag: follower's fetch offset lags too far behind leader
    (controlled by same replica.lag.time.max.ms)

ISR changes are tracked by ZooKeeper/KRaft:
  ZK mode:  /brokers/topics/{topic}/partitions/{id}/state
  KRaft:    metadata log (Raft-based)

Example:
  Topic: orders, Partition 0, RF=3
  Leader: Broker-1 (offset 1000)
  Follower Broker-2: offset 998 → IN ISR (within lag threshold)
  Follower Broker-3: offset 850 → OUT OF ISR (lagging too far)
  ISR: [1, 2]
```

---

## How – Replication Protocol

```
Fetch-based replication:
  Followers continuously send FETCH requests to leader
  Leader responds with records from the follower's current offset
  No push from leader → follower controls fetch rate

High-water mark (HWM):
  Offset up to which all ISR replicas have confirmed
  Consumers can only read up to HWM (not leader's end offset!)
  → Prevents reading uncommitted data

Log End Offset (LEO):
  Latest offset in leader's log (ahead of HWM if some followers behind)

Producer ACK flow (acks=all):
  1. Producer sends batch to leader
  2. Leader appends to local log (LEO advances)
  3. Followers FETCH and append to their logs
  4. Followers report their LEO back to leader
  5. Leader advances HWM when all ISR have replicated
  6. Leader sends ACK to producer

Timeline:
  t0: Leader LEO=100, HWM=95, ISR=[B1,B2,B3]
  t1: Producer sends msg → Leader LEO=101
  t2: B2 fetches → LEO=101; B3 fetches → LEO=101
  t3: Leader sees all ISR at LEO=101 → HWM=101
  t4: Leader ACKs producer
```

---

## How – Leader Election

```
Trigger: leader broker fails or network partition

ZooKeeper mode:
  1. ZK detects broker failure (ZK session expires)
  2. Controller broker (elected by ZK) handles leader election
  3. Controller selects first ISR replica as new leader
  4. Controller updates ZK with new leader metadata
  5. All brokers notified (LeaderAndIsr request)
  
KRaft mode (faster):
  1. Active controller detects broker failure
  2. Controller selects new leader from ISR
  3. Updates metadata log (Raft)
  4. Followers apply metadata change
  Speed: ~10s (KRaft) vs ~30-60s (ZK) for large clusters

ISR-based election:
  New leader = first broker in ISR list
  If ISR is empty: depends on unclean.leader.election.enable
```

---

## How – min.insync.replicas & acks

```
Configuration interaction:
  acks=all + min.insync.replicas=2 + RF=3

  Scenario 1: All 3 brokers up → ISR=[1,2,3]
    - Write succeeds: 3 ISR ≥ min.insync.replicas=2 ✅

  Scenario 2: 1 broker down → ISR=[1,2]
    - Write succeeds: 2 ISR ≥ min.insync.replicas=2 ✅

  Scenario 3: 2 brokers down → ISR=[1]
    - Write FAILS: 1 ISR < min.insync.replicas=2 ❌
    - Producer gets NotEnoughReplicasException
    - CORRECT: prevents data loss (if accepted, 1 copy = high loss risk)

  Scenario 4: acks=1, min.insync.replicas=2
    - min.insync.replicas only checked with acks=all
    - acks=1: leader ACKs immediately → min.insync.replicas ignored

Rule:
  RF=3, min.insync.replicas=2, acks=all
  → Tolerate 1 broker failure without data loss
  → Production standard
```

```properties
# Broker defaults
default.replication.factor=3
min.insync.replicas=2

# Per-topic
kafka-configs.sh --alter --entity-type topics --entity-name orders \
  --add-config min.insync.replicas=2

# Verify
kafka-configs.sh --describe --entity-type topics --entity-name orders
```

---

## How – Unclean Leader Election

```
Unclean leader election: elect a leader from OUT-OF-ISR replicas
  Trigger: no ISR replica available (all ISR brokers are down)
  
  unclean.leader.election.enable=false (default, production):
    - Partition offline (unavailable) until an ISR broker comes back
    - ✅ No data loss
    - ❌ Partition unavailable (potential downtime)

  unclean.leader.election.enable=true:
    - Elect any available replica (out-of-sync)
    - ✅ Partition stays available
    - ❌ DATA LOSS: missing records that weren't replicated
    - Use for: non-critical topics where availability > durability

Decision matrix:
  Financial/critical:  unclean=false (no data loss ever)
  Metrics/logs:        unclean=true (availability over durability)
  Event streaming:     unclean=false (default)
```

```bash
# Per-topic unclean election
kafka-configs.sh --alter --entity-type topics --entity-name app-metrics \
  --add-config unclean.leader.election.enable=true
```

---

## How – Preferred Replica Election

```
Problem: After broker restarts, leadership doesn't auto-return to original broker
  → Imbalanced: 1 broker becomes leader for many partitions

Solution: Preferred replica election
  preferred replica = first broker listed in partition's replicas list
  auto.leader.rebalance.enable=true (default): 
    - Background check every leader.imbalance.check.interval.seconds (300s)
    - Rebalance if any broker's leadership imbalance > leader.imbalance.per.broker.percentage (10%)

Manual rebalance:
  kafka-preferred-replica-election.sh --bootstrap-server localhost:9092
  # KRaft/newer: kafka-leader-election.sh
```

---

## How – Follower Fetching (KIP-392, Kafka 2.4+)

```
Consumer Fetch from Follower:
  Default: consumers read from leader (all reads concentrated)
  KIP-392: consumers can read from closest replica
    → Reduce cross-AZ network costs
    → Lower latency for consumers in same AZ as follower
    → Trade-off: may read slightly stale data (behind HWM)
```

```properties
# Consumer config
client.rack=us-east-1a  # consumer's AZ/rack

# Broker replica config
broker.rack=us-east-1a  # for rack-aware replica placement

# Topic: assign replicas across AZs
# Kafka auto-assigns if broker.rack configured on all brokers
# → RF=3 on 3 brokers in 3 AZs → 1 replica per AZ
```

---

## How – Monitoring Replication

```bash
# Under-Replicated Partitions (most critical metric!)
kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions
# → Should always be 0

# Under minimum ISR partitions
kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-min-isr-partitions

# Offline partitions (no leader!)
kafka-topics.sh --bootstrap-server localhost:9092 --describe --unavailable-partitions

# Describe all topics with replica details
kafka-topics.sh --bootstrap-server localhost:9092 --describe
# Partition: 0  Leader: 1  Replicas: 1,2,3  Isr: 1,2,3

# Log dirs and sizes
kafka-log-dirs.sh --bootstrap-server localhost:9092 --topic-list orders

# Replica lag (JMX)
# kafka.server:type=ReplicaFetcherManager,name=MaxLag,clientId=Replica
```

```
JMX Metrics to monitor:
  UnderReplicatedPartitions:   > 0 = CRITICAL ALERT
  UnderMinIsrPartitionCount:   > 0 = WARNING
  OfflinePartitionsCount:      > 0 = CRITICAL (data unavailable)
  ActiveControllerCount:       != 1 = CRITICAL
  IsrShrinks/IsrExpands:       high rate = instability
  LeaderElectionRateAndTimeMs: high = broker restarts or network issues
  ReplicationBytesInPerSec:    replication traffic
  ReplicaMaxLag:               follower lag threshold
```

---

## Why – Kafka Replication vs Database Replication

```
Kafka:
  Pull-based: followers pull from leader
  ✅ Follower controls rate (no overwhelming slow followers)
  ✅ Leader has no state per follower (scalable)
  ❌ Higher latency than push for single record

PostgreSQL streaming replication:
  Push-based: primary pushes WAL to standbys
  ✅ Lower latency for small writes
  ❌ Primary must track each standby's state

Kafka ISR vs Database quorum:
  Kafka ISR: dynamic set (falls out when lagging)
    → Flexible: faster writes when followers are slow
  Database Quorum (Raft/Paxos): majority must confirm
    → Strict: write waits for majority regardless of lag
  
  Kafka trade-off: ISR can shrink to 1 (leader only) during lag
    → Potential durability window if leader fails during lag
    → Mitigated by min.insync.replicas
```

---

## Trade-offs

```
RF=1:
  ✅ Fastest, cheapest
  ❌ Data loss on broker failure
  → Dev/test only

RF=3 + min.insync.replicas=2:
  ✅ Standard production: tolerate 1 failure
  Balanced: availability vs durability
  → Most production use cases

RF=3 + min.insync.replicas=3:
  ✅ All 3 must confirm
  ❌ Any broker down → writes fail
  → Very strict durability, low availability
  → Don't use unless absolutely necessary

replica.lag.time.max.ms:
  Low (10s):  ISR shrinks/expands more aggressively (GC pauses cause false shrinks)
  High (60s): tolerates slow followers, but lag detection slower
  → Default 30s usually fine

Leader election speed:
  ZK mode:   30-60s for large clusters (controller has many partitions to update)
  KRaft:     ~10s (metadata propagation faster)
  → Migrate to KRaft for faster failover
```

---

## Real-world

```
Production replication checklist:
  ✅ RF=3 for all critical topics
  ✅ min.insync.replicas=2 (broker-level default)
  ✅ acks=all for critical producers
  ✅ unclean.leader.election.enable=false (default)
  ✅ auto.leader.rebalance.enable=true (default)
  ✅ broker.rack configured for AZ-aware replica placement
  ✅ Monitor: UnderReplicatedPartitions + OfflinePartitionsCount
  ✅ Regularly test broker failure recovery

Rack-aware assignment (production multi-AZ setup):
  3 brokers: broker-1 (AZ-a), broker-2 (AZ-b), broker-3 (AZ-c)
  RF=3: Kafka auto-assigns 1 replica per AZ
  → Survive AZ failure (not just broker failure)

MirrorMaker2 (disaster recovery, multi-datacenter):
  See connect.md for cross-cluster replication setup
```

---

## Ghi chú – Chủ đề tiếp theo
> `kafka_streams.md`: Kafka Streams API, KStream/KTable/GlobalKTable, stateful operations, joins, windowing, state stores (in-memory, RocksDB), exactly-once processing, topology

---

*Cập nhật lần cuối: 2026-05-06*
