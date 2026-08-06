# PostgreSQL Security & Row-Level Security

> Mục tiêu: bảo vệ PostgreSQL 18 theo nhiều lớp, từ đường truyền và danh tính đến
> quyền trên object và ranh giới từng row. Chương này ưu tiên các mẫu có thể vận
> hành được trong production, đặc biệt với SaaS multi-tenant.

---

## 1. Security không phải một cấu hình duy nhất

Một kết nối thành công chưa có nghĩa là nó nên đọc được mọi dữ liệu. Ngược lại,
RLS đúng cũng không bảo vệ password bị lộ hoặc traffic không được xác minh TLS.

```text
Client / workload identity
          │
          ▼
Network boundary + TLS certificate
          │
          ▼
pg_hba.conf: nguồn nào được thử cơ chế xác thực nào?
          │
          ▼
Authentication: SCRAM / certificate / OAuth / peer
          │
          ▼
Role membership + ownership + object privilege
          │
          ▼
RLS policy: role này thấy và ghi được row nào?
          │
          ▼
Audit + alert + rotation + incident response
```

Mỗi lớp trả lời một câu hỏi khác nhau:

| Lớp | Câu hỏi | Sai lầm thường gặp |
|---|---|---|
| Network/TLS | Có đúng server và đường truyền được mã hóa không? | Dùng `sslmode=require` rồi tưởng đã xác minh hostname |
| HBA | Kết nối từ đâu được thử auth nào? | Đặt rule rộng phía trên rule hẹp |
| Authentication | Ai đang chứng minh danh tính? | Còn dùng MD5 hoặc password nằm trong URL/log |
| Authorization | Role được làm gì với object? | Runtime role sở hữu table hoặc có quyền qua `PUBLIC` |
| RLS | Role thấy/sửa row nào? | Bật RLS nhưng owner vẫn bypass; chỉ viết `USING` mà quên `WITH CHECK` |
| Operations | Có phát hiện, thu hồi và điều tra được không? | Log mọi bind parameter, vừa tốn disk vừa lộ PII/secret |

**Mental model:** defense in depth không có nghĩa mỗi lớp thay thế lớp khác. TLS
không thay authorization; RLS không thay constraint; audit không ngăn tấn công;
encryption không sửa được quyền cấp quá rộng.

---

## 2. Threat model trước khi viết GRANT

Trước khi cấu hình, ghi rõ ít nhất các actor sau:

1. Application runtime bình thường.
2. Migration/deployment job.
3. Read-only analyst hoặc BI tool.
4. DBA/SRE vận hành.
5. Replication, backup và monitoring agent.
6. Tenant/user độc hại nhưng dùng API hợp lệ.
7. Credential bị lộ hoặc host ứng dụng bị chiếm.
8. Người có quyền cloud/OS/storage nhưng không nên đọc plaintext.

Sau đó xác định asset và boundary:

- PII, payment, token, audit record và encryption key nằm ở đâu?
- Database dùng chung nhiều tenant hay mỗi tenant một database/schema?
- Client có kết nối trực tiếp database không, hay luôn qua trusted backend?
- Ai có thể đổi `pg_hba.conf`, certificate, role membership, policy và extension?
- Backup, WAL archive, replica, log và temporary file có cùng mức bảo vệ không?
- Superuser/cloud admin có nằm ngoài rủi ro chấp nhận được không?

Nếu không trả lời được các câu này, một danh sách `GRANT` dài thường chỉ tạo cảm
giác an toàn giả.

---

## 3. Shared responsibility

Trên self-managed PostgreSQL, đội vận hành chịu trách nhiệm cả OS, file permission,
certificate, patch và database. Trên managed service, provider có thể quản lý host
và control plane, nhưng khách hàng vẫn thường chịu trách nhiệm:

- network policy/security group/private endpoint;
- database role, password, HBA tương đương hoặc parameter được provider cho phép;
- schema privilege, RLS và application identity;
- KMS/key policy, backup retention, log export và alert;
- kiểm tra tính năng nào là PostgreSQL core, extension hay dịch vụ riêng của provider.

Không sao chép nguyên runbook self-managed sang cloud nếu provider đã thay đổi
superuser, file system, certificate rotation hoặc log pipeline.

---

## 4. TLS: mã hóa và xác minh đúng endpoint

Server self-managed cần bật TLS và trỏ tới certificate/key:

```conf
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root-ca.crt'
```

Sau đó chỉ cho workload production đi qua `hostssl` trong `pg_hba.conf`. Certificate
server phải có SAN phù hợp hostname mà client dùng và private key phải chỉ tài khoản
dịch vụ PostgreSQL đọc được.

Phía libpq/driver, lựa chọn an toàn cho kết nối nhạy cảm là:

```text
sslmode=verify-full
sslrootcert=/path/to/trusted-root-ca.pem
```

`verify-ca` xác minh certificate chain nhưng không chắc hostname đúng. `verify-full`
xác minh cả chain lẫn hostname/IP. `require` chỉ yêu cầu encryption trong cấu hình
thông thường; nó không diễn đạt rõ yêu cầu chống giả mạo server. Đừng dựa vào hành
vi tương thích ngược giữa `require` và sự hiện diện của root certificate.

Ví dụ URI không nhúng password:

```text
postgresql://orders-api@db.internal.example/orders
  ?sslmode=verify-full
  &sslrootcert=/run/secrets/postgres-ca.pem
```

TLS không bảo vệ:

- plaintext sau khi đã vào server/process;
- data file, WAL, backup và log ở trạng thái lưu trữ;
- client/server đã bị chiếm quyền;
- query hợp lệ nhưng role được cấp quá nhiều quyền.

---

## 5. Kiểm tra TLS đang dùng thật

`pg_stat_ssl` có một row cho mỗi backend hoặc WAL sender đang kết nối:

```sql
SELECT a.pid,
       a.usename,
       a.application_name,
       a.client_addr,
       s.ssl,
       s.version,
       s.cipher,
       s.bits,
       s.client_dn,
       s.issuer_dn
FROM pg_stat_activity AS a
JOIN pg_stat_ssl AS s USING (pid)
WHERE a.backend_type = 'client backend'
ORDER BY a.usename, a.application_name;
```

Đừng chỉ kiểm tra một kết nối từ laptop. Kiểm tra từng đường đi thực tế: application,
pooler, migration job, monitoring, backup và replication. Nếu có PgBouncer/proxy thì
TLS client → proxy và proxy → PostgreSQL là hai hop độc lập.

---

## 6. Mutual TLS và certificate authentication

`hostssl` có thể yêu cầu client certificate được CA tin cậy xác minh:

```conf
hostssl orders app_runtime 10.20.0.0/16 scram-sha-256 clientcert=verify-full
```

Hoặc dùng phương thức `cert`, trong đó certificate client là credential chính. Có
thể dùng `pg_ident.conf` để map certificate identity sang database role.

Ưu điểm của mTLS là workload phải có cả private key hợp lệ. Đổi lại, đội vận hành
phải làm tốt issuance, short lifetime, revocation/CRL, rotation, clock và mapping
identity. Certificate hết hạn vào 02:00 vẫn là outage dù SQL hoàn toàn đúng.

