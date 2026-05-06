# Redis Design Patterns

## 1. Caching Patterns

### 1.1 Cache-Aside (Lazy Loading)

**What**: Application code tự quản lý cache. Read-through khi cache miss.

```
Read flow:
  App → GET cache_key
  Cache HIT  → return from cache
  Cache MISS → read from DB → SET in cache → return

Write flow:
  App → write to DB
  App → DEL cache_key  (invalidate, not update)
```

```python
import redis
import json
from functools import wraps
from typing import Optional, Callable, Any

r = redis.Redis(decode_responses=True)

def get_user(user_id: int) -> dict:
    cache_key = f"user:{user_id}"
    
    # 1. Check cache
    cached = r.get(cache_key)
    if cached:
        return json.loads(cached)
    
    # 2. Cache miss: fetch from DB
    user = db.query("SELECT * FROM users WHERE id = ?", user_id)
    
    # 3. Store in cache with TTL
    r.setex(cache_key, 3600, json.dumps(user))
    
    return user

def update_user(user_id: int, data: dict):
    # 1. Update DB first
    db.execute("UPDATE users SET ... WHERE id = ?", user_id)
    
    # 2. Invalidate cache (not update!)
    r.delete(f"user:{user_id}")
    # Why delete not update? Avoids race condition:
    # T1: write DB → T2: read DB → T2: write cache → T1: write cache (stale!)
    # Delete + Cache-Aside: consistent

# Generic cache decorator
def cache(key_prefix: str, ttl: int = 3600, key_func: Optional[Callable] = None):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # Build cache key
            if key_func:
                cache_key = f"{key_prefix}:{key_func(*args, **kwargs)}"
            else:
                cache_key = f"{key_prefix}:{':'.join(str(a) for a in args)}"
            
            cached = r.get(cache_key)
            if cached is not None:
                return json.loads(cached)
            
            result = func(*args, **kwargs)
            r.setex(cache_key, ttl, json.dumps(result))
            return result
        
        wrapper.invalidate = lambda *args, **kwargs: r.delete(
            f"{key_prefix}:{key_func(*args, **kwargs)}" if key_func
            else f"{key_prefix}:{':'.join(str(a) for a in args)}"
        )
        return wrapper
    return decorator

@cache("product", ttl=1800, key_func=lambda product_id: product_id)
def get_product(product_id: int) -> dict:
    return db.get_product(product_id)

# Usage
product = get_product(42)     # cache miss → DB
product = get_product(42)     # cache hit → Redis
get_product.invalidate(42)    # invalidate cache
```

### 1.2 Write-Through

**What**: Application write cả DB lẫn cache đồng thời.

```python
def update_product_price(product_id: int, new_price: float):
    # Write to DB AND cache in same transaction
    cache_key = f"product:{product_id}"
    
    # Strategy: write DB first, then cache
    db.execute("UPDATE products SET price = ? WHERE id = ?", new_price, product_id)
    
    # Update cache (không delete → giảm cache miss)
    cached_product = r.get(cache_key)
    if cached_product:
        product = json.loads(cached_product)
        product['price'] = new_price
        r.setex(cache_key, 3600, json.dumps(product))

# Better: pipeline both operations
def update_with_pipeline(product_id: int, new_price: float):
    db.execute("UPDATE products SET price = ? WHERE id = ?", new_price, product_id)
    
    with r.pipeline() as pipe:
        pipe.hset(f"product:{product_id}", "price", new_price)
        pipe.expire(f"product:{product_id}", 3600)
        pipe.execute()
```

**Trade-offs:**
| | Cache-Aside | Write-Through |
|--|------------|--------------|
| Cache freshness | May be stale until TTL | Always fresh |
| Write latency | Lower (only DB) | Higher (DB + cache) |
| Cache population | On demand | On every write |
| Cache size | Only accessed data | All written data |
| Best for | Read-heavy, tolerate stale | Write-heavy, need fresh data |

### 1.3 Write-Behind (Write-Back)

**What**: Write cache trước, async write DB sau.

