---
title: "PostgreSQL Architecture & Storage Engine"
topic: postgresql
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "PostgreSQL 18"
source_count: 10
---
# PostgreSQL Architecture & Storage Engine

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này xây mental model từ client
> connection tới backend process, shared memory, page/tuple, WAL, checkpoint và
> vacuum. Đây là nền tảng để hiểu transaction, index, performance và HA.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md).

---

## 1. PostgreSQL phải giải quyết điều gì?

Một database OLTP phải đồng thời:

1. cho nhiều transaction đọc/ghi mà không thấy trạng thái nửa chừng;
2. giữ transaction đã commit qua crash;
3. trả lời query trên dữ liệu lớn hơn RAM;
4. tái sử dụng version cũ mà không xóa dữ liệu snapshot còn cần;
5. phục hồi/replicate từ log thay đổi;
6. giữ metadata, index và constraint nhất quán.

```text
Client
  │ PostgreSQL wire protocol
  ▼
Backend process
  │ parser → rewriter → planner → executor
  ▼
Shared memory
  │ shared buffers, WAL buffers, locks, process state
  ▼
Storage
  ├── heap/index/TOAST relation
  ├── WAL
  └── catalog + transaction status
```

Ba câu cần nhớ:

1. **UPDATE tạo tuple version mới**, vì vậy vacuum là thành phần correctness và
   capacity, không chỉ “dọn rác”.
2. **WAL phải bền trước data page**, vì vậy commit không cần flush mọi table page.
3. **Một connection thường có một backend process**, vì vậy connection là tài
   nguyên đáng kể.

---

## 2. Thuật ngữ dễ nhầm

| PostgreSQL gọi | Nghĩa |
|---|---|
| Cluster | một data directory/server instance chứa nhiều database |
| Database | namespace cấp cao; session kết nối vào đúng một database |
| Schema | namespace object bên trong database |
| Relation | table, index, sequence, materialized view và object dạng relation |
| Heap | storage table không có thứ tự vật lý theo primary key |
| Tuple | row version vật lý |
| Page/block | đơn vị I/O, mặc định thường 8 KiB |
| WAL | log thay đổi vật lý/logical đủ để crash recovery/replication |
| XID | transaction ID dùng cho visibility và freezing |

“PostgreSQL cluster” trong bài không có nghĩa Kubernetes cluster hoặc một nhóm
primary/replica tự bầu leader.

Kiểm tra instance:

```sql
SELECT version();

SHOW data_directory;
SHOW server_version_num;
SHOW block_size;
```

---

## 3. Process model

PostgreSQL truyền thống dùng process-per-connection:

```text
postmaster / main postgres process
  ├── backend cho connection A
  ├── backend cho connection B
  ├── backend cho connection C
  ├── checkpointer
  ├── background writer
  ├── WAL writer
  ├── autovacuum launcher/workers
  ├── archiver
  ├── WAL sender/receiver
  └── logical/parallel/background workers
```

Main process nhận connection và tạo backend process. Các backend có address space
riêng nhưng phối hợp qua shared memory, semaphore/latch và lock.

Hệ quả:

- connection có startup/authentication/process/session-memory cost;
- crash một backend bất thường có thể khiến postmaster xử lý như server crash để
  bảo vệ shared state;
- không gửi `SIGKILL` tùy tiện cho backend;
- mỗi session giữ transaction, prepared statement, temp object và GUC riêng;
- `max_connections` không phải throughput knob.

Quan sát:

```sql
SELECT
    backend_type,
    state,
    count(*) AS sessions
FROM pg_stat_activity
GROUP BY backend_type, state
ORDER BY backend_type, state;
```

---

## 4. Connection pool là admission control

Một nghìn connection không có nghĩa PostgreSQL chạy một nghìn query hiệu quả cùng
lúc. CPU, lock, buffer và I/O vẫn hữu hạn.

```text
application instances
       │
       ▼
bounded application pool
       │
       ├── direct PostgreSQL
       └── PgBouncer (session/transaction pooling)
```

Pool cần:

