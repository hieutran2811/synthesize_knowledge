---
title: "MongoDB Replica Set – High Availability và vận hành production"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 12
---
# MongoDB Replica Set – High Availability và vận hành production

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: hiểu replica set bảo vệ điều gì, write được coi là durable khi nào, vì sao secondary có thể stale và cách chẩn đoán election, lag, rollback, initial sync.
>
> Phiên bản mục tiêu: **MongoDB 8.2**.

---

## 1. Mental model: replication không chỉ là “copy dữ liệu”

Replica set là một nhóm tiến trình `mongod` cùng duy trì một dataset:

```text
Application / MongoDB Driver
             │
             │ topology discovery + server selection
             ▼
      ┌─────────────────┐
      │ PRIMARY         │
      │ nhận write      │
      │ ghi oplog       │
      └───────┬─────────┘
              │ asynchronous replication
        ┌─────┴──────────┐
        ▼                ▼
┌──────────────┐  ┌──────────────┐
│ SECONDARY A  │  │ SECONDARY B  │
│ copy + apply │  │ copy + apply │
└──────────────┘  └──────────────┘
```

Replica set cung cấp:

- nhiều bản sao dữ liệu;
- tự động bầu primary mới khi đủ majority;
- khả năng rolling maintenance;
- nền tảng cho transactions và change streams;
- tùy chọn đọc từ secondary khi workload chấp nhận stale data.

Replica set **không tự cung cấp**:

- backup chống xóa nhầm hoặc ransomware;
- zero-downtime tuyệt đối khi election;
- zero data loss với mọi write concern;
- read mới nhất khi đọc từ bất kỳ secondary;
- read scaling miễn phí.

Ba câu hỏi phải tách riêng:

1. **Availability:** còn đủ voting member để bầu/duy trì primary không?
2. **Durability:** write đã được bao nhiêu data-bearing member ghi durable?
3. **Visibility/recency:** read đang chạy trên member nào và được phép thấy mốc dữ liệu nào?

Nếu gộp ba câu hỏi này thành “cluster đang healthy” thì rất dễ chọn sai read/write concern.

---

## 2. Primary, secondary và majority

### 2.1. Primary

Primary nhận write từ client, áp dụng thay đổi rồi ghi operation vào oplog. Một replica set chỉ có một primary có khả năng xác nhận write với `w: "majority"`.

Trong network partition, một former primary có thể chưa nhận ra ngay rằng nó đã mất vai trò. Tuy nhiên partition có majority mới là phía có thể duy trì primary hợp lệ và hoàn tất majority write; write chỉ tồn tại ở former primary có thể bị rollback khi node tái gia nhập.

### 2.2. Secondary

Secondary:

- chọn sync source;
- copy oplog;
- áp dụng operation theo thứ tự replication;
- duy trì bản sao dataset;
- có thể trở thành primary nếu `priority > 0`, có vote và đủ điều kiện;
- có thể phục vụ read nếu read preference cho phép.

Replication là bất đồng bộ. “Secondary đang `SECONDARY`” không đồng nghĩa lag bằng 0.

### 2.3. Majority là majority của voting member

Số vote cần để bầu primary:

```text
majorityVoteCount = floor(votingMembers / 2) + 1
```

| Voting members | Majority | Có thể mất bao nhiêu voting member mà vẫn bầu primary? |
|---:|---:|---:|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 4 | 3 | 1 |
| 5 | 3 | 2 |
| 6 | 4 | 2 |
| 7 | 4 | 3 |

Thêm member chẵn không nhất thiết tăng fault tolerance. Hãy ưu tiên số **voting member** lẻ, không phải chỉ tổng số member lẻ.

MongoDB hỗ trợ tối đa 50 member trong một replica set, nhưng tối đa 7 voting member.

---

## 3. Kiến trúc production

### 3.1. P-S-S: lựa chọn mặc định

```text
Availability Zone A: Primary
Availability Zone B: Secondary
Availability Zone C: Secondary
```

Ba data-bearing voting member:

- có ba bản sao dữ liệu;
- chịu được một member mất;
- hai data-bearing member có thể xác nhận majority write;
- mỗi secondary có thể được rolling maintenance riêng.

MongoDB khuyến nghị tối thiểu ba member có dữ liệu: một primary và hai secondary.

### 3.2. P-S-A: arbiter không phải bản sao dữ liệu

Arbiter:

- có đúng một election vote;
- không lưu dataset;
- không áp dụng oplog;
- không thể thành primary;
- không xác nhận data durability.

```text
Primary + Secondary + Arbiter
```

Topology này có majority election 2/3 nhưng chỉ có hai bản sao dữ liệu. Nếu secondary data-bearing không khả dụng, primary và arbiter vẫn có vote majority, nhưng `w: "majority"` không thể hoàn tất vì arbiter không lưu dữ liệu.

Do đó P-S-A là giải pháp do hạn chế chi phí, không tương đương P-S-S. Đặc biệt tránh dùng PSA cho shard nếu chưa hiểu rõ ảnh hưởng availability của majority write.

### 3.3. Phân bố địa lý phải thiết kế theo failure domain

