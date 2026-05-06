# Redis Performance & Internals

## 1. Memory Model & Optimization

### 1.1 Memory Eviction Policies

**Khi `maxmemory` bị đầy**, Redis cần quyết định key nào cần xóa:

```bash
# redis.conf
maxmemory 4gb
maxmemory-policy allkeys-lru

# Policies:
# noeviction (default): return error on write commands (NEVER use for cache)
# allkeys-lru:     LRU trên tất cả keys (best for pure cache)
# allkeys-lfu:     LFU trên tất cả keys (Redis 4.0+, better for skewed access)
# allkeys-random:  Random eviction
# volatile-lru:    LRU chỉ trên keys có TTL set
# volatile-lfu:    LFU chỉ trên keys có TTL set
# volatile-random: Random trên keys có TTL
# volatile-ttl:    Evict keys với TTL gần hết nhất

# LRU approximation (không phải true LRU)
maxmemory-samples 5    # sample 5 keys, evict least-recently-used
# Higher = more accurate but slower, 10 = close to true LRU
```

**LRU vs LFU:**
| | LRU (Least Recently Used) | LFU (Least Frequently Used) |
|--|--------------------------|------------------------------|
| Evict | Longest time since last access | Lowest access frequency |
| Good for | General caching | Hot key patterns (viral content) |
| Problem | Scan-once pollution (spike evicts hot keys) | Needs warm-up time |
| Redis impl | Clock-based approximation | Morris counter |

```bash
# LFU tuning
lfu-log-factor 10       # higher = slower frequency increase, better precision
lfu-decay-time 1        # minutes between frequency decay (0 = no decay)

# Check object frequency
OBJECT FREQ key         # requires lfu policy or lfu-policy-config
```

### 1.2 Memory Optimization Tips

```bash
# 1. Choose right data type + size thresholds
# Hash vs String for objects:
# HSET user:1 name Alice age 30 → uses listpack if < 128 fields, each < 64 bytes
# vs SET user:1 '{"name":"Alice","age":30}' → raw string

# Config for compressed encodings
hash-max-listpack-entries 128   # up to 128 fields → use listpack
hash-max-listpack-value 64      # field value <= 64 bytes → listpack
list-max-listpack-size -2       # -2 = max 8kb per listpack node
zset-max-listpack-entries 128
zset-max-listpack-value 64
set-max-intset-entries 512      # all-integer sets up to 512 → intset
set-max-listpack-entries 128    # small string sets → listpack (Redis 7.2+)

# 2. Key naming: short but meaningful
# Bad:  user_session_token_for_authentication_service
# Good: s:{userId}  (prefix:id pattern)

# 3. Memory analysis
redis-cli --bigkeys              # find largest keys
redis-cli --memkeys              # memory usage per key pattern
redis-cli --hotkeys              # most accessed keys (requires LFU)

MEMORY USAGE key [SAMPLES count]  # memory for specific key (bytes)
MEMORY STATS                      # detailed memory breakdown
MEMORY DOCTOR                     # diagnostic recommendations
MEMORY PURGE                      # defragment (active defrag must be enabled)

# 4. Active defragmentation (Redis 4.0+)
activedefrag yes              # enable
active-defrag-ignore-bytes 100mb  # start when fragmentation > 100MB
active-defrag-threshold-lower 10  # start when fragmentation > 10%
active-defrag-threshold-upper 100 # max effort at 100% fragmentation
active-defrag-cycle-min 1         # min CPU % for defrag
active-defrag-cycle-max 25        # max CPU % for defrag

# 5. Lazy freeing (async DEL for large objects)
lazyfree-lazy-eviction yes    # async eviction
lazyfree-lazy-expire yes      # async key expiry
lazyfree-lazy-server-del yes  # async internal deletes
lazyfree-lazy-user-del yes    # UNLINK = async DEL
lazyfree-lazy-user-flush yes  # async FLUSHDB/FLUSHALL

# Use UNLINK instead of DEL for large keys!
UNLINK large_list_with_millions_elements  # non-blocking
```

### 1.3 Memory Monitoring