---

## 7. `pg_hba.conf`: first match wins

PostgreSQL đọc record từ trên xuống. **Record đầu tiên khớp** connection type,
database, user và address sẽ quyết định phương thức auth. Nếu auth của record đó
thất bại, PostgreSQL không rơi xuống record sau.

Một baseline dễ đọc:

```conf
# TYPE      DATABASE   USER           ADDRESS          METHOD
# Unix local socket: map OS user bằng peer.
local       all        postgres                        peer

# Workload nội bộ: rule hẹp đặt trước.
hostssl     orders     +app_login     10.20.0.0/16     scram-sha-256

# Replication identity riêng.
hostssl     replication replicator    10.30.0.0/24     scram-sha-256

# Từ chối plaintext TCP một cách rõ ràng.
hostnossl   all        all            0.0.0.0/0        reject
hostnossl   all        all            ::/0             reject

# Không có allow rộng "host all all 0.0.0.0/0" phía sau.
```

Trong trường `USER`, `+app_login` khớp các member trực tiếp hoặc gián tiếp của group
role `app_login`; `app_login` không có dấu `+` chỉ khớp đúng role có tên đó.

Các nguyên tắc:

- rule cụ thể trước rule tổng quát;
- giới hạn đồng thời database, role, CIDR và auth method;
- ưu tiên private network, nhưng không xem private network là identity;
- `trust` chỉ phù hợp boundary rất hẹp và hiểu rõ; nó bỏ qua chứng minh password;
- `peer` hữu ích cho local socket vì dựa vào OS username;
- rule replication và administrative access tách khỏi application;
- IPv4 và IPv6 là hai phạm vi riêng, đừng quên một bên.

---

## 8. Chia nhỏ HBA nhưng vẫn phải hiểu thứ tự

`include`, `include_if_exists` và `include_dir` giúp chia cấu hình theo owner/workload.
Nội dung được chèn đúng vị trí directive, không tạo một tầng precedence mới.
File trong `include_dir` được đọc theo thứ tự tên dùng C locale, vì vậy nên dùng prefix:

```text
00-local.conf
10-admin.conf
20-application.conf
30-replication.conf
90-explicit-reject.conf
```

Kiểm tra parser trước và sau reload:

```sql
SELECT rule_number,
       file_name,
       line_number,
       type,
       database,
       user_name,
       address,
       auth_method,
       error
FROM pg_hba_file_rules
ORDER BY rule_number NULLS LAST, file_name, line_number;
```

`error IS NOT NULL` báo dòng không parse được. View phản ánh file hiện tại trên disk,
không đảm bảo đó là cấu hình đã được tiến trình server load. Sau khi review, reload:

```sql
SELECT pg_reload_conf();
```

Luôn giữ một admin session dự phòng khi sửa remote access. Đừng đóng cửa duy nhất rồi
mới kiểm tra rule mới.

---

## 9. Runbook: connection bị HBA từ chối hoặc dùng nhầm rule

1. Ghi chính xác database, requested user, source IP nhìn từ server và SSL/non-SSL.
2. Kiểm tra DNS/proxy/NAT; IP server nhìn thấy có thể khác IP client nghĩ mình có.
3. Đọc `pg_hba_file_rules`, xử lý mọi parse error.
4. Tìm record đầu tiên khớp đủ bốn chiều, không chỉ tìm chuỗi username.
5. Xác nhận membership nếu rule dùng `+group_role`.
6. Xác nhận TLS hop thực tế nếu rule là `hostssl`.
7. Reload và kiểm tra log; không đổi sang `trust` để “thử cho nhanh”.
8. Test cả allow case và deny case từ đúng network path.

Nếu lỗi là `password authentication failed`, HBA đã chọn được một auth method; thêm
một rule phía dưới không sửa được lỗi vì không có fall-through.

---

## 10. SCRAM-SHA-256 và migration khỏi MD5

PostgreSQL 18 ưu tiên SCRAM-SHA-256. Hỗ trợ MD5 password đã bị deprecated và sẽ bị
loại bỏ ở phiên bản tương lai.

Migration an toàn:

1. Inventory driver, pooler, proxy, backup và monitoring client; xác nhận hỗ trợ SCRAM.
2. Đặt verifier mới thành SCRAM:

   ```conf
   password_encryption = 'scram-sha-256'
   ```

3. Reset password của từng login role để tạo verifier SCRAM mới.
4. Quan sát client đã chuyển thành công.
5. Đổi HBA từ `md5` sang `scram-sha-256`.
6. Xóa exception và cập nhật policy/automation.

Trong giai đoạn chuyển tiếp, HBA ghi `md5` nhưng role có SCRAM verifier sẽ tự chọn
SCRAM. Đây là cầu nối migration, không phải lý do giữ `md5` vô thời hạn.

Tạo/reset bí mật bằng `\password` trong `psql` giúp tránh đặt plaintext vào command
history và server log như một câu `ALTER ROLE ... PASSWORD '...'` thô.

`password` auth method gửi password dạng cleartext trên protocol; chỉ TLS mới che
đường truyền. Thực tế nên dùng `scram-sha-256` thay vì dựa vào cặp `password` + TLS.

---

## 11. Password policy là một lifecycle

Một password dài không giải quyết được secret nằm trong image, Git hoặc log. Lifecycle
cần có:

- sinh secret bằng CSPRNG và lưu trong secret manager;
- phân phối theo workload identity, không copy tay qua chat/ticket;
- không nhúng password trong URI, source code, command line hoặc log;
- rotation định kỳ và ngay khi nghi lộ;
- telemetry để biết credential cũ còn được dùng;
- owner, expiry, dependency và runbook thu hồi rõ ràng.

`VALID UNTIL` chỉ giới hạn password authentication của role. Nó không tự vô hiệu hóa
peer, certificate hoặc OAuth; cũng không kết thúc session đã xác thực.

`scram_iterations` được ghi vào verifier lúc đổi password. Tăng setting chỉ tác động
password được đặt lại sau đó và tăng CPU lúc authentication, vì vậy benchmark login
storm trước khi tăng mạnh.

---

## 12. OAuth trong PostgreSQL 18

PostgreSQL 18 có HBA method `oauth` và libpq hỗ trợ OAuth token. Server vẫn cần validator
library được cấu hình qua `oauth_validator_libraries`; đây là primitive để tích hợp,
không phải một identity provider hoàn chỉnh.

Khi dùng OAuth vẫn phải thiết kế:

- issuer, audience/scope và mapping token → database role;
- TLS `verify-full`;
- token lifetime, refresh, revocation và clock skew;
- behavior khi IdP/validator lỗi;
- log không ghi token;
- break-glass identity độc lập, được bảo vệ và audit.

Chỉ chuyển từ password sang bearer token mà không giới hạn scope/lifetime có thể đổi
loại credential bị lộ chứ chưa giảm blast radius.

---

## 13. Role là cluster-wide identity

Role PostgreSQL tồn tại ở cấp cluster, không riêng một database. `LOGIN` cho phép role
được dùng làm session identity; role `NOLOGIN` phù hợp để gom ownership hoặc privilege.

Tách ít nhất ba loại:

```text
owner role (NOLOGIN)       sở hữu schema/table/function
        ▲
        │ SET ROLE chỉ khi migration
migration login            triển khai DDL có kiểm soát

runtime group (NOLOGIN)    quyền DML tối thiểu
        ▲
        │ membership
workload login             credential có thể rotate
```

Ví dụ:

```sql
CREATE ROLE orders_owner NOLOGIN;
CREATE ROLE orders_runtime NOLOGIN;
CREATE ROLE orders_readonly NOLOGIN;
CREATE ROLE orders_login NOLOGIN;

CREATE ROLE orders_api_blue LOGIN PASSWORD NULL;
GRANT orders_login TO orders_api_blue;
GRANT orders_runtime TO orders_api_blue;

CREATE ROLE orders_migrator LOGIN NOINHERIT PASSWORD NULL;
GRANT orders_owner TO orders_migrator
  WITH INHERIT FALSE, SET TRUE, ADMIN FALSE;
```

Migration session dùng `SET ROLE orders_owner` chỉ trong cửa sổ cần thiết. Runtime
login không được member của owner role.

Từ PostgreSQL 16, mỗi membership edge có các option `INHERIT`, `SET`, `ADMIN`:

- `INHERIT`: privilege thông thường của group role có hiệu lực tự động;
- `SET`: member được `SET ROLE` sang group role;
- `ADMIN`: member được grant/revoke membership đó cho role khác.

Kiểm tra membership và option bằng `\drg+` trong `psql`; đừng chỉ nhìn cột `rolinherit`
theo mental model cũ trước PostgreSQL 16.

---

## 14. Các attribute quyền lực phải cực hiếm

| Attribute | Khả năng | Nguyên tắc |
|---|---|---|
| `SUPERUSER` | Bypass hầu hết access control | Không cấp cho application; dùng break-glass có audit |
| `CREATEROLE` | Quản lý role/membership trong phạm vi rộng | Tách identity automation, test escalation path |
| `CREATEDB` | Tạo database | Chỉ provisioning role |
| `REPLICATION` | Kết nối replication, quản lý slot liên quan | Identity riêng, CIDR/HBA riêng |
| `BYPASSRLS` | Bỏ qua mọi row policy | Không cấp runtime/BI; giám sát như privilege đặc biệt |

Các attribute đặc biệt không được “thừa kế” giống object privilege thông thường;
thường phải `SET ROLE` sang role có attribute đó. Dù vậy, membership có `SET TRUE`
vẫn là đường tăng quyền, nên review cả graph chứ không chỉ login role.

Các predefined role như `pg_read_all_data`, `pg_write_all_data`, `pg_monitor` rất tiện
nhưng blast radius lớn và quyền có thể tiến hóa theo phiên bản. Đặc biệt thận trọng với
`pg_read_server_files`, `pg_write_server_files`, `pg_execute_server_program`: chúng mở
khả năng đọc/ghi file hoặc chạy chương trình phía server và có thể dẫn tới kiểm soát
toàn bộ hệ thống.

---

## 15. Ownership không phải một GRANT thông thường

Owner có quyền vốn có để alter/drop object và có toàn bộ grant option. Quyền sở hữu
không thể thu hồi bằng một `REVOKE` thông thường.

Do đó:

- schema/table/function do role `NOLOGIN` sở hữu;
- runtime role chỉ nhận DML cần thiết;
- migration `SET ROLE` owner;
- không để CI/CD login, cá nhân hoặc application login sở hữu object;
- sau restore/migration, kiểm tra owner drift.

Ví dụ baseline schema:

```sql
SET ROLE orders_owner;

CREATE SCHEMA orders AUTHORIZATION orders_owner;

CREATE TABLE orders.purchase_order (
    tenant_id   uuid        NOT NULL,
    order_id    uuid        NOT NULL,
    external_ref text       NOT NULL,
    total       numeric(18,2) NOT NULL CHECK (total >= 0),
    created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (tenant_id, order_id),
    UNIQUE (tenant_id, external_ref)
);

RESET ROLE;
```

---

## 16. Schema và `search_path` là trust boundary

`USAGE` trên schema cho phép resolve object; `CREATE` cho phép tạo object trong schema.
Nếu một schema writable bởi user không tin cậy nằm trong `search_path`, user đó có thể
tạo function/operator/relation trùng tên để hijack câu lệnh không qualify đầy đủ.

Baseline:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA orders FROM PUBLIC;

GRANT USAGE ON SCHEMA orders TO orders_runtime, orders_readonly;
```

Database tạo mới từ PostgreSQL 15 có mặc định `public` an toàn hơn, nhưng cluster nâng
cấp từ PostgreSQL 14 trở xuống có thể còn `CREATE` cho `PUBLIC`. Hãy kiểm tra thực tế,
không suy luận từ version binary hiện tại.

Trong code nhạy cảm:

- qualify `schema.object`;
- chỉ đưa trusted, non-writable schema vào `search_path`;
- đặt `pg_temp` cuối `search_path` của security-definer function;
- không cấp `CREATE` rộng trên schema nằm trong path.

---

## 17. Cấp quyền tối thiểu theo operation

```sql
GRANT SELECT, INSERT, UPDATE, DELETE
ON orders.purchase_order
TO orders_runtime;

GRANT SELECT
ON orders.purchase_order
TO orders_readonly;
```

Không dùng `GRANT ALL` vì nhanh. Tách rõ:

- runtime có cần `DELETE`, `TRUNCATE`, `TRIGGER`, `REFERENCES` hay `MAINTAIN` không?
- read-only có cần mọi cột hay chỉ một view?
- job có cần mọi table hay chỉ một schema/object cụ thể?
- function có thể đóng gói operation thay vì cấp table trực tiếp không?

Sequence là object riêng. Nếu dùng sequence/identity mà runtime cần gọi trực tiếp,
phải cấp quyền sequence phù hợp; `GRANT INSERT ON table` không tự cấp `USAGE` trên
sequence.

Column-level privilege có ích trong trường hợp hẹp nhưng dễ tạo ma trận khó kiểm toán.
Với API ổn định, view hoặc function thường diễn đạt boundary tốt hơn.

---

## 18. `PUBLIC` là tất cả role

`PUBLIC` không phải role bình thường; nó đại diện cho mọi role hiện tại và tương lai.
Audit các mặc định đáng chú ý:

- `CONNECT` và `TEMPORARY` trên database;
- `USAGE`/`CREATE` trên schema;
- `EXECUTE` trên function/procedure;
- privilege do extension hoặc restore tạo lại.

Ví dụ database dành riêng cho application:

```sql
REVOKE CONNECT, TEMPORARY ON DATABASE orders FROM PUBLIC;
GRANT CONNECT ON DATABASE orders TO orders_login, orders_migrator;
```

Nếu dùng group role trong HBA hoặc `GRANT CONNECT`, nhớ rằng login thực tế phải có
membership đúng và option/semantics đúng với cách truy cập.

---

## 19. Default privilege chỉ áp dụng object tương lai

`ALTER DEFAULT PRIVILEGES` không sửa object đã tồn tại. Default được tính theo **role
thực sự tạo object**, không tự gom default privilege từ mọi role mà nó là member.

Thiết lập dưới đúng owner role:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE orders_owner
  REVOKE EXECUTE ON ROUTINES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE orders_owner IN SCHEMA orders
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO orders_runtime;

ALTER DEFAULT PRIVILEGES FOR ROLE orders_owner IN SCHEMA orders
  GRANT SELECT ON TABLES TO orders_readonly;

ALTER DEFAULT PRIVILEGES FOR ROLE orders_owner IN SCHEMA orders
  GRANT USAGE, SELECT ON SEQUENCES TO orders_runtime;
```

