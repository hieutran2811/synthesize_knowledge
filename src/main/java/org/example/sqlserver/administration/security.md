# SQL Server Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – SQL Server Security Model

SQL Server có **layered security**: Authentication (ai được login), Authorization (được làm gì), Encryption (data được bảo vệ thế nào).

```
Security Layers:
  Network:         TLS encryption, firewall
  Instance:        Logins (SQL/Windows/Azure AD)
  Database:        Users, Roles, Schema
  Object:          GRANT/DENY/REVOKE per table/view/proc
  Row:             Row-Level Security (RLS)
  Column:          Dynamic Data Masking, Always Encrypted
  Data at rest:    TDE (Transparent Data Encryption)
```

---

## How – Authentication Modes

```sql
-- Windows Authentication (Recommended):
-- SSPI, Kerberos/NTLM, no passwords in app → most secure
-- SQL Server Agent, maintenance jobs: Windows service accounts

-- SQL Server Authentication (Mixed Mode):
-- Username + password stored in SQL Server
-- Less secure but required for non-Windows clients

-- Enable Mixed Mode (via SSMS or registry)
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode', REG_DWORD, 2;  -- 1=Windows only, 2=Mixed
-- Restart SQL Server after change

-- Check current authentication mode
EXEC xp_loginconfig 'login mode';
```

---

## How – Logins, Users, Roles

### Logins (Instance level)

```sql
-- Windows login
CREATE LOGIN [DOMAIN\SQLService] FROM WINDOWS
WITH DEFAULT_DATABASE = master;

-- SQL login
CREATE LOGIN AppUser WITH
    PASSWORD = 'S3cur3P@ssw0rd!',
    DEFAULT_DATABASE = SalesDB,
    CHECK_POLICY = ON,       -- enforce Windows password policy
    CHECK_EXPIRATION = ON;   -- enforce password expiration

-- Disable/Enable login
ALTER LOGIN AppUser DISABLE;
ALTER LOGIN AppUser ENABLE;

-- Change password
ALTER LOGIN AppUser WITH PASSWORD = 'NewP@ssw0rd!' OLD_PASSWORD = 'S3cur3P@ssw0rd!';

-- Server-level roles
ALTER SERVER ROLE sysadmin ADD MEMBER [DOMAIN\DBATeam];
ALTER SERVER ROLE serveradmin ADD MEMBER [DOMAIN\OpsTeam];

-- Built-in server roles:
-- sysadmin:       full control (avoid!)
-- serveradmin:    server settings
-- securityadmin:  manage logins
-- bulkadmin:      BULK INSERT
-- dbcreator:      create/alter/drop/restore databases
-- diskadmin:      manage disk files
-- processadmin:   kill processes
-- public:         all logins (minimal permissions)
```

### Users & Database Roles

```sql
-- Create database user mapped to login
USE SalesDB;
CREATE USER AppUser FOR LOGIN AppUser
    WITH DEFAULT_SCHEMA = dbo;

-- Contained database user (không cần login at instance level)
CREATE USER ContainedUser WITH PASSWORD = 'P@ssw0rd!';
-- Requires: ALTER DATABASE SalesDB SET CONTAINMENT = PARTIAL;

-- Add to database roles
ALTER ROLE db_datareader ADD MEMBER AppUser;   -- SELECT trên tất cả tables
ALTER ROLE db_datawriter ADD MEMBER AppUser;   -- INSERT/UPDATE/DELETE
ALTER ROLE db_ddladmin ADD MEMBER AppUser;     -- DDL changes

-- Built-in database roles:
-- db_owner:              tất cả quyền trong DB
-- db_securityadmin:      manage roles/users
-- db_accessadmin:        manage access
-- db_backupoperator:     backup database
-- db_ddladmin:           DDL (CREATE/ALTER/DROP)
-- db_datawriter:         INSERT/UPDATE/DELETE tất cả tables
-- db_datareader:         SELECT tất cả tables
-- db_denydatawriter:     DENY write
-- db_denydatareader:     DENY read
-- public:                default, tất cả users

-- Custom database role
CREATE ROLE SalesReader;
GRANT SELECT ON SCHEMA::Sales TO SalesReader;
GRANT EXECUTE ON dbo.GetSalesReport TO SalesReader;
ALTER ROLE SalesReader ADD MEMBER ReportingUser;
```

### Schema Separation