```bash
INFO memory | grep -E "used_memory_human|mem_fragmentation_ratio|used_memory_peak_human"

# Key metrics:
# used_memory: allocated by Redis
# used_memory_rss: actual RSS from OS
# mem_fragmentation_ratio = rss / used_memory
#   - < 1.0: data is being swapped (critical problem!)
#   - 1.0-1.5: healthy range
#   - > 2.0: very fragmented (run MEMORY PURGE or restart)
# used_memory_peak_human: peak memory (helps size maxmemory)
```

---

## 2. Pipelining

### 2.1 What & Why

**Pipelining** = gửi nhiều commands trong một batch mà không cần đợi response từng lệnh.

```
Without Pipeline:
Client → [SET k1 v1] → Server → [OK] → Client (1 RTT)
Client → [SET k2 v2] → Server → [OK] → Client (1 RTT)
Client → [GET k3]    → Server → [v3] → Client (1 RTT)
Total: 3 RTTs

With Pipeline:
Client → [SET k1 v1 | SET k2 v2 | GET k3] → Server
Server → [OK | OK | v3] → Client
Total: 1 RTT

At 1ms latency: 1000 commands = 1000ms vs 1ms (1000x faster throughput!)
```

```python
# redis-py pipelining
import redis

r = redis.Redis(host='localhost', port=6379, decode_responses=True)

# Pipeline (no auto-execute)
pipe = r.pipeline(transaction=False)  # transaction=False = pure pipeline, no MULTI/EXEC

pipe.set('k1', 'v1')
pipe.set('k2', 'v2')
pipe.incr('counter')
pipe.hset('user:1', mapping={'name': 'Alice', 'age': '30'})

results = pipe.execute()
# results = [True, True, 1, 1]  # responses in order

# Context manager
with r.pipeline(transaction=False) as pipe:
    for i in range(1000):
        pipe.set(f'key:{i}', f'value:{i}')
    pipe.execute()

# Pipeline vs Transaction (MULTI/EXEC):
# Pipeline: commands sent in batch, executed sequentially (no atomicity guarantee)
# Transaction: MULTI/EXEC wraps → all-or-nothing, but holds server until EXEC

# Benchmark pipelining impact
import time

def benchmark(r, use_pipeline=False):
    count = 10000
    start = time.time()
    
    if use_pipeline:
        with r.pipeline(transaction=False) as pipe:
            for i in range(count):
                pipe.set(f'bench:{i}', i)
            pipe.execute()
    else:
        for i in range(count):
            r.set(f'bench:{i}', i)
    
    elapsed = time.time() - start
    print(f"{'Pipeline' if use_pipeline else 'Sequential'}: {elapsed:.2f}s ({count/elapsed:.0f} ops/sec)")

benchmark(r, False)   # ~500 ops/sec (local!) → imagine with network latency
benchmark(r, True)    # ~50000 ops/sec
```

### 2.2 Pipelining in Java (Lettuce / Jedis)

```java
// Lettuce async pipeline
@Service
public class RedisBatchService {
    
    @Autowired
    private RedisTemplate<String, String> redisTemplate;
    
    public void batchWrite(List<Map.Entry<String, String>> entries) {
        redisTemplate.executePipelined(
            (RedisCallback<Object>) connection -> {
                StringRedisConnection stringRedis = (StringRedisConnection) connection;
                for (Map.Entry<String, String> entry : entries) {
                    stringRedis.set(entry.getKey(), entry.getValue());
                }
                return null;
            }
        );
    }
    
    // Lettuce reactive pipeline
    @Autowired
    private ReactiveRedisTemplate<String, String> reactiveRedis;
    
    public Flux<String> batchGet(List<String> keys) {
        return reactiveRedis.executePipelined(
            (ReactiveRedisCallback<Object>) connection -> {
                Flux<String> results = Flux.fromIterable(keys)
                    .flatMap(key -> connection.stringCommands()
                        .get(ByteBuffer.wrap(key.getBytes())));
                return results.then();
            }
        );
    }
}
```

---

## 3. Transactions (MULTI/EXEC)

### 3.1 Basic Transactions

