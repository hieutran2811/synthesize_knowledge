# Elasticsearch Security – thiết kế từ trust boundary

> Security không phải bật `xpack.security.enabled` rồi kết thúc. Một deployment an
> toàn phải trả lời được: ai đang gọi, credential lấy từ đâu, quyền hiệu lực cuối
> cùng là gì, dữ liệu tenant nào được thấy, transport nào được tin, sự kiện nào
> được audit và cách thu hồi quyền khi credential bị lộ.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Realm, DLS/FLS, audit,
cross-cluster security và một số cơ chế mã hóa phụ thuộc deployment hoặc
subscription. Kiểm tra capability/license thực tế trước khi thiết kế.

---

## 1. Threat model trước khi chọn setting

Tối thiểu phải xét:

| Tài sản | Tác nhân/rủi ro |
|---|---|
| Document và vector | đọc trái phép, inference qua search/aggregation |
| Credential/API key | lộ trong log, source code, CI artifact |
| Cluster state/config | sửa role, template, pipeline, lifecycle |
| Node transport | node giả tham gia cluster, MITM |
| HTTP endpoint | public exposure, brute force, stolen token |
| Snapshot/audit log | đọc/xóa/sửa ngoài Elasticsearch |
| Tenant boundary | IDOR, query thiếu tenant, role union làm rộng quyền |
| Availability | expensive query, bulk flood, privilege abuse |

Ghi rõ trust boundary:

```text
Browser
  │ HTTPS + SSO
  ▼
Kibana / Backend
  │ HTTPS + scoped credential
  ▼
Elasticsearch HTTP :9200
  │
  ├── transport TLS/mTLS :9300 giữa node
  ├── encrypted storage/snapshot
  └── audit log → hệ thống lưu trữ tách biệt
```

Không expose trực tiếp `:9200` ra Internet chỉ vì đã có password.

---

## 2. Security enabled khác security production-ready

Từ Elasticsearch 8.0, lần khởi động đầu của một node đủ điều kiện có thể tự:

- bật security;
- tạo certificate transport và HTTP;
- tạo password cho `elastic`;
- sinh enrollment token/fingerprint.

Auto-configuration là bootstrap tiện lợi, không thay threat model, network policy,
certificate lifecycle, least privilege hay audit.

Kiểm tra identity hiện tại:

```http
GET /_security/_authenticate
```

Kiểm tra TLS/API:

```powershell
curl.exe --cacert .\http_ca.crt `
  -u elastic `
  https://es-node-1.example.internal:9200/
```

Không dùng `-k`/`--insecure` trong production; nó bỏ xác minh danh tính endpoint.

---

## 3. Hai lớp TLS giải quyết hai boundary

| Lớp | Traffic | Mục tiêu |
|---|---|---|
| Transport TLS | node ↔ node, remote cluster | mã hóa và xác thực node |
| HTTP TLS | app/Kibana/operator ↔ Elasticsearch | bảo vệ request, response và credential |

Transport TLS là bắt buộc cho multi-node production khi security bật. HTTP TLS
được khuyến nghị cho mọi cluster, kể cả single-node.

```yaml
xpack.security.enabled: true

xpack.security.transport.ssl:
  enabled: true
  verification_mode: full
  client_authentication: required
  keystore.path: certs/transport.p12
  truststore.path: certs/transport.p12

xpack.security.http.ssl:
  enabled: true
  keystore.path: certs/http.p12
```

Password của keystore/truststore phải vào Elasticsearch keystore:

```powershell
bin\elasticsearch-keystore add xpack.security.transport.ssl.keystore.secure_password
bin\elasticsearch-keystore add xpack.security.transport.ssl.truststore.secure_password
bin\elasticsearch-keystore add xpack.security.http.ssl.keystore.secure_password
```

Không để secret trong `elasticsearch.yml`.

---

## 4. `verification_mode`: đừng chữa lỗi SAN bằng `none`

| Mode | Xác minh CA/chữ ký | Xác minh hostname/IP |
|---|---:|---:|
| `full` | Có | Có |
| `certificate` | Có | Không |
| `none` | Không | Không |

`full` là mục tiêu khi certificate có SAN đúng với publish address/DNS. Mode
`certificate` thường được dùng cho transport khi node certificate chia sẻ trust
domain nhưng không xác minh hostname; nó yếu hơn `full`. `none` chỉ là công cụ
chẩn đoán cực ngắn theo hướng dẫn hỗ trợ, không phải cách sửa production.

Certificate phải có:

- SAN DNS/IP đúng endpoint;
- EKU/key usage phù hợp;
- chain đầy đủ;
- thời hạn và rotation owner;
- CA tách theo trust domain nếu cần;
- private key permission tối thiểu.

---

## 5. Sinh certificate có inventory

