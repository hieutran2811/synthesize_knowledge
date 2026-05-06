# Redis High Availability

## 1. Master-Replica Replication

### 1.1 What & How

```
Master (primary):
  - Xử lý tất cả write operations
  - Gửi replication stream đến replicas
  - Không cần biết có bao nhiêu replicas

Replica (slave):
  - Nhận write commands từ master và apply
  - Phục vụ READ operations (scale đọc)
  - Mặc định: read-only (có thể config replica-read-only no)
  - Có thể có replica-of-replica (cascading replication)
```

**Replication flow:**
```
Full Synchronization (first time):
1. Replica sends PSYNC ? -1 (no state)
2. Master: BGSAVE → fork, create RDB snapshot
3. Master gửi RDB file to Replica
4. Master buffer write commands during RDB transfer
5. Replica load RDB (flushes DB first)
6. Master sends buffered commands → replica applies
7. Ongoing: real-time replication via replication buffer

Partial Synchronization (reconnect):
1. Replica tracks: master_replid + master_repl_offset
2. On reconnect: PSYNC replid offset
3. If master has the offset in backlog (repl-backlog-size)
   → sends only missing commands (partial sync)
4. If offset not in backlog → full sync again
```

### 1.2 Configuration

```bash
# redis.conf (replica)
replicaof 192.168.1.10 6379   # master IP + port
# Or: REPLICAOF 192.168.1.10 6379 (runtime command)

# Authentication
masterauth "strongpassword"    # if master requires AUTH

# Replica read-only (default: yes)
replica-read-only yes

# Lazy vs sync replica handling
repl-diskless-sync yes         # stream RDB directly over socket (skip disk)
repl-diskless-sync-delay 5     # wait 5s to allow more replicas to join before sending

# Replication backlog (for partial sync)
repl-backlog-size 1mb          # how much command history to keep
repl-backlog-ttl 3600          # release backlog after 3600s with no replica

# Serve stale data while resyncing
replica-serve-stale-data yes   # yes = serve (may be outdated), no = return error

# Priority for Sentinel promotion (lower = preferred)
replica-priority 100           # default 100, set 0 = never promote

# Check
INFO replication
# role:master / role:slave
# connected_slaves:2
# master_replid:abc123
# master_repl_offset:1234567
```

```python
# Python: setup replication via redis-py
import redis

master = redis.Redis(host='master-host', port=6379, decode_responses=True)
replica = redis.Redis(host='replica-host', port=6379, decode_responses=True)

# Check replication info
info = master.info('replication')
print(f"Role: {info['role']}")
print(f"Connected replicas: {info['connected_slaves']}")

# Read from replica (scale reads)
value = replica.get('hot-key')  # direct replica read
```

### 1.3 Asynchronous vs Synchronous Replication

```bash
# Default: ASYNC replication
# Master doesn't wait for replica to confirm write
# Risk: master crashes after write but before replica receives → data loss

# WAIT command: force sync for specific command
WAIT numreplicas timeout_ms

# Example: wait for 1 replica to confirm, max 1000ms
SET critical_key important_value
WAIT 1 1000    # returns number of replicas that confirmed
# If returns 0 → replica didn't confirm in time → retry or alert

# min-replicas-to-write / min-replicas-max-lag
min-replicas-to-write 1        # refuse writes if < 1 replica connected
min-replicas-max-lag 10        # replica must have responded in last 10 seconds
# Setting: guarantees at least 1 replica is up-to-date, else master rejects writes
```

---

## 2. Redis Sentinel

### 2.1 What & Why

**Redis Sentinel** = distributed system cho automatic failover. Gồm nhiều Sentinel processes monitor master + replicas.

```
Sentinel responsibilities:
1. Monitoring: ping master và replicas mỗi 1 second
2. Notification: alert khi instance fails
3. Automatic Failover: promote replica → master khi master down
4. Service Discovery: clients query Sentinel để biết current master address
```