```bash
# MULTI/EXEC: queue commands, execute atomically
MULTI
SET user:1:name "Alice"
INCR user:1:visits
EXPIRE user:1:visits 86400
EXEC
# Returns array of responses in order

# DISCARD: cancel transaction
MULTI
SET foo bar
DISCARD   # queued commands discarded

# Error handling in transaction:
# 1. Syntax error (enqueue error): entire transaction aborted
MULTI
SET key value
NOTACOMMAND   # error on queue → EXEC returns error for this only
INCR counter
EXEC         # both SET and INCR execute (only NOTACOMMAND fails)

# 2. Runtime error: only failing command returns error, others succeed
MULTI
SET name "Alice"
INCR name     # runtime error: name is string not int
SET age 30
EXEC         # SET name ✓, INCR name ✗ (returns error), SET age ✓
# Redis transactions do NOT rollback on runtime errors!

# WATCH: optimistic locking
WATCH balance  # start watching
current = GET balance
MULTI
SET balance (current - 100)  # conditional update
result = EXEC
# If 'balance' changed between WATCH and EXEC → EXEC returns nil (transaction aborted)
# Retry loop pattern:
```

```python
# Optimistic locking with WATCH (CAS pattern)
import redis

r = redis.Redis(decode_responses=True)

def transfer_money(from_account, to_account, amount, max_retries=5):
    for attempt in range(max_retries):
        with r.pipeline() as pipe:
            try:
                # WATCH both keys
                pipe.watch(from_account, to_account)
                
                # Read current balances (non-transactional read)
                from_balance = float(pipe.get(from_account) or 0)
                to_balance = float(pipe.get(to_account) or 0)
                
                if from_balance < amount:
                    raise ValueError("Insufficient funds")
                
                # MULTI: begin transaction
                pipe.multi()
                pipe.set(from_account, from_balance - amount)
                pipe.set(to_account, to_balance + amount)
                
                # EXEC: if watched keys changed, raises WatchError
                pipe.execute()
                return True
                
            except redis.WatchError:
                # Another client modified the keys, retry
                continue
    
    raise Exception(f"Failed after {max_retries} retries")
```

### 3.2 Transactions vs Lua Scripts

| Feature | MULTI/EXEC | Lua Script |
|---------|-----------|-----------|
| Atomicity | Yes (no rollback on runtime error) | Yes (full atomicity) |
| Conditional logic | No (WATCH for CAS only) | Yes (if/else in Lua) |
| Read-then-write | Via WATCH (optimistic) | Directly in script |
| Error handling | Partial (per-command error) | Custom error handling |
| Performance | Multiple RTTs | Single RTT |
| Complexity | Simple | Requires Lua knowledge |
| Replication | Sent as individual commands | Sent as EVALSHA |

---

## 4. Lua Scripting

### 4.1 EVAL Basic

```bash
# EVAL script numkeys [key [key ...]] [arg [arg ...]]
EVAL "return 1" 0
EVAL "return redis.call('SET', KEYS[1], ARGV[1])" 1 mykey myvalue
EVAL "return redis.call('GET', KEYS[1])" 1 mykey

# KEYS[1..n]: key arguments
# ARGV[1..n]: value arguments

# Script with logic
EVAL "
  local current = redis.call('GET', KEYS[1])
  if current == false then
    return redis.call('SET', KEYS[1], ARGV[1])
  end
  return current
" 1 mykey defaultvalue
```

```python
# Python Lua scripting
import redis

r = redis.Redis(decode_responses=True)

# Rate limiter using Lua (atomic check-and-increment)
RATE_LIMIT_SCRIPT = """
local key = KEYS[1]
local limit = tonumber(ARGV[1])
local window = tonumber(ARGV[2])

local current = redis.call('INCR', key)
if current == 1 then
    redis.call('EXPIRE', key, window)
end

if current > limit then
    return 0  -- rate limited
else
    return 1  -- allowed
end
"""

# Register script (cache SHA)
rate_limit_sha = r.script_load(RATE_LIMIT_SCRIPT)

def check_rate_limit(user_id: str, limit: int, window_seconds: int) -> bool:
    key = f"ratelimit:{user_id}"
    result = r.evalsha(rate_limit_sha, 1, key, limit, window_seconds)
    return result == 1  # True = allowed

# Usage
if not check_rate_limit("user:1", 10, 60):  # 10 requests per 60 seconds
    raise Exception("Rate limit exceeded")
```

