---
title: "ClickHouse Security & Access Control"
topic: clickhouse
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# ClickHouse Security & Access Control

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [clickhouse_operations.md](clickhouse_operations.md) (cluster/Keeper) và [clickhouse_production.md](clickhouse_production.md) (multi-tenancy). Theo phương pháp What/How/Why/Compare/Trade-offs.

## Mục lục
1. [Mô hình bảo mật & Access Control (What & Why)](#1-mô-hình-bảo-mật)
2. [Users – CREATE USER & authentication](#2-users)
3. [Roles & Privileges (RBAC)](#3-roles--privileges)
4. [Row Policies – cách ly multi-tenant](#4-row-policies)
5. [Quotas – chống lạm dụng tài nguyên](#5-quotas)
6. [Settings Profiles & Constraints](#6-settings-profiles--constraints)
7. [Column-level security & masking](#7-column-level-security)
8. [Network, TLS & External Auth (LDAP/Kerberos)](#8-network-tls--external-auth)
9. [Encryption at rest & in transit](#9-encryption)
10. [Audit & Compliance](#10-audit--compliance)
11. [Trade-offs & Best Practices](#11-trade-offs--best-practices)

---

## 1. Mô hình bảo mật

### What – hai cơ chế access control
| | XML-based (legacy) | **SQL-driven RBAC** (khuyến nghị) |
|--|--------------------|-----------------------------------|
| Khai báo | `users.xml` (file) | Câu lệnh SQL (`CREATE USER/ROLE/GRANT`) |
| Lưu trữ | File config | `access_control_path` (đồng bộ cluster qua DDL) |
| Linh hoạt | Phải reload file | Runtime, replicate qua Keeper |
| Bật | Mặc định | `access_management = 1` trong user profile |

```xml
<!-- users.xml: bật RBAC SQL cho user admin -->
<users><admin><access_management>1</access_management></admin></users>
```
> ClickHouse mặc định có user `default` **không mật khẩu, full quyền** → **rủi ro lớn**. Production: đặt mật khẩu/khóa `default`, tạo user riêng với quyền tối thiểu.

### Why – các tầng phòng thủ
Authentication (bạn là ai) → Authorization (RBAC: được làm gì) → Row policy (thấy dòng nào) → Quota (dùng bao nhiêu) → Network/TLS (kết nối an toàn) → Encryption → Audit.

---

## 2. Users

```sql
-- Tạo user với các kiểu authentication
CREATE USER analyst IDENTIFIED WITH sha256_password BY 'StrongPass!';
CREATE USER svc      IDENTIFIED WITH bcrypt_password BY 'secret';     -- bcrypt (an toàn nhất cho password)
CREATE USER app      IDENTIFIED WITH ldap SERVER 'my_ldap';
CREATE USER kuser    IDENTIFIED WITH kerberos REALM 'EXAMPLE.COM';
CREATE USER cert_user IDENTIFIED WITH ssl_certificate CN 'client.example.com'; -- mTLS

-- Giới hạn host kết nối + default role + settings
CREATE USER analyst
  IDENTIFIED WITH sha256_password BY '...'
  HOST IP '10.0.0.0/8'                 -- chỉ cho phép từ subnet
  DEFAULT ROLE reader
  SETTINGS max_memory_usage = 10000000000 READONLY;
```
| `IDENTIFIED WITH` | Ghi chú |
|-------------------|---------|
| `no_password` | ❌ tránh (chỉ dev) |
| `plaintext_password` | ❌ tránh |
| `sha256_password` | OK |
| `bcrypt_password` | ✅ tốt nhất cho mật khẩu (slow hash) |
| `ldap` / `kerberos` | SSO doanh nghiệp |
| `ssl_certificate` | mTLS, không cần mật khẩu |

---

## 3. Roles & Privileges (RBAC)

```sql
-- Role = bó quyền, gán cho nhiều user
CREATE ROLE reader;
GRANT SELECT ON analytics.* TO reader;

CREATE ROLE writer;
GRANT SELECT, INSERT, ALTER UPDATE, ALTER DELETE ON analytics.events TO writer;

-- Gán role cho user + đặt mặc định
GRANT reader TO analyst;
SET DEFAULT ROLE reader TO analyst;

-- Role hierarchy (role kế thừa role)
GRANT reader TO writer;            -- writer có luôn quyền của reader

-- WITH GRANT OPTION: cho phép user cấp lại quyền
GRANT SELECT ON db.* TO lead WITH GRANT OPTION;

-- Kích hoạt role trong phiên
SET ROLE writer;                   -- hoặc SET ROLE ALL
```
### Granular privileges
- Theo cấp: `*.*` (toàn cục), `db.*`, `db.table`, **`db.table(column)`** (cấp cột).
- Các quyền: `SELECT`, `INSERT`, `ALTER` (UPDATE/DELETE/ADD COLUMN...), `CREATE`, `DROP`, `TRUNCATE`, `OPTIMIZE`, `SHOW`, `dictGet`, `SYSTEM` (RELOAD/FLUSH...), `INTROSPECTION`.
- Xem: `SHOW GRANTS FOR analyst;`, `system.grants`, `system.role_grants`.

> Nguyên tắc **least privilege**: tạo role theo chức năng (reader/writer/admin), gán role cho user, không GRANT trực tiếp lên user.

---

## 4. Row Policies

Lọc dòng tự động theo user/role — nền tảng **multi-tenancy** an toàn (mỗi tenant chỉ thấy dữ liệu của mình).

```sql
-- Mỗi tenant chỉ SELECT được dòng của tenant mình
CREATE ROW POLICY tenant_isolation ON analytics.events
  USING tenant_id = currentUser()                    -- hoặc map qua dictionary
  TO ALL EXCEPT admin;

-- Theo role cụ thể
CREATE ROW POLICY region_eu ON sales
  FOR SELECT USING region = 'EU' TO eu_team;
```
- **PERMISSIVE** (mặc định): các policy nối bằng OR (thấy dòng nếu thỏa ít nhất 1). **RESTRICTIVE**: nối bằng AND (phải thỏa tất cả) → siết chặt.
- ⚠️ Khi có row policy, query **không** lộ tổng thật nếu không khớp filter → cẩn thận với aggregate "toàn cục".
- Xem `system.row_policies`. Liên hệ multi-tenancy ở [clickhouse_production.md](clickhouse_production.md).

---

## 5. Quotas

Giới hạn tài nguyên một user/role tiêu thụ trong một khoảng thời gian → chống query "phá hoại".

```sql
CREATE QUOTA analyst_quota
  FOR INTERVAL 1 hour MAX queries = 1000, errors = 100,
                          result_rows = 1000000, read_rows = 1000000000,
                          execution_time = 3600
  TO reader;
```
- Tham số: `queries`, `query_selects`, `query_inserts`, `errors`, `result_rows`, `read_rows`, `read_bytes`, `execution_time`.
- Vượt quota → query bị từ chối tới hết interval. Xem `system.quotas`, `system.quota_usage`.

---

## 6. Settings Profiles & Constraints

Áp đặt/giới hạn settings cho user → chặn query nuốt hết RAM/CPU.

```sql
CREATE SETTINGS PROFILE restricted SETTINGS
  max_memory_usage = 5000000000 MAX 10000000000,    -- giá trị + trần cứng
  max_execution_time = 60 READONLY,                 -- user không đổi được
  max_threads = 4,
  readonly = 1
  TO reader;
```
- `CONSTRAINT`: `MIN`/`MAX`/`READONLY`/`CHANGEABLE_IN_READONLY` → khóa không cho user nâng giới hạn.
- Liên hệ memory & parallelism settings ở [clickhouse_performance.md](clickhouse_performance.md) và [clickhouse_query_execution.md](clickhouse_query_execution.md).

---

## 7. Column-level security

```sql
-- Cấp quyền đọc CHỈ một số cột (ẩn cột nhạy cảm)
GRANT SELECT(user_id, event_type, event_time) ON analytics.events TO reader;
-- reader KHÔNG select được cột email, ssn...

-- Masking động bằng View + role (ẩn/băm dữ liệu nhạy cảm)
CREATE VIEW analytics.events_masked AS
SELECT user_id, event_type,
       if(has(currentRoles(), 'pii_reader'), email, 'REDACTED') AS email
FROM analytics.events;
GRANT SELECT ON analytics.events_masked TO reader;
REVOKE SELECT ON analytics.events FROM reader;       -- chỉ cho qua view
```
> ClickHouse chưa có "dynamic data masking" native như một số DB thương mại → dùng **column GRANT + view** để đạt mục tiêu.

---

## 8. Network, TLS & External Auth

### Network
```xml
<!-- config.xml -->
<listen_host>0.0.0.0</listen_host>      <!-- cẩn thận: chỉ bind interface cần thiết -->
<tcp_port_secure>9440</tcp_port_secure> <!-- native TLS -->
<https_port>8443</https_port>           <!-- HTTPS -->
```
- Tắt port không mã hóa (8123/9000) ra ngoài; chỉ mở 8443/9440. Đặt sau firewall/VPC.
- `<openSSL>` cấu hình certificate, `<verificationMode>` cho mTLS (yêu cầu client cert).

### LDAP / Kerberos / SSL cert (SSO doanh nghiệp)
```xml
<ldap_servers><my_ldap>
  <host>ldap.example.com</host><port>636</port><enable_tls>yes</enable_tls>
  <bind_dn>uid={user_name},ou=users,dc=example,dc=com</bind_dn>
</my_ldap></ldap_servers>
```
- LDAP: xác thực password qua LDAP, hoặc map LDAP group → ClickHouse role (`<role_mapping>`).
- Kerberos: SSO ticket. SSL certificate: mTLS không cần password (mục 2).

---

## 9. Encryption

### In transit
TLS cho mọi giao tiếp client↔server và **inter-server** (replication/distributed): `<interserver_https_port>`, `secure=1`.

### At rest
```xml
<!-- Encrypted disk (AES) — mã hóa dữ liệu trên đĩa -->
<storage_configuration><disks>
  <enc><type>encrypted</type><disk>local_disk</disk>
       <key from_env="DISK_ENC_KEY"/></enc>
</disks></storage_configuration>
```
- Hoặc dựa vào mã hóa đĩa OS/cloud (LUKS, EBS encryption).

### Column-level encryption (function)
```sql
SELECT encrypt('aes-256-gcm', plaintext, key, iv);   -- mã hóa giá trị cụ thể
SELECT decrypt('aes-256-gcm', ciphertext, key, iv);
```
> Khóa nên lấy từ KMS/secret manager (không hardcode). Liên hệ secrets management (docker/security nếu có).

---

## 10. Audit & Compliance

| System table | Ghi gì |
|--------------|--------|
| `system.session_log` | Đăng nhập/đăng xuất, thành công/thất bại, user, địa chỉ |
| `system.query_log` | Mọi query: user, query text, thời gian, rows, lỗi |
| `system.text_log` | Log server chi tiết |
| `system.access`, `system.grants` | Trạng thái quyền hiện tại |

```sql
-- Phát hiện đăng nhập thất bại (brute force)
SELECT user, client_address, count() FROM system.session_log
WHERE type = 'LoginFailure' AND event_time > now() - INTERVAL 1 HOUR
GROUP BY user, client_address ORDER BY count() DESC;
```
> Đẩy log sang SIEM (ELK/Loki) để giám sát. Liên hệ monitoring ở [clickhouse_operations.md](clickhouse_operations.md).

---

## 11. Trade-offs & Best Practices

### Checklist production
- [ ] Khóa/đặt mật khẩu user `default`, tạo user theo least-privilege.
- [ ] Bật `access_management=1`, quản trị bằng SQL RBAC (replicate qua cluster).
- [ ] Role theo chức năng; row policy cho multi-tenant; quota + settings profile chặn query phá hoại.
- [ ] TLS cho client + inter-server; tắt port không mã hóa ra ngoài; firewall/VPC.
- [ ] Mã hóa at-rest (disk encrypted / OS) + secret từ KMS.
- [ ] Bật `session_log`/`query_log`, đẩy sang SIEM, alert login failure.

### Trade-offs
- (+) RBAC SQL: linh hoạt, replicate, granular tới cột; row policy cách ly tenant mạnh.
- (−) Row policy + column grant thêm overhead nhỏ & độ phức tạp; sai cấu hình row policy → lộ/giấu nhầm dữ liệu.
- (−) ClickHouse thiếu dynamic masking native → phải dùng view (bảo trì thêm).
- (−) TLS/encryption thêm chi phí CPU; cân bằng với mạng nội bộ tin cậy.

---

## Ghi chú – Keywords tiếp theo

- Liên quan: [clickhouse_operations.md](clickhouse_operations.md) (ON CLUSTER DDL, Keeper, monitoring), [clickhouse_production.md](clickhouse_production.md) (multi-tenancy), [clickhouse_query_execution.md](clickhouse_query_execution.md) (settings constraints), [clickhouse_performance.md](clickhouse_performance.md) (memory settings).
- **Keywords**: `access_control_path`, `SHOW ACCESS`, `currentUser()`/`currentRoles()`, `GRANT CURRENT GRANTS`, `system.privileges`, `allow_introspection_functions`, `distributed_ddl` security, `users_without_row_policies_can_read_rows`, `interserver_http_credentials`, named collections (ẩn credential cho S3/Kafka), `format_display_secrets_in_show_and_select`.

*Cập nhật lần cuối: 2026-06-04*