Tạo CA và certificate bằng `elasticsearch-certutil` là một lựa chọn cho
self-managed:

```powershell
bin\elasticsearch-certutil ca --out config\certs\elastic-stack-ca.p12
```

File instance:

```yaml
instances:
  - name: es-master-1
    dns:
      - es-master-1.example.internal
    ip:
      - 10.10.1.11
  - name: es-data-1
    dns:
      - es-data-1.example.internal
    ip:
      - 10.10.2.11
  - name: kibana
    dns:
      - kibana.example.internal
```

```powershell
bin\elasticsearch-certutil cert `
  --ca config\certs\elastic-stack-ca.p12 `
  --in instances.yml `
  --out certs.zip
```

Không dùng một private key cho mọi node nếu quy trình PKI có thể cấp riêng. Inventory
cần serial, SAN, node/service owner, CA, ngày hết hạn và nơi deploy.

---

## 6. Rotation certificate không gây mất quorum

Đổi CA/certificate transport sai có thể chia cluster thành hai trust domain.
Quy trình an toàn:

1. thêm CA mới vào truststore nhưng vẫn giữ CA cũ;
2. rolling restart/reload theo capability và xác minh mọi node tin cả hai;
3. cấp/deploy certificate mới từng node;
4. kiểm tra node join, transport handshake và cluster green;
5. đổi client/Kibana trust cho HTTP CA;
6. chỉ gỡ CA cũ sau khi không còn certificate cũ;
7. có break-glass và rollback bundle.

Theo dõi:

```http
GET /_ssl/certificates
```

```http
GET /_cat/nodes?v=true&h=name,role,master,version
```

Không thay CA và certificate toàn cluster trong một lần restart nếu chưa drill.

---

## 7. TLS không mã hóa dữ liệu at rest

TLS bảo vệ khi truyền. Dữ liệu vẫn tồn tại trong:

- Lucene segment/translog;
- filesystem/page cache;
- snapshot repository;
- audit/application log;
- crash dump;
- client cache/export.

At-rest protection thường đến từ encrypted disk/volume, cloud KMS, repository
encryption, host hardening và access control. Snapshot phải có chính sách riêng;
TLS trên endpoint không bảo vệ object trong bucket.

Nếu cần field mà cluster không bao giờ thấy plaintext, mã hóa phía ứng dụng nhưng
chấp nhận mất khả năng search/aggregate thông thường. Không gọi disk encryption là
field-level encryption.

---

## 8. Identity cho người và workload

| Đối tượng | Lựa chọn thường phù hợp |
|---|---|
| Human qua Kibana | SAML/OIDC/LDAP/AD + MFA ở IdP |
| Backend/service tùy biến | scoped API key |
| Elastic internal service được định nghĩa sẵn | service account token |
| Break-glass self-managed | file/native realm account được kiểm soát |
| Node | transport certificate |
| Remote cluster | cross-cluster API key/trust model hiện hành |

Không dùng chung user/password cho nhiều service. Khi có sự cố sẽ không biết nguồn
gọi và không thể thu hồi riêng.

---

## 9. Built-in user không phải application account

Một số built-in user phục vụ bootstrap hoặc thành phần nội bộ:

- `elastic`: superuser bootstrap/emergency;
- `kibana_system`: Kibana gọi Elasticsearch;
- các `*_system`: thành phần Elastic tương ứng.

Không dùng `elastic` cho ứng dụng, dashboard hoặc automation thường ngày. Không
dùng `kibana_system` để đăng nhập browser.

Reset password self-managed khi có quyền host:

```powershell
bin\elasticsearch-reset-password -i -u elastic
```

Built-in role/user thay đổi theo version. Không copy danh sách cũ rồi coi là
contract; kiểm tra API và tài liệu target version.

---

## 10. Realm chain: authentication có thứ tự

Realm xác minh credential:

- `file`, `native`;
- LDAP/Active Directory;
- PKI;
- SAML/OIDC;
- Kerberos/JWT và cơ chế được deployment hỗ trợ.

Ví dụ self-managed có break-glass file/native và LDAP:

```yaml
xpack.security.authc.realms:
  file.file1:
    order: 0
  native.native1:
    order: 1
  ldap.corp:
    order: 2
    url: "ldaps://ldap.example.internal:636"
    bind_dn: "cn=elastic-bind,ou=svc,dc=example,dc=internal"
    user_search:
      base_dn: "ou=people,dc=example,dc=internal"
      filter: "(uid={0})"
    group_search:
      base_dn: "ou=groups,dc=example,dc=internal"
    ssl:
      certificate_authorities:
        - certs/ldap-ca.crt