Không chỉ hỏi “có ba node không”; phải hỏi:

- mất một availability zone thì phía còn lại có majority không?
- mất WAN link thì data center nào có majority?
- primary mong muốn nằm ở đâu?
- cross-region RTT ảnh hưởng majority write latency thế nào?
- có đủ capacity khi một member/zone biến mất không?

Ví dụ 2 node ở DC-A và 1 node ở DC-B chịu được mất DC-B, nhưng mất toàn bộ DC-A thì DC-B còn dữ liệu nhưng không có majority để tự bầu primary.

`priority` ảnh hưởng xu hướng primary placement, nhưng không tạo thêm vote hay thay đổi failure math.

---

## 4. Oplog và luồng replication

### 4.1. Oplog là gì?

Oplog là capped collection đặc biệt:

```text
local.oplog.rs
```

Nó lưu rolling history của các operation làm thay đổi dữ liệu. Mỗi member có oplog riêng.

```javascript
const local = db.getSiblingDB("local");

local.oplog.rs
  .find()
  .sort({ $natural: -1 })
  .limit(5);
```

Một entry có thể chứa:

```javascript
{
  ts: Timestamp(1785302400, 1), // logical oplog timestamp
  t: NumberLong(42),            // election term
  op: "i",                      // i/u/d/c/n
  ns: "orders.orders",
  ui: UUID("..."),              // collection UUID
  o: { _id: "ORDER-1001", status: "PAID" },
  wall: ISODate("2026-07-29T08:00:00Z")
}
```

Update/delete thường có thêm `o2` để xác định document. Transaction có thể được biểu diễn thành các `applyOps` entry; đừng giả định một business request luôn tương ứng đúng một oplog entry.

Oplog là internal replication mechanism. Ứng dụng cần subscribe thay đổi nên dùng **change stream**, không tự tail và parse oplog.

### 4.2. Secondary không nhất thiết copy trực tiếp từ primary

Secondary có thể chọn member khác làm sync source. Chained replication hữu ích khi giảm WAN traffic, nhưng có thể làm lag lan theo chuỗi:

```text
Primary → Secondary A → Secondary B
```

Khi chẩn đoán lag, cần kiểm tra cả sync source, network từ source và tốc độ apply tại destination.

### 4.3. Oplog window

Oplog window là khoảng thời gian từ entry cũ nhất đến entry mới nhất:

```javascript
rs.printReplicationInfo();

// Dùng trong script vì trả document:
db.getReplicationInfo();
```

Nếu secondary bị gián đoạn lâu hơn oplog window, nó không còn đủ history liên tục để catch up bằng replication thông thường và phải initial sync/resync.

Kích thước oplog phụ thuộc **write churn**, không chỉ phụ thuộc kích thước database:

- multi-update có thể tạo nhiều replication operation;
- insert rồi delete liên tục không làm database lớn nhưng tiêu thụ oplog;
- index build, transaction và batch workload có burst riêng;
- late secondary hoặc initial sync cần window đủ dài.

Mục tiêu thực tế:

```text
oplog window
  > planned maintenance
  + worst expected lag
  + initial-sync catch-up duration
  + safety margin
```

Không đặt một con số GB cố định cho mọi cluster. Theo dõi cả `oplog GB/hour` và window theo thời gian ở workload cao điểm.

### 4.4. Resize oplog

Với self-managed deployment, resize động trên **từng member**:

```javascript
db.adminCommand({
  replSetResizeOplog: 1,
  size: Double(51200),
  minRetentionHours: 72
});
```

`size` dùng MB và `mongosh` yêu cầu cast bằng `Double()`. `minRetentionHours` là thời gian giữ tối thiểu, không biến oplog thành backup. Kích thước mới được lưu qua restart; nếu đặt minimum retention lúc runtime, cũng cập nhật `storage.oplogMinRetentionHours`/startup option để restart không đưa policy về giá trị cấu hình cũ.

Oplog có thể tạm vượt configured size để tránh xóa majority commit point.

Minimum retention cũng có thể làm oplog tăng vượt size để giữ đủ số giờ đã cấu hình; write volume cao có thể làm cạn disk. Phải alert cả window lẫn dung lượng thực tế.

Giảm size/retention có thể truncate history ngay, làm change stream mất resume point hoặc secondary phải resync. Đây là maintenance change cần kiểm tra consumer và member lag trước khi thực hiện.

---

## 5. Initial sync

Initial sync dùng khi thêm member mới hoặc resync member không còn bắt kịp oplog.

Logical initial sync về khái niệm:

```text
1. Clone collections từ sync source
2. Build indexes trong quá trình copy
3. Buffer các oplog entry mới phát sinh
4. Apply buffered oplog
5. Catch up tới trạng thái hiện tại
6. STARTUP2 → SECONDARY
```

Nếu oplog history cần thiết bị truncate trước khi quá trình catch-up hoàn tất, initial sync có thể phải chạy lại từ đầu.

Trước khi thêm member:

