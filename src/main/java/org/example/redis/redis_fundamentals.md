# Redis Fundamentals

## 1. Redis là gì? (What)

**Redis** (Remote Dictionary Server) là một **in-memory data structure store** mã nguồn mở, hoạt động như database, cache, và message broker. Nó lưu trữ dữ liệu chủ yếu trong RAM và hỗ trợ nhiều cấu trúc dữ liệu phong phú.

### Đặc điểm cốt lõi:
- **In-memory**: dữ liệu nằm trong RAM → tốc độ cực nhanh (100k+ ops/sec)
- **Single-threaded** (main thread): tránh race condition, không cần lock
- **Persistence optional**: có thể backup xuống disk (RDB/AOF)
- **Rich data structures**: String, List, Hash, Set, Sorted Set, Stream, HyperLogLog, Bitmap, Geo
- **Atomic operations**: mỗi command là atomic
- **Replication + Clustering**: High Availability built-in

---

## 2. Tại sao cần Redis? (Why)

```
Problem: Database quá chậm cho operations cần < 1ms latency

Solutions được so sánh:
├── MySQL/PostgreSQL: disk-based → ~1-10ms per query
├── Memcached: in-memory cache nhưng chỉ String, không persistence
└── Redis: in-memory + rich data types + persistence + pub/sub + cluster

Redis giải quyết:
✓ Session store: thay thế DB session (100x nhanh hơn)
✓ Caching: cache kết quả expensive queries
✓ Real-time analytics: counter, leaderboard, bitset
✓ Message queue: pub/sub, streams
✓ Rate limiting: atomic increment + expire
✓ Distributed locking: SET NX PX
```

---

## 3. Kiến trúc Redis (How)

### 3.1 Single-Threaded Event Loop

```
┌─────────────────────────────────────────┐
│                Redis Process             │
│                                         │
│  Network I/O     Event Loop (epoll)     │
│  ┌─────────┐     ┌──────────────────┐  │
│  │ Client  │────>│  Command Queue   │  │
│  │ Client  │     │  (single thread) │  │
│  │ Client  │<────│  Execute + Reply │  │
│  └─────────┘     └──────────────────┘  │
│                                         │
│  Background threads (non-blocking I/O): │
│  - AOF fsync                           │
│  - RDB snapshot (fork)                 │
│  - Lazy free (DEL large keys)          │
│  - Network I/O threads (Redis 6.0+)    │
└─────────────────────────────────────────┘
```

**Tại sao single-threaded lại nhanh?**
- Không có context switching overhead
- Không cần mutex/lock → mọi operation atomic
- Redis 6.0+: I/O multithreading (đọc/ghi socket) nhưng command execution vẫn single-thread
- Redis 7.0+: IO threads cải thiện đáng kể throughput

### 3.2 Memory Layout

```
Redis Memory:
├── used_memory: total allocated by allocator (jemalloc)
├── used_memory_rss: actual RSS from OS (includes fragmentation)
├── mem_fragmentation_ratio = used_memory_rss / used_memory
│   - < 1.0: swapping to disk (BAD)
│   - 1.0-1.5: healthy
│   - > 1.5: high fragmentation (run MEMORY PURGE)
└── maxmemory: hard limit → triggers eviction policy
```

---

## 4. Data Types (Components)

### 4.1 String

**What**: Binary-safe string, tối đa 512MB. Có thể chứa text, JSON, binary, serialized object.

```bash
# Basic set/get
SET key value
SET key value EX 3600        # với TTL 3600 giây
SET key value PX 3600000     # với TTL 3600000 ms
SET key value NX             # chỉ set nếu key chưa tồn tại (atomic)
SET key value XX             # chỉ set nếu key đã tồn tại
SET key value EXAT timestamp # expire tại unix timestamp
SET key value KEEPTTL        # giữ nguyên TTL cũ

GET key
GETDEL key                   # get + delete atomically
GETEX key EX 60              # get + set new TTL
MGET key1 key2 key3          # multi-get (atomic? No, but fast)
MSET k1 v1 k2 v2             # multi-set
MSETNX k1 v1 k2 v2           # multi-set only if all don't exist

# Counter operations (atomic)
INCR key          # increment by 1 (return new value)
INCRBY key 10     # increment by 10
INCRBYFLOAT key 1.5
DECR key
DECRBY key 5

# String operations
APPEND key " world"
STRLEN key
GETRANGE key 0 4   # substring (0-indexed)
SETRANGE key 6 "Redis"  # overwrite at offset

# Encoding optimization (auto selected):
# int encoding: when value is integer → most compact
# embstr: string <= 44 bytes (Redis 3.2+)
# raw: string > 44 bytes
OBJECT ENCODING key
```