Lưu ý:

- global default và per-schema default cộng lại;
- per-schema `REVOKE` không thể phủ định privilege đã được global default cấp;
- function mặc định có `EXECUTE` cho `PUBLIC`, nên revoke global dưới owner trước khi
  tạo function nhạy cảm;
- migration phải `SET ROLE orders_owner` trước khi tạo object;
- dùng `\ddp` và query catalog để kiểm tra drift;
- vẫn cần backfill `GRANT/REVOKE` cho object cũ.

---

## 20. Kiểm kê effective access, không chỉ ACL trực tiếp

Role có thể nhận quyền qua membership nhiều tầng, ownership, `PUBLIC`, default
privilege, predefined role hoặc `SECURITY DEFINER` function. Một vài probe hữu ích:

```sql
SELECT has_database_privilege('orders_api_blue', 'orders', 'CONNECT');
SELECT has_schema_privilege('orders_api_blue', 'orders', 'USAGE');
SELECT has_table_privilege(
    'orders_api_blue',
    'orders.purchase_order',
    'SELECT,INSERT,UPDATE,DELETE'
);
SELECT pg_has_role('orders_api_blue', 'orders_runtime', 'MEMBER');
```

Liệt kê object owner bất ngờ:

```sql
SELECT n.nspname AS schema_name,
       c.relname AS object_name,
       c.relkind,
       pg_get_userbyid(c.relowner) AS owner
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND pg_get_userbyid(c.relowner) <> 'orders_owner'
ORDER BY 1, 2;
```

Audit phải chạy dưới account đủ quyền nhìn catalog nhưng report không nên công khai
credential, policy secret hoặc dữ liệu business.

---

## 21. `SECURITY INVOKER` là mặc định nên ưu tiên

Function mặc định chạy với quyền caller (`SECURITY INVOKER`). Đây là lựa chọn dễ hiểu:
caller chỉ làm được điều họ vốn có quyền làm.

Chỉ dùng `SECURITY DEFINER` khi function thực sự là một capability hẹp, ví dụ:

- đọc mapping identity mà runtime không được đọc trực tiếp;
- thực hiện một mutation được validate chặt;
- cung cấp API database giới hạn thay vì cấp table rộng.

Không dùng definer function như cách né thiết kế privilege.

---

## 22. Viết `SECURITY DEFINER` an toàn

Checklist bắt buộc:

1. Owner là `NOLOGIN` tối thiểu quyền, không phải superuser.
2. `search_path` chỉ có trusted schema và `pg_temp` ở cuối.
3. Object nhạy cảm được schema-qualify.
4. Validate input, tenant và cardinality; không nối dynamic SQL thô.
5. Revoke `EXECUTE` khỏi `PUBLIC`, grant đúng caller.
6. Tạo function và revoke/grant trong cùng transaction để không có exposure window.
7. Review lại owner/ACL khi `CREATE OR REPLACE`; lệnh này giữ owner và privilege cũ.

Ví dụ capability chỉ trả tenant gắn với database login:

```sql
BEGIN;

CREATE ROLE tenant_identity_owner NOLOGIN;
CREATE SCHEMA IF NOT EXISTS authz AUTHORIZATION tenant_identity_owner;
REVOKE ALL ON SCHEMA authz FROM PUBLIC;

CREATE TABLE authz.login_tenant (
    login_role name PRIMARY KEY,
    tenant_id  uuid NOT NULL UNIQUE
);
ALTER TABLE authz.login_tenant OWNER TO tenant_identity_owner;

CREATE FUNCTION authz.current_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT m.tenant_id
    FROM authz.login_tenant AS m
    WHERE m.login_role = session_user
$function$;

ALTER FUNCTION authz.current_tenant_id() OWNER TO tenant_identity_owner;
REVOKE ALL ON FUNCTION authz.current_tenant_id() FROM PUBLIC;
GRANT USAGE ON SCHEMA authz TO orders_runtime;
GRANT EXECUTE ON FUNCTION authz.current_tenant_id() TO orders_runtime;

COMMIT;
```

`session_user` giữ identity đã đăng nhập, khác `current_user` có thể đổi khi `SET ROLE`
hoặc vào definer function. Mẫu này phù hợp khi mỗi tenant/workload có database login
riêng; không phù hợp cho một login dùng chung mọi end-user.

---

## 23. View không đồng nghĩa definer function

View mặc định thường kiểm tra quyền trên base relation theo view owner, còn quyền truy
cập view theo caller. `security_invoker = true` đổi việc kiểm tra base relation sang
caller:

```sql
CREATE VIEW orders.safe_order_summary
WITH (security_invoker = true) AS
SELECT tenant_id, order_id, total, created_at
FROM orders.purchase_order;
```

`security_barrier` có thể cần cho view dùng làm security boundary để ngăn một số phép
biến đổi planner làm lộ dữ liệu qua function/operator không leakproof. Tuy nhiên view,
RLS và function có semantics khác nhau; đừng gắn nhãn “secure” rồi coi chúng tương đương.

---

## 24. RLS giải quyết điều gì?

Object privilege trả lời “role có được SELECT table không?”. RLS thêm câu hỏi “trong
table đó role được thấy hoặc thay đổi row nào?”.

```sql
ALTER TABLE orders.purchase_order ENABLE ROW LEVEL SECURITY;
```

Khi RLS bật:

- nếu không có policy áp dụng, mặc định deny;
- policy có thể theo command và role;
- `USING` lọc row hiện hữu được nhìn/chọn/sửa/xóa;
- `WITH CHECK` kiểm tra row mới do INSERT/UPDATE tạo ra;
- nhiều permissive policy kết hợp bằng `OR`;
- restrictive policy kết hợp bằng `AND`, nhưng vẫn cần ít nhất một permissive policy;
- policy expression false hoặc null đều không cho phép.

RLS không tự cấp `SELECT/INSERT/...`; caller vẫn phải có object privilege tương ứng.

---

## 25. Ai bypass RLS?

Ba trường hợp quan trọng:

1. Superuser luôn bypass.
2. Role có `BYPASSRLS` luôn bypass.
3. Table owner thường bypass, trừ khi table dùng `FORCE ROW LEVEL SECURITY`.

Vì vậy runtime role không được sở hữu table. Với table tenant:

```sql
ALTER TABLE orders.purchase_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders.purchase_order FORCE ROW LEVEL SECURITY;
```

`FORCE` giúp owner thông thường chịu policy, nhưng không biến superuser/BYPASSRLS thành
subject của RLS. Maintenance cần bypass phải là identity riêng, được cấp tạm thời,
audit và thu hồi; đừng gắn bypass vào pool role.