```python
import asyncio
from datetime import datetime

class WriteBehindCache:
    def __init__(self, redis_client, flush_interval=5):
        self.r = redis_client
        self.flush_interval = flush_interval
        self.dirty_keys = set()
    
    def write(self, key: str, value: dict):
        # Write to cache immediately (fast)
        self.r.hset(f"cache:{key}", mapping=value)
        self.r.expire(f"cache:{key}", 3600)
        
        # Track dirty keys for DB flush
        self.r.sadd("cache:dirty_keys", key)
        self.r.expire("cache:dirty_keys", 86400)
    
    async def flush_loop(self):
        while True:
            await asyncio.sleep(self.flush_interval)
            await self.flush_dirty_keys()
    
    async def flush_dirty_keys(self):
        # Get and clear dirty set atomically
        dirty_keys = self.r.smembers("cache:dirty_keys")
        if not dirty_keys:
            return
        
        self.r.delete("cache:dirty_keys")
        
        for key in dirty_keys:
            data = self.r.hgetall(f"cache:{key}")
            if data:
                await db.upsert(key, data)  # async DB write

# Risk: data loss if Redis crashes before flush
# Mitigation: Redis persistence (AOF everysec) + proper shutdown handling
```

### 1.4 Cache Stampede (Thundering Herd) Prevention

```python
# Problem: key expires → 100 requests simultaneously → 100 DB queries!

# Solution 1: Probabilistic Early Expiration
import math
import random
import time

def get_with_early_expiry(key: str, ttl: int, recompute_fn, beta=1.0):
    data_str = r.get(key)
    
    if data_str:
        data = json.loads(data_str)
        remaining_ttl = r.ttl(key)
        
        # XFetch algorithm: early expiry probability
        # Simulate: should we refresh early?
        delta = time.time() - data.get('_computed_at', 0)
        if -delta * beta * math.log(random.random()) >= remaining_ttl:
            # Refresh early (only this one request does it)
            result = recompute_fn()
            r.setex(key, ttl, json.dumps({**result, '_computed_at': time.time()}))
            return result
        
        return {k: v for k, v in data.items() if not k.startswith('_')}
    
    # Cache miss
    result = recompute_fn()
    r.setex(key, ttl, json.dumps({**result, '_computed_at': time.time()}))
    return result

# Solution 2: Mutex lock on cache miss
import redis

def get_with_mutex(key: str, ttl: int, recompute_fn):
    cached = r.get(key)
    if cached:
        return json.loads(cached)
    
    # Try to acquire lock (only one request recomputes)
    lock_key = f"{key}:lock"
    lock_acquired = r.set(lock_key, "1", nx=True, ex=10)  # 10s timeout
    
    if lock_acquired:
        try:
            result = recompute_fn()
            r.setex(key, ttl, json.dumps(result))
            return result
        finally:
            r.delete(lock_key)
    else:
        # Wait for lock holder to populate cache
        for _ in range(10):
            import time; time.sleep(0.1)
            cached = r.get(key)
            if cached:
                return json.loads(cached)
        # Fallback: direct DB query
        return recompute_fn()
```

---

## 2. Pub/Sub

### 2.1 Basic Pub/Sub

```bash
# Publisher
PUBLISH news:sports "Team A wins 3-2!"
PUBLISH news:tech "New iPhone announced"

# Subscriber (blocking, receives messages)
SUBSCRIBE news:sports news:tech         # exact channel names
PSUBSCRIBE news:*                       # pattern subscription
# Returns: subscribe/message/psubscribe/pmessage types

# Unsubscribe
UNSUBSCRIBE news:sports
PUNSUBSCRIBE news:*

# Check subscribers
PUBSUB CHANNELS news:*                  # list active channels matching pattern
PUBSUB NUMSUB news:sports news:tech     # subscriber count per channel
PUBSUB NUMPAT                           # number of pattern subscriptions
PUBSUB SHARDCHANNELS *                  # Redis 7.0+ shard channels
```

```python
# Python Pub/Sub
import redis
import threading
import json

r = redis.Redis(decode_responses=True)

# Subscriber (runs in background thread)
def start_subscriber():
    pubsub = r.pubsub(ignore_subscribe_messages=True)
    pubsub.subscribe(
        **{
            'news:sports': lambda msg: print(f"Sports: {msg['data']}"),
            'notifications:user:123': lambda msg: handle_user_notification(msg['data']),
        }
    )
    pubsub.psubscribe(**{'notifications:*': handle_wildcard_notification})
    
    # Blocking listen (runs forever)
    pubsub.run_in_thread(sleep_time=0.001, daemon=True)

# Publisher
def publish_notification(user_id: int, event: dict):
    channel = f"notifications:user:{user_id}"
    r.publish(channel, json.dumps(event))

# Limitations:
# - Not durable: if subscriber disconnects, messages are LOST
# - Not persistent: no storage
# - No consumer groups
# → For reliable messaging, use Streams instead!
```

