---
title: "SQL Server Security"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 2
---
# SQL Server Security

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Ledger table và granular UNMASK là tính năng của 2022; Microsoft Entra ID authentication trên instance Arc-connected cũng từ 2022.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [HA & DR](ha_dr.md), [Backup & Recovery](backup_recovery.md). Đọc tiếp: [Linux & Containers](../platform/linux_containers.md).

---

## 1. Mô hình phòng thủ nhiều lớp

Mỗi lớp trả lời một câu hỏi khác nhau, và không lớp nào thay thế lớp khác:

```text
Mạng            : ai kết nối tới được port 1433?          → firewall, network policy, private endpoint
Kênh truyền     : dữ liệu trên đường có bị đọc được?      → TLS, mTLS
Authentication  : ai được đăng nhập?                       → Windows/Entra ID/SQL login
Authorization   : đăng nhập rồi được làm gì?               → role, GRANT/DENY, schema
Dữ liệu - hàng  : thấy được những hàng nào?                → Row-Level Security
Dữ liệu - cột   : thấy giá trị thật hay bị che?            → Dynamic Data Masking
Dữ liệu - mã hóa: DBA/kẻ lấy được file có đọc được?        → TDE, Always Encrypted
Toàn vẹn        : có bằng chứng dữ liệu chưa bị sửa?       → Ledger table
Bằng chứng      : ai đã làm gì, khi nào?                   → SQL Server Audit
```

Câu hỏi định hướng cho mọi quyết định trong tài liệu này là: **bạn đang phòng ai?**

| Mối đe dọa | Lớp bảo vệ đúng |
|---|---|
| Kẻ lấy được file `.mdf`/`.bak` | TDE, backup encryption |
| Kẻ nghe trên đường mạng | TLS |
| DBA nội bộ tò mò dữ liệu PII | Always Encrypted (TDE **không** chặn được) |
| Ứng dụng bị SQL injection | Tham số hóa + least privilege (DDM **không** chặn được) |
| Tenant A xem dữ liệu tenant B | RLS + kiểm soát ở tầng ứng dụng |
| Người dùng nội bộ sửa lịch sử giao dịch | Ledger table |
| Tài khoản bị chiếm | Audit + alert + MFA ở tầng identity |

---

## 2. Authentication

### 2.1 Các phương thức

| Phương thức | Cơ chế | Khi nào |
|---|---|---|
| **Windows / Kerberos** | SSPI, không có mật khẩu trong ứng dụng | Mặc định tốt nhất trên môi trường AD |
| **Microsoft Entra ID** | Token OAuth (Azure SQL; on-prem cần Arc-connected, 2022+) | Cloud/hybrid, muốn MFA và quản lý danh tính tập trung |
| **SQL login** | Username + mật khẩu trong SQL Server | Ứng dụng ngoài AD, container, Linux không join domain |
| **Contained database user** | Xác thực ở phạm vi database | AG failover, database di động |
| **Certificate / mTLS ở tầng client** | Chứng thư | Always Encrypted, kết nối máy–máy chặt |

```sql
-- Kiểm tra chế độ xác thực hiện tại
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS WindowsAuthOnly;   -- 1 = chỉ Windows

-- Windows login
CREATE LOGIN [CORP\svc-sales-app] FROM WINDOWS WITH DEFAULT_DATABASE = SalesDB;

-- SQL login: bắt buộc bật kiểm tra chính sách
CREATE LOGIN app_sales WITH
    PASSWORD = '<sinh ngẫu nhiên, lưu trong Vault>',
    DEFAULT_DATABASE = SalesDB,
    CHECK_POLICY = ON,
    CHECK_EXPIRATION = ON;

-- Contained user (không cần login ở instance) — hữu ích cho AG
ALTER DATABASE SalesDB SET CONTAINMENT = PARTIAL;
USE SalesDB;
CREATE USER app_sales WITH PASSWORD = '<...>';
```

Contained database user giải quyết đúng vấn đề "orphaned user sau failover/restore" đã nêu ở [ha_dr.md](ha_dr.md) mục 2.6: user và mật khẩu nằm trong chính database, nên đi theo database.

### 2.2 Xử lý orphaned user

```sql
-- User trong database không map được tới login nào
SELECT dp.name AS DbUser, dp.type_desc, dp.sid
FROM sys.database_principals dp
LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
WHERE dp.type IN ('S','U','G') AND dp.principal_id > 4 AND sp.sid IS NULL;

-- Nối lại
ALTER USER app_sales WITH LOGIN = app_sales;
```

Cách phòng ngừa gốc: khi tạo login trên nhiều instance, **tạo với cùng SID**:

```sql
-- Lấy SID và password hash từ instance nguồn
SELECT name, sid, password_hash FROM sys.sql_logins WHERE name = 'app_sales';

-- Tạo trên instance đích với cùng SID + hash (giữ nguyên mật khẩu)
CREATE LOGIN app_sales WITH PASSWORD = 0x0200... HASHED, SID = 0x1A2B..., CHECK_POLICY = OFF;
```

### 2.3 Cứng hóa authentication

```sql
-- Vô hiệu hóa sa (không xóa được; nên đổi tên và disable)
ALTER LOGIN sa DISABLE;
ALTER LOGIN sa WITH NAME = [disabled_sa_20260730];

-- Đăng nhập thất bại: ghi log để phát hiện dò mật khẩu
-- (mức 2 = failed only, 3 = successful only, 1 = both)
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
     N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', REG_DWORD, 2;

-- Login đang có quyền cao — rà soát định kỳ
SELECT sp.name, sp.type_desc, r.name AS ServerRole, sp.is_disabled, sp.create_date, sp.modify_date
FROM sys.server_role_members srm
JOIN sys.server_principals r  ON srm.role_principal_id = r.principal_id
JOIN sys.server_principals sp ON srm.member_principal_id = sp.principal_id
WHERE r.name IN ('sysadmin','securityadmin','serveradmin','setupadmin','processadmin','dbcreator')
ORDER BY r.name, sp.name;
```

---

## 3. Authorization

### 3.1 Ba tầng principal

```text
Server level : login, server role      → quyền trên instance
Database     : user, database role     → quyền trong một database
Schema/object: GRANT/DENY/REVOKE       → quyền trên đối tượng cụ thể
```

```sql
-- Server role: least privilege thay cho sysadmin
CREATE SERVER ROLE [role_readonly_dba];
GRANT VIEW SERVER STATE, VIEW ANY DEFINITION, VIEW ANY DATABASE TO [role_readonly_dba];
ALTER SERVER ROLE [role_readonly_dba] ADD MEMBER [CORP\Monitoring];

-- Database role tự định nghĩa — đây là cách nên làm, không dùng db_datareader/writer bừa
USE SalesDB;
CREATE ROLE [role_app_sales];
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Sales TO [role_app_sales];
GRANT EXECUTE                 ON SCHEMA::Sales TO [role_app_sales];
DENY  DELETE                  ON SCHEMA::Sales TO [role_app_sales];   -- xóa phải qua procedure
GRANT SELECT                  ON SCHEMA::Reference TO [role_app_sales];
ALTER ROLE [role_app_sales] ADD MEMBER app_sales;
```

Nguyên tắc quan trọng: **cấp quyền cho role, không cấp cho user**. Khi có người/ứng dụng mới, thêm vào role; khi rời đi, bỏ khỏi role. Cấp quyền trực tiếp cho user tạo ra mê cung không thể rà soát sau vài năm.

### 3.2 Thứ tự ưu tiên: DENY thắng GRANT

```sql
GRANT SELECT ON SCHEMA::Sales TO [role_app_sales];
DENY  SELECT ON Sales.Employees(Salary) TO [role_app_sales];   -- DENY thắng, dù GRANT ở mức schema
```

`DENY` luôn thắng `GRANT`, ở mọi mức — **trừ** thành viên `sysadmin`, những người bỏ qua toàn bộ kiểm tra quyền. Đây là lý do `sysadmin` phải là danh sách rất ngắn và được audit.

### 3.3 Ownership chaining và EXECUTE AS

```sql
-- Mẫu tốt nhất: app chỉ được EXECUTE procedure, không được truy cập bảng trực tiếp
CREATE OR ALTER PROCEDURE Sales.usp_CancelOrder @OrderID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Sales.Orders SET Status = 'CANCELLED' WHERE OrderID = @OrderID AND Status = 'PENDING';
    IF @@ROWCOUNT = 0 THROW 50040, 'Order not cancellable', 1;
END
GO
GRANT EXECUTE ON Sales.usp_CancelOrder TO [role_app_sales];
-- Không cần GRANT UPDATE trên Sales.Orders: ownership chaining lo phần đó
-- (điều kiện: procedure và bảng cùng owner)
```

Lợi ích kép của mẫu này: quyền tối thiểu **và** một điểm kiểm soát logic nghiệp vụ. Ngay cả khi ứng dụng có lỗ SQL injection, kẻ tấn công cũng chỉ gọi được các procedure đã định nghĩa.

Khi procedure cần chạm bảng khác owner, ownership chaining đứt và cần `EXECUTE AS`:

```sql
CREATE OR ALTER PROCEDURE Audit.usp_WriteEvent @Payload NVARCHAR(MAX)
WITH EXECUTE AS OWNER      -- chạy với quyền của owner, không phải của người gọi
AS
BEGIN
    INSERT INTO Audit.Events (Payload, CreatedAt, ActualUser)
    VALUES (@Payload, SYSUTCDATETIME(), ORIGINAL_LOGIN());   -- vẫn ghi được người gọi thật
END
```