- giới hạn theo database capacity, không theo số thread ứng dụng;
- timeout khi chờ pool;
- query/statement/transaction timeout;
- leak detection và connection lifetime;
- headroom cho operator, migration, replication và autovacuum;
- backpressure thay vì queue vô hạn.

Transaction pooling như PgBouncer có thể không tương thích session feature:

- temp table/session advisory lock;
- `SET` không dùng `SET LOCAL`;
- session prepared statement tùy mode/version;
- LISTEN/NOTIFY;
- session state mà application giả định giữ nguyên.

Không thêm pooler trước khi hiểu contract của client.

---

## 5. Shared memory và local memory

```text
RAM
├── PostgreSQL shared memory
│   ├── shared_buffers
│   ├── WAL buffers
│   ├── lock/process/transaction state
│   └── extension shared state
├── per-backend/local memory
│   ├── work_mem cho mỗi sort/hash node
│   ├── maintenance_work_mem cho maintenance
│   └── parser/planner/executor/session state
└── OS filesystem cache + process/native memory
```

`shared_buffers` không phải toàn bộ cache. PostgreSQL còn dựa vào filesystem cache
của OS.

`work_mem` không phải “RAM mỗi connection”:

```text
total có thể ≈ active sessions
             × operations đồng thời mỗi plan
             × parallel workers
             × work_mem
```

Một query có nhiều sort/hash có thể cấp nhiều vùng `work_mem`. Không đặt hàng trăm
MB toàn cục chỉ vì một báo cáo bị spill; dùng query/index/design hoặc `SET LOCAL`
có kiểm soát.

```sql
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW max_connections;
SHOW max_worker_processes;
```

---

## 6. Query pipeline

```text
SQL text
  ↓ parse
Parse tree
  ↓ analyze/rewrite
Query tree
  ↓ cost-based planner
Plan
  ↓ executor
Heap/index/buffer/WAL/lock operations
```

Planner dùng:

- table/index statistics;
- cost setting;
- available path/index/operator class;
- parameter/value visibility;
- join order và cardinality estimate;
- parallel-safety;
- partition pruning.

Storage engine không “sửa” plan estimate sai. Một index tồn tại không buộc planner
dùng index.

Chẩn đoán:

```sql
EXPLAIN (ANALYZE, BUFFERS, WAL, SETTINGS, VERBOSE)
SELECT order_id, status
FROM orders
WHERE customer_id = 1042
  AND created_at >= TIMESTAMPTZ '2026-07-01 00:00:00+00';
```

`ANALYZE` thật sự chạy query. Không dùng trên DML production nếu chưa bọc
transaction/rollback và hiểu side effect.

---

## 7. Relation, fork và file

Một table/index có thể có nhiều fork:

| Fork | Mục đích |
|---|---|
| `main` | page dữ liệu/index chính |
| `fsm` | Free Space Map |
| `vm` | Visibility Map |
| `init` | ảnh khởi tạo của unlogged relation |

Relation lớn được tách thành segment file, mặc định thường 1 GiB. Tên file vật lý
dựa trên relfilenode và có thể đổi sau rewrite.

```sql
SELECT
    c.oid::regclass AS relation,
    pg_relation_filepath(c.oid) AS path,
    pg_size_pretty(pg_relation_size(c.oid)) AS main_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class AS c
WHERE c.oid = 'orders'::regclass;
```

Không automation theo filename trong `PGDATA`. Dùng catalog/API backup chính thức.

Tablespace chỉ đổi vị trí storage:

- không partition dữ liệu logic;
- không tự tạo HA;
- object/tablespace symlink phải được backup đúng;
- planner có thể dùng tablespace cost setting nhưng hardware cần benchmark.

---

## 8. Page layout

Page heap mặc định thường 8 KiB:

```text
+-------------------------------+
| Page header                   |
+-------------------------------+
| ItemId / line pointer array   | grows ↓
|                               |
|          free space           |
|                               |
| tuple data                    | grows ↑
+-------------------------------+
| special space (tùy page type) |
+-------------------------------+
```

Line pointer giữ vị trí tuple trong page. Index TID/`ctid` trỏ tới
`(block number, item offset)`.