### 2.2 Pub/Sub Use Cases vs Streams

```
Pub/Sub best for:
✓ Real-time notifications (chat messages, live scores)
✓ Cache invalidation broadcast (invalidate cache on multiple servers)
✓ Lightweight fan-out (no need to persist)

Streams best for:
✓ Event sourcing (need persistence)
✓ Multiple consumer groups (each group processes independently)
✓ Replay events (new consumer catches up from past)
✓ Reliable delivery with acknowledgment
```

---

## 3. Streams (Event Streaming)

### 3.1 Producer-Consumer with Consumer Groups

```python
import redis
import json
import threading
import time

r = redis.Redis(decode_responses=True)
STREAM = "order:events"
GROUP = "order-processor"
CONSUMER = f"worker-{threading.current_thread().ident}"

# Setup stream and group
def setup_stream():
    try:
        # Create consumer group (MKSTREAM creates stream if not exists)
        r.xgroup_create(STREAM, GROUP, id='0', mkstream=True)
    except redis.exceptions.ResponseError as e:
        if "BUSYGROUP" not in str(e):
            raise

# Producer: publish events
def publish_order(order_id: str, data: dict) -> str:
    entry_id = r.xadd(
        STREAM,
        {
            'order_id': order_id,
            'data': json.dumps(data),
            'timestamp': str(time.time()),
        },
        maxlen=100000,  # cap stream size (~= retain last 100k events)
        approximate=True,  # ~ = faster, slightly over 100k
    )
    return entry_id

# Consumer: process events
def process_events(consumer_name: str, batch_size: int = 10):
    while True:
        try:
            # Read up to batch_size undelivered messages for this consumer
            messages = r.xreadgroup(
                groupname=GROUP,
                consumername=consumer_name,
                streams={STREAM: '>'},   # '>' = only new, undelivered
                count=batch_size,
                block=5000,              # block 5000ms if no messages
            )
            
            if not messages:
                continue
            
            for stream_name, entries in messages:
                for entry_id, fields in entries:
                    try:
                        order_id = fields['order_id']
                        data = json.loads(fields['data'])
                        
                        # Process the order
                        process_order(order_id, data)
                        
                        # Acknowledge: remove from pending list
                        r.xack(STREAM, GROUP, entry_id)
                        
                    except Exception as e:
                        print(f"Failed to process {entry_id}: {e}")
                        # Don't ACK → stays in pending for retry/DLQ
        
        except Exception as e:
            print(f"Consumer error: {e}")
            time.sleep(1)

# Dead Letter Queue: handle stale pending messages
def reclaim_stale_messages(idle_ms: int = 60000):
    while True:
        time.sleep(30)
        
        # Find messages pending for > 60s (likely dead consumer)
        response = r.xautoclaim(
            name=STREAM,
            groupname=GROUP,
            consumername="reclaim-worker",
            min_idle_time=idle_ms,
            start_id='0',
            count=100,
        )
        
        next_id, claimed, deleted = response
        
        for entry_id, fields in claimed:
            delivery_count = get_delivery_count(entry_id)  # custom tracking
            
            if delivery_count >= 3:
                # Too many retries → move to DLQ
                r.xadd("order:events:dlq", fields)
                r.xack(STREAM, GROUP, entry_id)
                print(f"Moved {entry_id} to DLQ")
            else:
                # Retry (just reclaim → will be redelivered)
                process_events_for_entry(entry_id, fields)
```

### 3.2 Stream Monitoring

```bash
# Stream info
XLEN events                         # total entries
XINFO STREAM events                 # stream details (length, first/last entry)
XINFO STREAM events FULL COUNT 10   # full info including consumer groups

XINFO GROUPS events                 # all consumer groups
# Fields: name, consumers, pending, last-delivered-id, entries-read, lag

XINFO CONSUMERS events my-group    # consumers in group
# Fields: name, pending, idle, inactive

# Check pending messages (not yet ACKed)
XPENDING events my-group - + 10    # show pending entries
XPENDING events my-group IDLE 60000 - + 10  # pending > 60s (idle time)

# Trim old entries
XTRIM events MAXLEN ~ 100000       # keep ~100k most recent
XTRIM events MINID ~ 1735000000000  # remove entries older than timestamp
```