### 4.2 Advanced Lua Patterns

```lua
-- Distributed lock with Lua (atomic check-and-set)
-- lua/acquire_lock.lua
local key = KEYS[1]
local value = ARGV[1]
local ttl_ms = tonumber(ARGV[2])

local existing = redis.call('GET', key)
if existing == false then
    redis.call('SET', key, value, 'PX', ttl_ms)
    return 1  -- acquired
else
    return 0  -- already locked
end

-- Release lock safely (only release if we own it)
-- lua/release_lock.lua
local key = KEYS[1]
local expected_value = ARGV[1]

local current = redis.call('GET', key)
if current == expected_value then
    redis.call('DEL', key)
    return 1  -- released
else
    return 0  -- not owner, not released
end
```

```python
# Complete distributed lock implementation
import uuid
import redis

ACQUIRE_SCRIPT = """
local key = KEYS[1]
local value = ARGV[1]
local ttl_ms = tonumber(ARGV[2])
if redis.call('SET', key, value, 'NX', 'PX', ttl_ms) then
    return 1
else
    return 0
end
"""

RELEASE_SCRIPT = """
local key = KEYS[1]
local value = ARGV[1]
if redis.call('GET', key) == value then
    return redis.call('DEL', key)
else
    return 0
end
"""

class RedisLock:
    def __init__(self, redis_client, key, ttl_ms=30000):
        self.r = redis_client
        self.key = key
        self.ttl_ms = ttl_ms
        self.value = str(uuid.uuid4())
        self._acquire_sha = self.r.script_load(ACQUIRE_SCRIPT)
        self._release_sha = self.r.script_load(RELEASE_SCRIPT)
    
    def acquire(self, retry_times=3, retry_delay=0.1) -> bool:
        for _ in range(retry_times):
            result = self.r.evalsha(self._acquire_sha, 1, self.key, self.value, self.ttl_ms)
            if result == 1:
                return True
            import time; time.sleep(retry_delay)
        return False
    
    def release(self):
        self.r.evalsha(self._release_sha, 1, self.key, self.value)
    
    def __enter__(self):
        if not self.acquire():
            raise Exception(f"Could not acquire lock: {self.key}")
        return self
    
    def __exit__(self, *args):
        self.release()

# Usage
r = redis.Redis(decode_responses=True)
with RedisLock(r, "lock:inventory:update", ttl_ms=5000):
    # critical section
    current_stock = int(r.get("inventory:widget") or 0)
    r.set("inventory:widget", current_stock - 1)
```

### 4.3 Script Management

```bash
SCRIPT LOAD "return 1"        # register script, returns SHA1
EVALSHA sha1 numkeys ...      # execute by SHA (avoids resending script)
SCRIPT EXISTS sha1 [sha1 ...]  # check if script cached
SCRIPT FLUSH                   # clear all cached scripts (e.g., after code deploy)
SCRIPT DEBUG YES|SYNC|NO       # Lua debugger mode
```

---

## 5. ACL (Access Control Lists)

```bash
# Redis 6.0+: per-user permissions

# Default user (legacy: requirepass)
user default on nopass ~* &* +@all

# Create users
ACL SETUSER alice on >password123 ~user:* +@read +@string -DEL
# on: enabled
# >password123: password
# ~user:*: can only access keys matching "user:*"
# +@read: all read commands
# +@string: all string commands
# -DEL: except DEL

# Examples:
ACL SETUSER reader on >readpass ~* +@read +INFO
ACL SETUSER writer on >writepass ~data:* +SET +GET +DEL +EXPIRE
ACL SETUSER admin on >adminpass ~* &* +@all  # full access

# Pub/Sub channels ACL (&)
ACL SETUSER pubsubuser on >pass ~* &events:* +PUBLISH +SUBSCRIBE

# List users
ACL LIST
ACL WHOAMI
ACL USERS
ACL GETUSER alice

# Auth as specific user
AUTH alice password123

# Save ACL to file
ACL SAVE   # requires aclfile in redis.conf

# redis.conf: use ACL file
aclfile /etc/redis/users.acl
# users.acl:
# user alice on >hash_of_password ~user:* +@read
# user writer on >hash_of_password ~data:* +SET +GET
```