```

Bind password:

```powershell
bin\elasticsearch-keystore add xpack.security.authc.realms.ldap.corp.secure_bind_password
```

Nếu tự cấu hình realm chain, khai báo rõ realm file/native muốn giữ. Test khi IdP/
LDAP unavailable và bảo vệ break-glass credential.

---

## 11. Authentication khác role mapping

Realm LDAP xác minh user và lấy group; role mapping là tài nguyên riêng:

```http
POST /_security/role_mapping/orders-analysts

{
  "enabled": true,
  "roles": [
    "orders_reader"
  ],
  "rules": {
    "all": [
      {
        "field": {
          "realm.name": "corp"
        }
      },
      {
        "field": {
          "groups": "cn=orders-analysts,ou=groups,dc=example,dc=internal"
        }
      }
    ]
  },
  "metadata": {
    "owner": "identity-team"
  }
}
```

Đặt role mapping dưới block realm như bài cũ là sai cấu trúc. Quản lý mapping bằng
API/UI hoặc role-mapping file đúng deployment.

SAML/OIDC thường phù hợp interactive login qua Kibana. Service không nên tự động
“đăng nhập SAML” thay cho API key.

---

## 12. Authorization là phép hợp

User có thể nhận role từ user record, realm mapping hoặc cơ chế khác. Quyền hiệu
lực là **union**:

```text
role_a grants orders-* read
role_b grants * read
effective = * read
```

Elasticsearch role không có “DENY thắng GRANT”. Một role hẹp không thu hồi quyền
rộng từ role khác.

Hệ quả:

- role “pii_hidden” không che PII nếu role khác cấp toàn field;
- DLS tenant không còn hiệu lực nếu role khác cấp cùng index không DLS;
- Kibana role rộng có thể phá data boundary;
- group lồng nhau ở IdP phải được audit.

Đánh giá **tập role cuối cùng**, không review từng role độc lập.

---

## 13. Tách reader, writer và operator

Reader:

```http
PUT /_security/role/orders_reader

{
  "cluster": [],
  "indices": [
    {
      "names": [
        "orders-read"
      ],
      "privileges": [
        "read",
        "view_index_metadata"
      ],
      "allow_restricted_indices": false
    }
  ],
  "metadata": {
    "owner": "orders-team",
    "environment": "prod"
  },
  "description": "Read the production orders alias"
}
```

Append-only writer:

```http
PUT /_security/role/orders_ingest

{
  "cluster": [],
  "indices": [
    {
      "names": [
        "orders-write"
      ],
      "privileges": [
        "create_doc",
        "view_index_metadata"
      ],
      "allow_restricted_indices": false
    }
  ],
  "description": "Create new order projection documents without overwrite"
}
```

`create_doc` không phù hợp nếu pipeline cần overwrite/update cùng `_id`; khi đó cấp
`index`/`write` có chủ đích và kiểm thử semantics. Quyền tạo index/template/ILM
thuộc deploy operator, không tự động trao cho runtime writer.

Operator monitor-only:

```http
PUT /_security/role/search_observer

{
  "cluster": [
    "monitor"
  ],
  "indices": [
    {
      "names": [
        "orders-*"
      ],
      "privileges": [
        "monitor",
        "view_index_metadata"
      ]
    }
  ],
  "description": "Observe cluster and order index health without data reads"
}
```

Không cấp `manage`, `all` hoặc `superuser` chỉ để một API hết 403. Tra đúng
privilege của API.

---

## 14. Index alias không mặc định là security boundary

Role nên trỏ vào alias/data stream ổn định khi phù hợp, nhưng:

- alias filter không thay DLS;
- người có quyền vào backing index có thể bỏ qua alias;
- người có `manage` alias/index có thể đổi boundary;
- wildcard có thể match index mới ngoài ý muốn;
- restricted/system index cần kiểm soát riêng.

Dùng naming convention versioned:

```text
orders-prod-read
orders-prod-write
orders-prod-v004
```

Test pattern khi tạo index mới và khi rollover/reindex.

---

## 15. Kiểm thử quyền bằng positive và negative test

Identity:

```http
GET /_security/_authenticate
```

Tự kiểm tra privilege:

```http
POST /_security/user/_has_privileges

