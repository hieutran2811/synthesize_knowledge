# MongoDB Transactions – correctness trước, transaction sau

> Mục tiêu phiên bản: **MongoDB 8.2**. Ví dụ chính dùng Java Sync Driver và `mongosh`; hãy kiểm tra compatibility matrix của driver/Spring Data trong dự án.
>
> Nên đọc trước: [CRUD & Aggregation Pipeline](crud_aggregation.md) và [Indexing](indexing.md). Tra cứu nhanh: [MongoDB Glossary](../glossary.md).

---

## 1. Transaction bảo vệ điều gì?

MongoDB luôn bảo đảm một write trên **một document** là atomic, kể cả khi update nhiều field hoặc phần tử embedded trong document đó.

```javascript
db.orders.updateOne(
  {
    _id: orderId,
    status: "PENDING"
  },
  {
    $set: {
      status: "PAID",
      paidAt: new Date()
    },
    $push: {
      history: {
        status: "PAID",
        at: new Date()
      }
    },
    $inc: {
      version: 1
    }
  }
);
```

Status, history và version cùng thay đổi hoặc cùng không thay đổi. Không cần multi-document transaction.

Transaction cần thiết khi một invariant phải thay đổi atomically trên nhiều document, collection, database hoặc shard:

```text
transfer:
  account A.balance -= amount
  account B.balance += amount
  ledger insert transfer

Invariant:
  không được chỉ debit mà chưa credit
  không được credit hai lần
  số dư nguồn không âm
```

MongoDB hỗ trợ multi-document transaction trên:

- replica set từ MongoDB 4.0;
- sharded cluster từ MongoDB 4.2.

Standalone `mongod` không hỗ trợ multi-document transaction. Local development muốn test transaction phải chạy replica set, kể cả replica set một node.

---

## 2. Quyết định có cần transaction không

Hỏi theo thứ tự:

```text
Invariant nằm trong một document?
  ├─ Có → atomic update / conditional update / unique index
  └─ Không
      │
      ├─ Chỉ cần eventual consistency?
      │    └─ workflow/outbox/saga có thể phù hợp
      │
      └─ Phải all-or-nothing ngay tại MongoDB?
           └─ multi-document transaction
```

| Tình huống | Công cụ thường phù hợp |
|---|---|
| Trừ tồn kho nếu còn đủ | Conditional `updateOne()` |
| Đổi status + thêm history cùng order | Embed và single-document update |
| Không trùng business key | Unique index |
| Chống lost update | Version trong filter |
| Debit một account, credit account khác | Transaction |
| Ghi aggregate và outbox document riêng | Transaction |
| Nhiều microservice/database khác nhau | Saga/workflow, không kéo dài DB transaction |

Transaction không sửa được data model kém. Nếu dữ liệu luôn được đọc/ghi cùng và bounded, embedding thường đơn giản, nhanh và bền hơn.

---

## 3. Transaction lifecycle và session

Transaction luôn gắn với một logical session:

```text
startSession
  → startTransaction
      → operation 1 (cùng session)
      → operation 2 (cùng session)
      → operation 3 (cùng session)
  → commit hoặc abort
→ endSession
```

Các nguyên tắc:

- mỗi operation muốn nằm trong transaction phải nhận đúng session;
- một session chỉ có tối đa một transaction đang mở;
- các operation trong cùng transaction phải chạy tuần tự;
- không dùng cùng session đồng thời từ nhiều thread;
- session kết thúc khi transaction còn mở thì transaction bị abort.

`startTransaction()` ở client chưa nhất thiết gửi command ngay. Transaction thực sự bắt đầu phía server khi operation đầu tiên dùng session được gửi.

---

## 4. Java Driver: dùng callback API làm đường chuẩn

Ví dụ chuyển tiền:

```java
import com.mongodb.ClientSessionOptions;
import com.mongodb.ReadConcern;
import com.mongodb.ReadPreference;
import com.mongodb.TransactionOptions;
import com.mongodb.WriteConcern;
import com.mongodb.client.ClientSession;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.result.UpdateResult;
import org.bson.Document;
import org.bson.types.Decimal128;
import org.bson.types.ObjectId;

import java.time.Instant;
import java.util.Date;
import java.util.concurrent.TimeUnit;

import static com.mongodb.client.model.Filters.and;
import static com.mongodb.client.model.Filters.eq;
import static com.mongodb.client.model.Filters.gte;
import static com.mongodb.client.model.Updates.inc;

public final class TransferService {

    private final MongoClient mongoClient;
    private final MongoCollection<Document> accounts;
    private final MongoCollection<Document> transfers;

    public TransferService(
            MongoClient mongoClient,
            MongoCollection<Document> accounts,
            MongoCollection<Document> transfers
    ) {
        this.mongoClient = mongoClient;
        this.accounts = accounts;
        this.transfers = transfers;
    }

    public void transfer(
            ObjectId transferId,
            ObjectId fromAccountId,
            ObjectId toAccountId,
            Decimal128 amount
    ) {
        Date requestedAt = Date.from(Instant.now());
        Decimal128 negativeAmount = new Decimal128(
                amount.bigDecimalValue().negate()
        );

        TransactionOptions options = TransactionOptions.builder()
                .readPreference(ReadPreference.primary())
                .readConcern(ReadConcern.SNAPSHOT)
                .writeConcern(WriteConcern.MAJORITY)
                .maxCommitTime(5, TimeUnit.SECONDS)
                .build();

        ClientSessionOptions sessionOptions =
                ClientSessionOptions.builder()
                        .causallyConsistent(true)
                        .build();

        try (ClientSession session =
                     mongoClient.startSession(sessionOptions)) {

            session.withTransaction(() -> {
                UpdateResult debit = accounts.updateOne(
                        session,
                        and(
                                eq("_id", fromAccountId),
                                gte("balance", amount)
                        ),
                        inc("balance", negativeAmount)
                );

                if (debit.getMatchedCount() != 1) {
                    throw new IllegalStateException(
                            "Account nguồn không tồn tại hoặc không đủ số dư"
                    );
                }

                UpdateResult credit = accounts.updateOne(
                        session,
                        eq("_id", toAccountId),
                        inc("balance", amount)
                );

                if (credit.getMatchedCount() != 1) {
                    throw new IllegalStateException(
                            "Account đích không tồn tại"
                    );
                }

                transfers.insertOne(
                        session,
                        new Document("_id", transferId)
                                .append("fromAccountId", fromAccountId)
                                .append("toAccountId", toAccountId)
                                .append("amount", amount)
                                .append("requestedAt", requestedAt)
                                .append("status", "COMMITTED")
                );

                return null;
            }, options);
        }
    }
}
```

Điểm quan trọng hơn syntax:

1. Conditional debit kiểm tra số dư và trừ tiền trong cùng write.
2. `matchedCount` được kiểm tra; không giả định account luôn tồn tại.
3. Mọi operation truyền cùng `session`.
4. `transferId` và `requestedAt` được tạo **trước** callback.
5. Ledger dùng stable `_id`, giúp nhận diện request nghiệp vụ.
6. Callback không gọi payment API, gửi email hay publish trực tiếp ra hệ thống ngoài.

### Vì sao dùng `withTransaction()`?

Callback API của driver:

- start transaction;
- gọi callback;
- commit hoặc abort;
- retry toàn transaction khi có `TransientTransactionError`;
- retry riêng commit khi có `UnknownTransactionCommitResult`.

Core API (`startTransaction`, `commitTransaction`, `abortTransaction`) cho nhiều quyền kiểm soát hơn nhưng application phải tự triển khai state machine retry đúng.

### Callback có thể chạy nhiều lần

Vì callback có thể được chạy lại:

```java
session.withTransaction(() -> {
    paymentGateway.charge(card, amount); // Sai: có thể charge nhiều lần.
    sendEmail();                         // Sai: transaction abort không thu hồi email.
    return null;
});
```

Không đặt side effect không rollback được trong callback. Nếu cần phát event sau commit, ghi **outbox document** trong cùng transaction rồi để worker riêng publish idempotently.

---

## 5. Idempotency ngoài transaction retry

Driver xử lý retry do lỗi tạm thời trong một lời gọi. Nhưng client HTTP có thể timeout rồi gửi lại toàn bộ request sau khi transaction đã commit.

```text
Request 1
  → transaction commit thành công
  → response bị mất

Request 2 cùng idempotency key
  → phải trả lại kết quả cũ
  → không chuyển tiền lần hai
```

Tạo unique identity cho business operation:

```javascript
db.transfers.createIndex(
  { idempotencyKey: 1 },
  { unique: true }
);
```

Luồng service:

1. Nhận `idempotencyKey`.
2. Nếu transfer đã tồn tại, xác minh payload tương thích rồi trả kết quả cũ.
3. Nếu chưa có, dùng key ổn định làm `_id` hoặc unique key trong transaction.
4. Nếu gặp duplicate key do request cạnh tranh, đọc record hiện có và quyết định replay/conflict.

Transaction bảo vệ atomicity trong database; idempotency bảo vệ retry ở biên hệ thống. Cần cả hai khi outcome có thể không đến được client.

---

## 6. Hai loại lỗi retry phải phân biệt

### 6.1 `TransientTransactionError`

Operation trong transaction gặp lỗi tạm thời như write conflict/election:

```text
abort attempt hiện tại
→ tạo transaction attempt mới
→ chạy lại toàn bộ callback
```

Không chỉ retry operation bị lỗi vì snapshot và các write trước đó thuộc cùng attempt.

### 6.2 `UnknownTransactionCommitResult`

Client không biết commit đã thành công hay chưa, thường do lỗi mạng:

```text
không chạy lại business operations ngay
→ retry commitTransaction
→ server trả outcome xác định hoặc hết retry budget
```

Chạy lại toàn bộ callback ngay có thể tạo business attempt thứ hai.

| Error label/tình huống | Hành động |
|---|---|
| `TransientTransactionError` trước commit hoàn tất | Retry toàn transaction |
| `UnknownTransactionCommitResult` lúc commit | Retry commit |
| Business validation fail | Abort, không retry tự động |
| Duplicate key/invariant violation | Phân loại conflict/idempotent replay |
| `TransactionTooLargeForCache` | Giảm transaction; server không tự retry từ MongoDB 6.2 |

Từ MongoDB 8.1, upsert trong multi-document transaction gặp duplicate key không tự retry. Application vẫn phải phân loại duplicate key theo business semantics.

### Retry cần budget

Callback API xử lý protocol retry, nhưng service vẫn cần:

- request deadline;
- driver/server timeout phù hợp;
- bounded outer retry;
- exponential backoff + jitter nếu tự orchestration;
- metrics theo attempt và error label;
- reconciliation khi kết quả cuối vẫn chưa xác định.

Không dùng vòng `while(true)` quanh transaction.

---

## 7. Atomicity, isolation và visibility

### Trước commit

- Transaction đọc được write của chính nó.
- Client bên ngoài không thấy write chưa commit.
- Nếu một operation fail và transaction abort, các thay đổi bị loại bỏ.

### Sau commit

Toàn bộ transaction commit hoặc không commit. Tuy nhiên trên sharded cluster, **outside read** với concern yếu không nhất thiết chờ mọi shard hiển thị kết quả cùng lúc:

- outside read với `snapshot`, `linearizable` hoặc causal dependency phù hợp sẽ chờ;
- read concern khác có thể thấy version trước transaction ở một số shard trong lúc commit đang hoàn tất.