`ORIGINAL_LOGIN()` là hàm quan trọng khi dùng `EXECUTE AS`: nó trả về danh tính thật ở đầu chuỗi, không phải danh tính đang mượn. Không có nó, audit trở nên vô nghĩa.

### 3.4 Rà soát quyền

```sql
-- Quyền hiệu lực của user hiện tại
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
SELECT * FROM fn_my_permissions('Sales.Orders', 'OBJECT');

-- Toàn bộ quyền đã cấp trong database (báo cáo audit)
SELECT
    dp.name                                            AS Principal,
    dp.type_desc                                       AS PrincipalType,
    p.class_desc,
    CASE p.class
        WHEN 0 THEN DB_NAME()
        WHEN 1 THEN OBJECT_SCHEMA_NAME(p.major_id) + '.' + OBJECT_NAME(p.major_id)
        WHEN 3 THEN SCHEMA_NAME(p.major_id)
    END                                                AS SecurableName,
    p.permission_name, p.state_desc
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.principal_id > 4
ORDER BY Principal, SecurableName, p.permission_name;

-- Thành viên của từng database role
SELECT r.name AS RoleName, m.name AS MemberName, m.type_desc
FROM sys.database_role_members drm
JOIN sys.database_principals r ON drm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON drm.member_principal_id = m.principal_id
ORDER BY r.name, m.name;
```

---

## 4. TLS cho kênh truyền

```sql
-- Kết nối nào đang được mã hóa
SELECT c.session_id, s.login_name, s.program_name, s.host_name,
       c.encrypt_option, c.net_transport, c.protocol_type, c.client_net_address
FROM sys.dm_exec_connections c
JOIN sys.dm_exec_sessions s ON c.session_id = s.session_id
WHERE s.is_user_process = 1;
```

Ba mức cấu hình, khác nhau về mức đảm bảo:

| Cấu hình | Kết quả |
|---|---|
Server không bắt buộc, client không yêu cầu | Chỉ handshake login được mã hóa; dữ liệu đi trần |
| Client `encrypt=true;trustServerCertificate=true` | Dữ liệu được mã hóa, nhưng **không xác minh danh tính server** → vẫn bị MITM |
| Client `encrypt=true;trustServerCertificate=false` + certificate hợp lệ | Mã hóa **và** xác minh — mức đúng cho production |

Trên Linux, cấu hình certificate qua `mssql-conf`:

```bash
sudo /opt/mssql/bin/mssql-conf set network.tlscert /etc/ssl/certs/mssql.pem
sudo /opt/mssql/bin/mssql-conf set network.tlskey  /etc/ssl/private/mssql.key
sudo /opt/mssql/bin/mssql-conf set network.tlsprotocols 1.2,1.3
sudo /opt/mssql/bin/mssql-conf set network.forceencryption 1
sudo systemctl restart mssql-server
```

`trustServerCertificate=true` là mặc định trong rất nhiều ví dụ trên internet và là một trong những cấu hình sai phổ biến nhất trong production: nó cho cảm giác an toàn (dữ liệu "được mã hóa") nhưng không chặn được kẻ đứng giữa. Chi tiết cho phía Java: [jdbc_java.md](../integration/jdbc_java.md).

---

## 5. Row-Level Security (RLS)

```sql
CREATE SCHEMA Security;
GO

-- Predicate function: trả về hàng nào thì hàng đó được thấy
CREATE OR ALTER FUNCTION Security.fn_TenantAccess (@TenantID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS ok
    WHERE
        -- Ứng dụng đặt tenant vào SESSION_CONTEXT sau khi xác thực
        @TenantID = CAST(SESSION_CONTEXT(N'TenantID') AS INT)
        -- Role vận hành thấy tất cả
        OR IS_MEMBER('role_platform_admin') = 1;
GO

CREATE SECURITY POLICY Security.TenantIsolation
ADD FILTER PREDICATE Security.fn_TenantAccess(TenantID) ON Sales.Orders,
ADD BLOCK  PREDICATE Security.fn_TenantAccess(TenantID) ON Sales.Orders AFTER INSERT,
ADD BLOCK  PREDICATE Security.fn_TenantAccess(TenantID) ON Sales.Orders AFTER UPDATE,
ADD FILTER PREDICATE Security.fn_TenantAccess(TenantID) ON Sales.OrderItems
WITH (STATE = ON, SCHEMABINDING = ON);
GO
```

Ứng dụng đặt context ngay sau khi lấy connection từ pool:

```sql
EXEC sys.sp_set_session_context @key = N'TenantID', @value = 42, @read_only = 1;
```

`@read_only = 1` là chi tiết bảo mật then chốt: sau khi đặt, chính session đó **không thể đổi** giá trị nữa trong suốt phiên. Không có nó, một lỗ SQL injection có thể đặt lại `TenantID` và vượt qua RLS hoàn toàn.

### 5.1 FILTER vs BLOCK

| Predicate | Tác dụng |
|---|---|
| `FILTER` | Ẩn hàng khỏi `SELECT`/`UPDATE`/`DELETE` — hàng "không tồn tại" với user đó |
| `BLOCK AFTER INSERT` | Chặn chèn hàng mà user sẽ không được thấy |
| `BLOCK AFTER UPDATE` | Chặn sửa hàng sang giá trị vượt phạm vi của user |
| `BLOCK BEFORE UPDATE/DELETE` | Chặn sửa/xóa hàng ngoài phạm vi |

Chỉ dùng `FILTER` là lỗ hổng: user có thể `INSERT` một hàng với `TenantID` của tenant khác — hàng đó sẽ biến mất khỏi tầm nhìn của họ nhưng đã ghi vào dữ liệu người khác. Vì vậy **luôn cặp FILTER với BLOCK**.

### 5.2 Hiệu năng và giới hạn của RLS

| Vấn đề | Chi tiết |
|---|---|
| Predicate được thêm vào mọi query | Cần index trên cột dùng để lọc (`TenantID` đứng đầu index) |
| Hàm predicate phải rất nhẹ | Tránh join/subquery bên trong; `SESSION_CONTEXT` hoặc `IS_MEMBER` là lựa chọn tốt |
| `sysadmin`/`db_owner` bỏ qua? | Không — RLS áp cho cả họ (khác DDM), trừ khi hàm predicate tự cho phép |
| Có thể suy luận thông tin qua kênh phụ | Ví dụ lỗi divide-by-zero hoặc unique violation tiết lộ sự tồn tại của hàng ẩn |
| RLS không thay thế kiểm soát tầng ứng dụng | Nó là lớp phòng thủ thứ hai, rất giá trị, nhưng không phải duy nhất |

```sql
-- Bật/tắt policy khi bảo trì
ALTER SECURITY POLICY Security.TenantIsolation WITH (STATE = OFF);
ALTER SECURITY POLICY Security.TenantIsolation WITH (STATE = ON);

-- Kiểm thử
EXECUTE AS USER = 'app_sales';
EXEC sys.sp_set_session_context @key = N'TenantID', @value = 42;
SELECT COUNT(*) FROM Sales.Orders;    -- chỉ tenant 42
REVERT;
```

---

## 6. Dynamic Data Masking (DDM)

```sql
CREATE TABLE Sales.Customers (
    CustomerID  INT IDENTITY PRIMARY KEY,
    FullName    NVARCHAR(100),
    Email       NVARCHAR(200) MASKED WITH (FUNCTION = 'email()'),
    Phone       VARCHAR(20)   MASKED WITH (FUNCTION = 'partial(3,"XXXX",2)'),
    NationalID  CHAR(12)      MASKED WITH (FUNCTION = 'default()'),
    CreditLimit DECIMAL(19,4) MASKED WITH (FUNCTION = 'random(1000, 5000)')
);

-- Thêm mask cho cột có sẵn
ALTER TABLE Sales.Customers
ALTER COLUMN CardNumber ADD MASKED WITH (FUNCTION = 'partial(0,"XXXX-XXXX-XXXX-",4)');

-- Quyền xem dữ liệu thật
GRANT UNMASK ON SCHEMA::Sales TO [role_support_lead];       -- toàn schema
GRANT UNMASK ON Sales.Customers(Email) TO [role_support];   -- 2022+: từng cột
```

Granular `UNMASK` theo cột (2022+) là cải tiến thực tế đáng kể: trước đó `UNMASK` là quyền all-or-nothing ở phạm vi database, nên gần như không dùng được cho mô hình "support xem được email nhưng không xem được số thẻ".

**Điều bắt buộc phải hiểu về DDM:** nó chỉ che ở tầng trả kết quả. Dữ liệu trong file vẫn là plaintext, và người có quyền `SELECT` có thể suy ra giá trị:

```sql
-- User bị mask vẫn dò được giá trị thật bằng cách này
SELECT COUNT(*) FROM Sales.Customers WHERE CreditLimit > 50000000;
SELECT * FROM Sales.Customers WHERE Email LIKE 'ceo@%';
```

Kết luận đúng: DDM là biện pháp **giảm phơi nhiễm tình cờ** (nhân viên support không vô tình thấy PII trên màn hình), không phải biện pháp bảo mật chống người có ý đồ. Với dữ liệu thật sự nhạy cảm, dùng Always Encrypted.

