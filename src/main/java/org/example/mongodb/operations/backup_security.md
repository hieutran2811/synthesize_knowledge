# MongoDB Backup & Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Backup & Security MongoDB

**Backup**: đảm bảo data recovery khi có sự cố. **Security**: bảo vệ data khỏi unauthorized access.

```
Security Layers:
  Network:      TLS/SSL, IP whitelist, VPN
  Auth:         SCRAM, x.509 certificates, LDAP, Kerberos
  Authorization: RBAC (Role-Based Access Control)
  Encryption:   At-rest (WiredTiger encryption), In-transit (TLS)
  Auditing:     MongoDB Enterprise audit log
```

---

## How – Authentication

```yaml
# mongod.conf: enable authentication
security:
  authorization: enabled      # RBAC
  javascriptEnabled: false    # disable server-side JS (security best practice)
  keyFile: /etc/mongodb/keyfile  # inter-node auth (replica set / sharded cluster)
  # hoặc: x.509 certs
  # clusterAuthMode: x509
```

```javascript
// Tạo admin user (phải làm trước khi enable auth!)
use admin;
db.createUser({
  user: "mongoAdmin",
  pwd: "S3cur3P@ssw0rd!",
  roles: [{ role: "userAdminAnyDatabase", db: "admin" }, "readWriteAnyDatabase"]
});

// Authentication mechanisms:
// SCRAM-SHA-256 (default, recommended)
// SCRAM-SHA-1 (older, still supported)
// x.509 (certificate-based, more secure)
// LDAP (Enterprise, external auth)
// Kerberos (Enterprise, SSO)

// Đổi auth mechanism
db.adminCommand({
  setParameter: 1,
  authenticationMechanisms: "SCRAM-SHA-256"
});
```

---

## How – RBAC (Role-Based Access Control)

### Built-in Roles

```javascript
// Database User Roles:
// read:           read all non-system collections
// readWrite:      read + write all non-system collections

// Database Admin Roles:
// dbAdmin:        administrative tasks (stats, index, clean)
// dbOwner:        dbAdmin + userAdmin + readWrite
// userAdmin:      manage users and roles (dangerous!)

// Cluster Admin Roles (admin DB only):
// clusterAdmin:   greatest cluster management access
// clusterManager: monitoring + management
// clusterMonitor: read-only monitoring
// hostManager:    server monitoring + management

// Backup/Restore:
// backup:         minimal privileges for mongodump
// restore:        minimal privileges for mongorestore

// Super:
// root:           EVERYTHING (use sparingly)
// __system:       internal use only
```

### Custom Roles

```javascript
// Tạo custom role
use mydb;
db.createRole({
  role: "orderReader",
  privileges: [
    {
      resource: { db: "mydb", collection: "orders" },
      actions: ["find"]
    },
    {
      resource: { db: "mydb", collection: "customers" },
      actions: ["find"]
    }
  ],
  roles: []  // inherit từ roles khác nếu cần
});

// Role với collection-level permissions
db.createRole({
  role: "salesManager",
  privileges: [
    {
      resource: { db: "mydb", collection: "orders" },
      actions: ["find", "insert", "update"]
    },
    {
      resource: { db: "mydb", collection: "" },  // all collections in mydb
      actions: ["find"]
    }
  ],
  roles: [{ role: "read", db: "reporting" }]  // also inherit read on reporting DB
});

// Tạo service account user
db.createUser({
  user: "apiService",
  pwd: passwordPrompt(),  // interactive password
  roles: [{ role: "orderReader", db: "mydb" }],
  mechanisms: ["SCRAM-SHA-256"],
  passwordDigestor: "server"  // hoặc "client" (hash client-side)
});

// Update user
db.updateUser("apiService", {
  roles: [
    { role: "orderReader", db: "mydb" },
    { role: "read", db: "analytics" }
  ]
});

// Xem users
db.getUsers();
db.getUser("apiService");

// Xem roles
db.getRoles({ showPrivileges: true });
```

---

## How – TLS/SSL

```yaml
# mongod.conf
net:
  tls:
    mode: requireTLS          # disabled, allowTLS, preferTLS, requireTLS
    certificateKeyFile: /etc/ssl/mongodb.pem     # server cert + key
    CAFile: /etc/ssl/ca.pem                      # CA certificate
    allowConnectionsWithoutCertificates: true    # true = client cert optional
    disabledProtocols: TLS1_0,TLS1_1             # disable old protocols
```