Vì vậy “transaction atomic” không đồng nghĩa mọi kiểu outside read có cùng global visibility behavior.

### Snapshot có thể stale

Transaction đọc từ snapshot được chọn cho attempt. Một document có thể đã bị client ngoài transaction xóa/sửa sau snapshot.

Khi cần lock một document hiện tại cho update, pattern `findOneAndUpdate()` với một thay đổi vô hại/có ý nghĩa trong transaction có thể lấy write lock và trả bản mới nhất phù hợp. Nhưng đây không phải lý do để khóa hàng loạt document; transaction dài làm conflict và cache pressure tăng.

---

## 8. Read concern, write concern và read preference

Các concern được đặt ở **transaction level**. Không đặt write concern/read concern riêng trên từng operation trong transaction.

### 8.1 Read preference

Transaction có read operation phải dùng:

```text
primary
```

Mọi operation trong transaction phải route tới cùng member phù hợp. Không dùng transaction để “đọc từ secondary rồi ghi primary”.

### 8.2 Read concern trong transaction

Transaction hỗ trợ:

| Level | Ý nghĩa chính |
|---|---|
| `local` | Đọc snapshot dữ liệu local; có thể gồm dữ liệu chưa majority committed |
| `majority` | Đọc majority-committed data, nhưng trên sharded cluster không đồng bộ snapshot giữa shard |
| `snapshot` | Snapshot đồng bộ giữa shard; phù hợp khi cần snapshot isolation |

`available` và `linearizable` không dùng làm transaction read concern.

Điều kiện hay bị bỏ sót:

- `majority`/`snapshot` chỉ cung cấp guarantee majority-committed đầy đủ khi transaction commit với write concern `majority`.
- Nếu không đặt transaction-level read concern, nó kế thừa session/client concern; đừng giả định transaction luôn mặc định là `snapshot`.

Ví dụ:

```java
TransactionOptions options = TransactionOptions.builder()
        .readConcern(ReadConcern.SNAPSHOT)
        .writeConcern(WriteConcern.MAJORITY)
        .readPreference(ReadPreference.primary())
        .build();
```

### 8.3 Write concern

Write concern điều khiển mức acknowledgment khi commit:

| Cấu hình | Ý nghĩa |
|---|---|
| `w: 1` | Primary xác nhận; commit có thể bị rollback khi failover |
| `w: "majority"` | Đợi majority data-bearing members xác nhận |
| `j: true` | Yêu cầu journal theo semantics cấu hình storage/deployment |
| `wtimeout` | Giới hạn thời gian chờ acknowledgment |

MongoDB 8.2 có global default write concern `majority`, nhưng deployment có thể cấu hình default riêng. Hãy kiểm tra effective configuration thay vì ghi cứng giả định trong code/docs.

`wtimeout` không tự rollback write đã được primary áp dụng. Nó chỉ nói client không nhận đủ acknowledgment trong thời gian chờ; kết quả phải được phân loại/reconcile.

Không gọi `w: "majority"` là “mạnh nhất” trong mọi topology. Custom write concern/tag set có thể biểu diễn durability theo region/rack khác.

---

## 9. Causal consistency không phải transaction

Causally consistent session bảo đảm thứ tự quan hệ nhân quả cho các operation tuần tự, ví dụ:

```text
write configuration
→ read configuration phải thấy write đó
```

Các guarantee gồm:

- read-your-writes;
- monotonic reads;
- monotonic writes;
- writes-follow-reads.

Để guarantee causal consistency, dùng:

- causally consistent session;
- `majority` read concern;
- `majority` write concern;
- operation tuần tự trong một session/thread.

```java
ClientSessionOptions options = ClientSessionOptions.builder()
        .causallyConsistent(true)
        .build();

try (ClientSession session = mongoClient.startSession(options)) {
    settings.updateOne(
            session,
            eq("_id", "feature-x"),
            new Document("$set", new Document("enabled", true))
    );

    Document setting = settings.find(
            session,
            eq("_id", "feature-x")
    ).first();
}
```