---

## 6. RESP3 Protocol

**RESP3** (Redis Serialization Protocol v3) = mới trong Redis 6.0. Thêm nhiều types mới.

```python
# RESP2 types:          # RESP3 added types:
# - Simple String       # - Blob String (binary safe)
# - Error               # - Simple Error  
# - Integer             # - Double
# - Bulk String         # - Boolean
# - Array               # - Blob Error
#                       # - Verbatim String
#                       # - Map (instead of paired Array)
#                       # - Set
#                       # - Attribute (metadata)
#                       # - Push (server push for Pub/Sub)

# Enable RESP3
import redis

r = redis.Redis(protocol=3)  # redis-py supports RESP3

# RESP3 returns proper types:
r.hgetall('user:1')  
# RESP2: ['field1', 'val1', 'field2', 'val2'] (list)
# RESP3: {'field1': 'val1', 'field2': 'val2'} (dict)

r.smembers('tags')
# RESP2: ['redis', 'nosql', 'cache'] (list)  
# RESP3: {'redis', 'nosql', 'cache'} (set)
```

---

## 7. Keyspace Notifications

```bash
# Subscribe to keyspace events
# redis.conf
notify-keyspace-events "KEA"
# K: Keyspace events (key__keyevent@db)
# E: Keyevent events (keyevent__event@db)
# g: Generic commands (DEL, EXPIRE, RENAME...)
# $: String commands
# l: List commands
# s: Set commands
# h: Hash commands
# z: Sorted set commands
# t: Stream commands
# x: Expired events (key expired)
# d: Module key type events
# m: Key miss events
# A: Alias for g$lshzxt

# Subscribe to all expired events
PSUBSCRIBE __keyevent@0__:expired   # DB 0 expired events
PSUBSCRIBE __keyevent@*__:expired   # all DBs

# Subscribe to keyspace events for specific key
PSUBSCRIBE __keyspace@0__:mykey    # all events on mykey in DB0
```

```python
# Python: listen for expired key events
import redis
import threading

r = redis.Redis(decode_responses=True)

def handle_expired_key(message):
    key = message['data']
    print(f"Key expired: {key}")
    # Handle session cleanup, cache invalidation, etc.

def start_expiry_listener():
    # Configure in redis.conf: notify-keyspace-events "Ex"
    pubsub = r.pubsub()
    pubsub.psubscribe(**{'__keyevent@0__:expired': handle_expired_key})
    
    for message in pubsub.listen():
        if message['type'] == 'pmessage':
            handle_expired_key(message)

thread = threading.Thread(target=start_expiry_listener, daemon=True)
thread.start()
```

---

## 8. Monitoring & Debugging

### 8.1 Key Monitoring Commands

```bash
# Real-time command monitoring (use for debugging only!)
MONITOR   # prints every command received - HEAVY performance impact!

# Slow log (commands exceeding threshold)
CONFIG SET slowlog-log-slower-than 10000  # 10ms = 10000 microseconds
CONFIG SET slowlog-max-len 128
SLOWLOG GET [count]   # recent slow commands
SLOWLOG LEN           # number of entries
SLOWLOG RESET

# Latency monitoring
CONFIG SET latency-monitor-threshold 100  # ms
LATENCY LATEST        # most recent latency events
LATENCY HISTORY event  # history for specific event
LATENCY RESET         # clear history
LATENCY GRAPH event   # ASCII graph

# Client list
CLIENT LIST           # all connected clients
CLIENT LIST TYPE normal|slave|pubsub|multi  # filter by type
CLIENT KILL ID 42    # kill specific client
CLIENT SETNAME myapp  # name current connection
CLIENT GETNAME
CLIENT NO-EVICT ON   # don't evict this client under memory pressure
CLIENT INFO          # info about current connection

# Keyspace statistics
INFO keyspace
# db0:keys=1234,expires=56,avg_ttl=3600000

# Command statistics
INFO commandstats
# cmdstat_get:calls=100000,usec=500000,usec_per_call=5.00

# Connection info
INFO clients
# connected_clients:42
# blocked_clients:0
# tracking_clients:0
```

