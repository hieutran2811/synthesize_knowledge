# MongoDB Backup & Security – Recovery và phòng thủ nhiều lớp

> Mục tiêu: thiết kế backup từ RPO/RTO, khôi phục replica set/sharded cluster đúng consistency boundary, và bảo vệ MongoDB bằng authentication, least privilege, TLS, encryption, auditing cùng incident runbook.
>
> Phiên bản mục tiêu: **MongoDB 8.2**.

---

## 1. Mental model: backup chỉ có giá trị khi restore được

Replica set bảo vệ availability trước lỗi node. Backup bảo vệ recovery history trước:

- xóa nhầm hoặc deploy ghi sai hàng loạt;
- ransomware và credential compromise;
- corruption được phát hiện muộn;
- mất cả failure domain;
- yêu cầu legal/audit retention.

```text
Production cluster
      │
      ├── snapshots ───────────────┐
      ├── oplog / continuous log ──┼──▶ Backup vault
      └── logical dump ────────────┘       │
                                           │ restore
                                           ▼
                                  Isolated recovery cluster
                                           │
                                     validate + reconcile
                                           │
                                        cutover
```

Một file backup tồn tại chưa chứng minh hệ thống recover được. Chỉ restore drill mới trả lời:

1. artifact có đọc được không?
2. key giải mã còn truy cập được không?
3. topology/version/tool có tương thích không?
4. data có nhất quán theo business invariant không?
5. thời gian thực tế có đạt RTO không?

Security cũng không phải một checkbox. Cần nhiều lớp độc lập:

```text
Private network → TLS → Authentication → RBAC
                → Encryption at rest / in use
                → Audit + detection → Immutable backup
```

Nếu application identity có quyền đọc plaintext và KMS key, encryption không ngăn được chính identity đó lấy dữ liệu. Threat model phải chỉ rõ lớp nào chặn loại attacker nào.

---

## 2. Bắt đầu bằng recovery contract

### 2.1. RPO và RTO

| Khái niệm | Câu hỏi | Ví dụ |
|---|---|---|
| RPO | Chấp nhận mất tối đa bao nhiêu dữ liệu? | 5 phút writes |
| RTO | Từ lúc declare incident đến lúc service dùng được mất bao lâu? | 60 phút |
| Retention | Cần quay lại quá khứ xa đến đâu? | 35 ngày + 12 tháng monthly |
| Recovery scope | Restore collection, database hay toàn cluster? | Toàn sharded cluster |

RTO không chỉ là thời gian copy bytes. Nó gồm:

- phát hiện và ra quyết định;
- provision topology/network/IAM;
- lấy snapshot và key;
- restore data/index/metadata;
- replay tới recovery point;
- validate, warm cache, đổi endpoint;
- reconcile writes phát sinh sau recovery point.

RPO phải gắn với failure mode. Snapshot mỗi ngày cho RPO 24 giờ; continuous oplog/PITR có thể giảm RPO, nhưng chỉ trong restore window đã cấu hình và khi log ingestion khỏe.

### 2.2. Recovery dependency inventory

Ngoài document data, ghi lại:

- MongoDB Server version, FCV và Database Tools version;
- replica set/sharded topology, shard IDs và zones;
- collection options, validators, indexes và users/roles;
- TLS CA/certificates, KMS/key-vault references và IAM recovery path;
- DNS, firewall/private endpoints và application connection settings;
- external source of truth, outbox/event offsets và reconciliation procedure.

Backup data mà mất Customer Master Key có thể trở thành dữ liệu không thể đọc.

---

## 3. Chọn backup method

| Method | Điểm mạnh | Giới hạn chính | Phù hợp |
|---|---|---|---|
| Atlas/Cloud Manager/Ops Manager | Coordinated snapshots, continuous log/PITR, hỗ trợ sharded consistency | Cost, platform dependency và policy phải cấu hình đúng | Production, đặc biệt sharded cluster |
| Filesystem/cloud-volume snapshot | Capture nhanh, restore bytes nhanh | Platform-specific; coordination phức tạp; không tự có PITR | Self-managed với storage snapshot chuẩn |
| `mongodump`/`mongorestore` | Logical BSON, chọn namespace, portable hơn physical files | Chậm/ảnh hưởng cache; không incremental; sharded cần lock/write stop | Deployment nhỏ, migration, partial recovery |
| `mongoexport`/`mongoimport` | JSON/CSV để trao đổi dữ liệu | Không phải deployment backup | Integration hoặc ad-hoc export |