---

## 4. Rate Limiting

### 4.1 Fixed Window Rate Limiter

```python
def fixed_window_rate_limit(user_id: str, limit: int, window_seconds: int) -> bool:
    key = f"ratelimit:fixed:{user_id}:{int(time.time() // window_seconds)}"
    
    with r.pipeline() as pipe:
        pipe.incr(key)
        pipe.expire(key, window_seconds)
        count, _ = pipe.execute()
    
    return count <= limit

# Problem: burst at window boundary
# Window ends at :59, new starts at :00 → 2x requests in 2 seconds!
```

### 4.2 Sliding Window Rate Limiter (Sorted Set)

```python
def sliding_window_rate_limit(user_id: str, limit: int, window_seconds: int) -> bool:
    key = f"ratelimit:sliding:{user_id}"
    now = time.time()
    window_start = now - window_seconds
    
    SCRIPT = """
    local key = KEYS[1]
    local now = tonumber(ARGV[1])
    local window_start = tonumber(ARGV[2])
    local limit = tonumber(ARGV[3])
    local window = tonumber(ARGV[4])
    
    -- Remove expired entries
    redis.call('ZREMRANGEBYSCORE', key, '-inf', window_start)
    
    -- Count requests in window
    local count = redis.call('ZCARD', key)
    
    if count < limit then
        -- Add current request (score=timestamp, member=unique_id)
        redis.call('ZADD', key, now, now .. '-' .. math.random(1000000))
        redis.call('EXPIRE', key, window)
        return 1  -- allowed
    else
        return 0  -- rate limited
    end
    """
    
    result = r.eval(SCRIPT, 1, key, now, window_start, limit, window_seconds + 1)
    return result == 1

# Usage: 100 requests per 60 seconds
if not sliding_window_rate_limit("user:123", 100, 60):
    raise Exception("Rate limited")
```

### 4.3 Token Bucket

```python
TOKEN_BUCKET_SCRIPT = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])      -- max tokens
local refill_rate = tonumber(ARGV[2])   -- tokens per second
local now = tonumber(ARGV[3])           -- current timestamp (float)
local requested = tonumber(ARGV[4])     -- tokens needed (usually 1)

local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
local tokens = tonumber(bucket[1]) or capacity
local last_refill = tonumber(bucket[2]) or now

-- Calculate refill
local elapsed = now - last_refill
local new_tokens = math.min(capacity, tokens + elapsed * refill_rate)

if new_tokens >= requested then
    redis.call('HMSET', key, 'tokens', new_tokens - requested, 'last_refill', now)
    redis.call('EXPIRE', key, math.ceil(capacity / refill_rate) + 1)
    return 1  -- allowed
else
    redis.call('HMSET', key, 'tokens', new_tokens, 'last_refill', now)
    redis.call('EXPIRE', key, math.ceil(capacity / refill_rate) + 1)
    return 0  -- rate limited
end
"""

def token_bucket_check(key: str, capacity: int, refill_rate: float, tokens: int = 1) -> bool:
    result = r.eval(TOKEN_BUCKET_SCRIPT, 1, key, capacity, refill_rate, time.time(), tokens)
    return result == 1

# 100 capacity, refill 10 tokens/second → 10 req/s sustained, burst up to 100
if not token_bucket_check(f"api:{user_id}", capacity=100, refill_rate=10):
    raise Exception("Rate limited")
```

---

## 5. Session Store

```python
import uuid
from datetime import timedelta

SESSION_TTL = 3600  # 1 hour

def create_session(user_id: int, user_data: dict) -> str:
    session_id = str(uuid.uuid4())
    session_key = f"session:{session_id}"
    
    session_data = {
        "user_id": str(user_id),
        "created_at": str(time.time()),
        **{k: json.dumps(v) if isinstance(v, (dict, list)) else str(v) 
           for k, v in user_data.items()}
    }
    
    with r.pipeline() as pipe:
        pipe.hset(session_key, mapping=session_data)
        pipe.expire(session_key, SESSION_TTL)
        pipe.execute()
    
    return session_id

def get_session(session_id: str) -> Optional[dict]:
    session_key = f"session:{session_id}"
    data = r.hgetall(session_key)
    
    if not data:
        return None
    
    # Refresh TTL on access (sliding expiry)
    r.expire(session_key, SESSION_TTL)
    
    return data

def destroy_session(session_id: str):
    r.delete(f"session:{session_id}")

def destroy_all_user_sessions(user_id: int):
    # Track user's sessions in a Set
    user_sessions_key = f"user:{user_id}:sessions"
    session_ids = r.smembers(user_sessions_key)
    
    with r.pipeline() as pipe:
        for sid in session_ids:
            pipe.delete(f"session:{sid}")
        pipe.delete(user_sessions_key)
        pipe.execute()

# Spring Boot Integration
# application.yml
# spring:
#   session:
#     store-type: redis
#     redis:
#       namespace: spring:session
#     timeout: 3600
```

