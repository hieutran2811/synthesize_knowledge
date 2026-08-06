# PostgreSQL Transactions, MVCC & Locking

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Bài này xây mental model về
> transaction, snapshot, isolation anomaly, row/table/advisory lock, deadlock,
> Serializable Snapshot Isolation và retry an toàn.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](architecture_storage.md) ·
[Data Modeling & Types](data_modeling_types.md).

---

## 1. Concurrency control phải bảo vệ điều gì?

Nhiều request có thể cùng đọc một trạng thái rồi đưa ra quyết định. Mỗi câu SQL
đều đúng riêng lẻ chưa có nghĩa kết quả cuối đúng.

```text
Transaction A                 Transaction B
-------------                 -------------
đọc trạng thái X              đọc cùng trạng thái X
quyết định dựa trên X         quyết định khác dựa trên X
ghi kết quả A                 ghi kết quả B
```

Database phải giải quyết ba vấn đề khác nhau:

1. **visibility:** transaction nhìn thấy row version nào;
2. **conflict:** writer/locker nào phải chờ hoặc thất bại;
3. **serializability:** kết quả commit có tương đương một thứ tự chạy tuần tự nào
   không.

MVCC chủ yếu giải quyết visibility và giảm reader/writer blocking. Constraint,
lock, isolation level và retry mới hoàn thiện business invariant.

---

## 2. ACID bằng ngôn ngữ vận hành

| Thuộc tính | Ý nghĩa thực tế |
|---|---|
| Atomicity | mọi thay đổi trong transaction cùng commit hoặc cùng rollback |
| Consistency | constraint được giữ; business rule còn phụ thuộc model/isolation |
| Isolation | quy định transaction thấy và xung đột với concurrent work ra sao |
| Durability | commit được bảo vệ bởi WAL theo durability configuration |

Hai hiểu nhầm:

- chữ **C** không có nghĩa PostgreSQL tự hiểu “mỗi ca phải còn một bác sĩ trực”;
  invariant phải được diễn đạt bằng constraint, lock hoặc serializable workflow;
- chữ **I** không có nghĩa mọi transaction mặc định chạy như từng cái một.
  PostgreSQL mặc định là `READ COMMITTED`.

Kiểm tra session:

```sql
SHOW transaction_isolation;
SHOW transaction_read_only;
SHOW transaction_deferrable;
SHOW synchronous_commit;
```

Durability/WAL đã được trình bày ở
[Architecture §14–16](architecture_storage.md); chương này tập trung vào
concurrency.

---

## 3. Autocommit vẫn là transaction

Nếu client không gửi `BEGIN`, mỗi statement thành công được chạy trong một
transaction ngầm và commit ở cuối statement:

```sql
UPDATE app.accounts
SET balance = balance - 100
WHERE account_id = 1;
```

Autocommit phù hợp cho một thao tác nguyên tử đơn statement. Khi invariant cần
nhiều statement, mở transaction rõ:

```sql
BEGIN;

UPDATE app.accounts
SET balance = balance - 100
WHERE account_id = 1;

UPDATE app.accounts
SET balance = balance + 100
WHERE account_id = 2;

COMMIT;
```

Không dựa vào default của driver/framework. Log transaction boundary ở code và
test failure giữa các statement.

---

## 4. Transaction boundary phải ôm đúng business unit

Một transfer tối thiểu cần:

```text
validate debit
    ↓
debit source
    ↓
credit destination
    ↓
write ledger/idempotency record
    ↓
COMMIT
```

Nếu commit sau debit nhưng trước credit, atomicity bị mất. Ngược lại, nếu giữ
transaction trong lúc gọi HTTP, chờ người dùng hoặc xử lý file lớn, lock/snapshot
bị giữ quá lâu.

Boundary tốt:

- đủ rộng để bảo vệ một invariant database;
- đủ ngắn để không ôm network/user think time;
- external side effect được xử lý bằng outbox/idempotency, không đặt niềm tin vào
  “hai hệ thống cùng commit”;
- mọi exit path đều commit hoặc rollback rõ ràng.

---

## 5. Một lỗi làm transaction vào trạng thái aborted

Sau một statement lỗi trong transaction, PostgreSQL không tiếp tục các statement
thường cho tới khi rollback:

```sql
BEGIN;

INSERT INTO app.accounts (account_id, balance)
VALUES (1, 100);

-- Nếu statement tiếp theo vi phạm constraint, transaction bị aborted.
INSERT INTO app.accounts (account_id, balance)
VALUES (1, 200);

ROLLBACK;
```

Client thường thấy:

```text
current transaction is aborted,
commands ignored until end of transaction block
```

Không “nuốt exception rồi tiếp tục dùng connection”. Framework phải rollback
transaction; connection chỉ được trả về pool sau khi state sạch.

---

## 6. Savepoint là partial rollback, không phải nested commit

Ví dụ độc lập:

```sql
CREATE TEMP TABLE transaction_demo (
    id integer PRIMARY KEY,
    note text NOT NULL
);

BEGIN;

INSERT INTO transaction_demo (id, note)
VALUES (1, 'bắt buộc');

SAVEPOINT optional_part;

INSERT INTO transaction_demo (id, note)
VALUES (2, 'có thể hoàn tác');

ROLLBACK TO SAVEPOINT optional_part;

COMMIT;
```

`ROLLBACK TO SAVEPOINT` hủy thay đổi sau savepoint và cho transaction tiếp tục.
`RELEASE SAVEPOINT` bỏ marker nhưng không commit độc lập.

Cần nhớ:

- PostgreSQL không có nested transaction commit độc lập;
- outer rollback vẫn hủy mọi thay đổi, kể cả phần đã release;
- lock lấy sau savepoint được release khi rollback về savepoint;
- quá nhiều savepoint/subtransaction có overhead và làm logic lỗi khó theo dõi.

Không dùng savepoint để biến một invariant bắt buộc thành “best effort”.

---

## 7. MVCC: row logic có nhiều tuple version

UPDATE thường tạo tuple version mới:

```text
logical account row
├── version V1: balance=100, visible với snapshot cũ
└── version V2: balance=80,  visible với snapshot mới sau commit
```

Snapshot không copy toàn database. Nó chứa thông tin đủ để quyết định transaction
nào đang chạy/đã hoàn thành, từ đó kiểm tra `xmin`/`xmax` của tuple.

Hệ quả:

- plain `SELECT` thường không khóa row chống writer;
- reader cũ có thể đọc V1 trong khi writer đã tạo V2;
- version chết cần VACUUM khi không snapshot nào còn cần;
- long transaction làm cleanup horizon đứng lại và gây bloat;
- “đọc không block ghi” không có nghĩa hai writer không block nhau.

Chi tiết tuple, visibility map và vacuum nằm ở
[Architecture §10–18](architecture_storage.md).

---

## 8. Snapshot không đồng nghĩa “dữ liệu mới nhất”

Snapshot trả lời:

```text
version nào được phép nhìn?
```

Nó không hứa:

```text
đây là trạng thái mới nhất tại thời điểm application dùng kết quả
```

Giữa lúc đọc và hành động, transaction khác có thể commit. Vì vậy:

- report cần view nhất quán có thể dùng stable snapshot;
- quyết định “nếu còn hàng thì trừ” nên là atomic write/lock/serializable;
- cache/API response không tự trở thành fresh chỉ vì query nằm trong transaction;
- replica còn có replication lag ngoài snapshot semantics.

---

## 9. Bốn isolation level, ba implementation

| Isolation yêu cầu | PostgreSQL 18 thực hiện | Snapshot | Anomaly còn có thể |
|---|---|---|---|
| Read Uncommitted | như Read Committed | mỗi statement | nonrepeatable, phantom, serialization |
| Read Committed | mặc định | mỗi statement | nonrepeatable, phantom, serialization |
| Repeatable Read | snapshot isolation | từ statement dữ liệu đầu tiên | serialization anomaly/write skew |
| Serializable | SSI trên snapshot isolation | từ statement dữ liệu đầu tiên | transaction có thể bị abort để ngăn anomaly |

PostgreSQL không cho dirty read, kể cả khi yêu cầu `READ UNCOMMITTED`.
`REPEATABLE READ` của PostgreSQL còn ngăn phantom read, mạnh hơn mức tối thiểu của
SQL standard, nhưng chưa serializable.

Thiết lập ngay khi bắt đầu:

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ READ WRITE;
```

Hoặc:

```sql
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

Isolation phải được đặt trước query/data-modification statement tạo snapshot.

---

## 10. Read Committed dùng snapshot theo statement

```text
BEGIN READ COMMITTED
  SELECT A  → snapshot S1
  ...
  transaction khác COMMIT
  ...
  SELECT B  → snapshot S2
COMMIT
```

Hai `SELECT` liên tiếp trong cùng transaction có thể thấy kết quả khác:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT balance
FROM app.accounts
WHERE account_id = 1;

-- Một transaction khác có thể commit ở đây.

SELECT balance
FROM app.accounts
WHERE account_id = 1;

COMMIT;
```

Mỗi statement không thấy uncommitted data, nhưng toàn transaction không có stable
snapshot.

Read Committed phù hợp cho nhiều OLTP flow khi:

- write được diễn đạt nguyên tử;
- constraint bảo vệ uniqueness/relation;
- row cần quyết định được khóa;
- workflow chấp nhận retry khi deadlock/constraint race.

---

## 11. Read Committed recheck row bị concurrent update

`UPDATE`, `DELETE` và locking `SELECT` tìm candidate theo snapshot đầu statement.
Nếu candidate đã bị transaction khác update:

1. statement chờ transaction đó kết thúc;
2. nếu transaction kia commit, PostgreSQL lấy version mới;
3. `WHERE` được đánh giá lại trên version mới;
4. nếu còn match, operation tiếp tục.

Atomic inventory decrement:

```sql
UPDATE app.inventory
SET quantity_on_hand = quantity_on_hand - :requested
WHERE sku = :sku
  AND quantity_on_hand >= :requested
RETURNING quantity_on_hand;
```

Hai buyer cạnh tranh cùng row sẽ serialize ở row update; điều kiện được recheck.
Không có row trả về nghĩa là thiếu hàng hoặc SKU không tồn tại, cần phân biệt nếu
domain yêu cầu.

Read Committed có thể thấy version mới của row đang update nhưng không thấy mọi
thay đổi khác của concurrent transaction trong cùng snapshot. Tránh một statement
write có search condition phức tạp nếu logic giả định global snapshot đồng nhất.

---

## 12. Lost update do read–compute–write

Anti-pattern:

```text
A đọc balance=100          B đọc balance=100
A tính 100-10              B tính 100-20
A UPDATE balance=90
                           B UPDATE balance=80
```

Kết quả 80 làm mất thay đổi của A.

Giải pháp ưu tiên là đưa phép tính vào một statement:

```sql
UPDATE app.accounts
SET balance = balance - :amount
WHERE account_id = :account_id
  AND balance >= :amount