```javascript
// Connection string với TLS
mongodb://user:pass@host:27017/mydb?tls=true&tlsCAFile=/etc/ssl/ca.pem

// x.509 client certificate authentication
mongodb://host:27017/mydb
  ?authMechanism=MONGODB-X509
  &tls=true
  &tlsCertificateKeyFile=/etc/ssl/client.pem
  &tlsCAFile=/etc/ssl/ca.pem
```

---

## How – Encryption at Rest

```yaml
# mongod.conf (Enterprise only: native encryption)
security:
  enableEncryption: true
  encryptionKeyFile: /etc/mongodb/encryption-keyfile  # local key file
  # hoặc: KMIP (external key management)
  # kmip:
  #   serverName: kmip-server
  #   port: 5696
  #   clientCertificateFile: /etc/ssl/kmip-client.pem
  #   serverCAFile: /etc/ssl/kmip-ca.pem
```

```
Community Edition: không có native encryption
→ Alternatives:
  1. Storage-level encryption (dm-crypt/LUKS on Linux)
  2. Cloud provider encryption (EBS encryption, Azure Disk Encryption)
  3. MongoDB Atlas: always encrypted at rest

WiredTiger encryption (Enterprise):
  - AES256-CBC encryption
  - Encrypt data on disk, decrypt in memory
  - Key rotation supported
  - Transparent to application
```

---

## How – Field-Level Encryption (Client-Side)

```javascript
// MongoDB 4.2+: Client-Side Field Level Encryption (CSFLE)
// Application encrypts specific fields before sending to MongoDB
// MongoDB server never sees plaintext

// Schema with encrypted fields
const encryptedFieldsMap = {
  "mydb.patients": {
    fields: [
      {
        path: "ssn",
        bsonType: "string",
        queries: { queryType: "equality" }  // allows equality queries on encrypted field
      },
      {
        path: "medicalRecord",
        bsonType: "object"
        // no queries = randomized encryption (most secure)
      }
    ]
  }
};

// Auto Encryption (Queryable Encryption - MongoDB 6.0+)
const client = new MongoClient(uri, {
  autoEncryption: {
    keyVaultNamespace: "encryption.__keyVault",
    kmsProviders: {
      aws: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
      }
    },
    encryptedFieldsMap
  }
});

// Insert: fields tự động encrypted
await db.collection("patients").insertOne({
  name: "Nguyen Van A",
  ssn: "123-45-6789",           // encrypted before send
  medicalRecord: { diagnosis: "..." }  // encrypted before send
});

// Query on encrypted field (with equality queryType)
await db.collection("patients").findOne({ ssn: "123-45-6789" });
// Works! SSN encrypted but equality query supported
```

---

## How – Backup Strategies

### mongodump / mongorestore

```bash
# Full dump (logical backup)
mongodump \
  --uri="mongodb://user:pass@host:27017" \
  --out="/backup/dump-$(date +%Y%m%d)" \
  --gzip \
  --numParallelCollections=4

# Dump specific DB/collection
mongodump \
  --uri="mongodb://host:27017" \
  --db=mydb \
  --collection=orders \
  --out=/backup/orders

# Dump with readPreference (reduce primary load)
mongodump \
  --host="mongo1:27017,mongo2:27017,mongo3:27017" \
  --readPreference=secondary \
  --gzip --out=/backup/

# Restore
mongorestore \
  --uri="mongodb://host:27017" \
  --gzip \
  --numParallelCollections=4 \
  /backup/dump-20260506

# Restore specific collection
mongorestore \
  --uri="mongodb://host:27017" \
  --nsInclude="mydb.orders" \
  --drop \  # drop collection before restore
  /backup/dump-20260506

# Export/Import JSON (for smaller datasets)
mongoexport --collection=orders --db=mydb --out=orders.json
mongoimport --collection=orders --db=mydb --file=orders.json
```

### mongodump Limitations

```
❌ Không phải true point-in-time (takes snapshot over time)
❌ Lock-free → may miss some operations during dump
❌ Large databases: slow, large files
❌ No incremental backup natively

Better alternatives:
  - Atlas Backup: continuous cloud backup, PITR
  - Ops Manager/Cloud Manager: scheduled snapshots
  - Filesystem snapshots (LVM, cloud EBS) + oplog: faster + consistent
```

### Filesystem Snapshot Backup