- kiểm tra source và destination còn dư CPU, I/O, network;
- bảo đảm destination đủ disk cho data, index và temporary oplog;
- bảo đảm oplog window bao phủ thời gian clone + catch-up;
- thêm member trước khi cluster đã bão hòa;
- theo dõi ảnh hưởng cache và latency trên sync source.

MongoDB Enterprise còn hỗ trợ file-copy-based initial sync trong các điều kiện tương ứng. Atlas có quy trình managed riêng; không áp dụng máy móc runbook self-managed cho Atlas.

---

## 6. Election, term và failover

### 6.1. Election xảy ra khi nào?

Các trigger thường gặp:

- khởi tạo replica set;
- primary mất kết nối quá `electionTimeoutMillis`;
- `rs.stepDown()`;
- một số thay đổi qua `rs.reconfig()`;
- thay đổi topology/member.

Mặc định, các member heartbeat nhau khoảng mỗi 2 giây và election timeout là 10 giây. Với cấu hình mặc định, MongoDB mô tả median time để có primary mới thường không quá khoảng 12 giây, nhưng đây **không phải SLA**.

WAN latency, packet loss, DNS, TLS, member load và catch-up đều có thể kéo dài khoảng không có primary.

Hạ `electionTimeoutMillis` để failover nhanh hơn có thể làm election giả tăng khi mạng chỉ chập chờn. Chỉ tune sau khi đo failure detector và network thực tế.

### 6.2. Candidate cần gì?

Một member muốn thành primary phải:

- có `priority > 0`;
- là voting member;
- ở state/health phù hợp;
- nhìn thấy majority vote;
- có optime mới nhất trong các member nó nhìn thấy;
- nhận majority vote.

`priority` là preference/best effort, không cho phép một node stale thắng chỉ vì priority cao. MongoDB có thể bầu tạm member priority thấp rồi tiếp tục election để ưu tiên member cao hơn.

### 6.3. Term dùng để fence primary cũ

Mỗi election thành công tiến sang một term mới. Oplog entry ghi term `t`; term giúp protocol phân biệt leadership cũ và mới.

```text
Term 41: P1 là primary
network partition
Term 42: P2 được majority bầu
P1 thấy term mới → step down
```

Trong lúc election:

- không có primary nên write không hoàn tất;
- read dùng `primary` cũng không có server phù hợp;
- secondary read có thể tiếp tục nếu read preference cho phép, nhưng có thể stale;
- driver liên tục topology discovery và server selection.

Application phải xem election là sự kiện bình thường có thể xảy ra, không phải case “không bao giờ”.

### 6.4. Mirrored reads

MongoDB mirror một mẫu read từ primary sang các electable secondary để làm ấm cache, giảm cold-cache shock sau election. Mirrored read là fire-and-forget và không ảnh hưởng kết quả trả cho client.

MongoDB 8.2 hỗ trợ targeted read mirroring để chọn server cần warm cache bằng tag. Đây là công cụ tối ưu failover recovery, không thay capacity planning.

---

## 7. Majority commit point

Primary tính majority commit point: optime cao nhất đã được commit theo majority semantics.

```text
oplog mới nhất trên primary
          │
          ├── có thể chưa majority committed
          │
          ▼
majority commit point
          │
          └── history trước/tại đây đủ điều kiện majority visibility
```

Phải phân biệt:

- **applied optime:** member đã áp dụng tới operation nào;
- **durable optime:** member đã ghi durable tới operation nào;
- **last committed optime:** replica set đã majority-commit tới operation nào.

Flow control, majority read và majority write đều liên quan tới khoảng cách giữa các mốc này.

---

## 8. Write concern – client đợi điều gì?

### 8.1. Các mức phổ biến

| Write concern | Client đợi | Rủi ro/chú ý |
|---|---|---|
| `w: 0` | không đợi acknowledgment | không biết validation/write error đáng tin cậy |
| `w: 1` | primary áp dụng write | write có thể rollback nếu chưa replicate |
| `w: 2`, `w: 3` | đủ số data-bearing member | semantics không tự thích nghi tốt khi topology đổi |
| `w: "majority"` | calculated majority data-bearing voting member commit durable | latency phụ thuộc member trong majority |
| custom tag concern | đủ member theo failure-domain tag | cấu hình/phân bố tag phải đúng |

Từ MongoDB 8.0, majority write được acknowledgment sau khi calculated majority data-bearing member ghi oplog entry durable. Với phần lớn replica set configuration, `w: "majority"` cũng là default, nhưng production nên kiểm tra effective default:

```javascript
db.adminCommand({ getDefaultRWConcern: 1 });
```

Đừng dựa vào trí nhớ về default khi cluster đã upgrade/reconfigure hoặc có global policy.

### 8.2. Journaling

```javascript
{
  writeConcern: {
    w: "majority",
    j: true,
    wtimeout: 5000
  }
}
```

`j: true` yêu cầu journal acknowledgment. Với WiredTiger, journaling bật mặc định; `w: "majority"` thường bao hàm journal durability khi `writeConcernMajorityJournalDefault` là `true`.

Điều quan trọng là kiểm tra effective storage/configuration, không chỉ thấy chuỗi `j=true` trong URI.