RETURNING balance;
```

Nếu quyết định phức tạp cần application:

- `SELECT ... FOR UPDATE` rồi tính;
- optimistic version check;
- hoặc Serializable + retry toàn transaction.

Isolation level cao không thay thế việc hiểu write pattern. `REPEATABLE READ` sẽ
abort một transaction khi update cùng row version đã đổi, nhưng application vẫn
phải retry.

---

## 13. Pessimistic row locking

```sql
BEGIN;

SELECT account_id, balance
FROM app.accounts
WHERE account_id IN (:source_id, :destination_id)
ORDER BY account_id
FOR UPDATE;

-- Validate và update sau khi đã khóa cả hai account.

COMMIT;
```

`FOR UPDATE` khóa row trả về tới transaction end. Transaction khác vẫn plain
`SELECT` được version visible, nhưng update/delete/lock xung đột phải chờ.

Lock trước khi gọi external service là anti-pattern. Nếu transaction giữ lock rồi
chờ HTTP 30 giây, mọi request cùng row xếp hàng và deadlock surface tăng.

---

## 14. Bốn row lock mode

| Lock clause | Chặn chính | Dùng khi |
|---|---|---|
| `FOR UPDATE` | mọi locker/writer xung đột | sẽ đổi key/delete hoặc cần mạnh nhất |
| `FOR NO KEY UPDATE` | update/delete mạnh, nhưng không chặn key-share | update không đổi FK-referenceable key |
| `FOR SHARE` | update/delete; cho share/key-share khác | cần shared protection mạnh |
| `FOR KEY SHARE` | delete hoặc update key | bảo vệ referenced key |

PostgreSQL tự chọn row lock cho `UPDATE`:

- update column thuộc suitable unique key có thể dùng `FOR UPDATE`;
- update không đổi key thường dùng `FOR NO KEY UPDATE`;
- FK dùng key-share semantics để parent key không biến mất.

Row lock:

- không chặn plain reader;
- được release ở transaction end/savepoint rollback;
- có thể gây disk write vì tuple phải được đánh dấu locked;
- không có một in-memory row-lock count limit như object lock table.

Chọn lock yếu nhất **đủ đúng**, không chọn yếu hơn vì benchmark.

---

## 15. `NOWAIT` và `SKIP LOCKED`

Fail ngay nếu row đang bị khóa:

```sql
SELECT *
FROM app.orders
WHERE order_id = :order_id
FOR UPDATE NOWAIT;
```

`NOWAIT` phù hợp khi caller có fallback rõ và không muốn xếp hàng.

Bỏ qua row đang khóa:

```sql
SELECT *
FROM app.jobs
WHERE status = 'READY'
ORDER BY available_at, job_id
FOR UPDATE SKIP LOCKED
LIMIT 1;
```

`SKIP LOCKED` cố ý cho view không nhất quán, phù hợp queue-like consumers. Không
dùng nó cho report, billing scan hoặc batch bắt buộc xử lý đủ row; row “skip” có
thể bị bỏ quên nếu không có vòng quét/recovery.

---

## 16. Queue claim bằng một statement

```sql
WITH next_job AS (
    SELECT job_id
    FROM app.jobs
    WHERE status = 'READY'
      AND available_at <= now()
    ORDER BY available_at, job_id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
UPDATE app.jobs AS j
SET
    status = 'RUNNING',
    worker_id = :worker_id,
    started_at = now(),
    lease_until = now() + interval '2 minutes'
FROM next_job
WHERE j.job_id = next_job.job_id
RETURNING j.*;
```

Worker nên commit claim nhanh rồi xử lý ngoài transaction. Thiết kế còn cần:

- lease/heartbeat để reclaim job khi worker chết;
- attempt count và dead-letter policy;
- idempotent handler vì job có thể được giao lại;
- index bắt đầu bằng trạng thái/thời điểm phù hợp query;
- fairness không được bảo đảm tuyệt đối bởi concurrent workers.

Database queue phù hợp volume vừa và cần transaction cùng dữ liệu. Nó không tự có
mọi tính chất của Kafka/message broker.

---

## 17. Repeatable Read giữ một snapshot

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT SUM(balance)
FROM app.accounts;

-- Concurrent commits sau snapshot không xuất hiện.

SELECT SUM(balance)
FROM app.accounts;

COMMIT;
```

Snapshot được cố định ở statement `SELECT`/DML đầu tiên, không nhất thiết ngay tại
`BEGIN`. Transaction vẫn thấy write của chính nó.

Phù hợp cho:

- report/export cần nhiều query cùng một cut;
- read–modify flow chấp nhận serialization retry;
- batch cần stable set nhưng không yêu cầu kết quả tương đương serial execution.

Snapshot ổn định có thể giữ version cũ lâu và cản vacuum cleanup. Report nhiều giờ
nên cân nhắc replica, batching, exported snapshot có kiểm soát và bloat budget.

---

## 18. Repeatable Read có thể abort concurrent updater

Nếu row target đã được transaction khác thay đổi sau snapshot:

```text
ERROR: could not serialize access due to concurrent update
SQLSTATE: 40001
```

PostgreSQL không thể chuyển sang version mới mà vẫn giữ stable snapshot, nên hủy
transaction.

Phải:

1. rollback;
2. bắt đầu transaction mới;
3. đọc snapshot mới;
4. chạy lại toàn bộ decision logic;
5. commit lại.

Không chỉ retry statement cuối vì giá trị dùng để tạo statement có thể đến từ
snapshot cũ.

---

## 19. Write skew: stable snapshot vẫn chưa đủ

Giả sử mỗi ca phải có ít nhất một bác sĩ trực:

```sql
CREATE TABLE app.doctors_on_call (
    shift_date date NOT NULL,
    doctor_id bigint NOT NULL,
    on_call boolean NOT NULL,
    PRIMARY KEY (shift_date, doctor_id)
);
```

Hai transaction Repeatable Read:

```text
Transaction A                      Transaction B
-------------                      -------------
đếm 2 bác sĩ trực                  đếm 2 bác sĩ trực
tắt doctor 10                      tắt doctor 20
COMMIT                             COMMIT
```

Hai transaction update **hai row khác nhau**, nên không có write-write conflict.
Cả hai có thể commit và để lại 0 bác sĩ trực. Đây là write skew/serialization
anomaly.

Giải pháp:

- Serializable cho mọi writer tham gia invariant và retry `40001`;
- hoặc lock một coordination row chung cho `(shift_date)`;
- hoặc remodel để invariant thành constraint declarative nếu có thể.

Chỉ đổi từ Read Committed sang Repeatable Read không sửa được invariant cross-row.

---

## 20. Serializable là kết quả, không phải “khóa mọi thứ”

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT count(*)
FROM app.doctors_on_call
WHERE shift_date = :shift_date
  AND on_call;

UPDATE app.doctors_on_call
SET on_call = false
WHERE shift_date = :shift_date
  AND doctor_id = :doctor_id;

COMMIT;
```

PostgreSQL Serializable dùng **Serializable Snapshot Isolation (SSI)**:

1. đọc bằng stable snapshot như Repeatable Read;
2. theo dõi read/write dependencies giữa transaction;
3. phát hiện pattern có thể tạo cycle không serializable;
4. abort một transaction để phá cycle.

Nó không đơn giản biến mọi read thành blocking lock. Giá phải trả là tracking
overhead và transaction retry.

Serializable đúng khi tất cả read/write liên quan invariant tham gia cùng
protocol. Một writer chạy Read Committed ngoài protocol có thể phá giả định.

---

## 21. Predicate lock `SIReadLock`

SSI theo dõi “transaction đã đọc predicate nào” bằng predicate lock:

```sql
SELECT
    locktype,
    mode,
    relation::regclass,
    page,
    tuple,
    pid
FROM pg_locks
WHERE mode = 'SIReadLock';
```

`SIReadLock` khác blocking lock:

- không block writer;
- ghi nhận dependency để SSI quyết định abort;
- có thể ở tuple, page hoặc relation level;
- query plan quyết định vùng dữ liệu được theo dõi;
- sequential scan thường cần relation-level predicate lock;
- nhiều fine-grained lock có thể được promote để tiết kiệm shared memory.

Tăng `max_pred_locks_*` không phải tuning đầu tiên. Đầu tiên phải đo serialization
failure, query plan, transaction length và contention.

---

## 22. `SERIALIZABLE READ ONLY DEFERRABLE`

Report read-only dài có thể chờ safe snapshot:

```sql
BEGIN
    ISOLATION LEVEL SERIALIZABLE
    READ ONLY
    DEFERRABLE;

SELECT /* báo cáo nhất quán */ count(*)
FROM app.orders;

COMMIT;
```

Transaction có thể chờ trước khi query bắt đầu. Khi lấy được safe snapshot, nó có
thể đọc mà không có nguy cơ serialization failure như read-write serializable
transaction.

Trade-off:

- latency khởi động không dự đoán chính xác dưới write load;
- phù hợp report có thể chờ, không phù hợp request latency thấp;
- `DEFERRABLE` chỉ có ý nghĩa với Serializable + Read Only;
- long snapshot vẫn ảnh hưởng vacuum/capacity.

Wait event có thể là `SafeSnapshot`.

---

## 23. Retry là một phần của transaction contract

Các SQLSTATE quan trọng:

| SQLSTATE | Tên | Retry |
|---|---|---|
| `40001` | `serialization_failure` | retry toàn transaction |
| `40P01` | `deadlock_detected` | thường retry toàn transaction |
| `55P03` | `lock_not_available` | tùy `NOWAIT`/timeout và SLA |
| `23505` | `unique_violation` | thường business conflict; chỉ retry khi biết là race |
| `23P01` | `exclusion_violation` | thường business conflict; chỉ retry theo domain |

Không parse message text; dùng SQLSTATE.

Retry loop:

```text
for attempt in 1..max_attempts
    begin transaction
    read + decide + write
    try commit
    if SQLSTATE retryable
        rollback
        wait exponential backoff + jitter
        continue
    else
        propagate error
fail with explicit overload/conflict result
```

Retry không được vô hạn. Theo dõi attempt count, total latency và exhausted retry.
Contention cao cần sửa hot spot/workflow, không chỉ tăng số lần retry.

---

## 24. Retry toàn bộ logic, không chỉ câu SQL lỗi

Sai:

```text
đọc price/stock một lần
BEGIN
UPDATE dùng giá trị cũ
COMMIT → 40001
BEGIN
retry chỉ UPDATE cũ
```

Đúng:

```text
BEGIN mới
đọc lại price/stock/rule
tính lại decision
ghi lại
COMMIT
```

Giá trị random/time/ID cũng cần semantics rõ:

- idempotency key phải giữ ổn định qua retry của cùng request;
- DB-generated ID có thể đổi và sequence có gap;
- `now()` được tính theo transaction mới;
- external response dùng để quyết định có thể đã thay đổi.

PostgreSQL không auto-retry vì server không biết logic ngoài SQL nào phải chạy lại.

---

## 25. External side effect làm retry nguy hiểm

Anti-pattern:

```text
BEGIN
INSERT payment
gọi cổng thanh toán → thành công
COMMIT → serialization failure
retry → gọi thanh toán lần hai
```

Giải pháp thường dùng:

```text
DB transaction
├── cập nhật aggregate
└── insert outbox row cùng commit

outbox worker
├── gửi với idempotency key
└── đánh dấu kết quả bằng transaction khác
```

Hoặc external API phải hỗ trợ idempotency key bền. Không giữ database transaction
mở trong lúc chờ network chỉ để “cảm giác atomic”.

Two-phase commit không tự biến một HTTP API thành transactional participant và
không loại bỏ nhu cầu idempotency.

---

## 26. Optimistic locking bằng version column

```sql
CREATE TABLE app.documents (
    document_id bigint PRIMARY KEY,
    content jsonb NOT NULL,
    version bigint NOT NULL DEFAULT 0
);
```

Client đọc `(content, version)` rồi compare-and-set:

```sql
UPDATE app.documents
SET
    content = :new_content,
    version = version + 1
WHERE document_id = :document_id
  AND version = :expected_version
RETURNING version;
```

Zero row nghĩa là stale version hoặc row không tồn tại. Application có thể:

- trả `409 Conflict`;
- đọc lại và merge;
- retry nếu operation thực sự commutative/idempotent.

Optimistic locking tốt khi conflict hiếm và user edit lâu ngoài transaction.
Nó chỉ bảo vệ row/version được check; invariant xuyên nhiều row vẫn cần protocol
khác.

---

## 27. Unique constraint là concurrency primitive

Check-then-insert có race:

```sql
SELECT 1
FROM app.idempotency_keys
WHERE key = :key;

-- Hai transaction đều có thể không thấy row.
```

Enforce bằng unique key:

```sql
INSERT INTO app.idempotency_keys (key, request_hash, status)
VALUES (:key, :request_hash, 'STARTED')
ON CONFLICT (key) DO NOTHING
RETURNING key;
```

Nếu không trả row, đọc record hiện có và kiểm tra:

- cùng key nhưng request hash khác phải lỗi;
- completed có thể trả stored response;
- in-progress cần wait/poll/lease policy;
- failed/retryable cần state machine rõ.

Constraint đóng race tại database. `ON CONFLICT` không tự thiết kế idempotency
semantics.

---

## 28. Table lock tồn tại bên cạnh row lock

Mọi statement lấy table-level lock, kể cả plain `SELECT`:

| Operation điển hình | Table lock |
|---|---|
| plain `SELECT` | `ACCESS SHARE` |
| `SELECT ... FOR UPDATE` | `ROW SHARE` |
| `INSERT`/`UPDATE`/`DELETE`/`MERGE` | `ROW EXCLUSIVE` |
| `VACUUM`/`ANALYZE`/concurrent index | `SHARE UPDATE EXCLUSIVE` |
| `CREATE INDEX` thường | `SHARE` |
| nhiều DDL/`TRUNCATE`/`VACUUM FULL` | `ACCESS EXCLUSIVE` |

Tên có chữ `ROW` vẫn là **table-level lock mode** lịch sử.

Điểm nhớ:

- chỉ `ACCESS EXCLUSIVE` chặn plain `SELECT`;
- DML có thể chạy song song vì `ROW EXCLUSIVE` không tự conflict với chính nó;
- row conflict được giải quyết thêm ở tuple/transaction ID;
- lock thường giữ tới transaction end, không tới statement end.

---

## 29. DDL “nhanh” vẫn có thể gây outage

Một `ALTER TABLE` metadata-only có thể chạy vài millisecond sau khi lấy lock,
nhưng chờ lock phía sau transaction dài:

```text
long SELECT giữ ACCESS SHARE
       ↓
ALTER TABLE chờ ACCESS EXCLUSIVE
       ↓
query mới xếp sau ALTER theo lock queue
       ↓
application latency tăng hàng loạt
```

Migration baseline:

```sql
BEGIN;

SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '15min';

ALTER TABLE app.orders
    ADD COLUMN risk_score integer;

COMMIT;
```

Nếu không lấy lock nhanh, fail migration và retry ở cửa sổ khác; đừng chờ vô hạn.
Trước DDL:

- tìm long/idle transaction;
- rehearsal với volume và concurrent workload;
- biết lock mode của câu lệnh/phiên bản cụ thể;
- chuẩn bị roll-forward, không chỉ rollback;
- tách concurrent index khỏi transaction block.

---

## 30. Deadlock khác lock wait dài

Lock wait:

```text
A giữ row 1
B chờ row 1
A có thể commit → B tiếp tục
```

Deadlock:

```text
A giữ row 1, chờ row 2
B giữ row 2, chờ row 1
không ai tự tiến được
```

PostgreSQL phát hiện cycle và abort một transaction:

```text
SQLSTATE 40P01: deadlock_detected
```

Victim không được bảo đảm là transaction “mới hơn”, “nhỏ hơn” hay ít quan trọng
hơn. Application phải rollback và thường retry toàn transaction.

`deadlock_timeout` là thời gian chờ trước khi server chạy deadlock detection, không
phải timeout hủy mọi lock wait.

---

## 31. Phòng deadlock bằng thứ tự lock

Transfer khóa account theo thứ tự tăng dần, bất kể source/destination:

```sql
SELECT account_id, balance
FROM app.accounts
WHERE account_id IN (:source_id, :destination_id)
ORDER BY account_id
FOR UPDATE;
```

Nguyên tắc:

1. mọi code path lấy cùng object theo cùng thứ tự;
2. lấy mode mạnh nhất cần ngay từ đầu, tránh lock upgrade;
3. transaction ngắn, không chờ user/network;
4. có index để tìm/lock đúng row, không quét và khóa quá rộng;
5. retry `40P01` với backoff;
6. log deadlock detail và correlation ID.

Order phải áp dụng xuyên service/job/migration cùng chạm dữ liệu, không chỉ trong
một function.

---

## 32. Ba timeout không thay thế nhau

| Setting | Hủy khi |
|---|---|
| `lock_timeout` | một lần chờ lấy lock quá lâu |
| `statement_timeout` | toàn statement chạy quá lâu |
| `transaction_timeout` | session ở trong transaction quá lâu |
| `idle_in_transaction_session_timeout` | session idle trong transaction quá lâu |

Thiết lập theo role/workload hoặc transaction:

```sql
BEGIN;

SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '5s';
SET LOCAL idle_in_transaction_session_timeout = '30s';

-- Business statements.

COMMIT;
```

`SET LOCAL` chỉ có hiệu lực trong transaction. Lưu ý:

- `statement_timeout` gồm cả thời gian chờ lock;
- `lock_timeout` bằng/lớn hơn statement timeout thường không có tác dụng;
- timeout là safety net, không thay query/index/lock design;
- client timeout không chắc server statement đã dừng nếu client không cancel đúng;
- transaction timeout quá thấp có thể giết legitimate batch.

---

## 33. Advisory lock: mutex do application đặt nghĩa

Transaction-level advisory lock:

```sql
BEGIN;

SELECT pg_advisory_xact_lock(:tenant_id, :resource_id);

-- Critical section.

COMMIT;
```

Try-lock:

```sql
SELECT pg_try_advisory_xact_lock(:tenant_id, :resource_id);
```

Phù hợp cho:

- bảo đảm một scheduler task theo resource chỉ chạy một instance;
- serialize operation không map đẹp vào một row cố định;
- coordination nhẹ bên trong cùng PostgreSQL cluster.

Không phù hợp khi writer khác có thể bỏ qua protocol. PostgreSQL không tự gắn
advisory lock với row/business invariant.

---

## 34. Session-level và transaction-level advisory lock

| Loại | Hàm ví dụ | Release |
|---|---|---|
| session | `pg_advisory_lock` | explicit unlock hoặc session end |
| transaction | `pg_advisory_xact_lock` | transaction end |

Session-level lock không theo rollback:

```sql
SELECT pg_advisory_lock(42);
-- ROLLBACK không release lock này.
SELECT pg_advisory_unlock(42);
```

Trong connection pool, session-level lock dễ rò sang request kế tiếp nếu code
quên unlock. Ưu tiên transaction-level cho critical section ngắn.

Key design:

- namespace key để hai feature không vô tình collision;
- hash phải ổn định và hiểu collision risk;
- khóa nhiều key theo thứ tự nhất quán;
- không tạo hàng trăm nghìn lock không cần thiết vì advisory lock dùng shared lock
  memory.

---

## 35. Prepared transaction và 2PC

PostgreSQL hỗ trợ:

```sql
BEGIN;
-- Database work.
PREPARE TRANSACTION 'payment-20260731-001';
```

Sau đó coordinator quyết định:

```sql
COMMIT PREPARED 'payment-20260731-001';
-- hoặc ROLLBACK PREPARED ...
```

Prepared transaction sống qua session/crash và tiếp tục giữ lock/resources. Nếu
coordinator mất quyết định, nó có thể chặn hệ thống lâu.

Feature này cần `max_prepared_transactions` lớn hơn 0; nhiều cài đặt để 0 nên mặc
định không cho prepare. Giá trị cấu hình còn phải được tính cho primary/standby.

Kiểm tra:

```sql
SELECT
    gid,
    prepared,
    owner,
    database
FROM pg_prepared_xacts
ORDER BY prepared;
```

Chỉ dùng 2PC khi thật sự có transactional resource manager và recovery protocol.
Không dùng như cách giữ transaction qua request; đặt alert/age limit/runbook cho
mọi prepared transaction.

---

## 36. Sequence không rollback cùng transaction

```sql
BEGIN;
SELECT nextval('app.orders_order_id_seq');
ROLLBACK;
```

Giá trị sequence đã cấp không quay lại. Điều này đúng với sequence đứng sau
`serial`/identity.

Hệ quả:

- gap không biểu thị row bị xóa hay lỗi dữ liệu;
- ID không phải commit order;
- retry có thể tiêu thụ nhiều ID;
- không dùng sequence value làm gap-free invoice number;
- `currval` là session state và chỉ hợp lệ sau `nextval` trong session đó.

Sequence ưu tiên concurrency/uniqueness, không cung cấp transactional numbering.

---

## 37. Long transaction là capacity incident

Transaction mở lâu có thể:

- giữ table/row/advisory lock;
- giữ snapshot khiến dead tuple chưa reclaim được;
- làm autovacuum/bloat và XID horizon xấu đi;
- làm DDL/maintenance chờ;
- giữ connection và application resource;
- kéo dài recovery/retry blast radius.

Tìm transaction lâu:

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    xact_start,
    now() - xact_start AS xact_age,
    wait_event_type,
    wait_event,
    left(query, 200) AS query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

Đặc biệt ưu tiên `idle in transaction`: query không chạy nhưng transaction vẫn
mở.

---

## 38. `pg_stat_activity` cho biết ai đang chờ

```sql
SELECT
    pid,
    usename,
    application_name,
    state,
    wait_event_type,
    wait_event,
    query_start,
    xact_start,
    left(query, 300) AS query
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY xact_start NULLS LAST, query_start;
```

Diễn giải:

- `wait_event_type = 'Lock'`: backend đang chờ lock manager;
- `wait_event = 'transactionid'`: thường chờ transaction giữ row version/lock;
- `state = 'idle in transaction'`: client không gửi query nhưng transaction mở;
- query hiển thị là current hoặc last query tùy state, không luôn là câu đã lấy
  lock ban đầu;
- một backend đang `active` vẫn có thể chờ.

Luôn kết hợp application name, trace/request ID trong comment hoặc log và
transaction age.

---

## 39. Dùng `pg_blocking_pids()` thay self-join lock ngây thơ

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.application_name AS blocked_app,
    blocked.wait_event_type,
    blocked.wait_event,
    now() - blocked.query_start AS blocked_for,
    blocker_pid,
    blocker.application_name AS blocker_app,
    blocker.state AS blocker_state,
    now() - blocker.xact_start AS blocker_xact_age,
    left(blocked.query, 200) AS blocked_query,
    left(blocker.query, 200) AS blocker_query
FROM pg_stat_activity AS blocked
CROSS JOIN LATERAL
    unnest(pg_blocking_pids(blocked.pid)) AS b(blocker_pid)
LEFT JOIN pg_stat_activity AS blocker
    ON blocker.pid = b.blocker_pid
ORDER BY blocked_for DESC;
```

`pg_locks` self-join rất dễ sai vì conflict mode, lock group và parallel query.
Tài liệu PostgreSQL khuyến nghị `pg_blocking_pids()` để xác định blocker trực tiếp.

Root blocker có thể không chờ ai nhưng chặn cả cây. Đừng kill mọi waiter; chúng
thường là nạn nhân.

---

## 40. Xem lock chi tiết bằng `pg_locks`

```sql
SELECT
    l.pid,
    a.application_name,
    l.locktype,
    l.mode,
    l.granted,
    l.relation::regclass AS relation,
    l.page,
    l.tuple,
    l.transactionid,
    l.virtualxid,
    l.classid,
    l.objid,
    l.objsubid
FROM pg_locks AS l
LEFT JOIN pg_stat_activity AS a
    ON a.pid = l.pid
WHERE l.database IS NULL
   OR l.database = (
       SELECT oid
       FROM pg_database
       WHERE datname = current_database()
   )
ORDER BY l.granted, l.pid, l.locktype, l.mode;
```

Không phải mọi row lock hiện thành một tuple-lock row dễ đọc. Backend thường chờ
transaction ID của transaction đã sửa/khóa tuple. Dùng wait event,
`pg_blocking_pids()` và query context cùng nhau.

`pg_locks` là ảnh tức thời; incident nhanh cần sampling/log/observability từ trước.

---

## 41. Cancel hay terminate blocker?

Ưu tiên:

```sql
SELECT pg_cancel_backend(:pid);
```

Cancel statement hiện tại. Nếu session đang idle in transaction, không có
statement để cancel; transaction/lock vẫn còn.

Mạnh hơn:

```sql
SELECT pg_terminate_backend(:pid);
```

Terminate session, rollback transaction và release lock sau cleanup. Trước khi
terminate:

- xác minh PID, user, application, transaction age và blocker graph;
- hiểu rollback có thể mất thời gian;
- kiểm tra đây có phải migration/backup/failover-critical session;
- chuẩn bị application reconnect/retry;
- lưu evidence trước khi state biến mất.

Không tự động kill theo query duration đơn thuần. Root cause thường là transaction
boundary, missing index, lock order hoặc DDL workflow.

---

## 42. Isolation không thay constraint

Serializable ngăn serialization anomaly giữa transaction tham gia, nhưng vẫn cần:

- `UNIQUE` cho duplicate;
- `FOREIGN KEY` cho reference;
- `CHECK` cho row invariant;
- `EXCLUDE` cho overlap;
- `NOT NULL` cho required value.

Ngược lại, constraint không bảo vệ mọi cross-row business decision. Chọn lớp phù
hợp:

```text
declarative invariant → constraint trước
single-row transition → atomic UPDATE / row lock
cross-row decision     → Serializable hoặc coordination lock
external side effect   → outbox + idempotency
```

Thiết kế tốt giảm số explicit lock và retry cần dùng.

---

## 43. Failure modes thường gặp

### “Bọc `@Transactional` là hết race”

Transaction chỉ tạo boundary. Isolation mặc định vẫn Read Committed và plain read
không khóa row.

### “Repeatable Read là Serializable”

PostgreSQL Repeatable Read ngăn phantom nhưng snapshot isolation vẫn cho write
skew trên các row khác nhau.

### “`SELECT FOR UPDATE` chặn mọi người đọc”

Plain MVCC reader vẫn đọc version visible; lock chủ yếu chặn writer/locker xung
đột.

### “Retry câu COMMIT là đủ”

Transaction đã abort; phải rollback và chạy lại toàn bộ read/decision/write.

### “`SKIP LOCKED` giúp query không bao giờ chậm”

Nó bỏ qua dữ liệu đang lock và trả view không nhất quán. Chỉ dùng khi semantics
queue chấp nhận.

### “Deadlock là PostgreSQL bug”

Database phát hiện cycle do các transaction lấy lock khác thứ tự. Sửa lock order
và transaction length, đồng thời retry victim.

### “DDL metadata-only không gây downtime”

Thời gian thực thi ngắn không loại bỏ thời gian chờ `ACCESS EXCLUSIVE` và lock
queue phía sau.

### “Advisory lock bảo vệ table”

Chỉ client cùng dùng đúng key/protocol mới tôn trọng nó.

---

## 44. Checklist production

### Boundary

- [ ] Transaction ôm đúng một business unit?
- [ ] Không chờ user/network/file processing trong transaction?
- [ ] Mọi error path rollback trước khi trả connection về pool?
- [ ] External side effect có outbox/idempotency key?
- [ ] Savepoint không che lỗi invariant bắt buộc?

### Concurrency

- [ ] Atomic `UPDATE` được ưu tiên thay read–compute–write?
- [ ] Row cần quyết định có lock hoặc optimistic version?
- [ ] Cross-row invariant có Serializable/coordination design?
- [ ] Mọi writer của invariant dùng cùng protocol?
- [ ] Unique/FK/EXCLUDE vẫn bảo vệ declarative invariant?

### Lock

- [ ] Lock nhiều object theo cùng thứ tự?
- [ ] Query có index để khóa đúng tập row?
- [ ] `NOWAIT`/`SKIP LOCKED` có semantics và fallback rõ?
- [ ] Advisory key được namespace và ưu tiên transaction-level?
- [ ] DDL có `lock_timeout` và rehearsal?

### Retry

- [ ] Dùng SQLSTATE, không parse message?
- [ ] `40001`/`40P01` retry toàn transaction?
- [ ] Có exponential backoff + jitter + max attempts?
- [ ] Side effect trong retry loop là idempotent?
- [ ] Metric có attempt, exhausted retry và total latency?

### Vận hành

- [ ] Alert long/idle transaction?
- [ ] Có blocker query dùng `pg_blocking_pids()`?
- [ ] `lock_timeout`, `statement_timeout`, transaction/idle timeout theo workload?
- [ ] Prepared transaction có owner, age alert và recovery runbook?
- [ ] Operator lưu evidence trước cancel/terminate?

---

## 45. Câu hỏi phỏng vấn

1. Autocommit trong PostgreSQL có phải không dùng transaction không?
2. Vì sao một statement lỗi làm cả transaction cần rollback?
3. Savepoint khác nested transaction thế nào?
4. MVCC giúp reader/writer concurrency ra sao?
5. Snapshot khác “latest data” thế nào?
6. PostgreSQL triển khai bốn isolation level thành ba mức thế nào?
7. Snapshot của Read Committed và Repeatable Read khác nhau ở đâu?
8. Read Committed xử lý row bị concurrent update và recheck `WHERE` ra sao?
9. Lost update xuất hiện trong read–compute–write như thế nào?
10. Bốn row lock mode khác nhau ở điểm nào?
11. `NOWAIT` và `SKIP LOCKED` phù hợp trường hợp nào?
12. Vì sao job queue cần lease/idempotency dù dùng `SKIP LOCKED`?
13. Write skew là gì và vì sao Repeatable Read vẫn cho phép?
14. Serializable Snapshot Isolation phát hiện anomaly ra sao?
15. `SIReadLock` có block writer không?
16. Khi nào dùng `SERIALIZABLE READ ONLY DEFERRABLE`?
17. Vì sao phải retry toàn transaction khi nhận `40001`?
18. `23505` có nên luôn retry không?
19. Optimistic version column bảo vệ gì và không bảo vệ gì?
20. Table lock mode có chữ `ROW` có phải row lock không?
21. Vì sao DDL nhanh vẫn gây lock queue?
22. Deadlock khác lock wait thế nào?
23. Thứ tự lấy lock giúp tránh deadlock ra sao?
24. `lock_timeout`, `statement_timeout` và transaction timeout khác nhau gì?
25. Session-level advisory lock nguy hiểm thế nào với connection pool?
26. Prepared transaction giữ rủi ro vận hành gì?
27. Vì sao sequence có gap sau rollback?
28. Cách tìm root blocker bằng `pg_stat_activity` và `pg_blocking_pids()`?

---

## 46. Nguồn và chủ đề tiếp theo

Nguồn PostgreSQL chính thức:

- [Concurrency Control introduction](https://www.postgresql.org/docs/18/mvcc-intro.html)
- [Transaction Isolation](https://www.postgresql.org/docs/18/transaction-iso.html)
- [Explicit Locking](https://www.postgresql.org/docs/18/explicit-locking.html)
- [Application-level consistency](https://www.postgresql.org/docs/18/applevel-consistency.html)
- [Serialization Failure Handling](https://www.postgresql.org/docs/18/mvcc-serialization-failure-handling.html)
- [MVCC caveats](https://www.postgresql.org/docs/18/mvcc-caveats.html)
- [BEGIN](https://www.postgresql.org/docs/18/sql-begin.html)
- [SET TRANSACTION](https://www.postgresql.org/docs/18/sql-set-transaction.html)
- [SAVEPOINT](https://www.postgresql.org/docs/18/sql-savepoint.html)
- [SELECT locking clause](https://www.postgresql.org/docs/18/sql-select.html)
- [LOCK TABLE](https://www.postgresql.org/docs/18/sql-lock.html)
- [`pg_locks`](https://www.postgresql.org/docs/18/view-pg-locks.html)
- [Monitoring locks](https://www.postgresql.org/docs/18/monitoring-locks.html)
- [Client timeout settings](https://www.postgresql.org/docs/18/runtime-config-client.html)
- [Lock management settings](https://www.postgresql.org/docs/18/runtime-config-locks.html)
- [Advisory lock functions](https://www.postgresql.org/docs/18/functions-admin.html)

Học tiếp:

1. [Indexing & Query Planner](indexing_planner.md).
2. [Advanced SQL](advanced_sql.md).
3. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md).

---

*Cập nhật lần cuối: 2026-07-31.*