| Causal session | Transaction |
|---|---|
| Giữ thứ tự phụ thuộc giữa operations | All-or-nothing cho nhóm operations |
| Không rollback nhiều write như một đơn vị | Abort loại toàn bộ write trong attempt |
| Ít overhead hơn | Giữ snapshot/locks/state |
| Hợp read-your-writes | Hợp invariant đa document |

Nếu chỉ cần read-your-writes, transaction thường là công cụ quá nặng.

---

## 10. Tránh transaction bằng atomic data model

### 10.1 Embed dữ liệu cùng lifecycle

```javascript
{
  _id: "ORD-1001",
  status: "PAID",
  payment: {
    transactionId: "PAY-9001",
    amount: Decimal128("119.30")
  },
  history: [
    {
      status: "PAID",
      at: ISODate("2026-07-29T09:00:00Z")
    }
  ]
}
```

Một `updateOne()` thay status, payment và history atomically.

### 10.2 Conditional update

```javascript
const result = db.products.updateOne(
  {
    _id: productId,
    stock: { $gte: quantity }
  },
  {
    $inc: {
      stock: -quantity
    }
  }
);

if (result.matchedCount !== 1) {
  throw new Error("Không đủ tồn kho");
}
```

Không cần “đọc stock → kiểm tra → ghi stock” trong transaction.

### 10.3 Optimistic concurrency

```javascript
const result = db.orders.updateOne(
  {
    _id: orderId,
    version: expectedVersion,
    status: "PENDING"
  },
  {
    $set: {
      status: "PAID"
    },
    $inc: {
      version: 1
    }
  }
);
```

### 10.4 Unique index + upsert

Unique index bảo vệ business key trên mọi writer và thường loại nhu cầu “check rồi insert” trong transaction.

### 10.5 Saga/workflow

Khi nghiệp vụ đi qua payment service, inventory service và shipping service:

```text
Reserve inventory
→ Authorize payment
→ Create shipment
→ nếu fail: release inventory / void authorization
```

Không giữ MongoDB transaction mở trong lúc gọi network service. Dùng durable workflow, idempotent step và compensation.

---

## 11. Transactional outbox

Nếu thay đổi business state và phát event phải cùng tồn tại:

```text
Transaction:
  update order
  insert outbox event
Commit

Publisher:
  claim unpublished event
  publish với eventId ổn định
  mark published
```

Trong transaction:

```javascript
const session = db.getMongo().startSession();
const sessionDb = session.getDatabase(db.getName());

try {
  session.withTransaction(
    () => {
      sessionDb.orders.updateOne(
        {
          _id: orderId,
          status: "PENDING"
        },
        {
          $set: {
            status: "PAID"
          }
        }
      );

      sessionDb.outbox.insertOne({
        _id: eventId,
        aggregateId: orderId,
        type: "OrderPaid",
        payload: {
          orderId
        },
        createdAt: new Date(),
        publishedAt: null
      });
    },
    {
      readConcern: { level: "snapshot" },
      writeConcern: { w: "majority" }
    }
  );
} finally {
  session.endSession();
}
```

`mongosh` `withTransaction()` có retry commit/toàn transaction tương tự callback API; callback vì thế vẫn phải tránh external side effect và dùng ID ổn định.

Outbox không tạo exactly-once end-to-end:

- publisher có thể publish xong rồi crash trước khi mark;
- consumer phải deduplicate/idempotent theo `eventId`;
- cần retention, retry, dead-letter và observability.

Nếu outbox có thể embed bounded trong aggregate và cùng document, single-document atomicity còn đơn giản hơn.

---

## 12. Giới hạn và chi phí production

### 12.1 Lifetime