### 8.3. `wtimeout` là kết quả không chắc chắn

```javascript
db.orders.insertOne(
  {
    _id: "ORDER-1001",
    status: "CREATED"
  },
  {
    writeConcern: {
      w: "majority",
      wtimeout: 5000
    }
  }
);
```

Nếu timeout:

```text
Không được kết luận: "write chắc chắn thất bại"

Có thể:
- primary đã apply;
- một số secondary đã nhận;
- majority acknowledgment đến quá muộn;
- write tiếp tục replicate sau khi client nhận lỗi.
```

Client phải dùng stable business ID/idempotency key, retry protocol của driver và read-back/reconciliation khi business cần biết outcome.

Retryable writes giúp driver retry một lần cho các operation đủ điều kiện. Nó không tự làm toàn bộ business workflow hoặc external side effect idempotent.

---

## 9. Read preference khác read concern

Hai cấu hình trả lời hai câu hỏi khác nhau:

```text
Read preference → chọn member nào?
Read concern    → trên member đó, cho phép thấy dữ liệu ở mức nào?
```

### 9.1. Read preference modes

| Mode | Chọn member | Khi nên dùng | Rủi ro chính |
|---|---|---|---|
| `primary` | chỉ primary | mặc định, dữ liệu operational | không đọc được lúc không có primary |
| `primaryPreferred` | primary; fallback secondary | chỉ khi fallback stale được chấp nhận | semantics đổi trong failover |
| `secondary` | chỉ secondary | workload chuyên biệt chấp nhận stale | lỗi nếu không có secondary eligible |
| `secondaryPreferred` | ưu tiên secondary; có thể primary | offload có kiểm soát | stale và cạnh tranh replication |
| `nearest` | eligible member trong latency window | locality quan trọng hơn recency | “gần nhất” không có nghĩa “mới nhất” |

Mọi mode ngoài `primary` có thể trả stale data vì secondary replication bất đồng bộ.

`maxStalenessSeconds` lọc secondary mà driver ước lượng quá stale. Đây là **estimated bound**, không biến secondary read thành strongly consistent.

Tag set cho phép chọn member theo `region`, `workload` hoặc failure domain:

```javascript
const readPreference = {
  mode: "secondary",
  tags: [{ workload: "reporting" }],
  maxStalenessSeconds: 120
};
```

Cú pháp cụ thể phụ thuộc driver.

### 9.2. Read concern levels quan trọng

| Read concern | Ý nghĩa thực hành |
|---|---|
| `local` | thấy dữ liệu local của member; có thể gồm dữ liệu sau này rollback |
| `majority` | chỉ trả dữ liệu đã majority-committed |
| `snapshot` | snapshot nhất quán cho operation/transaction được hỗ trợ |
| `linearizable` | read trên primary với guarantee recency mạnh hơn; latency/availability đắt hơn |

`readConcern: "majority"` không đảm bảo **latest value toàn hệ thống** nếu chosen secondary chưa tiến tới commit point mới nhất. Nó đảm bảo dữ liệu trả về thuộc lịch sử majority-committed mà member đã biết.

Với `linearizable`, luôn đặt `maxTimeMS` để operation không chờ vô hạn khi không thể xác minh majority.

### 9.3. Read-your-writes

Để giữ causal/read-your-writes qua các member:

- dùng cùng causally consistent session;
- read concern `"majority"`;
- write concern `"majority"`;
- thực hiện operation tuần tự trong session.

Transaction có read phải dùng read preference `primary`, và mọi operation của transaction route cùng member.

---

## 10. Có nên đọc từ secondary để scale read?

Không mặc định.

Secondary vẫn phải:

- nhận và apply oplog;
- duy trì index;
- giữ cache phục vụ replication/failover;
- sẵn sàng trở thành primary.

Query reporting nặng trên secondary có thể làm eviction, disk I/O và replication lag tăng. Sau đó primary có thể bị flow control làm chậm write để majority lag không tăng thêm.

Chỉ route read sang secondary khi:

- stale data được business chấp nhận;
- query có resource budget;
- secondary có capacity riêng;
- `maxStalenessSeconds`/tags phù hợp;
- đã test failover khi secondary đó phải lên primary.

Với analytics workload rất khác operational workload, một cluster/read model riêng thường dễ cô lập hơn.

---

## 11. Special-purpose members

### 11.1. Priority 0

```javascript
{
  _id: 3,
  host: "mongo-dr.example.net:27017",
  priority: 0,
  votes: 0
}
```

Priority 0 member không thể thành primary. Non-voting member bắt buộc có priority 0.

### 11.2. Hidden member

```javascript
{
  _id: 3,
  host: "mongo-report.example.net:27017",
  hidden: true,
  priority: 0,
  votes: 0
}
```

Hidden member:

- không xuất hiện trong normal driver discovery;
- không nhận application read thông qua replica-set routing;
- vẫn giữ data và replicate;
- có thể được dùng cho task chuyên biệt qua direct connection có kiểm soát.

Hidden member bắt buộc priority 0. Hidden không tự đồng nghĩa non-voting; hãy tính vote/majority rõ ràng.