{
  "cluster": [
    "monitor"
  ],
  "index": [
    {
      "names": [
        "orders-read"
      ],
      "privileges": [
        "read"
      ]
    },
    {
      "names": [
        "payments-*"
      ],
      "privileges": [
        "read"
      ]
    }
  ]
}
```

CI security contract phải xác nhận:

- API được phép trả 2xx;
- API không được phép trả 403;
- index/tenant khác không thấy dữ liệu;
- direct backing-index access bị từ chối;
- role mới không match index tương lai ngoài scope;
- error message/log không lộ secret.

Đừng chỉ test “đọc được orders”; test cả “không đọc được payments”.

---

## 16. Kibana Space và Elasticsearch privilege

Kibana Space cô lập saved object và feature experience trong Kibana. Nó không tự
giới hạn Elasticsearch index.

Role cho người dùng Kibana thường cần hai phần:

1. Kibana feature/space privilege, cấu hình qua Kibana role management;
2. Elasticsearch index privilege, cấu hình trên data view/index tương ứng.

Không tự viết application privilege tên `kibana-.kibana` hoặc
`feature_dashboard.read` trong Elasticsearch role API rồi giả định Kibana hiểu.
Kibana quản lý application/resource identifier của chính nó.

Một user có Space `orders` nhưng role Elasticsearch đọc `*` vẫn có thể truy vấn
dữ liệu rộng qua Dev Tools/API nếu quyền UI cho phép hoặc credential dùng trực tiếp.

---

## 17. API key: credential cho workload

Tạo key có expiration và scope:

```http
POST /_security/api_key

{
  "name": "orders-api-prod-2026q3",
  "expiration": "30d",
  "role_descriptors": {
    "orders_api": {
      "cluster": [],
      "indices": [
        {
          "names": [
            "orders-read"
          ],
          "privileges": [
            "read",
            "view_index_metadata"
          ]
        }
      ]
    }
  },
  "metadata": {
    "service": "orders-api",
    "environment": "prod",
    "owner": "orders-team",
    "rotation": "2026q3"
  }
}
```

Response chứa `api_key`/`encoded` secret chỉ một lần. Đưa trực tiếp vào secret
manager; không in CI log, ticket hay chat.

Sử dụng:

```text
Authorization: ApiKey <encoded>
```

Quyền hiệu lực là giao giữa quyền của principal tạo key và `role_descriptors`.
Key không thể tự mở rộng quyền vượt creator.

Nếu không đặt `expiration`, key mặc định không hết hạn. Production nên có TTL theo
khả năng rotation và recovery của hệ thống.

---

## 18. Rotation API key không downtime

```text
1. Tạo key B với scope bằng/nhỏ hơn key A
2. Lưu B trong secret manager
3. Deploy workload đọc B
4. Xác minh B bằng _authenticate + business smoke test
5. Quan sát A không còn được dùng
6. Invalidate A
7. Dọn key expired/invalidated theo policy
```

Xác minh key hiện tại:

```http
GET /_security/_authenticate
```

Liệt kê key của principal:

```http
GET /_security/api_key?owner=true
```

Invalidate theo ID:

```http
DELETE /_security/api_key

{
  "ids": [
    "api-key-id-old"
  ]
}
```

Đừng rotate bằng cách overwrite cùng secret rồi restart mọi replica cùng lúc.
Phải có overlap ngắn, health check và rollback về key A trước khi invalidate.

---

## 19. API key lifecycle và ownership

Mỗi key cần:

- một service + environment;
- owner/on-call;
- scope/index pattern;
- issue/expiry/rotation time;
- nơi lưu secret;
- last-used signal nếu deployment cung cấp;
- incident revocation procedure.

Key cá nhân không nên chạy workload dài hạn: khi user rời team hoặc quyền creator
đổi, ownership trở nên khó quản lý. Dùng automation identity được kiểm soát để cấp
key, nhưng không trao `manage_api_key` rộng cho runtime.

API key tạo bởi API key khác có hạn chế đặc biệt: key con không thể nhận role
descriptor có privilege. Thiết kế issuer riêng thay vì chuỗi key tự sinh.

---

## 20. Service account token không dành cho mọi ứng dụng

Elasticsearch service account là principal được định nghĩa sẵn cho một số dịch vụ
Elastic. Role của nó cố định trong code và token có thể thu hồi.

Không tạo “service account tùy ý” cho microservice như với cloud IAM. Với ứng dụng
tùy biến, scoped API key thường đúng hơn.

Không dùng service token, enrollment token và API key như từ đồng nghĩa:

| Token | Mục đích |
|---|---|
| Enrollment token | bootstrap Kibana/node trong thời gian ngắn |
| Service account token | Elastic service account định nghĩa sẵn |
| Elasticsearch API key | workload/API access có scope |
| SAML/OIDC access token | session/federated human flow |

---

## 21. DLS và FLS chỉ dành cho read-only principal

Field-level security giới hạn field được đọc; document-level security giới hạn
document được đọc.

```http
PUT /_security/role/orders_apac_analyst

{
  "cluster": [],
  "indices": [
    {
      "names": [
        "orders-read"
      ],
      "privileges": [
        "read",
        "view_index_metadata"
      ],
      "field_security": {
        "grant": [
          "order_id",
          "status",
          "amount_minor",
          "region",
          "@timestamp"
        ]
      },
      "query": {
        "term": {
          "region": "APAC"
        }
      }
    }
  ]
}
```

Không cấp write cho principal có DLS/FLS:

- DLS/FLS được thiết kế cho read-only access;
- update/bulk update và các API đổi tên/copy index có limitation;
- DLS không phải write predicate/RLS để bảo vệ document ghi;
- application phải validate tenant write và dùng credential writer riêng.

---

## 22. DLS/FLS role union trap

```text
role tenant_17:
  orders-* read + DLS tenant_id=17