Mặc định transaction phải chạy dưới một phút; `transactionLifetimeLimitSeconds` điều khiển server limit. Đây là safety limit, không phải latency target.

Transaction application nên thường ở mức millisecond/giây ngắn:

- không chờ user input;
- không gọi HTTP;
- không sleep;
- không scan/query không index;
- không xử lý CPU nặng trong callback.

### 12.2 Cache, snapshot và conflict

Transaction dài giữ snapshot cũ và tăng history/cache pressure. MongoDB có thể abort với:

- write conflict;
- snapshot/resource pressure;
- `TransactionTooLargeForCache`;
- lock timeout;
- lifetime expiry.

Không có magic number “mọi transaction phải dưới 1.000 document”. Bound đúng phụ thuộc kích thước document, số index, cache, contention, shard và SLA. Chia batch dựa trên benchmark/telemetry.

### 12.3 Oplog và kích thước

Transaction hiện tạo nhiều oplog entry nếu cần, nên không còn total transaction limit 16 MiB do một oplog entry duy nhất. Nhưng:

- mỗi BSON document/oplog entry vẫn chịu limit 16 MiB;
- transaction lớn vẫn tốn cache, oplog, replication và recovery work;
- “không có total 16 MiB limit” không có nghĩa transaction vô hạn.

### 12.4 Sharded transaction

Transaction chạm nhiều shard thêm coordination và commit cost. Nó còn có thể xung đột với:

- chunk migration;
- metadata/DDL operation;
- shard participant unavailable;
- network latency giữa vùng.

Thiết kế shard key để hot transaction thường route ít shard nhất có thể.

---

## 13. Operation hỗ trợ và restriction

MongoDB hỗ trợ CRUD trên nhiều collection/database/shard trong transaction, nhưng không phải command nào cũng hợp lệ.

Không hỗ trợ hoặc bị hạn chế:

- parallel operation trong cùng transaction;
- write vào capped collection;
- read/write collection trong `config`, `admin`, `local`;
- write vào `system.*`;
- `explain`;
- `listCollections`, `listIndexes`;
- `$out`, `$merge`;
- cursor/getMore đi qua biên transaction sai cách;
- tạo collection mới trong cross-shard write transaction.

DDL không bị cấm tuyệt đối:

- có thể tạo collection/index trong transaction nếu không phải cross-shard write transaction;
- explicit create/index yêu cầu transaction read concern `local`;
- index chỉ tạo trên collection không tồn tại hoặc collection mới, rỗng được tạo trong transaction.

Thực tế production nên pre-create collection/index bằng migration trước khi traffic sử dụng. Đừng biến DDL transaction thành đường chạy bình thường của request.

### Không chạy song song

```java
// Sai về transaction semantics của Java driver:
CompletableFuture.allOf(
    debitAsync(session),
    creditAsync(session)
).join();
```

Chạy operation tuần tự. Một session không phải concurrent work container.

---

## 14. Spring Data MongoDB

### 14.1 Khai báo transaction manager

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.mongodb.MongoDatabaseFactory;
import org.springframework.data.mongodb.MongoTransactionManager;

@Configuration
class MongoTransactionConfiguration {