---

## 6. Distributed Lock (Redlock)

### 6.1 Simple Lock (Single Redis)

```python
# Simple: works for most cases with single Redis or Sentinel

import uuid
import redis

r = redis.Redis(decode_responses=True)

ACQUIRE_SCRIPT = """
if redis.call('SET', KEYS[1], ARGV[1], 'NX', 'PX', ARGV[2]) then
    return 1
else
    return 0
end
"""

RELEASE_SCRIPT = """
if redis.call('GET', KEYS[1]) == ARGV[1] then
    return redis.call('DEL', KEYS[1])
else
    return 0
end
"""

class DistributedLock:
    def __init__(self, key: str, ttl_ms: int = 30000, retry_count: int = 3, retry_delay: float = 0.1):
        self.key = f"lock:{key}"
        self.ttl_ms = ttl_ms
        self.retry_count = retry_count
        self.retry_delay = retry_delay
        self.token = str(uuid.uuid4())
        self._acquire_sha = r.script_load(ACQUIRE_SCRIPT)
        self._release_sha = r.script_load(RELEASE_SCRIPT)
    
    def acquire(self) -> bool:
        for i in range(self.retry_count):
            result = r.evalsha(self._acquire_sha, 1, self.key, self.token, self.ttl_ms)
            if result == 1:
                return True
            if i < self.retry_count - 1:
                time.sleep(self.retry_delay * (2 ** i))  # exponential backoff
        return False
    
    def release(self):
        r.evalsha(self._release_sha, 1, self.key, self.token)
    
    def extend(self, additional_ms: int) -> bool:
        # Extend lock TTL if still owner
        EXTEND_SCRIPT = """
        if redis.call('GET', KEYS[1]) == ARGV[1] then
            return redis.call('PEXPIRE', KEYS[1], ARGV[2])
        else
            return 0
        end
        """
        return bool(r.eval(EXTEND_SCRIPT, 1, self.key, self.token, additional_ms))
    
    def __enter__(self):
        if not self.acquire():
            raise Exception(f"Failed to acquire lock: {self.key}")
        return self
    
    def __exit__(self, *args):
        self.release()

# Usage
with DistributedLock("inventory:product:42", ttl_ms=5000) as lock:
    # Critical section
    current = int(r.get("inventory:42") or 0)
    if current > 0:
        r.decr("inventory:42")
```

### 6.2 Redlock (Multi-Node)

```python
# Redlock: acquire lock on majority (N/2 + 1) of independent Redis nodes
# Handles single-node failure

import time
import uuid
import redis

NODES = [
    redis.Redis(host='redis1', port=6379),
    redis.Redis(host='redis2', port=6379),
    redis.Redis(host='redis3', port=6379),
    redis.Redis(host='redis4', port=6379),
    redis.Redis(host='redis5', port=6379),
]

QUORUM = len(NODES) // 2 + 1  # 3

class Redlock:
    def __init__(self, resource: str, ttl_ms: int = 10000):
        self.resource = f"redlock:{resource}"
        self.ttl_ms = ttl_ms
        self.token = str(uuid.uuid4())
    
    def acquire(self) -> bool:
        start = time.time() * 1000
        acquired = 0
        
        for node in NODES:
            try:
                result = node.set(self.resource, self.token, nx=True, px=self.ttl_ms)
                if result:
                    acquired += 1
            except redis.RedisError:
                pass  # node unavailable, continue
        
        # Check: acquired majority AND within valid time
        elapsed = time.time() * 1000 - start
        validity_time = self.ttl_ms - elapsed - (self.ttl_ms * 0.01)  # 1% drift factor
        
        if acquired >= QUORUM and validity_time > 0:
            return True
        else:
            # Failed: release any partial locks
            self.release()
            return False
    
    def release(self):
        RELEASE_SCRIPT = """
        if redis.call('GET', KEYS[1]) == ARGV[1] then
            return redis.call('DEL', KEYS[1])
        else
            return 0
        end
        """
        for node in NODES:
            try:
                node.eval(RELEASE_SCRIPT, 1, self.resource, self.token)
            except redis.RedisError:
                pass

# Use redlock-py library for production:
# pip install redlock-py
from redlock import Redlock as RedlockLib

dlm = RedlockLib([
    {"host": "redis1", "port": 6379, "db": 0},
    {"host": "redis2", "port": 6379, "db": 0},
    {"host": "redis3", "port": 6379, "db": 0},
])

my_lock = dlm.lock("resource_name", 10000)  # 10s TTL
if my_lock:
    try:
        # critical section
        pass
    finally:
        dlm.unlock(my_lock)
```