---

## 7. TDE – mã hóa dữ liệu tại chỗ nghỉ

```sql
-- 1. Service master key → database master key trong master
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong>';

-- 2. Certificate bảo vệ DEK
CREATE CERTIFICATE TDE_SalesDB WITH SUBJECT = 'TDE for SalesDB', EXPIRY_DATE = '2031-12-31';

-- 3. BACKUP CERTIFICATE — bước không được bỏ, làm NGAY
BACKUP CERTIFICATE TDE_SalesDB TO FILE = '/secure/TDE_SalesDB.cer'
WITH PRIVATE KEY (FILE = '/secure/TDE_SalesDB.pvk', ENCRYPTION BY PASSWORD = '<strong2>');

-- 4. DEK trong database đích
USE SalesDB;
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TDE_SalesDB;

-- 5. Bật
ALTER DATABASE SalesDB SET ENCRYPTION ON;

-- Theo dõi tiến độ
SELECT DB_NAME(database_id) AS DbName, encryption_state_desc, percent_complete,
       key_algorithm, key_length, encryptor_type
FROM sys.dm_database_encryption_keys;
```

TDE bảo vệ và không bảo vệ những gì:

| Bảo vệ | Không bảo vệ |
|---|---|
| Data file, log file bị copy đi | Dữ liệu qua kết nối (cần TLS) |
| Backup file bị lấy | Người có quyền `SELECT` |
| Snapshot storage bị truy cập | DBA (`sysadmin` đọc bình thường) |
| Ổ đĩa bị tháo mang đi | Dump memory của tiến trình |

Ba lưu ý vận hành:

1. Bật TDE trên bất kỳ database nào cũng **mã hóa luôn `tempdb`** cho toàn instance — nghĩa là có ảnh hưởng hiệu năng lên mọi database, kể cả không bật TDE.
2. Backup của database TDE **không nén hiệu quả** trừ khi `MAXTRANSFERSIZE > 65536` ([backup_recovery.md](backup_recovery.md) mục 3.1).
3. Với Always On, **mọi replica cần cùng certificate** — nếu không, secondary không mở được database.

### 7.1 Extensible Key Management (EKM)

Thay vì certificate trong `master`, khóa gốc có thể nằm trong HSM hoặc Azure Key Vault:

```sql
CREATE CRYPTOGRAPHIC PROVIDER AzureKeyVault
    FROM FILE = 'C:\Program Files\SQL Server Connector for Microsoft Azure Key Vault\Microsoft.AzureKeyVaultService.EKM.dll';

CREATE CREDENTIAL AkvCred WITH IDENTITY = '<vault-name>', SECRET = '<clientId><clientSecret>'
    FOR CRYPTOGRAPHIC PROVIDER AzureKeyVault;

CREATE ASYMMETRIC KEY TDE_AKV_Key
    FROM PROVIDER AzureKeyVault
    WITH PROVIDER_KEY_NAME = 'tde-sales-key', CREATION_DISPOSITION = OPEN_EXISTING;

USE SalesDB;
CREATE DATABASE ENCRYPTION KEY WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER ASYMMETRIC KEY TDE_AKV_Key;
```

Lợi ích của EKM: khóa gốc không nằm trên máy database, rotate và audit tập trung, và **thu hồi khóa** trở thành một hành động khả thi (khi máy bị chiếm, revoke key ở vault làm dữ liệu không đọc được).

---

## 8. Always Encrypted – mã hóa mà server không thấy plaintext

```text
Column Master Key (CMK)      : nằm NGOÀI SQL Server (Windows cert store / Azure Key Vault / HSM)
      └── mã hóa Column Encryption Key (CEK)
              └── mã hóa dữ liệu cột

SQL Server chỉ giữ ciphertext và metadata về khóa.
Driver ở phía CLIENT mã hóa/giải mã. DBA không đọc được dữ liệu.
```

```sql
CREATE COLUMN MASTER KEY CMK_Sales
WITH (KEY_STORE_PROVIDER_NAME = N'AZURE_KEY_VAULT',
      KEY_PATH = N'https://vault.vault.azure.net/keys/cmk-sales/abc123');

CREATE COLUMN ENCRYPTION KEY CEK_Sales
WITH VALUES (COLUMN_MASTER_KEY = CMK_Sales, ALGORITHM = 'RSA_OAEP',
             ENCRYPTED_VALUE = 0x01700000...);

CREATE TABLE HR.Employees (
    EmployeeID INT PRIMARY KEY,
    FullName   NVARCHAR(100),
    NationalID CHAR(12) COLLATE Latin1_General_BIN2 ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Sales,
        ENCRYPTION_TYPE = DETERMINISTIC,     -- cho phép so sánh bằng, join, GROUP BY
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'),
    Salary DECIMAL(19,4) ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = CEK_Sales,
        ENCRYPTION_TYPE = RANDOMIZED,        -- an toàn hơn, nhưng không so sánh/sắp xếp được
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256')
);
```