**Use cases**: Session token, counter, JSON object, rate limit counter, feature flag.

### 4.2 List

**What**: Doubly-linked list (trước Redis 3.2) hoặc quicklist (ListPack sau Redis 7.0). Ordered, allows duplicates.

```bash
# Push/Pop
LPUSH list val1 val2 val3   # push to head (returns new length)
RPUSH list val1 val2 val3   # push to tail
LPOP list [count]           # pop from head
RPOP list [count]           # pop from tail
LMPOP numkeys key [key...] LEFT|RIGHT [COUNT count]  # Redis 7.0+

# Blocking pop (wait if list empty - great for queues)
BLPOP list1 list2 timeout   # block until item or timeout
BRPOP list1 list2 timeout
BLMOVE src dest LEFT RIGHT timeout  # atomic move between lists

# Read operations
LRANGE list 0 -1    # get all elements (0=first, -1=last)
LRANGE list 0 9     # first 10 elements
LLEN list           # length
LINDEX list 0       # get by index (O(n)!)
LPOS list value     # find position (Redis 6.0.6+)

# Modification (O(n) - avoid on large lists)
LINSERT list BEFORE "pivot" "new"
LSET list index value    # set by index
LREM list count value    # remove count occurrences of value
LTRIM list 0 99         # keep only elements 0-99

# Reliable queue pattern (src → dst atomically)
LMOVE source destination LEFT RIGHT   # atomic move

# Internal encoding:
# listpack (formerly ziplist): when len <= list-max-listpack-size AND each element <= list-max-ziplist-value
# quicklist: otherwise (linked list of listpacks)
OBJECT ENCODING mylist
```

**Use cases**: Message queue (LPUSH + BRPOP), activity feed, recent items, stack (LPUSH + LPOP).

### 4.3 Hash

**What**: Field-value map. Optimal khi store nhiều fields của một object.

```bash
# Set/Get
HSET user:1 name "Alice" age 30 email "alice@example.com"  # multi-field
HGET user:1 name
HMGET user:1 name age email   # multi-field get
HGETALL user:1               # all fields + values (CAREFUL on large hashes)
HKEYS user:1                 # all field names
HVALS user:1                 # all values
HLEN user:1                  # number of fields

# Conditional
HSETNX user:1 name "Bob"    # set only if field doesn't exist

# Numeric
HINCRBY user:1 age 1
HINCRBYFLOAT user:1 balance 9.99

# Delete
HDEL user:1 email
HEXISTS user:1 name  # check field exists

# Scan large hash (non-blocking)
HSCAN user:1 cursor [MATCH pattern] [COUNT hint]

# Internal encoding:
# listpack (ziplist): <= hash-max-listpack-entries (default 128) AND field <= hash-max-listpack-value (64 bytes)
# hashtable: otherwise
```

**Use cases**: User profile, product details, configuration, session data with multiple fields.

**Tại sao Hash tốt hơn JSON string?**
- Có thể update/read từng field riêng lẻ (không cần parse toàn bộ JSON)
- HINCRBY để increment field mà không cần GET+increment+SET
- Tiết kiệm memory hơn khi nhiều objects có cùng field names (hash encoding)

### 4.4 Set

**What**: Unordered collection of unique strings. Supports set operations (union, intersection, difference).