---

## 7. Leaderboard

```python
import redis
from typing import List, Tuple

r = redis.Redis(decode_responses=True)
LEADERBOARD = "game:leaderboard"

def add_score(player_id: str, score: float, player_name: str):
    # Store score in sorted set
    r.zadd(LEADERBOARD, {player_id: score})
    
    # Store player info in hash
    r.hset(f"player:{player_id}", mapping={
        "name": player_name,
        "score": score,
    })

def increment_score(player_id: str, increment: float) -> float:
    new_score = r.zincrby(LEADERBOARD, increment, player_id)
    r.hset(f"player:{player_id}", "score", new_score)
    return new_score

def get_rank(player_id: str) -> Tuple[int, float]:
    rank = r.zrevrank(LEADERBOARD, player_id)  # 0-indexed, highest score = 0
    score = r.zscore(LEADERBOARD, player_id)
    return (rank + 1 if rank is not None else None), score  # 1-indexed rank

def get_top_players(count: int = 10) -> List[dict]:
    # Get top N (highest scores)
    entries = r.zrange(LEADERBOARD, 0, count-1, rev=True, withscores=True)
    
    result = []
    for rank, (player_id, score) in enumerate(entries, 1):
        player_info = r.hgetall(f"player:{player_id}")
        result.append({
            "rank": rank,
            "player_id": player_id,
            "name": player_info.get("name", "Unknown"),
            "score": score,
        })
    return result

def get_around_player(player_id: str, range_size: int = 5) -> List[dict]:
    # Get players around specified player
    rank = r.zrevrank(LEADERBOARD, player_id)
    if rank is None:
        return []
    
    start = max(0, rank - range_size)
    end = rank + range_size
    
    entries = r.zrange(LEADERBOARD, start, end, rev=True, withscores=True)
    
    return [{"rank": start + i + 1, "player_id": pid, "score": s} 
            for i, (pid, s) in enumerate(entries)]

def get_score_range(min_score: float, max_score: float) -> List[dict]:
    entries = r.zrangebyscore(LEADERBOARD, min_score, max_score, withscores=True)
    return [{"player_id": pid, "score": s} for pid, s in entries]
```

---

## 8. Job Queue

```python
# Reliable queue using List (LPUSH + BRPOP)
# With LMOVE for at-least-once delivery

QUEUE = "jobs:pending"
PROCESSING = "jobs:processing"
DLQ = "jobs:failed"

def enqueue(job: dict, priority: int = 0) -> str:
    job_id = str(uuid.uuid4())
    job['id'] = job_id
    job['enqueued_at'] = time.time()
    
    if priority == 0:
        r.lpush(QUEUE, json.dumps(job))    # normal: push to front
    else:
        r.rpush(QUEUE, json.dumps(job))    # low priority: push to back
    
    return job_id

def dequeue_and_process():
    while True:
        # Atomically move from QUEUE to PROCESSING (reliable)
        # If worker crashes, job stays in PROCESSING (not lost)
        job_json = r.lmove(QUEUE, PROCESSING, 'RIGHT', 'LEFT')  # or BLMOVE for blocking
        
        if not job_json:
            time.sleep(0.1)
            continue
        
        job = json.loads(job_json)
        
        try:
            process_job(job)
            # Remove from processing queue on success
            r.lrem(PROCESSING, 1, job_json)
            
        except Exception as e:
            job['attempts'] = job.get('attempts', 0) + 1
            job['last_error'] = str(e)
            
            r.lrem(PROCESSING, 1, job_json)
            
            if job['attempts'] >= 3:
                # Move to DLQ
                r.lpush(DLQ, json.dumps(job))
            else:
                # Re-queue with delay
                r.lpush(QUEUE, json.dumps(job))

# Recover stuck jobs (monitoring process)
def recover_stuck_jobs(max_age_seconds: int = 300):
    jobs = r.lrange(PROCESSING, 0, -1)
    now = time.time()
    
    for job_json in jobs:
        job = json.loads(job_json)
        age = now - job.get('enqueued_at', 0)
        
        if age > max_age_seconds:
            r.lrem(PROCESSING, 1, job_json)
            job['attempts'] = job.get('attempts', 0) + 1
            r.lpush(QUEUE, json.dumps(job))
            print(f"Re-queued stuck job: {job['id']}")
```