`TRUNCATE` và `REFERENCES` không chịu RLS. Đây là lý do runtime thường không cần hai
privilege này.

---

## 26. `USING` và `WITH CHECK`

Ví dụ policy tách theo operation:

```sql
CREATE POLICY po_select_tenant
ON orders.purchase_order
FOR SELECT TO orders_runtime
USING (tenant_id = authz.current_tenant_id());

CREATE POLICY po_insert_tenant
ON orders.purchase_order
FOR INSERT TO orders_runtime
WITH CHECK (tenant_id = authz.current_tenant_id());

CREATE POLICY po_update_tenant
ON orders.purchase_order
FOR UPDATE TO orders_runtime
USING (tenant_id = authz.current_tenant_id())
WITH CHECK (tenant_id = authz.current_tenant_id());

CREATE POLICY po_delete_tenant
ON orders.purchase_order
FOR DELETE TO orders_runtime
USING (tenant_id = authz.current_tenant_id());
```

`USING` của UPDATE ngăn lấy row tenant khác làm target. `WITH CHECK` ngăn đổi
`tenant_id` của row sang tenant khác. Nếu policy `ALL`/`UPDATE` không ghi `WITH CHECK`,
PostgreSQL có thể tái dùng `USING`, nhưng viết rõ hai ý làm review dễ hơn.

INSERT policy chỉ có `WITH CHECK`. UPDATE thường còn cần SELECT privilege/policy vì
engine phải nhìn được row target. `RETURNING`, `ON CONFLICT` và `MERGE` cũng có thể kích
hoạt policy/privilege ngoài nhánh mà application tưởng đang chạy; phải integration test.

---

## 27. Mẫu RLS với một database login cho mỗi tenant

Đây là boundary mạnh và dễ chứng minh hơn:

```text
tenant A workload → login tenant_a_api ─┐
tenant B workload → login tenant_b_api ─┼→ cùng orders_runtime privilege
                                        └→ mapping session_user → tenant_id
```

Ưu điểm:

- client không thể tự đổi `session_user`;
- audit phân biệt tenant ở database identity;
- policy không tin header/GUC do client tự đặt.

Đổi lại, số role/credential và connection pool tăng. Mẫu phù hợp tenant lớn hoặc cell
architecture; không nhất thiết phù hợp hàng trăm nghìn tenant nhỏ.

---

## 28. Mẫu shared login + transaction-local tenant context

Trusted backend thường dùng một pool login và đặt tenant context sau khi xác thực API:

```sql
BEGIN;

SELECT set_config('app.tenant_id', '5ef0c8d7-0c93-4b79-a177-5fc143e96418', true);

SELECT order_id, total
FROM orders.purchase_order
ORDER BY created_at DESC
LIMIT 50;

COMMIT;
```

`true` tương đương transaction-local; context tự mất khi commit/rollback. Helper:

```sql
CREATE FUNCTION authz.request_tenant_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $function$
    SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid
$function$;

REVOKE ALL ON FUNCTION authz.request_tenant_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION authz.request_tenant_id() TO orders_runtime;
```

Policy thay `authz.current_tenant_id()` bằng `authz.request_tenant_id()`.

**Cảnh báo quan trọng:** custom GUC không phải credential. Client có SQL access thường
có thể tự đặt `app.tenant_id`. Mẫu này chỉ an toàn khi database connection nằm sau
trusted middle tier, end-user không thể gửi SQL tùy ý, và backend lấy tenant từ identity
đã xác thực chứ không tin request parameter.

Nếu client/tenant kết nối database trực tiếp, dùng database identity riêng, token được
validator map đáng tin cậy, hoặc một capability function xác minh mapping/chữ ký; không
coi `SET app.tenant_id = ...` là authorization.

---

## 29. Connection pool và lỗi rò tenant

Sai nguy hiểm:

```sql
SET app.tenant_id = 'tenant-a'; -- session-scoped
SELECT ...;
-- connection trả về pool nhưng context còn nguyên
```

Request tenant B mượn lại connection có thể thấy tenant A nếu code quên overwrite hoặc
exception đi qua nhánh cleanup.

Contract an toàn hơn:

1. `BEGIN`.
2. Đặt tenant bằng `set_config(..., true)`/`SET LOCAL`.
3. Chạy mọi query của request trong chính transaction đó.
4. `COMMIT` hoặc `ROLLBACK` trong `finally`.
5. Không cho query chạy trước bước đặt context.
6. Pool reset vẫn là defense bổ sung, không thay transaction-local scope.
7. Test exception, timeout, retry và connection reuse giữa hai tenant.

Với transaction-pooling PgBouncer, session state không ổn định qua transaction. Điều đó
càng củng cố yêu cầu “đặt context và query trong cùng transaction”, nhưng application
phải chắc không query sau commit với giả định context còn tồn tại.

---

## 30. Tenant key phải đi xuyên constraint

RLS lọc row nhưng không thay data integrity. Dùng tenant key trong business uniqueness,
primary key và foreign key để database không tạo reference xuyên tenant:

```sql
CREATE TABLE orders.customer (
    tenant_id  uuid NOT NULL,
    customer_id uuid NOT NULL,
    email      text NOT NULL,
    PRIMARY KEY (tenant_id, customer_id),
    UNIQUE (tenant_id, email)
);

ALTER TABLE orders.purchase_order
ADD COLUMN customer_id uuid,
ADD CONSTRAINT po_customer_fk
FOREIGN KEY (tenant_id, customer_id)
REFERENCES orders.customer (tenant_id, customer_id);
```

Chỉ dùng global `UNIQUE(email)` vừa sai domain nếu email được lặp giữa tenant, vừa có
thể làm tenant suy ra sự tồn tại của dữ liệu qua lỗi unique.

PostgreSQL bỏ qua RLS trong referential-integrity check để bảo đảm constraint. Lỗi
unique/FK, timing và sequence có thể tạo covert channel về sự tồn tại của row. Với
tenant thù địch và yêu cầu isolation cao, cân nhắc database/cell riêng thay vì tin RLS
là biên tuyệt đối chống mọi side channel.

---

## 31. Policy phụ thuộc bảng khác có race khó thấy

Policy có subquery sang bảng membership/quyền có thể đọc snapshot không đồng bộ với
row đang sửa. Trong concurrent transaction, quyết định authorization có thể dựa trên
membership cũ trong khi row mục tiêu đã thay đổi.

Giảm rủi ro bằng cách:

- ưu tiên predicate dựa trên cột của chính row và stable identity;
- đặt tenant key trực tiếp trên mọi bảng tenant;
- nếu phải lookup, giới hạn definer helper thật hẹp và hiểu snapshot/lock;
- thay đổi membership/quyền theo transaction và runbook nhất quán;
- test concurrency, không chỉ happy-path tuần tự;
- tránh khóa bảng authorization trong policy cho mọi row nếu sẽ gây contention.

Policy chạy “mỗi row” còn có cost. Index cột dùng trong policy, ví dụ `tenant_id`, và
đọc `EXPLAIN (ANALYZE, BUFFERS)` với role/context production-like.

---

## 32. Permissive và restrictive policy