```
Normal operation:
  Client ──► Sentinel (query master address)
             Sentinel ──► Master (172.16.0.1:6379)
  Client ──► Master (writes)
  Client ──► Replica (reads)

After failover:
  Master DOWN detected
  Sentinels vote → elect new master from replicas
  Sentinels reconfigure remaining replicas → new master
  Sentinel broadcasts new master address
  Clients (with Sentinel-aware driver) reconnect to new master
```

### 2.2 Sentinel Configuration

```bash
# sentinel.conf
port 26379
daemonize yes
logfile /var/log/redis/sentinel.log
dir /tmp

# Monitor master (name, host, port, quorum)
sentinel monitor mymaster 192.168.1.10 6379 2
# quorum = 2: at least 2 sentinels must agree master is down

# Timeout configuration
sentinel down-after-milliseconds mymaster 30000  # consider down after 30s no response
sentinel failover-timeout mymaster 180000         # failover timeout
sentinel parallel-syncs mymaster 1                # max replicas syncing simultaneously

# Authentication
sentinel auth-pass mymaster "strongpassword"

# Notification script
sentinel notification-script mymaster /var/redis/notify.sh
sentinel client-reconfig-script mymaster /var/redis/reconfig.sh
```

```python
# Python client with Sentinel support (redis-py)
from redis.sentinel import Sentinel

sentinel = Sentinel(
    [
        ('sentinel1', 26379),
        ('sentinel2', 26379),
        ('sentinel3', 26379),
    ],
    socket_timeout=0.5,
    password='strongpassword',  # Redis password
    sentinel_kwargs={'password': 'sentinel-password'},  # Sentinel AUTH
)

# Get master (for writes)
master = sentinel.master_for('mymaster', socket_timeout=0.5, decode_responses=True)
master.set('key', 'value')

# Get replica (for reads)
replica = sentinel.slave_for('mymaster', socket_timeout=0.5, decode_responses=True)
value = replica.get('key')
```

### 2.3 Failover Process

```
Timeline:
t=0s:   Master crashes (power failure, OOM, etc.)
t=30s:  Sentinels can't reach master → mark SDOWN (subjectively down)
t=30s:  Sentinels communicate → if quorum agree → ODOWN (objectively down)
t=30s:  Leader election among Sentinels (Raft-like)
t=31s:  Leader selects best replica to promote:
        - Priority (replica-priority, lower = better)
        - Replication offset (most up-to-date = better)
        - Run ID (tiebreaker)
t=32s:  REPLICAOF NO ONE → promote chosen replica to master
t=32s:  Other replicas: REPLICAOF new_master
t=33s:  Sentinels update their config with new master
t=33s:  Clients query Sentinel → get new master address → reconnect
```

### 2.4 Sentinel Limitations

```
Issues:
✗ Clients must be Sentinel-aware (handle failover reconnect)
✗ No horizontal scaling of writes (still single master)
✗ Split-brain risk if network partition isolates Sentinel nodes
✗ Configuration complexity (3+ Sentinel nodes needed)

Not suitable for:
- High write throughput (need sharding → Cluster)
- Pure in-memory (no persistence): losing master = losing data
```

---

## 3. Redis Cluster

### 3.1 What & Architecture

**Redis Cluster** = automatic sharding solution. Data phân tán trên nhiều master nodes thông qua **hash slots**.

```
Hash Slots:
- 16384 total slots (0 - 16383)
- Key → CRC16(key) % 16384 → slot number → which node handles it
- Hash tags: {user}.profile and {user}.settings → same slot (uses "user" as hash key)

Example 3-master setup:
  Node A (master): slots 0 - 5460
  Node B (master): slots 5461 - 10922
  Node C (master): slots 10923 - 16383
  
  + Each master has 1-N replicas

                    ┌──── Node A (master) 0-5460
                    │     └── Node D (replica)
Client ──► Cluster ─┤
                    ├──── Node B (master) 5461-10922
                    │     └── Node E (replica)
                    └──── Node C (master) 10923-16383
                          └── Node F (replica)
```