`ctid` không phải business key:

- UPDATE có thể tạo tuple ở vị trí khác;
- `VACUUM FULL`, `CLUSTER` hoặc table rewrite đổi vị trí;
- row version mới có `ctid` mới;
- không dùng làm cursor/id lâu dài.

```sql
SELECT ctid, xmin, xmax, order_id
FROM orders
WHERE order_id = 1001;
```

Các system column hữu ích để học/debug nhưng không nên trở thành application
contract.

---

## 9. Heap tuple và MVCC metadata

Tuple header chứa thông tin như:

- `xmin`: XID tạo version;
- `xmax`: XID xóa/thay thế hoặc row-lock metadata;
- command/infomask;
- null bitmap;
- `ctid`.

Snapshot quyết định version visible dựa trên transaction status và XID, không chỉ
“timestamp nhỏ hơn hiện tại”.

```text
UPDATE row

old tuple: xmin=10, xmax=25
new tuple: xmin=25, xmax=0

snapshot trước XID 25 → thấy old
snapshot sau commit 25 → thấy new
```

Đây là lý do reader thường không block writer và ngược lại. Nhưng MVCC không loại
bỏ:

- row/table lock conflict;
- DDL lock;
- unique/FK conflict;
- deadlock;
- write skew/lost update tùy isolation/application;
- vacuum bị old snapshot giữ lại.

Chi tiết sẽ nằm ở `transactions_mvcc.md` trong chủ đề tiếp theo.

---

## 10. UPDATE/DELETE tạo dead tuple

PostgreSQL thường không overwrite row:

```sql
UPDATE orders
SET status = 'paid'
WHERE order_id = 1001;
```

Luồng đơn giản:

1. khóa tuple cần thay;
2. tạo tuple version mới;
3. đánh dấu version cũ bằng `xmax`;
4. cập nhật index cần thiết;
5. WAL-log thay đổi;
6. sau khi không snapshot nào cần version cũ, VACUUM đánh dấu space tái sử dụng.

DELETE cũng để lại version cũ cho tới khi vacuum được phép cleanup.

Hệ quả:

- update-heavy table cần autovacuum tích cực hơn;
- index có thể giữ entry tới dead tuple;
- long transaction làm bloat tăng;
- disk không giảm ngay sau DELETE;
- table/index size là steady-state capacity, không chỉ live row size.

---

## 11. HOT update

Heap-Only Tuple (HOT) update có thể tránh tạo index entry mới khi:

- column thay đổi không được index tham chiếu;
- page hiện tại còn đủ chỗ cho version mới;
- các điều kiện nội bộ khác được đáp ứng.

```text
index entry → root heap tuple → HOT chain → newest visible tuple
```

Lợi ích:

- giảm index write/WAL;
- giảm index bloat;
- update nhanh hơn.

`fillfactor` thấp chừa chỗ trong page:

```sql
ALTER TABLE orders SET (fillfactor = 80);
```

Không đặt 80 cho mọi table:

- tăng table size và cache footprint;
- insert-only table ít lợi;
- HOT ratio phụ thuộc update pattern và index;
- cần rewrite/maintenance để thay đổi có hiệu lực đầy đủ trên dữ liệu cũ.

Theo dõi:

```sql
SELECT
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    CASE
        WHEN n_tup_upd = 0 THEN 0
        ELSE round(100.0 * n_tup_hot_upd / n_tup_upd, 2)
    END AS hot_update_pct
FROM pg_stat_user_tables
ORDER BY n_tup_upd DESC;
```

---

## 12. TOAST: row không trải qua nhiều heap page

PostgreSQL page có kích thước cố định, tuple không span nhiều heap page. Giá trị
lớn như `text`, `bytea`, `jsonb` có thể được:

- giữ inline;
- nén inline;
- lưu out-of-line trong TOAST table;
- nén rồi lưu out-of-line.

```text
heap tuple
  └── TOAST pointer
        └── pg_toast relation chunks
```

TOAST transparent về mặt SQL nhưng không miễn phí:

- đọc `_source`-like payload lớn cần detoast/decompress;
- UPDATE column nhỏ vẫn có thể tạo tuple mới;
- query `SELECT *` kéo payload không cần;
- TOAST table và index cũng vacuum/bloat;
- random access tùy storage strategy/type.

Đo:

```sql
SELECT
    pg_size_pretty(pg_relation_size('documents')) AS heap,
    pg_size_pretty(pg_indexes_size('documents')) AS indexes,
    pg_size_pretty(
        pg_total_relation_size('documents')
        - pg_relation_size('documents')
        - pg_indexes_size('documents')
    ) AS toast_and_aux;
```

Không dùng JSONB khổng lồ thay schema chỉ vì TOAST lưu được.

---

## 13. FSM và Visibility Map

### 13.1 Free Space Map

FSM theo dõi page còn chỗ để insert/update có thể tìm nhanh. Nó là hint có thể
được rebuild, không phải source of truth business.

### 13.2 Visibility Map

VM giữ hai bit cho mỗi heap page:

- all-visible: mọi tuple visible với mọi transaction hiện tại/tương lai;
- all-frozen: tuple không cần freeze tiếp cho tới khi page bị sửa.

Index-only scan:

```text
index chứa đủ column
        │
        ├── VM page all-visible → không cần heap visit
        └── chưa all-visible    → phải kiểm tra heap tuple
```

Vì vậy “covering index” chưa chắc loại heap read. UPDATE làm clear visibility bit;
VACUUM có thể đặt lại.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, created_at
FROM orders
WHERE customer_id = 1042;
```

Đọc `Heap Fetches` của Index Only Scan; số cao có thể do churn/vacuum/visibility.

---

## 14. WAL: log đi trước data page

Quy tắc Write-Ahead Logging:

```text
WAL record mô tả thay đổi
        ↓ flush WAL cần thiết
commit acknowledgement
        ↓
dirty data page có thể ghi sau
```

Nếu crash trước khi data page được ghi, startup process replay WAL (REDO).

WAL cho phép:

- crash recovery;
- physical streaming replication;
- physical base backup + PITR;
- logical decoding khi `wal_level=logical`;
- forensic/replication progress bằng LSN.

```sql
SELECT
    pg_current_wal_lsn(),
    pg_walfile_name(pg_current_wal_lsn());

SELECT *
FROM pg_stat_wal;
```

WAL segment thường 16 MiB nhưng có thể chọn khác khi `initdb`; không hard-code vào
tooling.

---

## 15. Commit path và durability knobs

Đường commit đơn giản:

```text
backend tạo WAL
  ↓
WAL buffer
  ↓ write + durable sync
  ↓
COMMIT trả thành công
```

Group commit cho phép một lần sync phục vụ nhiều transaction gần nhau.

Các setting nguy hiểm:

| Setting | Vai trò | Nếu tắt/giảm |
|---|---|---|
| `fsync` | yêu cầu durable flush | có thể corrupt/mất dữ liệu sau OS/power crash |
| `full_page_writes` | chống torn page sau checkpoint | có thể silent corruption |
| `synchronous_commit` | chờ WAL local/remote theo mode | `off` có thể mất recent commit sau crash nhưng không làm database inconsistent |

```sql
SHOW fsync;
SHOW full_page_writes;
SHOW synchronous_commit;
SHOW wal_level;
```

Không tắt `fsync`/`full_page_writes` trên dữ liệu cần durability để benchmark đẹp.
`SET LOCAL synchronous_commit = off` chỉ khi business chấp nhận mất một cửa sổ
transaction và operation có thể replay/reconcile.

Storage controller phải trung thực về durable flush. WAL không cứu được disk nói
dối `fsync`.

---

## 16. Checkpoint, background writer và crash recovery

Checkpoint:

1. xác định recovery point;
2. đảm bảo dirty buffer cần thiết được ghi theo tiến độ;
3. tạo checkpoint WAL record/control metadata;
4. cho phép WAL cũ được recycle khi không còn retention khác.

Checkpoint không phải:

- backup;
- “commit toàn bộ transaction”;
- lệnh cần chạy định kỳ từ application;
- cách làm query nhanh.

Checkpoint quá thường:

- nhiều full-page image sau mỗi checkpoint;
- write burst;
- WAL volume tăng;
- latency spike.

Checkpoint quá xa:

- recovery phải replay nhiều WAL hơn;
- cần nhiều WAL/disk;
- dirty-page working set lớn.

PostgreSQL 18 tách statistic checkpointer:

```sql
SELECT *
FROM pg_stat_checkpointer;