role support_reader:
  orders-* read không DLS

user có cả hai
  → đọc toàn bộ document orders-*
```

Tương tự, một role FLS chỉ grant vài field kết hợp role khác không FLS có thể mở
toàn bộ field.

Nếu restriction là boundary nghiêm ngặt:

- tránh chồng role cùng index;
- tạo identity/credential riêng theo persona;
- cân nhắc index/cluster/cell riêng;
- chạy effective privilege và negative data test;
- audit IdP group membership.

DLS vẫn có limitation/inference surface qua global index statistics, field/term
metadata và query feature. Không quảng cáo nó như chống mọi side channel.

---

## 23. DLS theo tenant metadata

Role query template có thể lấy metadata của authenticated user:

```http
PUT /_security/role/tenant_orders_reader

{
  "cluster": [],
  "indices": [
    {
      "names": [
        "orders-shared"
      ],
      "privileges": [
        "read",
        "view_index_metadata"
      ],
      "query": {
        "template": {
          "source": "{\"term\":{\"tenant_id\":\"{{_user.metadata.tenant_id}}\"}}"
        }
      }
    }
  ]
}
```

User/realm phải cung cấp metadata đáng tin:

```http
PUT /_security/user/tenant17_analyst

{
  "password": "replace-through-secret-channel",
  "roles": [
    "tenant_orders_reader"
  ],
  "metadata": {
    "tenant_id": "tenant-17"
  }
}
```

Không cho user tự sửa tenant metadata. Test missing/null/malformed metadata và
không dùng `now` trong DLS date range.

---

## 24. Chọn mô hình multi-tenant

| Mô hình | Isolation | Chi phí/giới hạn |
|---|---:|---|
| Cluster/cell riêng | cao nhất | vận hành và capacity cao |
| Index/data stream riêng | cao | shard/cluster-state explosion nếu tenant nhỏ |
| Nhóm tenant theo cell/index | cân bằng | routing/migration phức tạp |
| Shared index + DLS | logic/read-only | role-union, inference, query overhead |
| App thêm tenant filter | không phải security boundary ES | bug/credential rộng gây cross-tenant |

Alias filter hoặc app filter không thay authorization. Với dữ liệu pháp lý/nhạy
cảm, isolation vật lý hoặc cell thường dễ chứng minh hơn shared DLS.

Tenant lớn/noisy neighbor còn cần quota, routing và rate limit; RBAC không bảo vệ
availability.

---

## 25. `run_as` là impersonation có kiểm soát

Role cho support service:

```http
PUT /_security/role/support_impersonator