Không có method tốt nhất cho mọi workload. Có thể kết hợp:

- managed snapshot + PITR cho disaster recovery;
- periodic logical dump cho selective recovery;
- immutable cross-region copy cho ransomware;
- frequent restore drills ở target cô lập.

---

## 4. Logical backup với `mongodump`

`mongodump` tạo BSON data cùng collection metadata/index definitions. Nó vẫn là online workload:

- scan collection và đọc nhiều disk/cache;
- có thể đẩy working set nóng khỏi RAM;
- dump lớn làm tăng backup window;
- không tự tạo continuous PITR;
- partial dump có thể phá consistency giữa các collection.

### 4.1. Replica set full dump có oplog

Ví dụ chạy từ host quản trị đã có CA và backup storage:

```bash
mongodump \
  --uri="mongodb://backup-agent@db-a.example.net,db-b.example.net,db-c.example.net/?replicaSet=rs0&authSource=admin&tls=true" \
  --tlsCAFile="/etc/mongodb/pki/ca.pem" \
  --archive="/secure-backup/rs0-2026-07-29.archive" \
  --gzip \
  --oplog
```

Không đặt password trực tiếp trong URI, shell history hay process arguments. Để tool prompt hoặc inject qua secret-management mechanism đã được kiểm soát.

`--oplog`:

- chỉ dùng với node có oplog, như replica set member;
- yêu cầu full dump;
- tạo top-level `oplog.bson` chứa writes xảy ra trong thời gian dump;
- không biến artifact thành continuous PITR sau khi dump kết thúc;
- không dùng cho toàn sharded cluster qua `mongos`.

Các DDL/user/role changes nhất định trong lúc dump có thể làm `--oplog` thất bại. Đặt change freeze cho schema và identity trong backup window.

### 4.2. Restore logical artifact

Restore vào **target cô lập/đã xác minh**, không mặc định overwrite production:

```bash
mongorestore \
  --uri="mongodb://restore-agent@restore-a.example.net/?authSource=admin&tls=true" \
  --tlsCAFile="/etc/mongodb/pki/ca.pem" \
  --archive="/secure-backup/rs0-2026-07-29.archive" \
  --gzip \
  --oplogReplay
```

`--oplogReplay` chỉ replay `oplog.bson` do `mongodump --oplog` tạo; nó không phải công cụ tùy ý để “nối” filesystem snapshot với một oplog bất kỳ.

Built-in `restore` role đủ cho nhiều restore thông thường, nhưng không đủ cho `--oplogReplay`. Oplog replay cần custom role rất rộng (`anyAction` trên `anyResource`); chỉ cấp cho restore identity tạm thời trong target cô lập rồi thu hồi ngay.

Checklist compatibility:

- dùng cùng Database Tools version cho dump và restore;
- ưu tiên cùng Server major version/FCV cho metadata, archive và oplog replay;
- không coi restore là shortcut để upgrade major version;
- nếu restore fail hoặc target rollback giữa chừng, làm sạch target và chạy lại từ đầu;
- chỉ dùng `--drop` sau khi xác minh chính xác target và chấp nhận destructive overwrite.

### 4.3. Partial restore

Selective namespace restore hữu ích khi một collection bị xóa, nhưng phải hỏi:

- collection khác có reference tới version mới hơn không?
- unique/index/validator đã được restore đúng chưa?
- outbox, ledger hoặc aggregate có cần rebuild không?
- writes sau recovery point sẽ merge hay bị ghi đè?

Partial restore là business merge problem, không chỉ là lệnh `mongorestore`.

---

## 5. Filesystem snapshot

Filesystem snapshot capture data files ở block/storage layer và thường nhanh hơn logical dump.

### Điều kiện an toàn

- journaling được bật;
- snapshot capture nhất quán mọi volume chứa data/journal cần thiết;
- nếu storage không cung cấp atomic multi-volume snapshot, dùng đúng quy trình quiesce/`fsyncLock()` theo phiên bản;
- snapshot secondary phải ghi nhận optime/lag vì có thể stale;
- không dùng `cp`/`rsync` trên live `dbPath` như một atomic backup;
- không mount rồi block-copy một filesystem đang hoạt động theo cách trái hướng dẫn của storage/MongoDB.