SELECT *
FROM pg_stat_bgwriter;

SELECT *
FROM pg_stat_io
WHERE backend_type IN ('checkpointer', 'background writer', 'client backend');
```

`track_io_timing`/`track_wal_io_timing` phải bật để timing tương ứng có ý nghĩa.

---

## 17. VACUUM làm bốn việc

Routine vacuum:

1. tái sử dụng space của dead tuple;
2. cập nhật một phần planner statistics cùng ANALYZE khi yêu cầu;
3. cập nhật visibility map;
4. freeze XID/MXID để tránh wraparound.

```sql
VACUUM (ANALYZE, VERBOSE) orders;
```

Standard `VACUUM`:

- chạy cùng SELECT/INSERT/UPDATE/DELETE thông thường;
- đánh dấu space để relation tái sử dụng;
- thường không trả file space cho OS, trừ page trống ở cuối có thể truncate;
- tạo I/O nhưng không rewrite toàn table.

`VACUUM FULL`:

- rewrite table sang file mới;
- cần extra disk trong lúc chạy;
- lấy `ACCESS EXCLUSIVE`;
- trả space về OS;
- không phải maintenance định kỳ.

Mục tiêu là vacuum đủ thường để steady-state không cần `VACUUM FULL`.

---

## 18. Autovacuum và wraparound

Autovacuum launcher tạo worker theo table activity. Trigger vacuum gần đúng dựa
trên threshold + scale factor × table size, nhưng insert threshold, analyze,
freeze, worker availability và per-table setting cũng ảnh hưởng.

Hot table lớn thường cần per-table tuning:

```sql
ALTER TABLE orders SET (
    autovacuum_vacuum_scale_factor = 0.02,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_analyze_threshold = 1000
);
```

Các số chỉ là ví dụ; tính trigger bằng write rate và acceptable dead tuples.

XID là không gian 32-bit có so sánh vòng. PostgreSQL phải freeze tuple đủ cũ.
Nếu tiến sát wraparound:

- anti-wraparound vacuum chạy quyết liệt;
- failsafe có thể bỏ cost delay/index cleanup không thiết yếu;
- cuối cùng server từ chối transaction cấp XID mới để tránh mất dữ liệu.

```sql
SELECT
    datname,
    age(datfrozenxid) AS xid_age
FROM pg_database
ORDER BY xid_age DESC;

SELECT
    n.nspname,
    c.relname,
    age(c.relfrozenxid) AS xid_age,
    c.reloptions
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm')
ORDER BY xid_age DESC
LIMIT 30;
```

Không tắt autovacuum toàn cluster. Anti-wraparound protection vẫn có hành vi riêng,
nhưng disable/tune sai làm bloat/statistics và incident khó hơn.

---

## 19. Old snapshot chặn cleanup

VACUUM không thể xóa version mà transaction/snapshot/slot còn cần.

Nghi phạm:

- transaction chạy lâu;
- `idle in transaction`;
- prepared transaction bỏ quên;
- replication slot/standby feedback;
- logical decoding/backup giữ horizon;
- session không commit/rollback sau lỗi.

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    xact_start,
    backend_xid,
    backend_xmin,
    wait_event_type,
    wait_event,
    left(query, 200) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

```sql
SELECT
    gid,
    prepared,
    owner,
    database,
    age(transaction) AS xid_age