| | DETERMINISTIC | RANDOMIZED |
|---|---|---|
| Cùng plaintext → cùng ciphertext | Có | Không |
| So sánh bằng, join, `GROUP BY`, index | Được | Không |
| So sánh dải, `LIKE`, `ORDER BY`, tính toán | Không | Không |
| Rủi ro suy luận từ phân bố | Có (cột ít giá trị phân biệt bị lộ pattern) | Không |
| Collation yêu cầu | `_BIN2` | `_BIN2` |

Giới hạn thực tế phải cân trước khi chọn Always Encrypted:

- Không `LIKE`, không so sánh dải, không `SUM`/`AVG` trên cột đã mã hóa (trừ khi dùng secure enclave nếu môi trường hỗ trợ).
- Mọi truy vấn phải **tham số hóa**; literal trong SQL không mã hóa được.
- Driver phải hỗ trợ và bật tính năng (`columnEncryptionSetting=Enabled` với JDBC).
- Thao tác bulk và ETL phức tạp hơn nhiều.
- Đổi khóa (rotate CEK) là quá trình phải ghi lại toàn bộ dữ liệu cột.

Cấu hình phía Java:

```properties
jdbc:sqlserver://sql1:1433;databaseName=SalesDB;encrypt=true;
  columnEncryptionSetting=Enabled;
  keyVaultProviderClientId=<...>;keyVaultProviderClientKey=<...>
```

Chọn giữa TDE và Always Encrypted không phải "cái nào tốt hơn" mà là "phòng ai": TDE phòng kẻ lấy file, Always Encrypted phòng cả người vận hành database. Nhiều hệ thống dùng cả hai: TDE cho toàn database, Always Encrypted cho vài cột PII nhạy cảm nhất.

---

## 9. Ledger table (SQL Server 2022+)

Ledger cung cấp **bằng chứng mật mã** rằng dữ liệu chưa bị sửa lịch sử — kể cả bởi người có quyền cao nhất.

```sql
-- Bảng có thể update, nhưng mọi thay đổi để lại dấu vết không xóa được
CREATE TABLE Finance.Balance (
    AccountID INT PRIMARY KEY,
    Amount    DECIMAL(19,4) NOT NULL
) WITH (LEDGER = ON);

-- Bảng chỉ được chèn thêm, không update/delete
CREATE TABLE Finance.Journal (
    EntryID   BIGINT IDENTITY PRIMARY KEY,
    AccountID INT NOT NULL,
    Amount    DECIMAL(19,4) NOT NULL,
    Memo      NVARCHAR(200) NULL
) WITH (LEDGER = ON (APPEND_ONLY = ON));

-- Xác minh toàn vẹn: engine tính lại hash tree và so với digest đã lưu ngoài
EXEC sys.sp_verify_database_ledger_from_digest_storage
     @table_name = NULL,
     @digest_locations = N'[{"path":"https://acct.blob.core.windows.net/ledger-digest"}]';
```

Khác biệt so với temporal table và audit — ba cơ chế nghe giống nhau nhưng khác bản chất:

| | Temporal table | SQL Server Audit | Ledger |
|---|---|---|---|
| Trả lời | Dữ liệu trông thế nào lúc đó | Ai làm gì khi nào | Dữ liệu có bị sửa lịch sử không |
| Có thể bị người có quyền cao xóa/sửa? | Có | Có (nếu ghi trên cùng hệ thống) | **Không**, nếu digest lưu ngoài |
| Chi phí | Bảng history | I/O ghi audit | Hash tree + digest, chi phí ghi cao hơn |

Ledger phù hợp cho dữ liệu cần chứng minh với bên thứ ba (tài chính, y tế, chuỗi cung ứng, log tuân thủ). Nó không thay thế audit — audit vẫn cần để biết *ai*.

---

## 10. SQL Server Audit