### 11.3. Delayed member

```javascript
{
  _id: 4,
  host: "mongo-delayed.example.net:27017",
  hidden: true,
  priority: 0,
  votes: 0,
  secondaryDelaySecs: NumberLong(3600)
}
```

Delayed member giữ một view trong quá khứ để hỗ trợ phục hồi một số lỗi thao tác.

Guardrail:

- delay phải nằm trong oplog window;
- member nên hidden, priority 0 và thường non-voting;
- application không được vô tình đọc dữ liệu delayed;
- delayed member vẫn replicate lệnh xóa sau thời gian delay;
- nó không thay backup immutable/off-cluster.

### 11.4. Arbiter

Chỉ dùng khi không thể cấp thêm data-bearing member. Không đặt arbiter cùng host với primary/secondary và không dùng nhiều arbiter để “mua vote”.

### 11.5. `votes` không phải công cụ chọn primary

Muốn ảnh hưởng member nào được ưu tiên primary, dùng `priority`. Chỉ thay `votes` trong trường hợp topology đặc biệt và phải tính lại:

- election majority;
- writable voting member;
- default/majority write behavior;
- fault tolerance khi từng failure domain mất.

---

## 12. Thiết lập self-managed replica set

> Atlas quản lý phần lớn provisioning/topology. Phần này dành cho self-managed deployment.

### 12.1. Điều kiện trước

- dùng DNS hostname ổn định, không cấu hình chỉ bằng IP;
- mọi member/client resolve được hostname;
- đồng bộ thời gian;
- bật authentication nội bộ bằng keyfile hoặc x.509;
- bật authorization và TLS trước khi expose network;
- tách `dbPath`, log, disk capacity và quyền filesystem đúng;
- cùng major version ngoài rolling upgrade;
- firewall chỉ mở luồng cần thiết.

Ví dụ `mongod.conf` tối giản:

```yaml
replication:
  replSetName: rs0

security:
  authorization: enabled
  keyFile: /run/secrets/mongodb-keyfile

net:
  bindIp: localhost,mongo1.example.net
  tls:
    mode: requireTLS
    certificateKeyFile: /run/secrets/mongodb.pem
    CAFile: /run/secrets/ca.pem
```

Không copy path/chứng chỉ mẫu trực tiếp vào production; tích hợp secret manager và permission policy của môi trường.

### 12.2. Khởi tạo

Chạy một lần trên member đầu tiên:

```javascript
rs.initiate({
  _id: "rs0",
  members: [
    {
      _id: 0,
      host: "mongo1.example.net:27017",
      priority: 1,
      votes: 1,
      tags: { region: "ap-southeast", az: "a" }
    },
    {
      _id: 1,
      host: "mongo2.example.net:27017",
      priority: 1,
      votes: 1,
      tags: { region: "ap-southeast", az: "b" }
    },
    {
      _id: 2,
      host: "mongo3.example.net:27017",
      priority: 1,
      votes: 1,
      tags: { region: "ap-southeast", az: "c" }
    }
  ]
});
```

Xác minh:

```javascript
rs.status();
rs.conf();
db.hello();
db.adminCommand({ getDefaultRWConcern: 1 });
```

Không tiếp tục production traffic chỉ vì `rs.initiate()` trả `ok: 1`; đợi đủ member đạt `SECONDARY`, kiểm tra optime/lag và thực hiện test write/read.

### 12.3. Connection string

```text
mongodb://app_user:<password>@mongo1.example.net:27017,mongo2.example.net:27017,mongo3.example.net:27017/orders
  ?replicaSet=rs0
  &authSource=admin
  &tls=true
  &readPreference=primary
  &w=majority
  &retryWrites=true
  &retryReads=true
```

Viết URI thực tế trên một dòng. Liệt kê nhiều seed host để bootstrap topology discovery; driver sẽ dùng `hello` để tìm topology hiện tại.

Không hard-code “primary hostname” trong application. Primary thay đổi sau election.

Với Spring Boot:

```yaml
spring:
  data:
    mongodb:
      uri: ${MONGODB_URI}
```

Credentials phải đến từ secret/config injection, không commit vào repository.

Timeout như `serverSelectionTimeoutMS`, `connectTimeoutMS` và `socketTimeoutMS` giải quyết các failure khác nhau. Chọn theo SLO và retry budget; không đặt tất cả cùng một giá trị tùy ý.

---

## 13. Monitoring đúng cách

### 13.1. Manual inspection

```javascript
rs.status();
rs.printReplicationInfo();
rs.printSecondaryReplicationInfo();
```

- `rs.status()` trả document và phù hợp cho script.
- Hai helper `print...` chủ yếu dùng để đọc thủ công.
- Chạy secondary replication info từ primary để có góc nhìn mới nhất.

### 13.2. Tính lag từ optime, không từ heartbeat

Heartbeat đo reachability/topology communication. `lastHeartbeat` không phải thời điểm secondary apply write.