```bash
# Add/Remove
SADD tags "redis" "database" "cache"  # returns number added
SREM tags "cache"
SPOP tags [count]         # random pop (remove)
SRANDMEMBER tags [count]  # random read (no remove)

# Query
SISMEMBER tags "redis"    # O(1) membership check
SMISMEMBER tags "redis" "nosql"  # multi-membership check
SMEMBERS tags             # all members (CAREFUL: O(N))
SCARD tags                # count

# Set operations (return result)
SUNION set1 set2          # union
SINTER set1 set2          # intersection
SDIFF set1 set2           # difference (in set1 but not set2)

# Set operations (store result in new key)
SUNIONSTORE dest set1 set2
SINTERSTORE dest set1 set2
SDIFFSTORE dest set1 set2

# Scan large set
SSCAN tags cursor [MATCH pattern] [COUNT hint]

# Internal encoding:
# intset: all members are integers AND count <= set-max-intset-entries (512)
# listpack (Redis 7.2+): count <= set-max-listpack-entries (128) AND member <= 64 bytes
# hashtable: otherwise
```

**Use cases**: Tags, unique visitors, friend lists, online users, blacklist/whitelist.

### 4.5 Sorted Set (ZSet)

**What**: Set where each member has a float score. Members unique, scores can repeat. Sorted by score.

```bash
# Add
ZADD leaderboard 1500 "alice" 2300 "bob" 800 "charlie"
ZADD leaderboard NX 1500 "diana"        # add only if not exist
ZADD leaderboard XX 1600 "alice"        # update only if exists
ZADD leaderboard GT 1700 "alice"        # update only if new > current
ZADD leaderboard LT 1000 "alice"        # update only if new < current
ZADD leaderboard CH 1800 "alice"        # return number of CHANGED (not just added)
ZADD leaderboard INCR 100 "alice"       # increment (like ZINCRBY)

# Read by rank (0-indexed, ascending)
ZRANGE leaderboard 0 -1                 # all (low to high score)
ZRANGE leaderboard 0 -1 WITHSCORES     # with scores
ZRANGE leaderboard 0 -1 REV            # high to low (Redis 6.2+)
ZRANGE leaderboard "(500" "+inf" BYSCORE LIMIT 0 10  # by score range

# Read by score
ZRANGEBYSCORE lb 1000 2000 WITHSCORES LIMIT 0 10  # deprecated, use ZRANGE BYSCORE
ZREVRANGEBYSCORE lb 2000 1000 LIMIT 0 10           # high to low

# Read by lex (when all scores equal, sort lexicographically)
ZRANGEBYLEX tags "[a" "[m"

# Rank / Score
ZRANK leaderboard "alice"        # rank (0-indexed, ascending)
ZREVRANK leaderboard "alice"     # rank (descending)
ZRANK leaderboard "alice" WITHSCORE  # Redis 7.2+
ZSCORE leaderboard "alice"       # get score
ZMSCORE leaderboard "alice" "bob"  # multi score

# Count
ZCARD leaderboard                # total members
ZCOUNT leaderboard 1000 2000     # count in score range
ZLEXCOUNT tags "[a" "[z"         # count in lex range

# Remove
ZREM leaderboard "charlie"
ZREMRANGEBYSCORE leaderboard "-inf" 500  # remove low scorers
ZREMRANGEBYRANK leaderboard 0 9          # remove bottom 10

# Pop (atomic)
ZPOPMIN leaderboard [count]     # pop lowest score
ZPOPMAX leaderboard [count]     # pop highest score
BZPOPMIN leaderboard timeout    # blocking pop

# Set operations (with weight/aggregate)
ZUNIONSTORE dest 2 zset1 zset2 WEIGHTS 1 2 AGGREGATE MAX
ZINTERSTORE dest 2 zset1 zset2

# Internal encoding:
# listpack: count <= zset-max-listpack-entries (128) AND member <= zset-max-listpack-value (64 bytes)
# skiplist + hashtable: otherwise
```

**Use cases**: Leaderboard, priority queue, range query by score, sliding window rate limiter, recommendation feed.

### 4.6 Stream

**What**: Append-only log with consumer groups (like Kafka in Redis). Each entry has auto-generated ID (timestamp-sequence).