Mặc định policy là permissive: nhiều policy phù hợp được OR. Ví dụ một policy tenant
và một policy support có thể vô tình cho support xem rộng hơn dự định.

Restrictive policy phù hợp điều kiện bắt buộc luôn đúng:

```sql
CREATE POLICY po_not_deleted
ON orders.purchase_order
AS RESTRICTIVE
FOR SELECT TO orders_runtime
USING (deleted_at IS NULL);
```

Ví dụ trên giả sử bảng đã có cột `deleted_at timestamptz` cho soft delete.

Nhưng restrictive policy không tự mở quyền: phải có ít nhất một permissive policy cho
row trước, sau đó điều kiện restrictive mới AND vào. Khi review, lập bảng chân trị cho
từng role/command thay vì đọc từng policy độc lập.

---

## 33. Trigger, generated behavior và policy

`BEFORE ROW` trigger chạy trước kiểm tra `WITH CHECK`; giá trị trigger sửa sẽ là giá trị
được policy kiểm tra. Điều này có thể hữu ích khi trigger chuẩn hóa tenant key, nhưng
cũng làm hành vi khó thấy.

Không dùng trigger để âm thầm lấy tenant context nếu application không hiểu contract.
Test ít nhất:

- INSERT thiếu tenant;
- INSERT tenant khác;
- UPDATE business field;
- UPDATE đổi tenant;
- UPSERT conflict cùng tenant và khác tenant;
- `RETURNING`;
- trigger thay tenant/key;
- COPY/MERGE nếu application dùng.

---

## 34. Backup và maintenance dưới RLS

Session backup chạy bằng role bị RLS lọc có thể tạo backup thiếu row mà job vẫn “xanh”.
Setting `row_security = off` **không bypass RLS**; nó làm query lỗi nếu kết quả sẽ bị
lọc, hữu ích để tránh backup âm thầm thiếu dữ liệu.

Thiết kế:

- backup identity riêng với privilege cần thiết;
- hiểu `pg_dump`/tool đang dùng owner, superuser hay `row_security=off` thế nào;
- restore drill và kiểm tra row count/invariant theo tenant;
- không cấp `BYPASSRLS` cho runtime chỉ để backup dễ hơn;
- audit mọi lần dùng maintenance/bypass identity.

---

## 35. Quan sát policy và trạng thái RLS

```sql
SELECT schemaname,
       tablename,
       policyname,
       permissive,
       roles,
       cmd,
       qual,
       with_check
FROM pg_policies
WHERE schemaname = 'orders'
ORDER BY tablename, policyname;
```

Tìm table có trạng thái đáng chú ý:

```sql
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS rls_forced,
       pg_get_userbyid(c.relowner) AS owner
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND n.nspname = 'orders'
ORDER BY c.relname;
```

Đặt migration gate: mọi table mang `tenant_id` phải bật RLS, có policy đủ command,
owner đúng và composite constraint đúng. Khi drop policy cuối cùng mà RLS vẫn bật,
table trở về default deny; khi disable RLS, policy còn trong catalog nhưng bị bỏ qua.

---

## 36. Test RLS như một authorization matrix

Không test bằng superuser hoặc owner. Với mỗi role, command và tenant:

| Case | Kỳ vọng |
|---|---|
| tenant A SELECT row A | thấy |
| tenant A SELECT row B | không thấy |
| tenant A INSERT key A | thành công |
| tenant A INSERT key B | lỗi policy |
| tenant A UPDATE row A thành tenant B | lỗi policy |
| tenant A DELETE row B | không tác động row |
| thiếu tenant context | default deny/lỗi rõ theo contract |
| context rỗng/UUID sai | fail closed, không cast lỗi mơ hồ trong happy path |
| runtime `TRUNCATE` | bị object privilege từ chối |
| owner/migrator | behavior đúng runbook, không dùng nhầm runtime pool |

Thêm property/integration test tái sử dụng cùng một pooled connection theo thứ tự A → B,
B → A, có exception giữa chừng. Đây là nơi nhiều lỗi tenant isolation thật sự xuất hiện.

---

## 37. Secret rotation không downtime bằng blue/green login

Một role chỉ có một password verifier. Đổi password tại chỗ dễ tạo khoảng lệch giữa
secret manager, pod cũ, pod mới và connection pool. Mẫu hai login giảm coupling:

```text
orders_api_blue  ─┐
                   ├─ member orders_runtime
orders_api_green ─┘
```

Runbook:

1. Tạo `orders_api_green` với credential/certificate mới, `NOLOGIN`/chưa allow nếu cần stage.
2. Cấp đúng membership như blue bằng automation, không copy privilege tùy hứng.
3. Cho HBA/network chấp nhận green.
4. Deploy canary dùng green; xác minh TLS, RLS, error rate và audit identity.
5. Rollout, drain pool blue; quan sát `pg_stat_activity` không còn session blue.
6. `ALTER ROLE orders_api_blue NOLOGIN` và thu hồi HBA/secret.
7. Kết thúc session còn sót theo runbook đã duyệt.
8. Sau retention ngắn, drop hoặc giữ disabled theo policy; đổi màu cho lần sau.

Membership group role giữ object privilege ổn định, còn login credential thay được.
Đừng dùng một login cho nhiều service nếu muốn biết service nào còn giữ secret cũ.

---

## 38. Khóa role không tự ngắt session hiện có

`ALTER ROLE ... NOLOGIN`, password expiry hoặc `REVOKE CONNECT` ngăn kết nối mới theo
semantics tương ứng nhưng không kết thúc backend đã xác thực.

Khi cần containment:

```sql
ALTER ROLE compromised_login NOLOGIN;

SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE usename = 'compromised_login'
  AND pid <> pg_backend_pid();
```

Thực hiện từ break-glass/admin identity, kiểm tra application retry storm và thay
credential trước khi mở lại. Nếu role chia sẻ giữa nhiều workload, blast radius chính
là bằng chứng thiết kế cần sửa sau incident.

---

## 39. Runbook khi nghi lộ credential

1. Ghi thời điểm, role, service, nguồn phát hiện; bảo toàn log/evidence.
2. Chặn kết nối mới: `NOLOGIN`, HBA/network/IdP revocation tùy credential.
3. Xác định và terminate session hiện có; chú ý transaction đang chạy.
4. Xoay secret/certificate/token và các secret dẫn xuất liên quan.
5. Kiểm tra membership, owner, grant, function, policy, extension và DDL bị thay đổi.
6. Điều tra query/connection log, source IP, application name và timeline.
7. Xác minh backup/WAL/log không bị đọc hoặc phá hoại.
8. Khôi phục bằng identity mới, privilege tối thiểu; theo dõi retry/anomaly.
9. Nếu integrity không chứng minh được, restore/compare từ mốc sạch theo incident plan.
10. Sửa root cause: secret distribution, shared identity, TTL, egress hoặc alert gap.

Không rotate xong rồi xóa log ngay. Containment và evidence preservation phải được phối
hợp với incident response policy.

---

## 40. Logging: đủ điều tra nhưng không biến log thành data leak

Một baseline có thể gồm connection/auth event, disconnect, DDL/role change và slow/error
query phù hợp. PostgreSQL 18 cho `log_connections` chọn các giai đoạn như receipt,
authentication, authorization và setup duration.