{
  "cluster": [],
  "indices": [],
  "run_as": [
    "tenant-support-*"
  ],
  "description": "Allow the support gateway to run as approved support identities"
}
```

Request:

```text
es-security-runas-user: tenant-support-17
```

Principal gốc phải authenticate và có `run_as`; user đích cung cấp role hiệu lực.
Audit phải giữ cả authenticating và run-as identity.

Không dùng impersonation để tránh tạo model authorization rõ ràng. Giới hạn
pattern, approval, session duration và lý do truy cập.

---

## 26. Restricted/system index

Các index hệ thống chứa security/Kibana/Fleet state. Chỉ internal system role nên
thường xuyên truy cập.

`allow_restricted_indices: true` là công tắc nguy hiểm và chỉ có tác dụng cùng
privilege/name match phù hợp. Không thêm nó chỉ vì wildcard `*` trả 403.

Không cho application role đọc `.security*`, `.kibana*` hoặc hidden index. Dùng
API công khai thay vì đọc trực tiếp internal index; schema nội bộ không phải
contract.

Snapshot/restore feature state có thể ghi đè security index và khóa operator.
Xem [Cluster Management §18–20](cluster_management.md).

---

## 27. Remote cluster cần credential riêng

Cross-cluster search và CCR mở thêm trust boundary:

- remote cluster identity;
- `remote_cluster` và `remote_indices` privilege;
- cross-cluster API key scope;
- network/TLS;
- local role và remote key intersection;
- DLS/FLS chỉ hỗ trợ một số flow.

Không dùng một key cho cả search DLS và replication nếu capability không hỗ trợ.
Tách remote connection/key theo mục đích.

CCR replication không hỗ trợ DLS/FLS như search. Follower chứa dữ liệu đã replicate
và phải có authorization riêng.

---

## 28. Network exposure và proxy

Defense in depth:

- private endpoint/VPC/VNet khi có thể;
- firewall/security group chỉ cho client/subnet cần thiết;
- TLS xác minh đầy đủ;
- load balancer/proxy có timeout/body/rate limit hợp lý;
- Elasticsearch vẫn authenticate/authorize, không chỉ tin proxy;
- transport port chỉ giữa node/remote cluster được phép;
- egress giới hạn cho snapshot/LDAP/IdP theo nhu cầu.

`network.host` là bind/publish configuration, không phải firewall.

CORS mặc định nên tắt. Nếu browser thật sự gọi trực tiếp Elasticsearch:

- exact origin, không `*` với credential;
- phương thức/header tối thiểu;
- hiểu API key/password sẽ tồn tại phía browser;
- ưu tiên backend-for-frontend để giữ credential và policy.

IP allowlist không thay identity; NAT/proxy và compromised host vẫn có thể gọi.

---

## 29. Secret management

Không đặt secret trong:

- Git/repository;
- Docker image/layer;
- environment dump;
- command line dễ lộ process list;
- application log;
- exception/HTTP trace;
- ticket/chat;
- Terraform state không mã hóa/giới hạn.

Phân lớp:

| Secret | Nơi phù hợp |
|---|---|
| Node keystore password, realm bind password | Elasticsearch keystore/secret integration |
| Application API key | secret manager + workload identity |
| TLS private key | file/secret volume permission chặt |
| Snapshot cloud credential | instance/workload role hoặc secure keystore |
| Break-glass | vault có dual control và audit |

Rotation phải được diễn tập trước expiry. Alert certificate/key expiry theo lead
time đủ để rollout.

---

## 30. Audit logging

Audit log ghi security event như authentication failure, access denied, run-as và
security configuration change. Nó bị tắt mặc định và có thể phụ thuộc
subscription.

Self-managed bật trên **mọi node**:

```yaml
xpack.security.audit.enabled: true
```

Ví dụ chọn event:

```yaml
xpack.security.audit.logfile.events.include:
  - authentication_failed
  - realm_authentication_failed
  - anonymous_access_denied
  - access_denied
  - run_as_granted
  - run_as_denied
  - tampered_request
  - security_config_change