FROM pg_prepared_xacts
ORDER BY prepared;
```

Không terminate theo tuổi một cách mù. Xác định owner/business operation, lock,
rollback cost và retry semantics. Phòng ngừa:

```sql
SHOW idle_in_transaction_session_timeout;
SHOW statement_timeout;
SHOW lock_timeout;
```

Đặt timeout ở role/database/application phù hợp, không một giá trị chung cho OLTP
và batch.

---

## 20. Bloat không chỉ là “file lớn”

Bloat có nhiều dạng:

- dead tuple chưa vacuum;
- free space đã vacuum nhưng chưa tái dùng;
- page sparsity do fillfactor/churn;
- index page split/dead entry;
- TOAST bloat;
- dung lượng hợp lệ do live data tăng.

```sql
SELECT
    schemaname,
    relname,
    n_live_tup,
    n_dead_tup,
    last_autovacuum,
    last_autoanalyze,
    autovacuum_count,
    autoanalyze_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

`n_dead_tup` là estimate. Không kết luận cần `VACUUM FULL` chỉ từ ratio hoặc table
size. Kiểm tra:

- write/update/delete rate;
- old snapshot;
- autovacuum progress;
- reusable space và growth trend;
- query latency/cache impact;
- maintenance window/disk.

Các lựa chọn tăng dần: tune vacuum → standard vacuum → REINDEX/online tool có
kiểm soát → table rewrite/VACUUM FULL khi lợi ích đáng downtime.

---

## 21. Unlogged và temporary table

Unlogged table:

- không WAL-log thay đổi data như logged table;
- nhanh hơn cho một số workload;
- bị truncate sau crash recovery;
- không replicate vật lý như dữ liệu logged theo kỳ vọng thông thường;
- index của nó cũng unlogged.

```sql
CREATE UNLOGGED TABLE import_stage (
    source_id bigint,
    payload jsonb
);
```

Chỉ dùng cho dữ liệu có thể rebuild. “Không cần backup” phải là quyết định domain.

Temporary table thuộc session/transaction theo option, dùng temp buffers và có
catalog/connection-pooling implications.

Sequence:

- không transactional như row update;
- `nextval` đã lấy thường không rollback;
- gap là bình thường;
- không dùng sequence để chứng minh số lượng transaction hoặc không có mất dữ liệu.

---

## 22. Lock và lightweight synchronization

Hai lớp dễ nhầm:

| Lớp | Ví dụ | Mục tiêu |
|---|---|---|
| SQL heavyweight lock | relation, row, transaction/advisory | concurrency semantics |
| LWLock/spin/latch/buffer pin | shared buffer/WAL/internal structure | bảo vệ state nội bộ |

MVCC giảm lock read/write nhưng DDL vẫn có thể cần lock mạnh. Buffer pin/LWLock
wait không được sửa bằng đổi isolation level.

```sql
SELECT
    pid,
    wait_event_type,
    wait_event,
    state,
    left(query, 160) AS query
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
ORDER BY pid;
```

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocker.pid AS blocker_pid,
    blocked.query AS blocked_query,
    blocker.query AS blocker_query
FROM pg_stat_activity AS blocked
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
JOIN pg_stat_activity AS blocker ON blocker.pid = b.blocker_pid;
```

Incident cần tìm blocker root, không kill mọi waiter.

---

## 23. Catalog và extension

PostgreSQL catalog là table hệ thống mô tả:

- database/schema/relation/column;
- type/function/operator;
- role/privilege;
- statistics/dependency;
- extension.

```sql
SELECT
    extname,
    extversion