`log_statement = 'all'` không tự động là audit chuẩn: volume lớn, khó phân loại và có
thể ghi SQL chứa PII/secret. Bind parameter còn có thể xuất hiện qua các setting log
parameter và error context.

Nguyên tắc:

- không đưa password/token vào SQL literal, URI hoặc `application_name`;
- giới hạn `log_parameter_max_length` và `_on_error` theo threat model;
- log line có timestamp, pid/session, database, user, client và application name;
- đồng bộ clock;
- ship log tới nơi append-oriented/tamper-resistant với RBAC và retention;
- alert auth failure burst, login từ source lạ, role/owner/policy/extension change;
- bảo vệ log như dữ liệu nhạy cảm vì nó có query text, identifier và đôi khi PII.

`pg_stat_activity` là trạng thái hiện tại, không phải lịch sử audit.

---

## 41. pgAudit khi cần audit có cấu trúc hơn

pgAudit là extension cung cấp session/object audit qua PostgreSQL logging. Nó có thể
phân loại READ, WRITE, FUNCTION, ROLE, DDL... tốt hơn việc bật mọi statement một cách
mù quáng.

Nhưng cần hiểu trade-off:

- phải dùng nhánh pgAudit tương thích đúng PostgreSQL major;
- thường cần `shared_preload_libraries` và restart;
- `CREATE EXTENSION pgaudit` cung cấp metadata object cần cho DDL audit;
- cấu hình rộng có thể tạo log volume/latency rất lớn;
- audit sink phải nằm ngoài blast radius của cùng DBA/superuser nếu cần chống sửa log;
- test COPY/batch/prepared statement và parameter redaction;
- audit không thay least privilege hoặc alert.

Chọn event từ compliance/threat model, ước lượng bytes/transaction và load test trước
production.

---

## 42. Encryption at rest và column encryption

PostgreSQL core cung cấp TLS cho transport và có `pgcrypto` cho một số nhu cầu mã hóa
ở tầng SQL. Data directory, WAL, temp, backup và snapshot thường được mã hóa bằng
filesystem/block/storage/cloud KMS bên ngoài PostgreSQL.

Không nên gọi storage encryption là giải pháp chống DBA tuyệt đối: nếu host/database
đang chạy có key và đọc được plaintext, actor đủ quyền trên endpoint có thể đọc qua
memory/query. Với `pgcrypto`, key và plaintext cũng xuất hiện trong server process trong
thời gian xử lý.

Khi cần giảm niềm tin vào database operator, cân nhắc mã hóa application-side/envelope:

```text
application plaintext
  └─ encrypt bằng per-record/per-tenant data key
       ├─ ciphertext → PostgreSQL
       └─ wrapped data key → PostgreSQL
KMS/HSM giữ key-encryption key và policy unwrap
```

Đổi lại, database mất khả năng search/index/range/constraint trên plaintext; key
rotation, deletion, cache và availability phức tạp hơn. Hash deterministic cho lookup
cũng rò equality/frequency và cần key/domain separation.

---

## 43. Backup, replica, WAL và log cũng là dữ liệu production

Một database được khóa tốt vẫn lộ dữ liệu nếu backup bucket public hoặc WAL archive
dùng key quá rộng.

Checklist:

- encryption in transit/at rest cho base backup, logical dump, WAL và snapshot;
- KMS key policy tách backup writer, restore reader và key admin;
- immutable/versioned retention phù hợp ransomware threat;
- secret/certificate không nằm trong dump hoặc debug bundle;
- restore environment có network/role/RLS tương đương trước khi mở cho user;
- log và backup expiry tuân thủ data retention/deletion policy;
- restore drill kiểm tra cả quyền, owner, default privilege, extension và policy.

Replica là một bản sao dữ liệu nhạy cảm đầy đủ; read endpoint, snapshot và operator
access của replica phải được bảo vệ tương đương primary.

---

## 44. DDL và migration an toàn về quyền

Mỗi migration nên có security diff:

1. Object mới do ai sở hữu?
2. Default privilege của role tạo object là gì?
3. `PUBLIC` nhận gì?
4. Runtime có nhận thêm DDL/TRUNCATE/REFERENCES không?
5. Table tenant đã có tenant key, composite constraint, RLS, FORCE và policy chưa?
6. Function mới là invoker hay definer; `search_path` và EXECUTE ra sao?
7. View dùng owner semantics hay `security_invoker`?
8. Extension/predefined role có mở capability server-side không?

Ví dụ transaction migration:

```sql
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '2min';
SET LOCAL ROLE orders_owner;

-- DDL + policy + explicit REVOKE/GRANT trong cùng changeset.

COMMIT;
```

Một changeset tạo table tenant nhưng deploy policy ở lần sau tạo exposure window. Tạo
table, enable/force RLS, policy và grant trong cùng rollout logic; nếu DDL không thể cùng
transaction thì giữ object chưa reachable cho đến khi boundary hoàn tất.

---

## 45. Baseline kiểm tra định kỳ

```sql
-- Login role có attribute nguy hiểm.
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls
FROM pg_roles
WHERE rolcanlogin
  AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls)
ORDER BY rolname;

-- Table tenant bật RLS nhưng chưa FORCE.
SELECT n.nspname, c.relname, pg_get_userbyid(c.relowner) AS owner
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND c.relrowsecurity
  AND NOT c.relforcerowsecurity
ORDER BY 1, 2;

-- Function SECURITY DEFINER ngoài system schema.
SELECT n.nspname,
       p.proname,
       pg_get_userbyid(p.proowner) AS owner,
       p.proconfig
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1, 2;
```

Query trên là tín hiệu review, không tự kết luận vulnerability. Ví dụ owner có thể cố
ý không bị FORCE cho maintenance table; definer function có thể an toàn sau khi review
body, owner, path và ACL.

---

## 46. Security SLO và alert hữu ích

Theo dõi outcome thay vì chỉ “setting đã bật”:

| Signal | Ý nghĩa | Alert gợi ý |
|---|---|---|
| Auth failure theo role/source | brute force, secret cũ hoặc deploy lỗi | burst khác baseline, source mới |
| Kết nối không TLS/cipher/version | đường đi cấu hình sai | bất kỳ non-TLS production client |
| Role/membership/owner change | privilege escalation hoặc migration | ngoài deployment window |
| RLS enable/force/policy change | tenant boundary đổi | bất kỳ thay đổi không có change ID |
| Definer function/extension change | capability mới | owner/path/ACL drift |
| Session của credential cũ | rotation chưa hoàn tất | còn sau deadline |
| Audit pipeline gap | mất khả năng điều tra | không nhận heartbeat/event |

Cardinality theo client IP/user có thể rất lớn; aggregate và retain raw evidence theo
policy thay vì gắn mọi giá trị vào metric label.

---

## 47. Anti-pattern và cách sửa

### “Database ở private subnet nên không cần TLS”

Private routing không xác minh server và không chống sniffing/compromised peer. Dùng
TLS `verify-full`, network allowlist và workload identity cùng nhau.

### “Runtime là owner để migration tiện”