```javascript
const status = rs.status();
const primary = status.members.find(
  member => member.stateStr === "PRIMARY"
);

if (primary) {
  status.members
    .filter(member => member.stateStr === "SECONDARY")
    .forEach(member => {
      const lagSeconds = Math.max(
        0,
        (primary.optimeDate - member.optimeDate) / 1000
      );

      printjson({
        member: member.name,
        lagSeconds,
        health: member.health,
        syncSourceHost: member.syncSourceHost
      });
    });
}
```

Đây là snapshot chẩn đoán, không thay monitoring system. Clock, inactivity và thời điểm heartbeat có thể làm helper hiển thị số âm/0 không đại diện toàn bộ health.

### 13.3. Metric cần theo dõi

#### Topology và election

- member `health`/`state`;
- primary count;
- term/election count và lý do election;
- thời gian không có writable primary;
- topology changes nhìn từ driver.

#### Replication

- applied/durable optime lag;
- majority commit lag;
- sync source changes;
- replication buffer/queue;
- slow oplog application log;
- initial sync progress/restart;
- rollback occurrence.

#### Oplog

- oplog window theo giờ;
- oplog growth rate/GB per hour;
- max member lag / oplog window ratio;
- window còn đủ maintenance và delayed member không.

#### Resource

- disk latency/queue/utilization;
- CPU, memory, WiredTiger cache eviction;
- network throughput/retransmit giữa member;
- filesystem free space;
- secondary read/query load;
- flow-control wait/time.

Không dùng ngưỡng cứng “lag > 60 giây” cho mọi hệ thống. Alert nên bám:

- freshness SLO của read;
- RPO;
- tỷ lệ lag so với oplog window;
- thời gian cần để catch up;
- nguy cơ mất majority.

---

## 14. Flow control – primary chậm có thể do secondary

Flow control bật mặc định. Khi majority committed lag tiến gần `flowControlTargetLagSeconds`, primary giới hạn ticket cho write nhằm giữ lag trong mục tiêu.

```text
secondary disk chậm
    ↓
majority commit point tụt lại
    ↓
flow control giữ write ticket
    ↓
write latency trên primary tăng
```

Vì vậy write latency tăng không nhất thiết do primary CPU cao.

Khi thấy flow control:

1. xác định member nào nằm trong writable majority và đang lag;
2. kiểm tra disk/network/cache/secondary query;
3. kiểm tra burst write và slow oplog apply;
4. xử lý bottleneck gốc;
5. chỉ tune/disable flow control sau khi hiểu durability/lag trade-off.

---

## 15. Rollback – former primary bỏ history phân nhánh

Rollback xảy ra khi former primary đã nhận write chưa được các secondary cần thiết replicate, sau đó một branch khác có majority bầu primary mới.

```text
          network partition
         /                 \
former primary          majority partition
accept w:1 writes       elect new primary
         \                 /
           reconnect
              ↓
former primary rollback divergent writes
```

Với self-managed deployment, MongoDB mặc định có thể ghi BSON rollback files dưới:

```text
<dbPath>/rollback/<collectionUUID>/
```

Đây không phải automatic business reconciliation. Operator phải:

- xác định time window và collection bị ảnh hưởng;
- giữ log/audit evidence;
- dùng `bsondump` đọc rollback data khi phù hợp;
- đối chiếu external systems và idempotency keys;
- quyết định replay, compensate hay bỏ;
- tìm nguyên nhân network/lag/write concern.

`w: "majority"` với journaling/durable configuration phù hợp giúp tránh rollback các write đã acknowledgment. `w: 1` chỉ chứng minh former primary đã nhận/applied, không chứng minh branch đó sẽ thắng election.

---

## 16. Runbook sự cố

### 16.1. Primary vừa mất

```text
1. Ứng dụng giữ request trong timeout/retry budget
2. Driver topology discovery tìm primary mới
3. Replica set election
4. Xác nhận PRIMARY mới + SECONDARY health
5. Xác nhận majority write hoạt động
6. Kiểm tra lag, rollback và latency sau failover
7. Phục hồi member cũ theo runbook
```

Không restart hàng loạt member ngay khi thấy election. Hành động đồng thời có thể làm mất majority và xóa evidence.

### 16.2. Không có primary

Kiểm tra theo thứ tự:

- còn bao nhiêu voting member reach nhau?
- member state/health và election log nói gì?
- DNS, network policy, TLS certificate, authentication nội bộ;
- disk full/read-only, process crash, clock;
- member có priority 0 hoặc quá stale không?
- vừa có `rs.reconfig()`/upgrade/maintenance không?

Không dùng `rs.reconfig(..., { force: true })` như bước đầu. Forced reconfiguration chỉ dành cho catastrophic recovery khi không còn majority; nó có thể làm rollback cả majority-committed write và gây inconsistency trong sharded cluster.

### 16.3. Secondary lag

Tách hai nhóm:

```text
Fetch lag:
  network / sync source / bandwidth / packet loss

Apply lag:
  disk / CPU / cache / query load / slow operation / write burst
```

Thực hiện:

1. so applied/durable optime giữa member;
2. kiểm tra `syncSourceHost`;
3. kiểm tra oplog window còn bao nhiêu;
4. đọc slow oplog application log;
5. kiểm tra disk latency/cache/secondary reads;
6. kiểm tra flow control trên primary;
7. giảm workload cạnh tranh hoặc tăng capacity;
8. xác minh lag đang giảm và tốc độ catch-up lớn hơn write rate.

### 16.4. Secondary đã rơi ngoài oplog window

Không thể “tăng oplog rồi tự có lại history đã mất”. Cần initial sync/resync theo quy trình chính thức.

Không xóa `dbPath` hoặc force remove/add theo thói quen khi chưa:

- xác nhận đúng member/volume;
- có backup cần thiết;
- đo capacity của sync source;
- bảo đảm oplog mới đủ cho lần sync;
- có maintenance/rollback plan.

### 16.5. Disk gần đầy

- xác định data, index, oplog, journal hay log tăng;
- bảo vệ majority trước;
- không xóa thủ công file WiredTiger/oplog;
- mở rộng disk/retention theo runbook được hỗ trợ;
- kiểm tra member catch-up sau xử lý;
- sửa alert/capacity model để không lặp lại.

---

## 17. Rolling maintenance và upgrade

Nguyên tắc:

```text
secondary 1
→ maintenance/restart
→ đợi SECONDARY + catch up
→ secondary 2
→ maintenance/restart
→ đợi SECONDARY + catch up
→ step down primary
→ đợi primary mới
→ maintenance former primary
```

Ví dụ planned step-down:

```javascript
rs.stepDown(300);
```

Member vừa step down không tìm cách trở lại primary trong khoảng chỉ định. Lệnh có thể ngắt operation/connection đang dùng primary; application phải chịu được topology change.

Trước từng bước:

- majority vẫn còn sau khi member dừng;
- remaining members đủ capacity;
- member không lag và oplog window đủ;
- backup/rollback plan sẵn sàng;
- driver retry/server selection đã test;
- không có initial sync hoặc reconfiguration cạnh tranh.

Rolling upgrade lên MongoDB 8.2 cần làm secondary trước, primary cuối, rồi có burn-in period trước khi nâng FCV. Không trộn major version lâu hơn rolling window cần thiết.

---

## 18. Replica set không phải backup

Các thao tác sau được replicate:

- `deleteMany({})`;
- drop collection/database;
- dữ liệu bị application ghi sai;
- credential hợp lệ thực hiện thao tác phá hoại.

Vì vậy:

```text
Replica set → HA + redundancy
Backup      → recovery từ history độc lập
Delayed node→ time-shifted replica, vẫn không phải immutable backup
```

Backup strategy cần:

- RPO: chấp nhận mất tối đa bao nhiêu dữ liệu;
- RTO: khôi phục dịch vụ trong bao lâu;
- snapshot/oplog consistency;
- off-cluster/immutable retention;
- encryption và access separation;
- restore test định kỳ;
- runbook chuyển application sang dữ liệu đã restore.

Một backup chưa từng restore chỉ là giả định.

---

## 19. Kiểm thử failover ở tầng application

Test ít nhất các tình huống:

| Scenario | Kỳ vọng |
|---|---|
| planned `rs.stepDown()` | driver tìm primary mới trong SLO |
| primary process crash | write retry đúng, không double business effect |
| network partition | minority không hoàn tất majority write |
| một secondary chậm | alert trước khi oplog window nguy hiểm |
| majority unavailable | request fail có kiểm soát, không treo vô hạn |
| write concern timeout | read-back/idempotency giải quyết unknown outcome |
| cold-cache primary mới | latency phục hồi trong capacity budget |
| member ngoài oplog window | initial sync runbook hoạt động |
| rollback simulation ở staging | biết tìm và reconcile rollback data |
| restore backup | đạt RPO/RTO đã công bố |

Đo cả:

- time to detect;
- time to elect;
- time driver chọn server mới;
- time application phục hồi success rate;
- duplicate/unknown write;
- latency sau election;
- catch-up time của member cũ.

“Database có primary mới” chưa đồng nghĩa user journey đã phục hồi.

---

## 20. Anti-pattern thường gặp

### 20.1. Hard-code primary

Application connect trực tiếp một hostname và coi đó luôn là primary. Sau election, client không topology-discover được member mới.

### 20.2. Dùng `lastHeartbeat` làm replication lag

Heartbeat trả lời “member còn giao tiếp không”, không trả lời “member đã apply tới oplog nào”.

### 20.3. Chọn `primaryPreferred` để “luôn đọc được”

Khi failover, semantics đổi từ primary data sang secondary data có thể stale. Đây phải là quyết định business, không phải timeout workaround.

### 20.4. Xem secondary là read replica miễn phí

Reporting query làm secondary lag, cache lạnh và giảm khả năng failover.

### 20.5. Xem arbiter là data redundancy

Arbiter chỉ thêm vote, không thêm bản sao, durability hay read capacity.

### 20.6. Kết luận write thất bại khi `wtimeout`

Write có thể đã apply và tiếp tục replicate. Retry bằng random ID có thể tạo duplicate business record.

### 20.7. Resize oplog chỉ trên primary