Quy trình khái niệm cho một replica set:

1. chọn member và xác nhận health/lag;
2. dừng competing maintenance/index build;
3. quiesce hoặc lock theo documented procedure;
4. tạo storage snapshot atomically;
5. unlock ngay cả khi snapshot command lỗi;
6. copy snapshot sang backup vault;
7. restore thử trên host cô lập;
8. đo optime và recovery gap.

Physical snapshot được restore bằng cách dựng `mongod` từ data files tương thích, không bằng `mongorestore`.

Nếu dùng encrypted storage engine, cold/hot restore và cipher mode có thêm key-rollover requirements. Luôn dùng procedure đúng phiên bản; không clone encrypted files/key tùy ý giữa process.

---

## 6. Backup sharded cluster

Sharded cluster có nhiều consistency boundary:

```text
Config metadata + Shard A + Shard B + ... + in-flight transactions
```

Snapshot một shard hoặc config server riêng lẻ không phải full-cluster backup.

### 6.1. Lựa chọn ưu tiên

Atlas, Cloud Manager và Ops Manager cung cấp coordinated backup/restore để giữ atomicity across shards trong khi cluster còn nhận writes. Đây thường là lựa chọn production an toàn hơn so với tự ghép snapshot.

### 6.2. Self-managed database dump

MongoDB 8.2 procedure yêu cầu:

1. chọn backup window;
2. dừng balancer và chờ migration hoàn tất;
3. dừng schema transformations;
4. lock cluster qua `mongos`, làm dừng writes;
5. xác nhận mọi shard/config component đã lock;
6. chạy `mongodump` qua `mongos`;
7. unlock trong `finally`/failure procedure;
8. bật lại balancer và xác minh.

```javascript
// Chỉ là các guard quan trọng; dùng full procedure chính thức khi vận hành.
sh.stopBalancer();
sh.getBalancerState();

db.getSiblingDB("admin").fsyncLock();

// ... mongodump qua mongos ...

db.getSiblingDB("admin").fsyncUnlock();
sh.startBalancer();
```

Không copy snippet này thành automation nếu chưa có timeout, failure cleanup, lock verification và operator escalation. Cluster bị quên ở trạng thái locked/balancer-off là một incident mới.

Khi restore dump vào sharded destination:

- `mongorestore` không tự shard collection;
- phải tạo/shard namespace ở target trước nếu cần giữ sharding;
- không restore `config` database như application data;
- kiểm tra shard key, zones, indexes và routing sau restore.

Filesystem snapshot cho sharded cluster còn phức tạp hơn: phải dừng writes/schema changes/balancer và capture config server cùng mọi shard theo procedure được hỗ trợ.

---

## 7. PITR và managed backup

Point-in-Time Recovery dùng base snapshot cộng continuous oplog history:

```text
Snapshot S ── oplog events ───────────────▶ Recovery time T
```

Để PITR thật sự đạt RPO:

- continuous backup đang bật;
- restore window dài hơn thời gian phát hiện sự cố;
- oplog ingestion không lag/lỗi;
- snapshot copy region cũng có oplog copy nếu cần regional PITR;
- operator biết timestamp/oplog point ngay trước bad write;
- KMS/network/IAM của restore target sẵn sàng.

Backup policy nên định nghĩa:

- hourly/daily/weekly/monthly frequency;
- retention theo legal và recovery needs;
- cross-region/cross-account copy;
- immutable/compliance lock;
- ai được thay policy, xóa snapshot hoặc chạy restore;
- alert khi snapshot/PITR stream thất bại.

Không restore trực tiếp lên cluster còn dữ liệu nếu platform sẽ xóa target trước restore. Restore sang cluster mới giúp so sánh, reconcile và rollback cutover an toàn hơn.

---

## 8. Backup không chống ransomware nếu attacker xóa được backup

Tách backup plane khỏi production plane:

- project/account/subscription khác khi khả thi;
- backup service identity khác application/DBA identity;
- immutable/WORM retention hoặc compliance policy;
- MFA và approval cho policy/delete/restore;
- keys giải mã backup lưu riêng khỏi backup artifact;
- ít nhất một copy ngoài primary region/failure domain;
- alert độc lập khi retention hoặc snapshot copy bị sửa.