```

Elasticsearch ghi file `<clustername>_audit.json` trên từng node. Không có REST
endpoint `GET _security/audit/log`. Orchestrated deployment phải cấu hình ship log
ra nơi người vận hành truy cập được.

Audit Kibana và Elasticsearch là hai nguồn khác nhau; bật cả hai nếu cần theo dõi
human action qua UI.

---

## 31. Audit log cũng là dữ liệu nhạy cảm

Một client request có thể sinh nhiều event trên nhiều node. Audit có trade-off
volume/I/O và có thể chứa:

- username, realm, source IP;
- index/action;
- run-as identity;
- request identifier;
- nếu bật request body, dữ liệu nhạy cảm dạng plaintext.

Không bật `emit_request_body` toàn cục mà không privacy review. Security API lọc
một số credential không có nghĩa mọi payload an toàn.

Audit pipeline cần:

- ship gần real-time sang hệ thống tách biệt;
- append-only/immutability và retention;
- clock synchronization;
- access ít hơn production admin;
- correlation bằng `X-Opaque-Id`/trace/client metadata;
- alert có baseline, tránh chỉ lưu mà không xem;
- giám sát chính pipeline audit bị ngắt.

---

## 32. Sự kiện cần cảnh báo

| Signal | Ý nghĩa có thể |
|---|---|
| Authentication failure tăng | secret hết hạn, brute force, deploy sai |
| Access denied tăng sau release | role/index pattern thiếu hoặc hành vi lạ |
| `security_config_change` ngoài window | privilege escalation |
| Superuser dùng cho app traffic | credential/model sai |
| API key tạo hàng loạt | issuer bị lạm dụng |
| Run-as bất thường | support impersonation abuse |
| TLS handshake/cert error | expiry, CA/SAN, client lạ |
| Audit silence | pipeline/logging bị tắt hoặc node mất log |

Threshold phải theo rate, identity và source, không hard-code “N lần” cho mọi hệ
thống.

---

## 33. Runbook authentication failure

1. Xác định 401 hay TLS failure trước HTTP.
2. Gọi `_security/_authenticate` bằng credential trong kênh an toàn.
3. Kiểm tra:
   - key expired/invalidated;
   - password/token sai;
   - realm order/cache/IdP/LDAP;
   - clock skew;
   - header bị proxy loại;
   - service đang dùng secret version nào.
4. So audit log theo principal/source.
5. Rotate/recover credential theo runbook, không cấp superuser tạm.
6. Negative-test sau sửa và thu hồi credential cũ.

401 = chưa authenticate được. 403 = đã có identity nhưng thiếu authorization.
Không chữa 403 bằng reset password.

---

## 34. Runbook certificate/TLS failure

Triệu chứng:

- hostname verification failed;
- unknown CA/untrusted chain;
- certificate expired/not yet valid;
- no cipher/protocol;
- transport node không join;
- client chỉ chạy được với `-k`.

Kiểm tra:

```http
GET /_ssl/certificates
```

Ngoài cluster dùng công cụ TLS để kiểm tra chain/SAN/expiry. Xác định lớp HTTP hay
transport.

Không đổi `verification_mode: none`. Sửa:

- endpoint dùng đúng SAN;
- deploy full chain/trust CA;
- đồng bộ clock;
- trust overlap khi rotate CA;
- rolling node, giữ voting majority;
- cập nhật client truststore trước khi gỡ CA cũ.

---

## 35. Runbook API key bị lộ

1. Xác định key ID/principal/scope/owner.
2. Invalidate ngay nếu blast radius chấp nhận được; nếu critical service, phát key
   mới và cutover khẩn có kiểm soát.
3. Tìm audit log từ thời điểm có thể bị lộ:
   - source IP;
   - action/index;
   - data read/write;
   - key khác được tạo;
   - security config change.
4. Thu hồi credential downstream có thể bị lộ.
5. Reconcile dữ liệu bị ghi/xóa và restore nếu cần.
6. Sửa nguồn leak, secret scanning và logging redaction.
7. Rút ngắn TTL/scope, tách key theo service/environment.

Đổi name/metadata không đổi secret. Invalidate key cũ là bước bắt buộc.

---

## 36. Runbook privilege escalation

Khi thấy role/user/mapping/API key đổi trái phép:

- bảo toàn audit log ngoài cluster;
- khóa/invalidate identity nghi ngờ;
- chụp role, role mapping, API key metadata và effective privilege;
- tìm thay đổi restricted index, snapshot repository, pipeline/template/script;
- kiểm tra persistence ở IdP group, file realm/role, orchestrator secret;
- rotate admin/break-glass credential theo phạm vi;
- restore/reconcile cấu hình từ nguồn versioned;
- không xóa evidence trước forensic.

Nếu attacker có superuser, giả định có thể đọc/sửa dữ liệu và tạo persistence;
không chỉ revert role vừa thấy.

---

## 37. Backup và break-glass

Snapshot full có thể chứa security feature state nhưng không chứa:

- repository registration;
- node config;
- filesystem realm files;
- keystore/private key bên ngoài;
- mọi cloud/network/IAM configuration.

Restore `security` feature state ghi đè authentication data và có thể làm mất
quyền truy cập. DR cần:

- file-realm break-glass hoặc platform console;
- CA/certificate/private-key backup đúng policy;
- encrypted config backup;
- repository credential recovery;
- restore drill với security state;
- dual control và audit khi dùng break-glass.

Break-glass chưa test không phải recovery plan.

---

## 38. Security change management

Mỗi thay đổi role/realm/TLS/audit cần:

- threat/risk ticket và owner;
- current effective privilege snapshot;
- positive + negative test;
- canary identity/service;
- rollback không làm mở quyền rộng;
- audit event xác nhận;
- expiry cho temporary privilege;
- review sau rollover/reindex/index mới;
- review deployment/subscription compatibility.

Role và mapping nên được version hóa dạng desired state, nhưng secret không vào
Git. Reconcile drift từ API với source-of-truth.

---

## 39. Anti-pattern

### 39.1 Application dùng `elastic`

Blast radius toàn cluster, không phân attribution và khó rotate. Dùng scoped API
key.

### 39.2 Role hẹp “ghi đè” role rộng

Sai vì role union. Xóa quyền rộng hoặc tách identity.

### 39.3 Shared DLS role có quyền write

DLS/FLS dành cho read-only principal. Dùng writer credential và tenant validation
riêng.

### 39.4 Kibana Space = data isolation

Space không tự thu hẹp Elasticsearch index privilege.

### 39.5 Alias filter = authorization

Credential đọc backing index có thể bypass. Dùng RBAC/DLS hoặc isolation vật lý.

### 39.6 Tắt verification để hết lỗi TLS

Biến encryption thành kết nối không xác minh peer. Sửa CA/SAN/chain.

### 39.7 API key không expiration

Key mặc định không hết hạn. Đặt TTL và rotation phù hợp.

### 39.8 Audit nằm cùng nơi admin có thể xóa

Attacker/admin bị compromise có thể xóa dấu vết. Ship sang boundary tách biệt.

### 39.9 Cấp `manage` khi thiếu một API

Privilege quá rộng gồm nhiều thao tác index lifecycle. Tra privilege tối thiểu và
negative-test.

### 39.10 CORS dùng thay authentication

CORS là browser policy, không ngăn curl/service gọi endpoint.

---

## 40. Checklist production

### Network và TLS

- [ ] HTTP và transport TLS bật, client không dùng `--insecure`?
- [ ] SAN/CA/chain đúng và verification mode không phải `none`?
- [ ] Port 9200/9300 chỉ mở cho source cần thiết?
- [ ] Certificate inventory, expiry alert và CA rotation drill có sẵn?
- [ ] At-rest/snapshot encryption được thiết kế riêng?

### Identity và secret

- [ ] Human dùng SSO/MFA nơi phù hợp; service dùng key riêng?
- [ ] Không application nào dùng `elastic` hoặc `*_system`?
- [ ] Realm order, role mapping và IdP outage đã test?
- [ ] Secret nằm trong keystore/secret manager và log được redact?
- [ ] API key có owner, scope, TTL, rotation và revoke runbook?
- [ ] Break-glass có dual control, audit và drill?

### Authorization và tenant

- [ ] Reader/writer/operator tách role?
- [ ] Review effective role union thay vì từng role?
- [ ] Positive và negative privilege/data test chạy trong CI?
- [ ] DLS/FLS principal chỉ read-only và không có role rộng chồng lên?
- [ ] Kibana Space không bị coi nhầm là data boundary?
- [ ] Restricted/system index không cấp cho application?
- [ ] Rollover/reindex/index mới không mở rộng wildcard ngoài ý muốn?

### Audit và incident

- [ ] Audit Elasticsearch/Kibana bật theo requirement/subscription?
- [ ] Log ship sang nơi tách biệt, immutable và có retention?
- [ ] Request body audit đã privacy review hoặc đang tắt?
- [ ] Alert auth failure, access denied, config change, key creation và audit silence?
- [ ] Runbook key leak, TLS expiry và privilege escalation đã diễn tập?
- [ ] Snapshot security feature state và config ngoài cluster đều được backup?

---

## 41. Câu hỏi phỏng vấn

1. Transport TLS và HTTP TLS bảo vệ hai boundary nào?
2. Vì sao `verification_mode: none` nguy hiểm dù traffic vẫn mã hóa?
3. Native/file/LDAP/SAML/OIDC realm khác role mapping thế nào?
4. Quyền từ nhiều role được kết hợp ra sao?
5. Vì sao một role DLS hẹp có thể bị role khác vô hiệu?
6. Kibana Space có phải ranh giới dữ liệu không?
7. Quyền API key được tính từ creator và role descriptor thế nào?
8. Vì sao API key nên có TTL dù có thể invalidate?
9. DLS/FLS có dùng để bảo vệ write được không?
10. `run_as` khác dùng chung credential thế nào?
11. Audit log nằm ở đâu và vì sao không có REST API đọc audit?
12. Bạn rotate transport CA không làm cluster mất quorum như thế nào?
13. Shared-index multi-tenancy khác cell/index-per-tenant ở failure mode nào?
14. Restore security feature state có thể khóa operator ra sao?

---

## 42. Nguồn và hoàn tất roadmap

Nguồn chính thức:

- [Secure a cluster or deployment](https://www.elastic.co/docs/deploy-manage/security)
- [Self-managed security setup](https://www.elastic.co/docs/deploy-manage/security/self-setup)
- [Minimal security setup](https://www.elastic.co/docs/deploy-manage/security/set-up-minimal-security)
- [Set up HTTPS](https://www.elastic.co/docs/deploy-manage/security/set-up-basic-security-plus-https/)
- [Users and roles](https://www.elastic.co/docs/deploy-manage/users-roles)
- [Role structure](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/role-structure)
- [LDAP authentication](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/ldap)
- [Elasticsearch API keys](https://www.elastic.co/docs/deploy-manage/api-keys/elasticsearch-api-keys)
- [Document and field level security](https://www.elastic.co/docs/deploy-manage/users-roles/cluster-or-deployment-auth/controlling-access-at-document-field-level)
- [Enable audit logging](https://www.elastic.co/docs/deploy-manage/security/logging-configuration/enabling-audit-logs)
- [Configure audit logging](https://www.elastic.co/docs/deploy-manage/security/logging-configuration/configuring-audit-logs)

Ôn lại:

1. [Cluster Management](cluster_management.md) – snapshot security state,
   certificate-aware upgrade và incident recovery.
2. [Indexing & Mapping](../fundamentals/indexing_mapping.md) – alias/data stream
   và versioned migration.
3. [Query DSL](../fundamentals/query_dsl.md) – expensive query, partial result và
   search correctness.
4. [Performance](../performance/optimization.md) – rate limit, resource isolation
   và backpressure.

---

*Cập nhật lần cuối: 2026-07-31.*