```bash
# Produce (append entry)
XADD events * action "purchase" user_id "123" amount "99.99"
# * = auto-generate ID (1735000000000-0)
XADD events 1735000000000-0 ...  # explicit ID
XADD events MAXLEN ~ 100000 * ...  # cap at ~100k entries (~ = approximate)
XADD events MAXLEN = 100000 * ...  # exact cap
XADD events MINID ~ 1735000000000 * ...  # remove entries older than timestamp

# Read (simple, no consumer group)
XREAD COUNT 10 STREAMS events 0              # read from beginning
XREAD COUNT 10 STREAMS events $              # read only new entries
XREAD COUNT 10 BLOCK 0 STREAMS events $     # block until new entries

# Consumer Groups (like Kafka consumer groups)
XGROUP CREATE events my-group $ MKSTREAM    # create group, start from now
XGROUP CREATE events my-group 0             # start from beginning

# Consumer reads (pending entries assigned to consumer)
XREADGROUP GROUP my-group consumer1 COUNT 10 STREAMS events >
# > = read undelivered entries

# Acknowledge processed
XACK events my-group 1735000000000-0

# Check pending entries (not yet acked)
XPENDING events my-group - + 10             # show pending
XPENDING events my-group - + 10 consumer1  # by consumer

# Claim stale entries (dead consumer recovery)
XCLAIM events my-group consumer2 60000 1735000000000-0  # claim if idle > 60s
XAUTOCLAIM events my-group consumer2 60000 0 COUNT 10  # auto-claim stale

# Read info
XLEN events                  # total entries
XRANGE events - +            # all entries
XRANGE events 1735000000000-0 + COUNT 10  # from ID, limit 10
XREVRANGE events + - COUNT 10             # reverse order
XINFO STREAM events          # stream info
XINFO GROUPS events          # consumer groups info
XINFO CONSUMERS events my-group  # consumers info

# Delete entry / trim
XDEL events 1735000000000-0
XTRIM events MAXLEN 10000
```

**Use cases**: Event log, activity stream, IoT sensor data, audit trail, microservice event bus.

### 4.7 HyperLogLog

**What**: Probabilistic data structure để estimate số lượng unique elements. Chỉ tốn ~12KB bất kể có bao nhiêu elements.

```bash
PFADD visitors "user1" "user2" "user3"   # add elements
PFCOUNT visitors                          # estimate unique count (0.81% error)
PFCOUNT visitors daily_visitors           # combined count
PFMERGE merged visitors daily_visitors   # merge multiple HLL
```

**When**: Khi cần đếm unique views/visitors nhưng không cần chính xác 100%, và không muốn dùng Set (quá tốn memory).

### 4.8 Bitmap

**What**: Bit array stored as String. Mỗi bit có thể set/get theo offset (0-indexed). 1 byte = 8 bits.

```bash
# Set/Get bit
SETBIT user:active 42 1    # set bit at offset 42 to 1
GETBIT user:active 42      # get bit value (0 or 1)

# Count bits
BITCOUNT user:active           # total bits set to 1
BITCOUNT user:active 0 3       # in bytes 0-3 (byte range!)

# Bit position
BITPOS user:active 1           # first position set to 1
BITPOS user:active 0           # first position set to 0

# Bitmap operations (AND, OR, XOR, NOT)
BITOP AND result active:jan active:feb   # users active both months
BITOP OR result active:jan active:feb    # users active either month
BITOP XOR result active:jan active:feb   # users active in exactly one month

# Practical: day-based activity tracking
# Mark user 1000 as active on day 365:
SETBIT daily:2024:365 1000 1
# Count active users today:
BITCOUNT daily:2024:365
```

**Uses**: Daily active users tracking, feature flags per user, permissions bitmap.

### 4.9 Geo

**What**: Sorted Set internally, stores geo coordinates as geohash. Supports radius/distance queries.