Một biến thể thực dụng của nguyên tắc 3-2-1:

```text
3 copies
2 loại storage/control plane
1 copy offsite
+ 1 immutable/offline
+ 0 lỗi chưa phát hiện qua restore verification
```

Logical dump từ encrypted database có thể chứa plaintext BSON. Phải mã hóa artifact ở backup layer và bảo vệ transport, staging directory, logs cùng temporary files.

---

## 9. Restore drill và validation

### 9.1. Workflow chuẩn

```text
Declare incident
      ↓
Chọn clean recovery point
      ↓
Restore vào network cô lập
      ↓
Validate kỹ thuật + business
      ↓
Reconcile post-RPO writes
      ↓
Warm up + controlled cutover
      ↓
Giữ old environment để điều tra
```

### 9.2. Validate gì?

Technical:

- process khởi động sạch, replica set/shards healthy;
- collection count/options/indexes/validators đúng;
- users/roles/cert/KMS access đúng nhưng không mở quá quyền;
- sharded metadata, shard keys, zones và targeted routing đúng;
- không có restore error, unexpected duplicate hoặc index build failure.

Business:

- ledger/balance/inventory invariants;
- foreign references và outbox/event offsets;
- sample read/write workflows;
- canary account/tenant;
- reconciled changes từ recovery point đến cutover.

Đừng chỉ so document count. Hai dataset cùng count vẫn có thể khác state hoặc mất write quan trọng.

### 9.3. Drill schedule

Tối thiểu, tự động hóa:

- restore canary thường xuyên;
- full disaster-recovery drill theo quý hoặc theo risk;
- annual region/account-loss exercise;
- key-recovery drill không dùng cached credential;
- đo RPO/RTO thực tế và lưu evidence.

---

## 10. Threat model cho security

| Threat | Control chính | Control không đủ nếu đứng một mình |
|---|---|---|
| Network sniffing/MITM | TLS + hostname/CA validation | Private subnet |
| Stolen disk/snapshot | Encryption at rest + backup encryption | TLS |
| Over-privileged service | RBAC/least privilege | Encryption at rest |
| DBA/server memory đọc plaintext | Queryable Encryption/CSFLE | RBAC nếu DBA là superuser |
| App/KMS credential bị chiếm | Secret rotation, workload identity, isolation, detection | Field encryption |
| Xóa/ransomware | Immutable independent backup + PITR | Replica set |
| Insider/data exfiltration | Least privilege, audit, egress/detection | Một audit file cùng host |

Control phải đi cùng owner, metric và recovery procedure.

---

## 11. Authentication: ai đang kết nối?

Authentication xác minh identity. Authorization quyết định identity đó được làm gì.

MongoDB self-managed không bật access control mặc định. Production phải enable authorization và internal member authentication.

### 11.1. Bootstrap an toàn

- bootstrap trên isolated/private network;
- dùng localhost exception đúng một lần nếu chưa có user;
- tạo user administrator trước application users;
- dùng TLS ngay cả khi gọi `db.createUser()`: password được gửi qua connection;
- đóng bootstrap path sau khi first admin tồn tại;
- với replica set/sharded cluster, triển khai internal auth bằng keyfile hoặc X.509 theo rolling procedure.

```yaml
security:
  authorization: enabled
  keyFile: /run/secrets/mongodb-internal.key
```

Keyfile là shared internal secret: permission file phải chặt, distribution có audit và rotation runbook. X.509 cho member authentication tránh một shared secret nhưng thêm PKI/certificate lifecycle.

### 11.2. SCRAM và external identity

- SCRAM là cơ chế mặc định; ưu tiên `SCRAM-SHA-256` cho client hỗ trợ.
- X.509 dùng certificate subject làm user trong `$external`.
- OIDC/short-lived identity giúp giảm long-lived password ở môi trường hỗ trợ.
- LDAP authentication/authorization đã deprecated từ MongoDB 8.0 và dự kiến bị bỏ ở major version tương lai.

Authentication database là nơi user được tạo, không giới hạn database mà role có quyền. Vì vậy luôn cấu hình đúng `authSource`.

### 11.3. Không nhúng password

Tránh:

```text
mongodb://admin:plaintext-password@host/
```

Ưu tiên:

- secret manager/workload identity;
- `passwordPrompt()` cho thao tác người dùng;
- file/config injection có permission phù hợp;
- dual-credential rotation để không downtime;
- percent-encoding đúng nếu URI bắt buộc chứa reserved characters;
- không log URI đã có credential.

---

## 12. RBAC và least privilege

MongoDB role là tập privileges; nhiều role được **hợp lại**, role ít quyền hơn không phủ định role rộng đã có.

### 12.1. Tách identity theo workload

| Identity | Quyền điển hình |
|---|---|
| `orders-api` | `find/insert/update` đúng collection |
| `reporting-reader` | read-only trên reporting views/collections |
| `backup-agent` | built-in `backup` trên `admin` |
| `restore-agent` | chỉ cấp khi restore, không dùng thường trực |
| monitoring | `clusterMonitor` |
| human admin | time-bound/JIT, audited |

Không dùng chung một `root` credential cho application, monitoring và backup.

### 12.2. Custom role

```javascript
const sales = db.getSiblingDB("sales");

sales.createRole({
  role: "ordersApi",
  privileges: [
    {
      resource: { db: "sales", collection: "orders" },
      actions: ["find", "insert", "update"]
    }
  ],
  roles: []
});

sales.createUser({
  user: "orders-api",
  pwd: passwordPrompt(),
  roles: [{ role: "ordersApi", db: "sales" }],
  mechanisms: ["SCRAM-SHA-256"]
});
```

Tạo backup identity riêng:

```javascript
const admin = db.getSiblingDB("admin");

admin.createUser({
  user: "backup-agent",
  pwd: passwordPrompt(),
  roles: [{ role: "backup", db: "admin" }],
  mechanisms: ["SCRAM-SHA-256"]
});
```

`userAdmin*` có thể tạo/grant role và vì thế là quyền rất nhạy cảm. `directShardOperations` có từ MongoDB 8.0 nhưng chỉ dành cho maintenance trực tiếp trên shard; dùng sai có thể gây corruption.

Review định kỳ:

- orphaned users/roles;
- privilege chưa dùng;
- shared/service credentials;
- database wildcard hoặc `*AnyDatabase`;
- break-glass access;
- failed/successful admin authentication và role changes.

---

## 13. Network và TLS

Private network/IP access list/firewall giảm exposure nhưng không thay TLS hoặc authentication.

### 13.1. Server configuration

Ví dụ client dùng SCRAM, member traffic dùng X.509:

```yaml
net:
  bindIp: 127.0.0.1,mongo-a.internal.example.net
  tls:
    mode: requireTLS
    certificateKeyFile: /run/secrets/mongodb-server.pem
    clusterFile: /run/secrets/mongodb-member.pem
    CAFile: /etc/mongodb/pki/ca.pem
    allowConnectionsWithoutCertificates: true

security:
  authorization: enabled
  clusterAuthMode: x509
```

`allowConnectionsWithoutCertificates: true` không cho phép plaintext: `requireTLS` vẫn mã hóa mọi connection. Nó chỉ cho client không có certificate dùng cơ chế khác như SCRAM.

Production certificates:

- do trusted CA ký;
- SAN khớp hostname driver/member dùng;
- private key khác nhau theo host;
- EKU/KU phù hợp server/client role;
- có expiry/revocation monitoring;
- không bật `tlsAllowInvalidCertificates` hoặc invalid-hostname bypass.

### 13.2. Client connection

```bash
mongosh \
  "mongodb://orders-api@mongo-router.internal.example.net/sales?authSource=sales&tls=true" \
  --tlsCAFile="/etc/mongodb/pki/ca.pem"
```

Driver phải verify cả CA lẫn hostname. “Connection đã mã hóa” nhưng không xác minh server identity vẫn có rủi ro MITM.

### 13.3. Rotate certificate

MongoDB 5.0+ hỗ trợ online rotation:

1. thay file certificate/CA/CRL tại đúng path;
2. kết nối trực tiếp từng `mongod`/`mongos`;
3. chạy `db.rotateCertificates()`;
4. xác minh new connections dùng certificate mới;
5. chủ động drain/reconnect connection cũ khi security incident.

Existing connections tiếp tục dùng certificate cũ. Online rotate không tự thu hồi session đã tồn tại.

---

## 14. Encryption at rest