### 3.2 Cluster Configuration

```bash
# redis.conf (each node)
port 7001
cluster-enabled yes
cluster-config-file nodes-7001.conf   # auto-managed by Redis
cluster-node-timeout 15000            # ms before node considered failed
cluster-announce-ip 192.168.1.10     # IP to announce to other nodes
cluster-announce-port 7001
cluster-announce-bus-port 17001      # gossip port = port + 10000

# Replication in cluster
cluster-migration-barrier 1  # min replicas a master must have before migrating

# Create cluster (redis-cli)
redis-cli --cluster create \
  192.168.1.10:7001 192.168.1.10:7002 192.168.1.10:7003 \
  192.168.1.11:7001 192.168.1.11:7002 192.168.1.11:7003 \
  --cluster-replicas 1  # 1 replica per master
# auto-assigns slots and replica relationships

# Check cluster status
redis-cli -c -p 7001 cluster info
redis-cli -c -p 7001 cluster nodes
redis-cli -c -p 7001 cluster slots
```

```python
# Python Redis Cluster client
from redis.cluster import RedisCluster

rc = RedisCluster(
    startup_nodes=[
        {"host": "192.168.1.10", "port": 7001},
        {"host": "192.168.1.10", "port": 7002},
    ],
    decode_responses=True,
    skip_full_coverage_check=True,
)

# Transparent: client automatically routes to correct node
rc.set("user:1000", "alice")   # → hash slot → correct node
value = rc.get("user:1000")

# Hash tags: force same slot
rc.set("{user:1000}.profile", "...")   # same slot as {user:1000}.settings
rc.set("{user:1000}.settings", "...")

# Multi-key operations: ALL keys must be in same slot
# If not, CROSSSLOT error!
rc.mset({"key1": "v1", "key2": "v2"})  # May fail if on different nodes
# Solution: use hash tags or pipeline per-node
```

### 3.3 Gossip Protocol

```
Cluster nodes communicate via gossip:
- Each node pings random subset every second
- Includes cluster state (who is master, who is replica, which slots)
- Failure detection:
  1. Node A can't reach Node B → marks B as PFAIL (probably failed)
  2. Node A gossips PFAIL to other nodes
  3. If majority of masters agree → B is FAIL (objectively failed)
  4. Automatic failover: B's replica promoted to master

Bus port = data port + 10000 (default)
Nodes must be able to communicate on both ports
```

### 3.4 Cluster Operations

```bash
# Add new master node
redis-cli --cluster add-node 192.168.1.12:7001 192.168.1.10:7001

# Add replica to existing master
redis-cli --cluster add-node 192.168.1.12:7002 192.168.1.10:7001 \
  --cluster-slave \
  --cluster-master-id <master-node-id>

# Rebalance slots (after adding nodes)
redis-cli --cluster rebalance 192.168.1.10:7001 --cluster-use-empty-masters

# Move specific slots
redis-cli --cluster reshard 192.168.1.10:7001 \
  --cluster-from <source-node-id> \
  --cluster-to <target-node-id> \
  --cluster-slots 1000 \
  --cluster-yes

# Remove node (must be empty of slots first)
redis-cli --cluster del-node 192.168.1.10:7001 <node-id>

# Check cluster health
redis-cli --cluster check 192.168.1.10:7001
redis-cli --cluster info 192.168.1.10:7001

# Fix cluster issues
redis-cli --cluster fix 192.168.1.10:7001
```

### 3.5 Cross-Slot Limitations