```sql
-- Schema: logical namespace + ownership boundary
CREATE SCHEMA Sales AUTHORIZATION SalesTeam;
CREATE SCHEMA Finance AUTHORIZATION FinanceTeam;
CREATE SCHEMA Audit;

-- Move objects to schema
ALTER SCHEMA Sales TRANSFER dbo.Orders;
ALTER SCHEMA Sales TRANSFER dbo.Customers;

-- Grant permission at schema level
GRANT SELECT ON SCHEMA::Sales TO SalesReader;
DENY SELECT ON SCHEMA::Finance TO SalesReader;

-- Fine-grained: grant per table/view/procedure
GRANT SELECT ON Sales.Orders TO ReportUser;
GRANT EXECUTE ON Sales.usp_GetCustomerOrders TO AppUser;
GRANT SELECT, INSERT, UPDATE ON Sales.Orders TO WriteUser;
DENY DELETE ON Sales.Orders TO WriteUser;

-- View effective permissions
SELECT * FROM fn_my_permissions(NULL, 'DATABASE');
SELECT * FROM fn_my_permissions('Sales.Orders', 'OBJECT');

-- Xem user permissions
SELECT
    dp.name AS Principal,
    dp.type_desc,
    p.permission_name,
    p.state_desc,
    OBJECT_NAME(p.major_id) AS ObjectName
FROM sys.database_permissions p
JOIN sys.database_principals dp ON p.grantee_principal_id = dp.principal_id
WHERE dp.name = 'AppUser';
```

---

## How – Row-Level Security (RLS)

```sql
-- RLS: filter rows based on current user context
-- Transparent to application (no WHERE clause needed)

-- Ví dụ: sales rep chỉ thấy orders của họ
CREATE FUNCTION Security.fn_OrdersFilter (@SalesRepID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS result
WHERE
    USER_NAME() = 'sa'                  -- admin thấy tất cả
    OR USER_NAME() = 'ReportingUser'    -- reporting thấy tất cả
    OR EXISTS (
        SELECT 1 FROM dbo.SalesReps
        WHERE LoginName = USER_NAME() AND SalesRepID = @SalesRepID
    );

-- Create security policy
CREATE SECURITY POLICY OrdersSalesFilter
ADD FILTER PREDICATE Security.fn_OrdersFilter(SalesRepID)
    ON dbo.Orders,
ADD BLOCK PREDICATE Security.fn_OrdersFilter(SalesRepID)
    ON dbo.Orders AFTER INSERT,    -- prevent insert for wrong SalesRepID
ADD BLOCK PREDICATE Security.fn_OrdersFilter(SalesRepID)
    ON dbo.Orders BEFORE UPDATE    -- prevent update to different SalesRepID
WITH (STATE = ON, SCHEMABINDING = ON);

-- Test RLS
EXECUTE AS USER = 'rep_alice';
SELECT * FROM dbo.Orders;   -- chỉ thấy orders của Alice
REVERT;

-- Disable/Enable policy
ALTER SECURITY POLICY OrdersSalesFilter WITH (STATE = OFF);
ALTER SECURITY POLICY OrdersSalesFilter WITH (STATE = ON);
```

---

## How – Dynamic Data Masking (DDM)

```sql
-- DDM: mask sensitive data cho unprivileged users
-- Data trong DB không thay đổi, chỉ query result bị mask

-- Mask functions:
-- default():             full mask (xxx for string, 0 for number, etc.)
-- email():               a***@xxx.com
-- partial(n, padding, n): partial reveal
-- random(from, to):      random number

-- Add masking to existing columns
ALTER TABLE Customers
ALTER COLUMN CreditCard ADD MASKED WITH (FUNCTION = 'partial(0,"XXXX-XXXX-XXXX-",4)');

ALTER TABLE Customers
ALTER COLUMN Email ADD MASKED WITH (FUNCTION = 'email()');

ALTER TABLE Employees
ALTER COLUMN Salary ADD MASKED WITH (FUNCTION = 'default()');

ALTER TABLE Employees
ALTER COLUMN Phone ADD MASKED WITH (FUNCTION = 'partial(3,"XXX-XX-",2)');

-- Create table with masking
CREATE TABLE Customers (
    CustomerID  INT IDENTITY PRIMARY KEY,
    Name        NVARCHAR(100),
    Email       NVARCHAR(200) MASKED WITH (FUNCTION = 'email()'),
    Phone       VARCHAR(20)   MASKED WITH (FUNCTION = 'partial(3,"XXX-",4)'),
    SSN         CHAR(11)      MASKED WITH (FUNCTION = 'default()'),
    CreditLimit MONEY         MASKED WITH (FUNCTION = 'default()')
);

-- Grant UNMASK permission (privileged users see real data)
GRANT UNMASK ON SCHEMA::dbo TO PrivilegedUser;
-- SQL 2022+: granular unmask per column
GRANT UNMASK ON dbo.Customers(Email) TO SupportUser;

-- DDM limitations: not protection against SQL injection, doesn't encrypt
-- Privileged users (db_owner, sysadmin) see unmasked data
```