---

## 9. Redis Stack (Extensions)

```bash
# Redis Stack = Redis + modules
# Install: docker run -d -p 6379:6379 redis/redis-stack-server

# Available modules:
# RedisJSON: JSON document store
# RediSearch: full-text search + secondary indexing
# RedisTimeSeries: time series data
# RedisBloom: probabilistic data structures
# RedisGraph: graph database (deprecated in Stack 7.x)
```

```python
# RedisJSON example
r.json().set("doc:1", "$", {
    "name": "Alice",
    "age": 30,
    "address": {"city": "HCMC", "country": "VN"},
    "tags": ["developer", "redis"]
})

r.json().get("doc:1", "$.name")        # get by JSONPath
r.json().get("doc:1", "$.address.city")
r.json().numincrby("doc:1", "$.age", 1)  # increment nested field
r.json().arrappend("doc:1", "$.tags", "python")

# RediSearch: full-text search with secondary index
from redis.commands.search.field import TextField, NumericField, TagField
from redis.commands.search.indexDefinition import IndexDefinition, IndexType

# Create index on JSON documents
r.ft("user:index").create_index(
    [
        TextField("$.name", as_name="name"),
        NumericField("$.age", as_name="age"),
        TagField("$.tags.*", as_name="tags"),
    ],
    definition=IndexDefinition(prefix=["user:"], index_type=IndexType.JSON)
)

# Search
results = r.ft("user:index").search(
    "@name:alice @age:[25 35] @tags:{developer}"
)

# RedisBloom: Bloom filter (probabilistic membership)
r.bf().reserve("email:blacklist", 0.001, 1000000)  # 0.1% error, 1M items
r.bf().add("email:blacklist", "spam@evil.com")
r.bf().exists("email:blacklist", "user@example.com")  # fast check

# RedisTimeSeries: metrics storage
r.ts().create("cpu:usage", retention_msecs=86400000)  # 24h retention
r.ts().add("cpu:usage", "*", 42.5)  # auto-timestamp
r.ts().range("cpu:usage", from_time="-1h", to_time="+")  # last hour
r.ts().createrule("cpu:usage", "cpu:usage:1min", "avg", 60000)  # downsample
```

---

## 10. Quick Reference: Pattern Selection

| Need | Pattern | Redis Commands |
|------|---------|---------------|
| Cache with auto-expiry | Cache-Aside | GET + SET EX |
| Cache always fresh | Write-Through | SET (always) |
| High-write cache | Write-Behind | HSET + async flush |
| Real-time notifications | Pub/Sub | PUBLISH/SUBSCRIBE |
| Durable event log | Streams | XADD/XREADGROUP/XACK |
| Rate limit (simple) | Fixed window | INCR + EXPIRE |
| Rate limit (accurate) | Sliding window | ZADD + ZREMRANGEBYSCORE |
| Rate limit (burst) | Token bucket | Lua script |
| User session | Hash + TTL | HSET + EXPIRE |
| Mutual exclusion | Distributed lock | SET NX PX + Lua release |
| Multi-node lock | Redlock | Acquire on majority nodes |
| Ranking | Leaderboard | ZADD/ZRANGE/ZRANK |
| Background jobs | Job queue | LPUSH + BLPOP/LMOVE |
| Unique count | HyperLogLog | PFADD/PFCOUNT |
| Feature flags | Bitmap | SETBIT/GETBIT/BITCOUNT |
| Geo proximity | Geo index | GEOADD/GEOSEARCH |
| Full-text search | RediSearch | FT.SEARCH |
| JSON documents | RedisJSON | JSON.SET/JSON.GET |
| Metrics/IoT | TimeSeries | TS.ADD/TS.RANGE |