```bash
# Add location (longitude, latitude, member)
GEOADD restaurants 106.6921 10.7765 "pho_ba_mien"
GEOADD restaurants 106.6897 10.7697 "bun_bo_hue" 106.6845 10.7750 "banh_mi_37"

# Get coordinates
GEOPOS restaurants "pho_ba_mien"

# Get geohash (string representation)
GEOHASH restaurants "pho_ba_mien"

# Distance between two members
GEODIST restaurants "pho_ba_mien" "bun_bo_hue" km   # unit: m, km, mi, ft

# Search by radius (Redis 6.2+)
GEOSEARCH restaurants FROMMEMBER "pho_ba_mien" BYRADIUS 1 km ASC COUNT 5 WITHCOORD WITHDIST
GEOSEARCH restaurants FROMLONLAT 106.690 10.775 BYBOX 2 2 km ASC COUNT 10

# Store search results in new sorted set
GEOSEARCHSTORE result restaurants FROMLONLAT 106.690 10.775 BYRADIUS 2 km ASC
```

---

## 5. Key Expiry & TTL

```bash
# Set expiry
EXPIRE key 3600          # seconds from now
PEXPIRE key 3600000      # milliseconds
EXPIREAT key 1735000000  # unix timestamp
PEXPIREAT key 1735000000000  # unix timestamp ms
PERSIST key              # remove TTL (make permanent)

# Check TTL
TTL key    # seconds remaining (-1 = no TTL, -2 = key not exist)
PTTL key   # milliseconds

# Set with expire in one command
SET key value EX 3600
SET key value PX 3600000
SET key value EXAT 1735000000

# EXPIRETIME (Redis 7.0+)
EXPIRETIME key   # unix timestamp when key expires
PEXPIRETIME key  # milliseconds timestamp
```

**Expiry mechanism:**
- **Lazy expiration**: check khi access key
- **Active expiration**: background sweeper mỗi 100ms lấy 20 random keys, delete nếu expired, lặp lại nếu > 25% expired
- Không cần chủ động xóa key expired → Redis tự quản lý

---

## 6. Persistence

### 6.1 RDB (Redis Database Backup)

**What**: Point-in-time snapshot của dataset, lưu binary format xuống disk.

```bash
# Manual snapshot
BGSAVE        # background save (non-blocking, forks process)
SAVE          # blocking save (blocks all operations - AVOID in production)
LASTSAVE      # unix timestamp of last save

# Auto-snapshot config (redis.conf)
save 3600 1    # save after 1 change in 3600s
save 300 100   # save after 100 changes in 300s
save 60 10000  # save after 10000 changes in 60s

# Disable RDB
save ""

# RDB file location
dir /var/lib/redis
dbfilename dump.rdb

# Compression
rdbcompression yes    # LZF compression
rdbchecksum yes       # CRC64 checksum

# Copy-on-Write (COW): fork() creates child process
# Parent continues serving requests
# Child writes snapshot (reads from copied page tables)
# Modified pages duplicated in memory → fork latency
# Problem: large key → large COW overhead
```

**Trade-offs:**
| Pros | Cons |
|------|------|
| Compact binary format | Potential data loss (between snapshots) |
| Fast restart (load from single file) | Fork overhead (memory doubles temporarily) |
| Good for backup/disaster recovery | Slow for large datasets (fork time) |

### 6.2 AOF (Append Only File)

**What**: Log mọi write command theo thứ tự. Có thể replay để rebuild dataset.

```bash
# Enable AOF (redis.conf)
appendonly yes
appendfilename "appendonly.aof"

# fsync policy (how often flush to disk)
appendfsync always      # sync on every write (safest, slowest)
appendfsync everysec    # sync every second (recommended, lose max 1s)
appendfsync no          # let OS decide (fastest, most data risk)

# AOF Rewrite (compact the log)
BGREWRITEAOF            # manual rewrite
# Rewrites produce compact representation (e.g., HMSET instead of 100 HSET commands)

# Auto-rewrite config
auto-aof-rewrite-percentage 100  # rewrite when AOF grows 100% from last rewrite
auto-aof-rewrite-min-size 64mb  # minimum size to trigger rewrite

# AOF Persistence Mode (Redis 7.0+)
aof-use-rdb-preamble yes  # hybrid AOF: starts with RDB snapshot + AOF tail
                           # faster loading than pure AOF
```