---

## How – TDE (Transparent Data Encryption)

```sql
-- TDE: encrypt data files + log files + backups at rest
-- Transparent: no application changes needed
-- Protects against: stolen disk/backup files

-- 1. Create master key in master DB
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'StrongPassword123!';

-- 2. Create certificate
CREATE CERTIFICATE TDECert
    WITH SUBJECT = 'TDE Certificate for SalesDB',
    EXPIRY_DATE = '2030-01-01';

-- 3. Backup certificate (CRITICAL: without this, cannot restore DB if cert lost!)
BACKUP CERTIFICATE TDECert
TO FILE = 'C:\Certs\TDECert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Certs\TDECert.pvk',
    ENCRYPTION BY PASSWORD = 'CertBackupPassword!'
);

-- 4. Create DEK (Database Encryption Key) in target DB
USE SalesDB;
CREATE DATABASE ENCRYPTION KEY
WITH ALGORITHM = AES_256
ENCRYPTION BY SERVER CERTIFICATE TDECert;

-- 5. Enable encryption
ALTER DATABASE SalesDB SET ENCRYPTION ON;

-- Monitor encryption progress
SELECT
    d.name,
    dek.encryption_state_desc,
    dek.percent_complete,
    dek.encryptor_type,
    dek.key_algorithm,
    dek.key_length
FROM sys.dm_database_encryption_keys dek
JOIN sys.databases d ON dek.database_id = d.database_id;
-- state: 0=unencrypted, 1=unencrypted, 2=encrypting, 3=encrypted, 4=key_change, 5=decrypting

-- Restore encrypted DB (cần restore cert first!)
USE master;
CREATE CERTIFICATE TDECert
FROM FILE = 'C:\Certs\TDECert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Certs\TDECert.pvk',
    DECRYPTION BY PASSWORD = 'CertBackupPassword!'
);
-- Sau đó restore DB như bình thường
```

---

## How – Always Encrypted

```sql
-- Always Encrypted: data encrypted in application, SQL Server never sees plaintext
-- Bảo vệ: DBA không thể đọc sensitive data, even SQL Server process

-- Key hierarchy:
-- Column Encryption Key (CEK): encrypt actual data
-- Column Master Key (CMK): encrypt CEK, stored outside SQL Server (Azure Key Vault / Windows cert)

-- Setup (SSMS Wizard là dễ nhất cho demo):
-- Database → Always Encrypted → Generate Keys

-- Create CMK (metadata only, actual key in Windows cert store)
CREATE COLUMN MASTER KEY MyCMK
WITH (
    KEY_STORE_PROVIDER_NAME = 'MSSQL_CERTIFICATE_STORE',
    KEY_PATH = 'LocalMachine/My/A1B2C3D4...'  -- cert thumbprint
);

-- Create CEK
CREATE COLUMN ENCRYPTION KEY MyCEK
WITH VALUES (
    COLUMN_MASTER_KEY = MyCMK,
    ALGORITHM = 'RSA_OAEP',
    ENCRYPTED_VALUE = 0x...  -- CEK encrypted with CMK
);

-- Encrypt column
CREATE TABLE Employees (
    EmployeeID INT,
    Name NVARCHAR(100),
    SSN CHAR(11) ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = MyCEK,
        ENCRYPTION_TYPE = DETERMINISTIC,  -- or RANDOMIZED
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    ),
    Salary MONEY ENCRYPTED WITH (
        COLUMN_ENCRYPTION_KEY = MyCEK,
        ENCRYPTION_TYPE = RANDOMIZED,  -- more secure, but no equality checks
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
);

-- DETERMINISTIC: supports equality comparison, GROUP BY
-- RANDOMIZED: same plaintext → different ciphertext, more secure, no equality

-- Application: configure Always Encrypted in connection string
-- Column Encryption Setting=enabled; dùng parameterized queries
-- Driver tự động encrypt/decrypt
```

---

## How – Audit