```sql
-- 1. Server audit: đích ghi
USE master;
CREATE SERVER AUDIT SalesAudit
TO FILE (FILEPATH = '/var/opt/mssql/audit/', MAXSIZE = 256MB,
         MAX_ROLLOVER_FILES = 40, RESERVE_DISK_SPACE = OFF)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
ALTER SERVER AUDIT SalesAudit WITH (STATE = ON);

-- 2. Server audit specification: sự kiện mức instance
CREATE SERVER AUDIT SPECIFICATION SrvAuditSpec
FOR SERVER AUDIT SalesAudit
ADD (FAILED_LOGIN_GROUP),
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
ADD (SERVER_PERMISSION_CHANGE_GROUP),
ADD (AUDIT_CHANGE_GROUP),                  -- ai sửa chính cấu hình audit
ADD (SERVER_PRINCIPAL_CHANGE_GROUP)
WITH (STATE = ON);

-- 3. Database audit specification: sự kiện trong database
USE SalesDB;
CREATE DATABASE AUDIT SPECIFICATION DbAuditSpec
FOR SERVER AUDIT SalesAudit
ADD (SELECT, INSERT, UPDATE, DELETE ON HR.Employees BY PUBLIC),   -- bảng nhạy cảm
ADD (SCHEMA_OBJECT_CHANGE_GROUP),                                  -- DDL
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
ADD (DATABASE_PERMISSION_CHANGE_GROUP)
WITH (STATE = ON);
```

```sql
-- Đọc audit log
SELECT event_time, action_id, succeeded,
       server_principal_name, database_principal_name,
       database_name, schema_name, object_name,
       client_ip, application_name, statement
FROM sys.fn_get_audit_file('/var/opt/mssql/audit/*.sqlaudit', DEFAULT, DEFAULT)
WHERE event_time > DATEADD(HOUR, -24, SYSUTCDATETIME())
ORDER BY event_time DESC;
```

Bốn quyết định thiết kế audit:

| Quyết định | Đánh đổi |
|---|---|
| `ON_FAILURE = CONTINUE` vs `SHUTDOWN` | `SHUTDOWN` đảm bảo không có hành động nào không được ghi, nhưng đĩa audit đầy = instance dừng. `FAIL_OPERATION` là trung gian. |
| `QUEUE_DELAY = 0` (đồng bộ) vs > 0 | Đồng bộ không mất event nhưng chậm hơn |
| Audit `SUCCESSFUL_LOGIN_GROUP` | Rất nhiều event; thường không đáng trên hệ có connection pool |
| Audit `SELECT` trên bảng nóng | Có thể sinh khối lượng khổng lồ; giới hạn cho bảng nhạy cảm |

Nguyên tắc không thể thiếu: **audit log phải được chuyển ra khỏi server** (SIEM, Elasticsearch, Splunk). Audit lưu trên chính máy bị xâm nhập là audit mà kẻ tấn công có thể xóa. `AUDIT_CHANGE_GROUP` ở trên chính là để phát hiện ai đã cố tắt audit.

---

## 11. Cứng hóa bề mặt tấn công

```sql
-- Tắt các tính năng không dùng
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 0;                        RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 0;          RECONFIGURE;
EXEC sp_configure 'Ad Hoc Distributed Queries', 0;         RECONFIGURE;
EXEC sp_configure 'clr enabled', 0;                        RECONFIGURE;   -- nếu không dùng CLR
EXEC sp_configure 'remote admin connections', 0;           RECONFIGURE;
EXEC sp_configure 'cross db ownership chaining', 0;        RECONFIGURE;
EXEC sp_configure 'default trace enabled', 1;              RECONFIGURE;

-- Rà soát cấu hình lệch khỏi mặc định an toàn
SELECT name, value_in_use, description
FROM sys.configurations
WHERE name IN ('xp_cmdshell','Ole Automation Procedures','Ad Hoc Distributed Queries',
               'clr enabled','remote access','cross db ownership chaining',
               'scan for startup procs','remote admin connections')
ORDER BY name;

-- Linked server: bề mặt tấn công thường bị bỏ quên (kèm credential lưu sẵn)
SELECT s.name AS LinkedServer, s.product, s.provider, s.data_source,
       l.remote_name, l.uses_self_credential
FROM sys.servers s
LEFT JOIN sys.linked_logins l ON s.server_id = l.server_id
WHERE s.server_id > 0;
```

`xp_cmdshell` là mục tiêu số một của kẻ tấn công sau khi có được quyền `sysadmin`: nó cho thực thi lệnh OS. Nếu nghiệp vụ cần chạy lệnh OS, dùng SQL Agent job với proxy account có quyền hạn hẹp, không bật `xp_cmdshell` toàn cục.

---

## 12. Trade-offs