### 8.2 Redis Benchmark

```bash
# Built-in benchmark tool
redis-benchmark -h localhost -p 6379 -n 100000 -c 50 -q
# -n: total requests
# -c: concurrent clients
# -q: quiet mode

# Benchmark specific commands
redis-benchmark -t set,get,incr,lpush,lrange -n 1000000 -q

# With pipelining
redis-benchmark -t set -n 1000000 -P 16 -q
# -P 16: pipeline 16 commands

# Benchmark results example:
# SET: 87260.03 requests per second
# GET: 93905.96 requests per second
# INCR: 90001.80 requests per second

# redis-cli --latency
redis-cli --latency -i 1   # measure latency every 1s
redis-cli --latency-history -i 1
redis-cli --latency-dist   # distribution
```

### 8.3 Redis Insight & Monitoring Stack

```yaml
# docker-compose: Redis + monitoring
services:
  redis:
    image: redis:7.2
    command: >
      redis-server
      --save 60 1000
      --loglevel notice
      --latency-monitor-threshold 100
      --slowlog-log-slower-than 10000
      --notify-keyspace-events Ex
    ports:
      - "6379:6379"

  redis-exporter:
    image: oliver006/redis_exporter
    environment:
      REDIS_ADDR: "redis://redis:6379"
    ports:
      - "9121:9121"
    depends_on:
      - redis

  # Prometheus scrapes redis-exporter:9121
  # Grafana dashboard: grafana.com/grafana/dashboards/763
```

```yaml
# Prometheus alerting rules for Redis
groups:
  - name: redis
    rules:
      - alert: RedisDown
        expr: redis_up == 0
        for: 1m
        annotations:
          summary: "Redis is down"
      
      - alert: RedisHighMemoryUsage
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        annotations:
          summary: "Redis memory usage > 90%"
      
      - alert: RedisTooManyConnections
        expr: redis_connected_clients > 1000
        for: 2m
        annotations:
          summary: "Too many connections"
      
      - alert: RedisKeyEviction
        expr: increase(redis_evicted_keys_total[5m]) > 0
        annotations:
          summary: "Redis is evicting keys - increase maxmemory"
      
      - alert: RedisReplicationLag
        expr: redis_master_repl_offset - redis_slave_repl_offset > 1000000
        for: 1m
        annotations:
          summary: "Replica is lagging behind master"
```

---

## 9. Production Performance Tuning

```bash
# redis.conf production settings

# Performance
tcp-backlog 511              # TCP listen backlog
timeout 0                    # don't disconnect idle clients (use 300 for client leak protection)
tcp-keepalive 300            # TCP keepalive interval
hz 10                        # event loop frequency (10-100, higher = more CPU but faster expiry)
dynamic-hz yes               # auto-adjust hz based on load
aof-rewrite-incremental-fsync yes  # fsync in chunks during rewrite
rdb-save-incremental-fsync yes

# Threading (Redis 6+)
io-threads 4                 # IO threads (set to CPU cores, max 8)
io-threads-do-reads yes      # use IO threads for reads too

# Latency
latency-tracking yes
latency-tracking-info-percentiles "50 99 99.9"  # Redis 7.0+

# Large key handling
proto-max-bulk-len 512mb     # max size of a bulk request

# OS optimization (run as root or via sysctl)
# echo never > /sys/kernel/mm/transparent_hugepage/enabled
# sysctl -w net.core.somaxconn=65535
# sysctl -w vm.overcommit_memory=1
# ulimit -n 65536
```

## Ghi chú – Topics tiếp theo

- **Caching Patterns**: Cache-Aside, Write-Through, Write-Behind → `redis_patterns.md`
- **Pub/Sub**: fan-out messaging → `redis_patterns.md`
- **Streams**: durable event streaming, consumer groups → `redis_patterns.md`
- **Rate Limiting**: token bucket, sliding window → `redis_patterns.md`
- **Distributed Lock**: Redlock algorithm → `redis_patterns.md`
- **Redis Stack**: RedisJSON, RediSearch → bonus topics