```python
# PROBLEM: Multi-key commands require same slot
import redis
r = redis.RedisCluster(startup_nodes=[...])

# These fail with CROSSSLOT error if keys map to different slots:
r.mget("key1", "key2", "key3")
r.rename("src", "dst")
r.sunionstore("dest", "set1", "set2")

# SOLUTION 1: Hash tags
r.set("{item}:price", 100)
r.set("{item}:stock", 500)
r.set("{item}:name", "Widget")
# All above go to same slot (hash of "item")
r.mget("{item}:price", "{item}:stock", "{item}:name")  # works!

# SOLUTION 2: Lua script (executes on single node)
# Only works if all keys in script are on same node!

# SOLUTION 3: Application-level logic
# Fetch individually and combine in app

# SOLUTION 4: Pipeline per node
# redis-py ClusterPipeline automatically batches by node
pipe = r.pipeline()
pipe.get("key1")
pipe.get("key2")
results = pipe.execute()  # batched per node transparently
```

### 3.6 Sentinel vs Cluster Comparison

| Feature | Sentinel | Cluster |
|---------|---------|--------|
| Purpose | HA for single master | HA + horizontal scaling |
| Write scaling | No (single master) | Yes (multiple masters) |
| Data sharding | No | Yes (16384 hash slots) |
| Multi-key ops | All supported | Cross-slot limited |
| Client complexity | Sentinel-aware client | Cluster-aware client |
| Min nodes | 1 master + 1 replica + 3 sentinels | 6 nodes (3 master + 3 replica) |
| Max dataset | Single machine RAM | N × single machine RAM |
| Config complexity | Medium | High |
| When to use | < 100GB, need HA | > 100GB or need write scaling |

---

## 4. Docker Compose: Redis HA Setup

### 4.1 Master-Replica với Sentinel

```yaml
# docker-compose.yml
version: '3.8'

services:
  redis-master:
    image: redis:7.2-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD} --appendonly yes
    ports:
      - "6379:6379"
    volumes:
      - redis_master_data:/data
    networks:
      - redis_net
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis-replica1:
    image: redis:7.2-alpine
    command: >
      redis-server
      --replicaof redis-master 6379
      --requirepass ${REDIS_PASSWORD}
      --masterauth ${REDIS_PASSWORD}
      --replica-read-only yes
    depends_on:
      redis-master:
        condition: service_healthy
    networks:
      - redis_net

  redis-replica2:
    image: redis:7.2-alpine
    command: >
      redis-server
      --replicaof redis-master 6379
      --requirepass ${REDIS_PASSWORD}
      --masterauth ${REDIS_PASSWORD}
      --replica-read-only yes
    depends_on:
      redis-master:
        condition: service_healthy
    networks:
      - redis_net

  sentinel1:
    image: redis:7.2-alpine
    command: >
      sh -c "echo 'sentinel monitor mymaster redis-master 6379 2
      sentinel auth-pass mymaster ${REDIS_PASSWORD}
      sentinel down-after-milliseconds mymaster 5000
      sentinel failover-timeout mymaster 30000
      sentinel parallel-syncs mymaster 1' > /etc/sentinel.conf
      && redis-sentinel /etc/sentinel.conf"
    ports:
      - "26379:26379"
    depends_on:
      - redis-master
    networks:
      - redis_net

  sentinel2:
    image: redis:7.2-alpine
    command: >
      sh -c "echo 'sentinel monitor mymaster redis-master 6379 2
      sentinel auth-pass mymaster ${REDIS_PASSWORD}
      sentinel down-after-milliseconds mymaster 5000
      sentinel failover-timeout mymaster 30000
      sentinel parallel-syncs mymaster 1' > /etc/sentinel.conf
      && redis-sentinel /etc/sentinel.conf"
    ports:
      - "26380:26379"
    depends_on:
      - redis-master
    networks:
      - redis_net

  sentinel3:
    image: redis:7.2-alpine
    command: >
      sh -c "echo 'sentinel monitor mymaster redis-master 6379 2
      sentinel auth-pass mymaster ${REDIS_PASSWORD}
      sentinel down-after-milliseconds mymaster 5000
      sentinel failover-timeout mymaster 30000
      sentinel parallel-syncs mymaster 1' > /etc/sentinel.conf
      && redis-sentinel /etc/sentinel.conf"
    ports:
      - "26381:26379"
    depends_on:
      - redis-master
    networks:
      - redis_net

networks:
  redis_net:
    driver: bridge

volumes:
  redis_master_data:
```