| Biện pháp | Được | Mất | Khi nào |
|---|---|---|---|
| Windows/Entra ID auth | Không có mật khẩu trong app, MFA, quản lý tập trung | Cần AD/Entra; khó trên container không join domain | Mặc định nếu môi trường cho phép |
| Contained database user | Sống sót qua failover/restore | Quản lý mật khẩu phân tán theo database | AG, database di động |
| Quyền chỉ qua stored procedure | Least privilege thật, một điểm kiểm soát | Nhiều procedure phải viết và bảo trì | Ứng dụng nghiệp vụ quan trọng |
| RLS | Cách ly dữ liệu ở tầng engine | Overhead mỗi query; cần index đúng; có kênh suy luận | Multi-tenant, dữ liệu phân quyền theo hàng |
| DDM | Nhanh, không sửa app | Không phải bảo mật thật; dò được | Giảm phơi nhiễm tình cờ |
| TDE | Bảo vệ file/backup, không sửa app | Mã hóa cả tempdb toàn instance; rủi ro mất certificate | Gần như luôn nên bật cho production |
| Always Encrypted | DBA không đọc được | Mất `LIKE`/range/aggregate; app phải sửa; khóa phức tạp | Vài cột PII nhạy cảm nhất |
| Ledger | Bằng chứng chống sửa lịch sử | Chi phí ghi cao hơn, cần digest lưu ngoài | Dữ liệu cần chứng minh với bên thứ ba |
| Audit chi tiết | Bằng chứng đầy đủ | I/O, dung lượng, có thể ảnh hưởng hiệu năng | Bảng nhạy cảm và sự kiện quyền hạn |
| `ON_FAILURE = SHUTDOWN` | Không hành động nào không được ghi | Đĩa audit đầy = instance dừng | Yêu cầu tuân thủ chặt |

---

## 13. Checklist bảo mật

```text
Authentication
□ sa disabled (và đổi tên)
□ Ưu tiên Windows/Entra ID; SQL login chỉ khi bắt buộc
□ Mật khẩu SQL login sinh ngẫu nhiên, lưu trong Vault/Key Vault, không trong config/wiki
□ CHECK_POLICY = ON cho mọi SQL login
□ Audit failed login đã bật và có alert khi đột biến
□ Rà soát thành viên sysadmin/securityadmin mỗi quý

Authorization
□ Không có ứng dụng nào chạy bằng sysadmin hoặc db_owner
□ Quyền cấp cho ROLE, không cấp trực tiếp cho user
□ Ứng dụng chỉ EXECUTE procedure ở đường đi quan trọng
□ Không có orphaned user
□ Báo cáo quyền được sinh và rà soát định kỳ
□ Linked server được kiểm kê, credential được rà soát

Mã hóa & kênh truyền
□ TLS bắt buộc; client dùng encrypt=true, trustServerCertificate=false
□ TLS 1.2/1.3, đã tắt các phiên bản cũ
□ TDE bật cho database production
□ Certificate TDE/backup đã backup ra ngoài, mật khẩu trong Vault
□ Backup encryption bật cho backup ra ngoài site
□ Always Encrypted cho cột PII nhạy cảm nhất (nếu có yêu cầu)

Dữ liệu
□ RLS có cả FILTER và BLOCK predicate
□ sp_set_session_context dùng @read_only = 1
□ DDM không bị coi là biện pháp bảo mật chính
□ Ledger cho dữ liệu cần chứng minh toàn vẹn

Bề mặt tấn công
□ xp_cmdshell, OLE Automation, Ad Hoc Distributed Queries đã tắt
□ CLR tắt nếu không dùng
□ Port 1433 chỉ mở cho subnet/pod cần thiết (network policy)
□ Chỉ cài các thành phần thực sự dùng

Audit & giám sát
□ Server audit + database audit spec bật cho sự kiện quyền hạn và bảng nhạy cảm
□ AUDIT_CHANGE_GROUP được audit (phát hiện ai tắt audit)
□ Audit log chuyển ra SIEM ngoài server
□ Alert: failed login đột biến, thay đổi role, DDL bất thường

Vá lỗi
□ CU trong vòng 3 tháng so với bản mới nhất
□ OS được vá
□ Có quy trình kiểm thử CU trước khi lên production
```

---

## 14. Ghi chú – chủ đề tiếp theo

- [linux_containers.md](../platform/linux_containers.md): cứng hóa khi chạy trong container/K8s, secret management.
- [jdbc_java.md](../integration/jdbc_java.md): TLS, Always Encrypted, session context từ phía Java.
- [backup_recovery.md](backup_recovery.md): quản lý certificate, backup encryption.
- [sqlserver_2025.md](../modern/sqlserver_2025.md): các bổ sung bảo mật của version mới.
- [security package](../../security/roadmap.md): OWASP, threat modeling, DevSecOps ở phạm vi rộng hơn.

Từ khóa mở rộng: `sp_set_session_context` + RLS cho multi-tenant, cell-level encryption (`ENCRYPTBYKEY`), `sys.dm_exec_connections.encrypt_option`, SQL Vulnerability Assessment, Microsoft Defender for SQL, Managed Identity cho Arc-connected instance, service account với quyền tối thiểu trên OS.

---

*Cập nhật lần cuối: 2026-07-30*