**AOF Rewrite process:**
```
1. BGREWRITEAOF command
2. Redis forks child
3. Child writes new compact AOF from current dataset
4. Parent buffers new write commands during rewrite
5. When child finishes, parent appends buffered commands to new AOF
6. Atomically rename new AOF file → replace old
```

### 6.3 RDB vs AOF

| Feature | RDB | AOF |
|---------|-----|-----|
| Data safety | May lose minutes | Max 1 second loss |
| Performance | Less overhead | More I/O |
| File size | Compact binary | Larger (text commands) |
| Restart speed | Fast | Slower (replay all commands) |
| Human readable | No | Yes (text commands) |
| Best for | Backup, periodic snapshot | High durability |

**Recommendation**: Use both! `aof-use-rdb-preamble yes` (hybrid mode Redis 4.0+)

### 6.4 No Persistence (Pure Cache)

```bash
# redis.conf
save ""          # disable RDB
appendonly no    # disable AOF

# Use when: pure caching layer, cache miss is acceptable
# Never use when: Redis is primary store
```

---

## 7. Basic Commands Reference

```bash
# Key operations
DEL key [key ...]        # delete keys
UNLINK key [key ...]     # async delete (non-blocking for large keys)
EXISTS key [key ...]     # check existence (returns count)
TYPE key                 # returns type: string/list/hash/set/zset/stream/none
RENAME key newkey        # rename (overwrite newkey if exists)
RENAMENX key newkey      # rename only if newkey doesn't exist
COPY key dest [REPLACE]  # copy to new key
OBJECT ENCODING key      # check internal encoding
OBJECT IDLETIME key      # seconds since last access
OBJECT FREQ key          # access frequency (LFU required)
OBJECT REFCOUNT key      # reference count
OBJECT HELP

# Debugging
DEBUG SLEEP 5            # sleep redis for 5s (test timeout)
DEBUG OBJECT key         # internal details
OBJECT ENCODING key

# Scan keys (never use KEYS in production!)
SCAN cursor [MATCH pattern] [COUNT hint] [TYPE type]
# cursor = 0 to start, iterate until cursor = 0 again
# COUNT = hint for iteration size, not exact
# Example: scan all "user:*" keys in batches:
# SCAN 0 MATCH "user:*" COUNT 100

# Keyspace info
DBSIZE           # number of keys in current DB
INFO keyspace    # info per DB (number of keys, expiring keys)

# Database selection (0-15)
SELECT 1         # switch to DB 1 (default: 0)
MOVE key 1       # move key to DB 1
SWAPDB 0 1       # swap two databases

# Flush (DANGEROUS!)
FLUSHDB [ASYNC]          # flush current DB
FLUSHALL [ASYNC]         # flush ALL databases

# Server info
INFO                     # all info sections
INFO memory             # memory usage
INFO clients            # client connections
INFO stats              # operations stats
INFO replication        # replication status
CONFIG GET maxmemory
CONFIG SET maxmemory 2gb
CONFIG REWRITE          # persist current config to redis.conf
```

---

## 8. Ghi chú – Topics tiếp theo

- **Replication**: Master-Replica, Sentinel failover → `redis_ha.md`
- **Cluster**: Sharding, hash slots, gossip protocol → `redis_ha.md`
- **Eviction policies**: LRU, LFU, allkeys-lru → `redis_performance.md`
- **Pipelining**: batch commands, reduce RTT → `redis_performance.md`
- **Lua scripting**: EVAL, EVALSHA, atomic scripts → `redis_performance.md`
- **MULTI/EXEC**: Transactions, WATCH → `redis_performance.md`
- **Pub/Sub**: PUBLISH/SUBSCRIBE/PSUBSCRIBE → `redis_patterns.md`
- **Streams**: Consumer groups deep dive → `redis_patterns.md`
- **Caching patterns**: Cache-Aside, Write-Through, Write-Behind → `redis_patterns.md`
- **Distributed Lock**: SET NX PX, Redlock algorithm → `redis_patterns.md`
- **Redis Stack**: RedisJSON, RediSearch, RedisTimeSeries, RedisBloom → bonus topics