FROM pg_extension
ORDER BY extname;
```

Extension chạy trong trust boundary của database server tùy loại:

- có thể thêm type/operator/index access method/background worker;
- version và binary phải tương thích khi upgrade/restore/replica;
- superuser/trusted extension semantics khác nhau;
- extension supply chain là security concern.

Không sửa catalog trực tiếp. Dùng DDL/API chính thức.

---

## 24. Checksums và corruption boundary

Data checksums giúp phát hiện một số page corruption khi page được đọc. Chúng không:

- sửa page;
- thay backup;
- phát hiện mọi lỗi logic/application;
- bảo vệ WAL/archive/snapshot nếu quy trình khác sai;
- chứng minh storage bền.

```sql
SHOW data_checksums;
```

Khi checksum error:

1. dừng thao tác ghi phá evidence theo incident policy;
2. xác định relation/block/copy;
3. kiểm tra kernel/storage/ECC/log;
4. so replica/backup và phạm vi corruption;
5. restore/rebuild đúng object;
6. không “zero page” hoặc bỏ checksum để hết cảnh báo.

`amcheck`/backup verification và restore drill bổ sung coverage nhưng không tạo
đảm bảo tuyệt đối.

---

## 25. Baseline chẩn đoán

### Session và wait

```sql
SELECT
    clock_timestamp() AS captured_at,
    pid,
    datname,
    usename,
    application_name,
    state,
    xact_start,
    query_start,
    wait_event_type,
    wait_event,
    left(query, 200) AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY query_start NULLS LAST;
```

### Table/vacuum

```sql
SELECT
    relid::regclass AS relation,
    n_live_tup,
    n_dead_tup,
    n_mod_since_analyze,
    last_autovacuum,
    last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

### Database

```sql
SELECT
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    temp_files,
    temp_bytes,
    deadlocks
FROM pg_stat_database
ORDER BY datname;
```

Cache hit ratio riêng lẻ không đủ kết luận. Sequential scan hợp lý có thể làm ratio
thấp; OS cache không xuất hiện đầy đủ trong `blks_hit`.

---

## 26. Runbook “database chậm”

### Bước 1 – Blast radius

- một query/service/database hay toàn instance;
- latency, throughput, error và timeout bắt đầu lúc nào;
- deploy/schema/batch/backup/vacuum/checkpoint gần đây;
- read, write, commit hay connection chậm;
- primary hay standby.

### Bước 2 – Saturation và wait

```sql
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions
FROM pg_stat_activity
WHERE state = 'active'
GROUP BY wait_event_type, wait_event
ORDER BY sessions DESC;
```

Đối chiếu CPU, RAM, swap, disk latency/queue, filesystem free space và network.

### Bước 3 – Blocker/long transaction

Dùng `pg_blocking_pids`, `xact_start`, prepared transaction và vacuum progress.

```sql
SELECT *
FROM pg_stat_progress_vacuum;
```

### Bước 4 – Workload/query

Nếu có `pg_stat_statements`, so total time/calls/mean/p95 từ telemetry; không chỉ
tìm query chậm nhất một lần. Dùng EXPLAIN an toàn và kiểm tra estimate/buffer/spill.

### Bước 5 – Giảm tác động

Theo bằng chứng:

- rate-limit/admission control;
- rollback release/query;
- cancel query cụ thể rồi terminate khi cần;
- sửa blocker transaction;
- tăng storage/capacity;
- tune autovacuum table nóng;
- dừng retry storm;
- failover chỉ khi primary thật sự là failure domain và có fencing.

Restart không phải root cause.

---

## 27. Failure mode thường gặp

### 27.1 Connection storm

Backend process/RAM/scheduler tăng, application timeout rồi retry. Giới hạn pool,
thêm backoff và giữ admin reserve.

### 27.2 `idle in transaction`

Giữ snapshot/lock, ngăn vacuum cleanup. Sửa transaction boundary và timeout.

### 27.3 Autovacuum “gây chậm” nên bị tắt

Tắt làm dead tuple/statistics/wraparound xấu hơn. Tune cost/worker/per-table và sửa
old snapshot.

### 27.4 DELETE xong disk không giảm

Standard vacuum tái dùng nội bộ, không nhất thiết trả OS. Dùng lifecycle/partition
hoặc rewrite có kế hoạch nếu thực sự cần shrink.

### 27.5 `VACUUM FULL` chạy định kỳ

Exclusive lock, rewrite và extra disk gây outage. Duy trì steady-state bằng routine
vacuum.

### 27.6 Tăng `work_mem` toàn cục

Memory nhân theo operation/concurrency/parallelism. Tune query/index hoặc local.

### 27.7 Checkpoint tay để “flush cho an toàn”

WAL/durability đã bảo vệ commit; checkpoint cưỡng bức có thể tạo I/O spike.