Owner có DDL power và thường bypass RLS. Tách owner `NOLOGIN`, migrator có `SET ROLE`,
runtime chỉ có DML.

### “Bật RLS là tenant isolation đã xong”

Owner/BYPASSRLS, `WITH CHECK`, pool state, constraint, policy race và side channel vẫn
có thể phá boundary. Test matrix và cân nhắc cell/database riêng theo risk.

### “Custom GUC là danh tính tenant”

GUC chỉ là session context. Nếu untrusted client đặt được nó, client tự nhận tenant bất
kỳ. Chỉ dùng sau trusted backend hoặc gắn tenant vào identity được database xác minh.

### “`REVOKE CONNECT` sẽ đá user ra”

Nó không terminate session hiện hữu. Kết hợp chặn login/auth với
`pg_terminate_backend()` theo runbook.

### “Bật `log_statement=all` là đạt audit”

Không có classification/tamper boundary và có thể lộ dữ liệu. Thiết kế event, sink,
redaction, retention và alert; dùng pgAudit nếu yêu cầu phù hợp.

### “Mã hóa disk là không ai đọc được dữ liệu”

Nó chủ yếu bảo vệ media/snapshot khi key không đi kèm. Endpoint đang chạy vẫn giải mã.
Giảm privilege, tách key và cân nhắc application-side encryption.

---

## 48. Production checklist

### Transport và authentication

- [ ] Chỉ endpoint cần thiết được expose; firewall/private endpoint giới hạn source.
- [ ] Mọi production hop dùng TLS; client dùng `verify-full` với CA đúng.
- [ ] `pg_stat_ssl` xác nhận application, pooler, backup và replication.
- [ ] HBA rule hẹp, đúng thứ tự; không có `trust`/allow-all ngoài ngoại lệ có owner.
- [ ] `pg_hba_file_rules` không có parse error; reload/test allow và deny case.
- [ ] SCRAM thay MD5; client inventory và rotation lifecycle hoàn chỉnh.
- [ ] Secret không nằm trong Git/image/URI/log; mỗi service có identity riêng.

### Role và object

- [ ] Owner role là `NOLOGIN`; runtime không member owner và không sở hữu object.
- [ ] Không runtime role nào có superuser/CREATEROLE/REPLICATION/BYPASSRLS.
- [ ] `PUBLIC`, schema `CREATE`, database CONNECT/TEMP và function EXECUTE đã review.
- [ ] Default privilege đặt dưới đúng object-creating role; object cũ đã backfill.
- [ ] `SECURITY DEFINER` có owner hẹp, trusted path, qualify name và explicit ACL.
- [ ] Predefined role/extension/server-file capability có owner và justification.

### Multi-tenant/RLS

- [ ] Mọi table tenant có `tenant_id NOT NULL`, key/FK/unique gồm tenant boundary.
- [ ] RLS `ENABLE` + `FORCE`; owner/bypass identity tách khỏi runtime.
- [ ] SELECT/INSERT/UPDATE/DELETE policy có `USING`/`WITH CHECK` đúng.
- [ ] Shared login context chỉ được đặt bởi trusted backend, dùng transaction-local.
- [ ] Pool reuse, exception, retry, UPSERT/MERGE/RETURNING và concurrency đã test.
- [ ] Backup/maintenance không âm thầm bị RLS lọc.

### Operations

- [ ] Blue/green credential rotation được drill; biết session nào còn dùng secret cũ.
- [ ] Incident runbook chặn login và terminate session hiện hữu.
- [ ] Audit/log không chứa secret quá mức, được ship ra sink chống sửa và có retention.
- [ ] Backup/WAL/replica/log được mã hóa, phân quyền và restore drill.
- [ ] Alert cho auth anomaly, role/owner/policy/definer/extension change và audit gap.

---

## 49. Câu hỏi phỏng vấn và tự kiểm tra

### HBA có thử rule tiếp theo khi password sai không?

Không. Record đầu tiên khớp quyết định phương thức auth; auth fail không fall-through.

### `sslmode=require` và `verify-full` khác gì?

`require` yêu cầu kết nối mã hóa; `verify-full` còn xác minh certificate chain và
hostname/IP, phù hợp endpoint authentication.

### Tại sao runtime không nên sở hữu table dùng RLS?

Table owner thường bypass RLS và còn có quyền alter/drop vốn có. Dùng owner `NOLOGIN`
riêng và `FORCE ROW LEVEL SECURITY`.

### `USING` và `WITH CHECK` khác gì?

`USING` quyết định row hiện hữu caller có thể nhìn/làm target; `WITH CHECK` quyết định
row mới sau INSERT/UPDATE có được chấp nhận không.

### RLS có thay foreign key và unique constraint không?

Không. RLS là row visibility/authorization; constraint bảo vệ integrity. Tenant key
nên nằm trong PK/unique/FK để ngăn reference chéo tenant.

### Vì sao `SET LOCAL app.tenant_id` chưa phải authentication?

Nó chỉ là session context và untrusted SQL client có thể tự đặt. Chỉ tin khi trusted
backend kiểm soát connection và lấy tenant từ identity đã xác thực.

### `NOLOGIN` có ngắt session đang chạy không?

Không. Nó chặn login mới; session hiện hữu cần được xác định và terminate riêng.

### Default privilege có sửa table cũ không?

Không. Nó chỉ áp dụng object tương lai do đúng role tạo; object cũ cần `GRANT/REVOKE`
backfill.

---

## 50. Nguồn chính thức và chủ đề tiếp theo

Tài liệu PostgreSQL 18:

- [Client Authentication và `pg_hba.conf`](https://www.postgresql.org/docs/18/client-authentication.html)
- [`pg_hba.conf`](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html)
- [SSL server](https://www.postgresql.org/docs/18/ssl-tcp.html)
- [libpq SSL support](https://www.postgresql.org/docs/18/libpq-ssl.html)
- [Password authentication và SCRAM](https://www.postgresql.org/docs/18/auth-password.html)
- [OAuth authentication](https://www.postgresql.org/docs/18/auth-oauth.html)
- [Database roles và role membership](https://www.postgresql.org/docs/18/user-manag.html)
- [`GRANT`](https://www.postgresql.org/docs/18/sql-grant.html)
- [Schemas và `search_path`](https://www.postgresql.org/docs/18/ddl-schemas.html)
- [`ALTER DEFAULT PRIVILEGES`](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html)
- [`CREATE FUNCTION` và Security Definer](https://www.postgresql.org/docs/18/sql-createfunction.html)
- [`CREATE VIEW`](https://www.postgresql.org/docs/18/sql-createview.html)
- [Row Security Policies](https://www.postgresql.org/docs/18/ddl-rowsecurity.html)
- [`CREATE POLICY`](https://www.postgresql.org/docs/18/sql-createpolicy.html)
- [Logging configuration](https://www.postgresql.org/docs/18/runtime-config-logging.html)
- [Encryption options](https://www.postgresql.org/docs/18/encryption-options.html)
- [pgAudit](https://github.com/pgaudit/pgaudit)

Học tiếp:

1. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md) – pgJDBC, HikariCP, PgBouncer, transaction, type mapping và retry.

---

*Cập nhật lần cuối: 2026-07-31.*