```sql
-- SQL Server Audit: track who did what, when
-- Server Audit: where to write (File, Windows Event Log)
-- Server Audit Spec: what server-level events
-- Database Audit Spec: what database-level events

-- 1. Create Server Audit
CREATE SERVER AUDIT SalesAudit
TO FILE (
    FILEPATH = 'C:\Audit\',
    MAXSIZE = 100MB,
    MAX_ROLLOVER_FILES = 20,
    RESERVE_DISK_SPACE = OFF
)
WITH (
    QUEUE_DELAY = 1000,     -- ms, 0 = synchronous (slower, more guarantee)
    ON_FAILURE = CONTINUE   -- CONTINUE hoặc SHUTDOWN
);
ALTER SERVER AUDIT SalesAudit WITH (STATE = ON);

-- 2. Database Audit Specification
USE SalesDB;
CREATE DATABASE AUDIT SPECIFICATION SalesDB_DataAccess
FOR SERVER AUDIT SalesAudit
ADD (SELECT, INSERT, UPDATE, DELETE ON dbo.Orders BY PUBLIC),
ADD (EXECUTE ON SCHEMA::dbo BY PUBLIC),
ADD (SCHEMA_OBJECT_ACCESS_GROUP),  -- audit access to all objects
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)  -- audit role membership changes
WITH (STATE = ON);

-- 3. Server Audit Specification (login events)
CREATE SERVER AUDIT SPECIFICATION LoginAudit
FOR SERVER AUDIT SalesAudit
ADD (FAILED_LOGIN_GROUP),     -- failed logins
ADD (SUCCESSFUL_LOGIN_GROUP)  -- successful logins (verbose!)
WITH (STATE = ON);

-- Read audit log
SELECT
    event_time,
    action_id,
    succeeded,
    server_principal_name AS LoginName,
    database_name,
    schema_name,
    object_name,
    statement
FROM sys.fn_get_audit_file('C:\Audit\SalesAudit_*.sqlaudit', DEFAULT, DEFAULT)
WHERE action_id IN ('SL', 'IN', 'UP', 'DL')  -- SELECT, INSERT, UPDATE, DELETE
ORDER BY event_time DESC;
```

---

## Compare – Encryption Options

| | TDE | Always Encrypted | Cell-Level Encryption | DDM |
|--|-----|----------------|----------------------|-----|
| Encrypts | Files (disk) | Data (app) | Columns (DB level) | Masks output |
| DBA can read | No (encrypted files) | No | No (needs key) | No (masked) |
| SQL can read | Yes | No | With key | Yes |
| App changes | None | Connection string | Query changes | None |
| Performance | Low impact | Medium | High | Low |
| Searchable | Yes | Deterministic only | Limited | No |

---

## Trade-offs

```
TDE:
✅ Protect data at rest (disk theft, backup theft)
✅ No app changes, low overhead
❌ SQL Server process still reads plaintext
❌ Certificate management critical (lose cert = lose data)

Always Encrypted:
✅ Maximum protection (DBA can't read)
✅ Compliance (GDPR, HIPAA, PCI-DSS)
❌ Application changes needed
❌ Cannot use range queries on RANDOMIZED columns
❌ Key management complexity

RLS:
✅ Enforce data access at DB level (not application)
✅ Transparent to app
❌ Performance overhead (predicate evaluation per row)
❌ Complex function debugging

DDM:
✅ Quick win for masking PII
❌ NOT encryption (data is plaintext in DB)
❌ Privileged users bypass masking
```

---

## Real-world – Security Checklist

```
Access Control:
□ Principle of least privilege: no unnecessary db_owner
□ Dedicated service accounts (not sa, not sysadmin)
□ Disable sa login: ALTER LOGIN sa DISABLE
□ Windows Authentication preferred over SQL Authentication
□ Regular access review (quarterly)
□ Disable unused features: xp_cmdshell, OLE Automation, CLR (if not needed)

Encryption:
□ TDE enabled on all production databases
□ TDE certificate backed up securely (offsite)
□ SSL/TLS for all connections: Force Encryption = Yes in SQL Server config
□ Backup encryption

Auditing:
□ Failed login attempts monitored (brute force detection)
□ Privileged user activity audited (sysadmin, db_owner)
□ DDL changes audited (schema changes)
□ Audit logs stored externally (not on same server)
□ DBCC TRACEON disabled in production

Patching:
□ SQL Server patch level within 3 months of latest CU
□ Windows OS patched
□ Vulnerability scans (SQL Server Assessment)

Commands to disable:
EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 0; RECONFIGURE;
EXEC sp_configure 'Ad Hoc Distributed Queries', 0; RECONFIGURE;
```

---

## Ghi chú – Tổng Kết SQL Server
> Đã hoàn thành 8 sub-topics SQL Server: architecture → tsql_advanced → indexing → transactions → query_optimization → backup_recovery → ha_dr → security

---

*Cập nhật lần cuối: 2026-05-06*