MongoDB Enterprise encrypted storage engine mã hóa WiredTiger data files. Atlas cung cấp encryption at rest và có tùy chọn customer-managed keys theo tier/configuration.

Self-managed Enterprise:

```yaml
security:
  enableEncryption: true
  kmip:
    serverName: kmip.internal.example.net
    port: 5696
    clientCertificateFile: /run/secrets/kmip-client.pem
    serverCAFile: /etc/mongodb/pki/kmip-ca.pem
```

Community deployment có thể dùng filesystem/device/cloud-volume encryption, nhưng threat boundary và key lifecycle thuộc storage platform.

Encryption at rest không bảo vệ trước:

- authenticated database superuser;
- process/root access khi database đang mở;
- plaintext logical dump;
- plaintext query/process/audit logs;
- network traffic không TLS.

Key management:

- tách key khỏi `dbPath` và backup artifact;
- mỗi node có key/database-key lifecycle đúng;
- ưu tiên remote KMIP/HSM cho production self-managed;
- hạn chế/ghi audit quyền decrypt;
- backup KMS configuration và test disaster recovery;
- diễn tập rotation, revocation và mất region;
- không xóa old key trước khi mọi artifact cần retention đã hết hạn hoặc re-encrypt.

---

## 15. Encryption in use: CSFLE và Queryable Encryption

Envelope encryption dùng:

```text
Customer Master Key (KMS)
          │ encrypts
          ▼
Data Encryption Key (key vault)
          │ encrypts
          ▼
Sensitive document fields
```

Database server chỉ giữ ciphertext cho field được bảo vệ; application/driver có quyền key mới thấy plaintext.

### 15.1. So sánh

| Cơ chế | Encryption | Query production | Điểm cần nhớ |
|---|---|---|---|
| CSFLE randomized | Randomized | Không query trực tiếp | Ít leakage hơn deterministic |
| CSFLE deterministic | Cùng plaintext → cùng ciphertext | Equality | Lộ frequency pattern |
| Queryable Encryption | Randomized + searchable metadata | Equality và range | Storage/write/query overhead |

Trong MongoDB 8.2, Queryable Encryption prefix/suffix/substring chỉ là public preview; không bật cho production. Một collection không dùng đồng thời CSFLE và Queryable Encryption.

### 15.2. Encryption schema

Ví dụ khái niệm cho Queryable Encryption equality:

```javascript
const encryptedFieldsMap = {
  "medical.patients": {
    fields: [
      {
        path: "ssn",
        bsonType: "string",
        keyId: dataKeyId,
        queries: { queryType: "equality" }
      },
      {
        path: "medicalRecord",
        bsonType: "object",
        keyId: medicalRecordKeyId
      }
    ]
  }
};
```

Đây không phải copy-paste production config. Cần chọn driver/crypt shared library/KMS, tạo key vault, server schema và IAM theo tutorial tương ứng.

### 15.3. Backup và vận hành

Phải bảo vệ đồng thời:

- encrypted collection;
- Queryable Encryption internal metadata collections và `__safeContent__`;
- key-vault collection;
- Customer Master Key/KMS policy;
- encryption schema/config.

Xóa/sửa QE internal metadata có thể làm query sai. Mất CMK hoặc key vault có thể làm ciphertext không thể giải mã.

Trước khi dùng:

- threat-model cả app host và KMS;
- benchmark payload/storage/index/write overhead;
- test query/operator/type limitations;
- thiết kế key rotation/revocation;
- bảo đảm logs/traces không ghi plaintext trước encryption hoặc sau decryption;
- restore drill gồm cả KMS/key-vault recovery.

---

## 16. Auditing, logs và detection

MongoDB Enterprise và Atlas M10+ auditing có thể ghi authentication, authorization và administrative events. Audit log không tự hữu ích nếu nằm cùng host và attacker có thể xóa.

Self-managed Enterprise example:

```yaml
auditLog:
  destination: file
  format: JSON
  path: /var/log/mongodb/audit.json
  filter: '{ atype: { $in: [ "authenticate", "createUser", "dropUser", "grantRolesToUser", "revokeRolesFromUser" ] } }'

security:
  redactClientLogData: true
```

`redactClientLogData` giảm nguy cơ PII xuất hiện trong process log nhưng cũng làm chẩn đoán khó hơn. Audit successful authorization cho mọi read/write có thể tạo volume và performance cost đáng kể; benchmark filter trên production-like workload.