### 27.8 Dùng `ctid` làm ID

Tuple location thay đổi sau update/rewrite. Dùng khóa nghiệp vụ/PK.

### 27.9 Tắt `fsync` hoặc `full_page_writes`

Có nguy cơ corruption sau crash/power loss. Không phải production tuning.

### 27.10 Replica = backup

DELETE/corruption logic có thể replicate. Cần base backup/WAL archive/restore drill.

---

## 28. Checklist production

### Connection/memory

- [ ] Pool bounded theo capacity và có wait timeout?
- [ ] Có reserve connection cho operator/replication?
- [ ] `work_mem` được tính theo plan × concurrency × parallel worker?
- [ ] `idle_in_transaction_session_timeout` phù hợp?
- [ ] PgBouncer mode tương thích session feature?

### Storage/WAL

- [ ] `fsync` và `full_page_writes` bật?
- [ ] WAL/archive/slot/disk có alert và headroom?
- [ ] Checkpoint statistic không có burst bất thường?
- [ ] Data checksums/backup verification theo risk?
- [ ] Unlogged/temp data thật sự rebuild được?

### MVCC/vacuum

- [ ] Autovacuum bật và table nóng có per-table threshold?
- [ ] Theo dõi dead tuple, last vacuum/analyze và progress?
- [ ] XID/MXID age có alert trước anti-wraparound emergency?
- [ ] Long/prepared transaction/slot không giữ horizon?
- [ ] `VACUUM FULL` không nằm trong routine schedule?

### Chẩn đoán

- [ ] Có `pg_stat_activity`, `pg_stat_io`, `pg_stat_wal`, checkpointer baseline?
- [ ] Metric được đọc theo delta và biết thời điểm stats reset?
- [ ] Query regression có `pg_stat_statements`/EXPLAIN evidence?
- [ ] Incident tìm root blocker thay vì kill mọi waiter?
- [ ] Backup đã restore drill, không chỉ “job xanh”?

---

## 29. Câu hỏi phỏng vấn

1. PostgreSQL cluster, database và schema khác nhau thế nào?
2. Process-per-connection ảnh hưởng pooling ra sao?
3. Vì sao `work_mem=64MB` không có nghĩa mỗi connection chỉ dùng 64 MB?
4. UPDATE tạo tuple version mới như thế nào?
5. HOT update cần điều kiện gì?
6. FSM và visibility map khác nhau ra sao?
7. Vì sao index-only scan vẫn có Heap Fetches?
8. TOAST giải quyết giới hạn page thế nào?
9. WAL cho phép commit trước khi data page xuống disk ra sao?
10. Checkpoint khác flush/backup thế nào?
11. Standard VACUUM và VACUUM FULL khác nhau gì?
12. Long transaction làm bloat thế nào?
13. XID wraparound nguy hiểm vì sao và freezing giải quyết gì?
14. Tại sao tắt autovacuum thường làm performance tệ hơn?

---

## 30. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/)
- [Architectural fundamentals](https://www.postgresql.org/docs/current/tutorial-arch.html)
- [Database physical storage](https://www.postgresql.org/docs/current/storage.html)
- [TOAST](https://www.postgresql.org/docs/current/storage-toast.html)
- [MVCC introduction](https://www.postgresql.org/docs/current/mvcc-intro.html)
- [Write-Ahead Logging](https://www.postgresql.org/docs/current/wal-intro.html)
- [WAL configuration](https://www.postgresql.org/docs/current/runtime-config-wal.html)
- [Routine vacuuming](https://www.postgresql.org/docs/current/routine-vacuuming.html)
- [VACUUM](https://www.postgresql.org/docs/current/sql-vacuum.html)
- [Monitoring statistics](https://www.postgresql.org/docs/current/monitoring-stats.html)

Học tiếp:

1. [Data Modeling & Types](data_modeling_types.md).
2. [Transactions & MVCC](transactions_mvcc.md).
3. [Indexing & Query Planner](indexing_planner.md).

---

*Cập nhật lần cuối: 2026-07-31.*