Mỗi member có oplog riêng. Member khác vẫn có window nhỏ và rơi khỏi history.

### 20.8. Force reconfig để chữa mọi lỗi

Forced reconfiguration có rủi ro mất/rollback dữ liệu và phá consistency topology.

### 20.9. Dùng delayed member thay backup

Xóa nhầm vẫn đi tới delayed member sau delay; attacker có thể tác động cùng security domain.

### 20.10. Tối ưu election timeout trước khi sửa mạng

Timeout thấp hơn có thể biến packet loss ngắn thành election/rollback thường xuyên.

---

## 21. Production checklist

### Topology

- [ ] Ít nhất 3 data-bearing member nếu không có constraint đặc biệt.
- [ ] Voting member/failure domain tạo majority sau failure đã chọn.
- [ ] Dùng DNS hostname và cùng major version ngoài rolling upgrade.
- [ ] Arbiter/delayed/hidden member có lý do và failure math rõ.
- [ ] Remaining members đủ capacity khi một member/zone mất.

### Durability và consistency

- [ ] Kiểm tra effective default read/write concern.
- [ ] Critical write dùng `w: "majority"` và stable business ID.
- [ ] Application xử lý `wtimeout` như unknown outcome.
- [ ] Read preference/read concern xuất phát từ freshness contract.
- [ ] Causal session được dùng khi cần read-your-writes qua member.

### Oplog và replication

- [ ] Oplog window bao phủ maintenance, lag, delay và initial sync.
- [ ] Theo dõi growth rate, window và lag/window ratio trên mọi member.
- [ ] Initial sync đã được capacity-test.
- [ ] Slow oplog apply, sync-source change và flow control có alert.
- [ ] Change stream dùng API chính thức thay vì tail oplog.

### Application

- [ ] URI chứa nhiều seed host và `replicaSet`.
- [ ] Không hard-code primary.
- [ ] Timeout và retry có tổng budget.
- [ ] Retry không double external/business side effect.
- [ ] Đã test planned/unplanned failover.

### Security và recovery

- [ ] TLS, authorization và member authentication bật.
- [ ] Secret không nằm trong source code.
- [ ] Backup độc lập/immutable theo RPO/RTO.
- [ ] Restore và rollback reconciliation được diễn tập.
- [ ] Forced reconfig có emergency approval/runbook riêng.

---

## 22. Tóm tắt

```text
Replica set
  → redundancy + high availability, không phải backup

Primary
  → nhận write và ghi oplog

Secondary
  → copy/apply bất đồng bộ, có thể stale

Election
  → cần majority vote; khoảng mất primary không có SLA cố định

Term
  → phân biệt leadership mới/cũ

Oplog window
  → lịch sử còn đủ để member catch up hay phải initial sync

w: "majority"
  → durability acknowledgment theo calculated majority

wtimeout
  → outcome không chắc chắn, không chứng minh write không tồn tại

Read preference
  → chọn member

Read concern
  → chọn visibility/consistency trên member đó

Flow control
  → secondary lag có thể làm primary write chậm

Rollback
  → former primary bỏ write ở branch không thắng majority
```

Thiết kế HA tốt không dừng ở ba node màu xanh trên dashboard. Nó cần application chịu được topology change, durability/visibility contract đúng, oplog đủ dài, alert gắn với failure budget và restore đã được diễn tập.

---

## 23. Đọc tiếp

- [Transactions](../fundamentals/transactions.md)
- [Schema Design Patterns](../performance/schema_design.md)
- [MongoDB Glossary](../glossary.md)
- [MongoDB Roadmap](../roadmap.md)
- Chủ đề tiếp theo: [Sharding](sharding.md)

## Tài liệu chính thức

- [Replication](https://www.mongodb.com/docs/v8.2/replication/)
- [Replica Set Members](https://www.mongodb.com/docs/v8.2/core/replica-set-members/)
- [Replica Set Deployment Architectures](https://www.mongodb.com/docs/v8.2/core/replica-set-architectures/)
- [Replica Set Oplog](https://www.mongodb.com/docs/v8.2/core/replica-set-oplog/)
- [Replica Set Data Synchronization](https://www.mongodb.com/docs/v8.2/core/replica-set-sync/)
- [Replica Set Elections](https://www.mongodb.com/docs/v8.2/core/replica-set-elections/)
- [Write Concern](https://www.mongodb.com/docs/v8.2/reference/write-concern/)
- [Read Concern](https://www.mongodb.com/docs/v8.2/reference/read-concern/)
- [Read Preference](https://www.mongodb.com/docs/v8.2/core/read-preference/)
- [Rollbacks During Replica Set Failover](https://www.mongodb.com/docs/v8.2/core/replica-set-rollbacks/)
- [Self-Managed Replica Set Maintenance](https://www.mongodb.com/docs/v8.2/administration/replica-set-maintenance/)
- [Upgrade a Replica Set to MongoDB 8.2](https://www.mongodb.com/docs/v8.2/release-notes/8.2-upgrade-replica-set/)

---

*Cập nhật lần cuối: 2026-07-29*