    @Bean
    MongoTransactionManager mongoTransactionManager(
            MongoDatabaseFactory databaseFactory
    ) {
        return new MongoTransactionManager(databaseFactory);
    }
}
```

### 14.2 Service boundary

```java
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class OrderPaymentService {

    private final OrderRepository orders;
    private final OutboxRepository outbox;

    OrderPaymentService(
            OrderRepository orders,
            OutboxRepository outbox
    ) {
        this.orders = orders;
        this.outbox = outbox;
    }

    @Transactional
    public void markPaid(
            String orderId,
            String eventId
    ) {
        int changed = orders.markPaidIfPending(orderId);

        if (changed != 1) {
            throw new IllegalStateException(
                    "Order không còn PENDING"
            );
        }

        outbox.insert(
                new OutboxEvent(
                        eventId,
                        orderId,
                        "OrderPaid"
                )
        );
    }
}
```

Lưu ý:

- `MongoTransactionManager` bind `ClientSession` vào thread; `MongoTemplate`/repository tham gia qua session đó.
- `@Transactional` phụ thuộc Spring proxy; self-invocation/private method không tạo boundary mới theo cách nhiều người kỳ vọng.
- Không catch exception rồi nuốt; muốn rollback phải truyền failure ra transaction interceptor hoặc mark rollback.
- Không gọi external service trong method transactional.
- Declarative Spring transaction quản lý begin/commit/abort, nhưng không nên mặc định rằng nó giống hệt Java Driver `withTransaction()` về retry toàn callback.
- Reactive stack cần `ReactiveMongoTransactionManager` và Reactor context; không dùng thread-local assumption.

Nếu retry toàn Spring service method, method phải idempotent và retry phải nằm **bên ngoài** transaction attempt.

---

## 15. Monitoring và observability

Server metrics:

```javascript
db.serverStatus().transactions;
```

Theo dõi các nhóm:

- current active/inactive/open transaction;
- total started/committed/aborted;
- abort causes;
- commit types trên sharded cluster;
- transaction duration;
- WiredTiger cache pressure;
- write conflict;
- replication lag;
- participant shard count.

Active operations:

```javascript
db.getSiblingDB("admin").aggregate([
  {
    $currentOp: {
      allUsers: true,
      idleConnections: false
    }
  },
  {
    $match: {
      transaction: {
        $exists: true
      }
    }
  },
  {
    $project: {
      opid: 1,
      secs_running: 1,
      ns: 1,
      client: 1,
      transaction: 1,
      waitingForLock: 1
    }
  }
]);
```

Application telemetry nên có:

```text
transaction.name
transaction.attempt
transaction.duration
transaction.outcome
mongo.error.code
mongo.error.labels
idempotency_key_hash
participant_shard_count (nếu lấy được)
```

Không log raw account/payment payload hoặc session token.

### Alert theo baseline, không theo số truyền miệng

Abort rate 10% không phải universal threshold. Tách:

- business abort mong đợi;
- write conflict;
- transient infrastructure error;
- lifetime/timeout;
- cache/size;
- duplicate key;
- application bug.

Alert theo SLO và baseline của từng transaction type.

---

## 16. Anti-pattern thường gặp

| Anti-pattern | Vấn đề | Hướng sửa |
|---|---|---|
| Transaction cho mọi write | Overhead không cần thiết | Tận dụng single-document atomicity |
| Đọc số dư rồi mới trừ | Race giữa read và update | Conditional update + kiểm tra result |
| Tự retry operation bị lỗi | Phá snapshot/atomic attempt | Retry toàn transaction theo error label |
| Gặp unknown commit rồi chạy lại callback | Có thể thực hiện business attempt lần hai | Retry commit, dùng idempotency key |
| Gọi HTTP/email trong callback | Callback có thể rerun, DB abort không rollback external effect | Outbox/after-commit workflow |
| Tạo ID/time ngẫu nhiên trong callback | Mỗi retry sinh business identity khác | Tạo stable values trước callback |
| Giả định transaction luôn snapshot | Default có thể kế thừa `local` | Đặt options có chủ đích |
| Set concern trên từng operation | Bị bỏ qua/không đúng API contract | Set ở transaction level |
| Chạy operation song song cùng session | Driver không hỗ trợ | Chạy tuần tự |
| Giữ transaction khi chờ user/network | Lifetime, locks, cache, conflict tăng | Thu thập input trước, transaction thật ngắn |
| Cố tăng lifetime để chữa query chậm | Che index/query problem | Tối ưu query/index, giảm scope |
| Dùng DB transaction qua microservice | Không bao phủ external systems | Saga/workflow + compensation |
| Hard-code “<1000 docs là an toàn” | Không xét size/index/cache/contention | Benchmark và bound theo workload |

---

## 17. Checklist review transaction

### Correctness

- [ ] Invariant thật sự vượt một document?
- [ ] Có thể embed hoặc conditional update không?
- [ ] Unique index/optimistic version đã bảo vệ race chưa?
- [ ] Mỗi write result được kiểm tra?
- [ ] Idempotency key có unique constraint và payload validation?

### Retry

- [ ] Dùng callback API hay core API có state machine đầy đủ?
- [ ] Phân biệt retry transaction và retry commit?
- [ ] Callback không có external side effect?
- [ ] Stable ID/time được tạo ngoài callback?
- [ ] Retry có deadline, backoff và reconciliation?

### Options

- [ ] Read preference là primary?
- [ ] Read concern phù hợp `local`/`majority`/`snapshot`?
- [ ] Commit dùng write concern phù hợp durability?
- [ ] Không set concern trên individual operation?
- [ ] Timeout phía client/server khớp request budget?

### Production

- [ ] Query trong transaction có index và bound?
- [ ] Transaction chạy tuần tự, ngắn và không gọi network?
- [ ] Đã test write conflict/failover/unknown commit?
- [ ] Đã test trên topology thật, không phải standalone?
- [ ] Theo dõi duration, abort cause, cache và participant shard?
- [ ] Collection/index được migration tạo trước?

---

## 18. Tóm tắt

- Single-document write đã atomic; chỉ dùng transaction khi invariant thật sự vượt document.
- Transaction luôn thuộc session và các operation phải chạy tuần tự với cùng session.
- Ưu tiên Java Driver `withTransaction()` để có retry protocol chuẩn.
- `TransientTransactionError` retry toàn attempt; `UnknownTransactionCommitResult` retry commit.
- Callback có thể chạy nhiều lần, nên không chứa side effect ngoài MongoDB.
- Transaction-level read/write concern quyết định isolation/durability; transaction không mặc định luôn `snapshot`.
- Causal consistency giải bài toán ordering/read-your-writes, không thay atomic transaction.
- Transaction dài/lớn/chạm nhiều shard tăng cache, conflict, replication và coordination cost.
- Idempotency và outbox vẫn cần thiết ở biên request/event.

## 19. Đọc tiếp

- [Schema Design Patterns](../performance/schema_design.md) – giảm nhu cầu transaction bằng aggregate document.
- [Replication](../operations/replication.md) – majority commit point, election và replication lag.
- [Sharding](../operations/sharding.md) – participant shard và distributed transaction.
- [Backup & Security](../operations/backup_security.md) – durability, restore và access control.
- [MongoDB Glossary](../glossary.md) – tra cứu thuật ngữ.

## Tài liệu chính thức

- [MongoDB Transactions](https://www.mongodb.com/docs/v8.2/core/transactions/)
- [Transactions in Applications](https://www.mongodb.com/docs/v8.2/core/transactions-in-applications/)
- [Production Considerations](https://www.mongodb.com/docs/v8.2/core/transactions-production-consideration/)
- [Transactions and Operations](https://www.mongodb.com/docs/v8.2/core/transactions-operations/)
- [Read Concern](https://www.mongodb.com/docs/v8.2/reference/read-concern/)
- [Write Concern](https://www.mongodb.com/docs/v8.2/reference/write-concern/)
- [Read Isolation, Consistency, and Recency](https://www.mongodb.com/docs/v8.2/core/read-isolation-consistency-recency/)
- [Java Sync Driver Transactions](https://www.mongodb.com/docs/drivers/java/sync/current/crud/transactions/)
- [Spring Data MongoDB Transactions](https://docs.spring.io/spring-data/mongodb/reference/mongodb/client-session-transactions.html)

---

*Cập nhật lần cuối: 2026-07-29 – MongoDB 8.2*