Audit pipeline cần:

- gửi gần real-time tới SIEM/storage tách biệt, immutable;
- encryption in transit/at rest;
- clock synchronization;
- retention theo policy;
- alert cho auth failures, role/user changes, audit config changes, backup policy changes;
- bảo vệ chính audit reader/admin roles;
- health alert khi log pipeline bị ngắt.

Audit destination là dependency availability: nếu MongoDB Enterprise không thể ghi vào configured audit destination, server có thể terminate. Theo dõi disk/permission/collector health; cũng hiểu rằng abrupt termination có thể làm mất event chưa flush.

Ngoài audit, theo dõi:

- connection spike và source IP mới;
- query volume/data returned bất thường;
- large export/scan;
- failed backup, PITR lag và restore failure;
- KMS decrypt/deny/rotation events;
- TLS certificate sắp hết hạn;
- firewall/private endpoint thay đổi.

---

## 17. Hardening checklist

### Network và host

- [ ] Không public exposure ngoài nhu cầu đã phê duyệt.
- [ ] Firewall/private endpoint giới hạn cả inbound và admin path.
- [ ] `bindIp` cụ thể; hiểu rằng nó không thay firewall.
- [ ] OS/service account không chạy quyền root.
- [ ] Patch cadence, file permissions và host hardening có owner.
- [ ] Egress được kiểm soát để giảm exfiltration.

### Identity và authorization

- [ ] Access control và internal authentication được bật.
- [ ] Mỗi service có identity riêng, không shared root.
- [ ] SCRAM secret lấy từ secret manager hoặc dùng short-lived/external identity.
- [ ] Custom role bám đúng database/collection/actions.
- [ ] Human admin dùng MFA/JIT/break-glass có audit.
- [ ] User/role review và credential rotation có automation.

### Encryption

- [ ] `requireTLS` cho client và member traffic.
- [ ] CA/SAN/hostname validation hoạt động; không bypass invalid certificate.
- [ ] Certificate expiry/revocation/rotation đã diễn tập.
- [ ] Data files, backups, temp files và logs có encryption policy.
- [ ] KMS/key-vault IAM tách khỏi database IAM.
- [ ] Mất key và restore key đã được drill.

### Backup

- [ ] RPO/RTO/retention theo từng tier dữ liệu được phê duyệt.
- [ ] Backup/PITR success và lag có alert.
- [ ] Có cross-region và immutable copy.
- [ ] Backup deletion/policy change cần quyền/approval riêng.
- [ ] Restore target cô lập và runbook có owner.
- [ ] Full restore + business validation đạt RTO trong drill gần nhất.

---

## 18. Incident runbooks

### 18.1. Xóa nhầm hoặc bad deployment

1. dừng writer gây lỗi hoặc chuyển service read-only;
2. xác định operation và clean point ngay trước nó;
3. bảo toàn current state phục vụ reconciliation;
4. PITR/restore vào cluster mới;
5. validate kỹ thuật và business;
6. merge hợp lệ các write sau recovery point;
7. controlled cutover;
8. giữ evidence và sửa guardrail gây sự cố.

Không vội restore đè production; làm vậy có thể xóa luôn dữ liệu mới cần reconcile.

### 18.2. Credential bị lộ

1. cô lập source và chặn network path nếu cần;
2. preserve audit/process/KMS logs;
3. xác định identity, privileges và thời gian compromise;
4. revoke/disable hoặc dual-rotate credential;
5. terminate/reconnect session nếu control yêu cầu;
6. rà data read/write/delete và backup-policy changes;
7. rotate downstream secrets có thể bị lấy;
8. reconcile/restore nếu data bị sửa.

Password rotation không hoàn tác dữ liệu đã bị exfiltrate.

### 18.3. Certificate/private key bị lộ

1. revoke certificate/đưa vào CRL;
2. thay cert/key và rotate trên từng process;
3. drain existing connections vì chúng có thể còn dùng cert cũ;
4. kiểm tra subject đã có MongoDB user/role nào;
5. rà audit theo certificate identity;
6. rotate CA chỉ khi scope compromise đòi hỏi và có migration plan.

### 18.4. KMS/field-encryption key bị lộ hoặc mất

Nếu bị lộ:

- chặn IAM principal;
- preserve KMS audit;
- xác định CMK hay DEK bị ảnh hưởng;
- rewrap hay re-encrypt theo đúng loại key;
- kiểm tra snapshot/query transcript bị lấy cùng key hay không.

Nếu bị mất:

- không sửa ciphertext/internal metadata;
- khôi phục KMS/key vault từ independent recovery path;
- xác minh key ID/version;
- test decrypt trên isolated copy trước production.

---

## 19. Anti-patterns

### “Replica set là backup”

Replication sao chép cả xóa nhầm, corruption logic và malicious writes.

### “Backup job exit code 0 nghĩa là recover được”

Artifact có thể thiếu key, sai version, hỏng retention hoặc restore quá chậm. Cần restore drill.

### “`mongoexport` là backup”

Nó là JSON/CSV interchange tool, không phải deployment backup.

### “`mongodump --oplog` cho PITR của sharded cluster”

`--oplog` không dùng cho toàn sharded cluster qua `mongos`; sharded consistency cần coordinated procedure.

### “Encryption at rest bảo vệ khỏi DBA”

Khi database mở, authorized server/user vẫn đọc plaintext. Dùng least privilege và in-use encryption cho threat đó.

### “Private subnet nên không cần TLS/auth”

Internal compromise, misrouting và operator error vẫn tồn tại. Private network chỉ là một lớp.

### “Cho thêm role read-only sẽ giảm quyền”

Role privileges được union. Role hẹp không phủ định một role rộng đã được cấp.

### “KMS key nằm cùng backup cho tiện”

Attacker lấy artifact và key cùng lúc sẽ vượt qua encryption; mất cả hai cùng lúc cũng làm recovery thất bại.

---

## 20. Tóm tắt

1. Thiết kế backup từ RPO/RTO và restore workflow, không từ cron schedule.
2. `mongodump` hợp logical/small recovery; filesystem snapshot cần storage consistency; sharded cluster ưu tiên coordinated backup.
3. `--oplogReplay` chỉ đi với dump có `oplog.bson`, không phải generic PITR.
4. Backup phải độc lập, encrypted, cross-region và immutable trước ransomware.
5. Authentication, authorization, TLS, encryption và audit giải các threat khác nhau.
6. Queryable Encryption equality/range là production; text prefix/suffix/substring vẫn preview ở 8.2.
7. Keys, key vault và QE metadata là một phần bắt buộc của recovery.
8. Restore drill và incident drill mới biến tài liệu thành năng lực vận hành.

---

## Tài liệu chính thức

- [Backup Methods for a Self-Managed Deployment](https://www.mongodb.com/docs/v8.2/core/backups/)
- [Backup and Restore a Self-Managed Sharded Cluster](https://www.mongodb.com/docs/v8.2/administration/backup-sharded-clusters/)
- [Atlas Backup Policies](https://www.mongodb.com/docs/atlas/backup/cloud-backup/configure-backup-policy/)
- [`mongodump` Behavior](https://www.mongodb.com/docs/database-tools/mongodump/mongodump-behavior/)
- [`mongorestore` Behavior](https://www.mongodb.com/docs/database-tools/mongorestore/mongorestore-behavior-access-usage/)
- [Authentication](https://www.mongodb.com/docs/v8.2/core/authentication/)
- [Role-Based Access Control](https://www.mongodb.com/docs/v8.2/core/authorization/)
- [Built-In Roles](https://www.mongodb.com/docs/v8.2/reference/built-in-roles/)
- [Configure TLS](https://www.mongodb.com/docs/v8.2/tutorial/configure-ssl/)
- [Encryption at Rest](https://www.mongodb.com/docs/v8.2/core/security-encryption-at-rest/)
- [In-Use Encryption](https://www.mongodb.com/docs/v8.2/core/security-in-use-encryption/)
- [Queryable Encryption Features](https://www.mongodb.com/docs/v8.2/core/queryable-encryption/features/)
- [Auditing](https://www.mongodb.com/docs/v8.2/core/auditing/)
- [Security Checklist](https://www.mongodb.com/docs/v8.2/administration/security-checklist/)

---

## Hoàn thành learning path

> Đã chuẩn hóa 8 chủ đề MongoDB: data model → CRUD/aggregation → indexing → transactions → schema design → replication → sharding → backup/security.

*Cập nhật lần cuối: 2026-07-29*