```bash
# Best practice for production: filesystem snapshot + oplog backup

# 1. Snapshot primary's disk (or secondary để không impact primary)
# AWS EBS snapshot:
aws ec2 create-snapshot --volume-id vol-xxxx --description "MongoDB backup $(date)"

# 2. Record oplog position at snapshot time
mongosh --eval 'db.adminCommand({isMaster:1}).lastWrite.opTime'

# 3. Restore:
#    a. Restore filesystem snapshot
#    b. Apply oplog từ snapshot time đến recovery time (mongorestore --oplogReplay)
mongorestore \
  --uri="mongodb://host:27017" \
  --oplogReplay \
  /backup/mongodump-with-oplog

# Dump with oplog (capture changes during dump for consistent snapshot)
mongodump \
  --uri="mongodb://host:27017" \
  --oplog \           # include oplog.bson
  --out=/backup/

mongorestore \
  --uri="mongodb://target:27017" \
  --oplogReplay \     # replay oplog
  /backup/
```

---

## How – Auditing (Enterprise)

```yaml
# mongod.conf (Enterprise)
auditLog:
  destination: file              # file, syslog, console
  format: BSON                   # BSON hoặc JSON
  path: /var/log/mongodb/audit.bson
  filter: >
    {
      atype: { $in: ["authenticate", "createUser", "dropUser",
                     "find", "insert", "update", "remove",
                     "createCollection", "dropCollection"] }
    }
```

```javascript
// Xem audit log (JSON format)
// {"atype":"authenticate","ts":{"$date":"2026-01-15T08:00:00.000Z"},
//  "local":{"ip":"127.0.0.1","port":27017},
//  "remote":{"ip":"10.0.0.1","port":52000},
//  "users":[{"user":"apiService","db":"mydb"}],
//  "roles":[{"role":"orderReader","db":"mydb"}],
//  "result":0}
```

---

## Compare – MongoDB vs SQL Server Security

| Feature | MongoDB | SQL Server |
|---------|---------|-----------|
| Auth | SCRAM, x.509, LDAP, Kerberos | Windows, SQL, Azure AD |
| RBAC | Built-in (roles) | Logins/Users/Roles/Schemas |
| Row-level | RLS via field-level or app | Row-Level Security (RLS) |
| Encryption at rest | Enterprise only (native) | TDE (all editions) |
| Client-side encryption | CSFLE (4.2+) | Always Encrypted (2016+) |
| Data masking | Atlas Data Masking | Dynamic Data Masking |
| Auditing | Enterprise only | All editions |
| Column/field level | CSFLE | Always Encrypted |

---

## Trade-offs

```
CSFLE vs TLS-only:
CSFLE: maximum protection (server never sees plaintext)
      ❌ Complex key management, performance overhead, limited query types
TLS: protect in transit, not at rest
     ✅ No app changes, good for most cases

mongodump vs filesystem snapshot:
mongodump: 
  ✅ Simple, works across platforms, no coordination needed
  ❌ Slow for large DBs, not consistent point-in-time
Filesystem snapshot:
  ✅ Fast, consistent, PITR with oplog
  ❌ Platform-specific, needs oplog window large enough

Open-source vs Enterprise security:
Community: TLS, SCRAM, RBAC, no audit, no native encryption
Enterprise: All above + audit, native encryption, LDAP, Kerberos
→ Production: use Atlas (includes enterprise features) or Enterprise
```

---

## Real-world – Security Checklist

```
Authentication:
□ NEVER run mongod without --auth in production
□ Rotate passwords quarterly, service account passwords annually
□ Use x.509 certs for inter-node auth (keyFile is minimum)
□ Disable SCRAM-SHA-1 if all clients support SHA-256

Network:
□ Bind mongod to specific IP (bindIp: 127.0.0.1,10.0.0.1)
□ Firewall: only app servers access MongoDB ports (27017)
□ VPC/private subnet: MongoDB not publicly accessible
□ TLS: requireTLS mode, disable TLS 1.0/1.1

Access Control:
□ Dedicated users per service (not shared credentials)
□ Principle of least privilege (read-only if only reads needed)
□ No direct connection from client browsers to MongoDB
□ Rotate service account credentials regularly

Backup:
□ Regular backups + retention policy
□ Test restore quarterly
□ Offsite backup (different region/cloud)
□ Backup encryption
□ Atlas: enable PITR (Continuous Cloud Backup)

Monitoring:
□ Failed auth attempts (possible brute force)
□ Unusual query patterns
□ Connection count spikes
□ Data exfiltration: large unexplained reads
```

---

## Ghi chú – Tổng Kết MongoDB
> Đã hoàn thành 8 sub-topics MongoDB: data_model → crud_aggregation → indexing → transactions → schema_design → replication → sharding → backup_security

---

*Cập nhật lần cuối: 2026-05-06*