### 4.2 Spring Boot với Redis Sentinel

```yaml
# application.yml
spring:
  data:
    redis:
      sentinel:
        master: mymaster
        nodes:
          - sentinel1:26379
          - sentinel2:26379
          - sentinel3:26379
        password: ${REDIS_SENTINEL_PASSWORD}
      password: ${REDIS_PASSWORD}
      lettuce:
        pool:
          max-active: 8
          max-idle: 8
          min-idle: 2
          max-wait: -1ms
```

```java
// Java: LettuceConnectionFactory với Sentinel
@Configuration
public class RedisConfig {
    
    @Bean
    public RedisConnectionFactory redisConnectionFactory() {
        RedisSentinelConfiguration sentinelConfig = new RedisSentinelConfiguration()
            .master("mymaster")
            .sentinel("sentinel1", 26379)
            .sentinel("sentinel2", 26379)
            .sentinel("sentinel3", 26379);
        
        sentinelConfig.setPassword("redis-password");
        sentinelConfig.setSentinelPassword("sentinel-password");
        
        // Read from replica for non-critical reads
        LettuceClientConfiguration clientConfig = LettuceClientConfiguration.builder()
            .readFrom(ReadFrom.REPLICA_PREFERRED)  // prefer replica, fallback to master
            .build();
        
        return new LettuceConnectionFactory(sentinelConfig, clientConfig);
    }
    
    @Bean
    public RedisTemplate<String, Object> redisTemplate(RedisConnectionFactory factory) {
        RedisTemplate<String, Object> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);
        template.setKeySerializer(new StringRedisSerializer());
        template.setValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.setHashKeySerializer(new StringRedisSerializer());
        template.setHashValueSerializer(new GenericJackson2JsonRedisSerializer());
        template.afterPropertiesSet();
        return template;
    }
}
```

---

## 5. Production Checklist: Redis HA

```bash
# 1. Persistence: use hybrid (RDB + AOF)
aof-use-rdb-preamble yes
appendonly yes
appendfsync everysec
save 3600 1
save 300 100
save 60 10000

# 2. Replication
# At least 1 replica per master
min-replicas-to-write 1
min-replicas-max-lag 10

# 3. Memory protection
maxmemory 8gb
maxmemory-policy allkeys-lru
# Or: volatile-lru (only expire keys), allkeys-lfu (LFU)

# 4. Security
requirepass "strongpassword"
bind 127.0.0.1  # don't expose to internet
tls-port 6380
# ACL: see redis_performance.md

# 5. Kernel settings (OS level)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
# Prevent THP causing fork latency spikes
sysctl -w vm.overcommit_memory=1
# Allow Redis to fork without "can't save" errors

# 6. Monitoring
latency-monitor-threshold 100  # track commands > 100ms
latency-history latency on
slowlog-log-slower-than 10000  # log commands > 10ms
slowlog-max-len 128

# 7. Sentinel quorum = majority
# 3 sentinels → quorum = 2
# 5 sentinels → quorum = 3
```

## Ghi chú – Topics tiếp theo

- **Eviction Policies**: LRU, LFU, volatile-*, allkeys-* → `redis_performance.md`
- **Pipelining**: batch RTT reduction → `redis_performance.md`
- **Lua scripting**: atomic custom logic → `redis_performance.md`
- **MULTI/EXEC**: transactions → `redis_performance.md`
- **ACL**: fine-grained authorization → `redis_performance.md`
- **RESP3**: new protocol (Redis 6+) → `redis_performance.md`
- **Monitoring**: LATENCY, SLOWLOG, MONITOR, redis-cli → `redis_performance.md`
