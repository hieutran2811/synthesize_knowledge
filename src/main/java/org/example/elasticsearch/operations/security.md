# Elasticsearch Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Elasticsearch Security

Elasticsearch Security (X-Pack, built-in từ ES 8.0) cung cấp: **Authentication** (who are you), **Authorization/RBAC** (what can you do), **Encryption** (TLS), và **Audit logging** (what did you do).

```
Security layers:
  1. Network:       TLS/SSL for transport + HTTP
  2. Authentication: verify identity (native, LDAP, AD, SAML, OIDC, PKI, JWT)
  3. Authorization:  RBAC (roles → privileges → resources)
  4. Data-level:     field-level security, document-level security
  5. Audit:          log all access events
```

---

## How – Enable Security (ES 8.x)

```bash
# ES 8.x: security enabled by default
# Auto-generated certs + passwords on first start
# Output on first start:
#   ✅ Elasticsearch security features have been automatically configured!
#   ✅ Authentication is enabled and cluster connections are encrypted.
#   ℹ️  Password for the elastic user (reset with `bin/elasticsearch-reset-password -u elastic`):
#       Bk9X3PqM2nF7vL1w
#   ℹ️  HTTP CA certificate SHA-256 fingerprint:
#       A1B2C3...

# Reset elastic password
bin/elasticsearch-reset-password -u elastic --interactive

# Create enrollment token for Kibana
bin/elasticsearch-create-enrollment-token --scope kibana

# Create enrollment token for new ES node
bin/elasticsearch-create-enrollment-token --scope node
```

```yaml
# elasticsearch.yml – security configuration
xpack.security.enabled: true

# HTTP layer (REST API)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/http.p12

# Transport layer (inter-node)
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.keystore.path: certs/transport.p12
xpack.security.transport.ssl.truststore.path: certs/transport.p12
xpack.security.transport.ssl.verification_mode: certificate  # certificate | full | none

# For manual cert setup (not auto-generated)
xpack.security.http.ssl.certificate_authorities: [ "certs/ca.crt" ]
xpack.security.http.ssl.certificate: certs/es-node.crt
xpack.security.http.ssl.key: certs/es-node.key
```

### Generate Certificates

```bash
# Generate CA
bin/elasticsearch-certutil ca \
  --out /etc/elasticsearch/certs/ca.p12 \
  --pass "" \                    # CA password (use for production)

# Generate node certs (signed by CA)
bin/elasticsearch-certutil cert \
  --ca /etc/elasticsearch/certs/ca.p12 \
  --ca-pass "" \
  --dns "es-node-1,es-node-1.internal" \
  --ip "10.0.1.1" \
  --out /etc/elasticsearch/certs/es-node-1.p12 \
  --pass ""

# Or batch generate for all nodes
cat > nodes.yml << EOF
instances:
  - name: es-node-1
    dns: [es-node-1, es-node-1.example.com]
    ip: [10.0.1.1]
  - name: es-node-2
    dns: [es-node-2, es-node-2.example.com]
    ip: [10.0.1.2]
  - name: kibana
    dns: [kibana, kibana.example.com]
    ip: [10.0.2.1]
EOF

bin/elasticsearch-certutil cert \
  --ca /etc/elasticsearch/certs/ca.p12 \
  --in nodes.yml \
  --out /tmp/certs.zip
```

---

## How – User Management

```bash
# Built-in superusers
# elastic:  full access (change password after setup)
# kibana_system: internal Kibana
# logstash_system: Logstash internal
# beats_system: Beats internal
# apm_system: APM internal
# remote_monitoring_user: monitoring cross-cluster

# Create user (native realm)
POST _security/user/app_user
{
  "password": "secure_password_here",
  "roles": ["orders_reader", "orders_writer"],
  "full_name": "Application User",
  "email": "app@example.com",
  "metadata": {
    "team": "orders",
    "created_by": "admin"
  }
}

# Update user
PUT _security/user/app_user
{
  "password": "new_password",
  "roles": ["orders_reader"],
  "full_name": "Application User Updated"
}

# Disable user (not delete)
PUT _security/user/app_user/_disable

# Change password
PUT _security/user/app_user/_password
{ "password": "new_password" }

# Delete user
DELETE _security/user/app_user

# List users
GET _security/user
GET _security/user/app_user
```

---

## How – RBAC (Role-Based Access Control)

```bash
# Create custom role
POST _security/role/orders_manager
{
  "cluster": [
    "monitor",               # GET _cluster/health, _cat/*, _nodes/stats
    "manage_ilm",            # manage ILM policies
    "manage_index_templates" # manage templates
  ],
  "indices": [
    {
      "names": ["orders-*", "payments-*"],
      "privileges": [
        "read",              # search, get, explain
        "write",             # index, delete, bulk, update
        "create_index",      # create new indices matching pattern
        "manage",            # open/close, forcemerge, refresh, etc.
        "view_index_metadata" # _mapping, _settings, _aliases
      ],
      "allow_restricted_indices": false
    },
    {
      "names": [".kibana*", ".reporting*"],
      "privileges": ["read", "view_index_metadata"]
    }
  ],
  "applications": [
    {
      "application": "kibana-.kibana",
      "privileges": ["feature_dashboard.read", "feature_discover.all"],
      "resources": ["space:orders-team"]
    }
  ]
}

# Read-only analyst role
POST _security/role/orders_analyst
{
  "cluster": ["monitor"],
  "indices": [
    {
      "names": ["orders-*"],
      "privileges": ["read", "view_index_metadata"],
      "field_security": {
        "grant": ["order_id", "status", "amount", "created_at", "region"],
        "except": []          # or use "except" to exclude specific fields
      },
      "query": "{\"term\": {\"region\": \"APAC\"}}"  # document-level security
    }
  ]
}

# List available privileges
GET _security/privilege
```

### Built-in Roles

```
superuser:         full cluster access (use for admin only)
kibana_admin:      full Kibana access
kibana_user:       basic Kibana access
monitoring_user:   read monitoring data
rollup_user:       rollup read
reporting_user:    Kibana reporting
viewer:            read-only cluster+index (ES 8+)
editor:            read/write indices (ES 8+)
```

---

## How – Field-Level Security (FLS)

```bash
# Grant access only to specific fields
POST _security/role/pii_restricted
{
  "indices": [
    {
      "names": ["customers-*"],
      "privileges": ["read"],
      "field_security": {
        "grant": [            # whitelist: only these fields visible
          "customer_id",
          "status",
          "order_count",
          "region",
          "created_at"
        ]
        # Excluded: email, phone, ssn, credit_card, address, date_of_birth
      }
    }
  ]
}

# Or use "except" to blacklist:
"field_security": {
  "grant": ["*"],             # all fields
  "except": ["ssn", "credit_card", "bank_account"]  # except these
}
```

---

## How – Document-Level Security (DLS)

```bash
# Users only see documents matching the DLS query
POST _security/role/apac_region_only
{
  "indices": [
    {
      "names": ["orders-*"],
      "privileges": ["read"],
      "query": {                        # stored as JSON string
        "term": { "region": "APAC" }
      }
    }
  ]
}

# Multi-condition DLS
POST _security/role/active_premium_only
{
  "indices": [
    {
      "names": ["customers-*"],
      "privileges": ["read"],
      "query": "{\"bool\": {\"must\": [{\"term\": {\"status\": \"active\"}}, {\"term\": {\"tier\": \"premium\"}}]}}"
    }
  ]
}

# DLS with template (dynamic: use username in query)
POST _security/role/own_data_only
{
  "indices": [
    {
      "names": ["user-data-*"],
      "privileges": ["read", "write"],
      "query": {
        "template": {
          "source": "{\"term\": {\"user_id\": \"{{_user.username}}\"}}"
        }
      }
    }
  ]
}
```

---

## How – API Keys

```bash
# Create API key (preferred for service-to-service auth)
POST _security/api_key
{
  "name": "orders-service-key",
  "expiration": "365d",           # optional expiration
  "role_descriptors": {           # optional: restrict permissions
    "orders_access": {
      "cluster": ["monitor"],
      "indices": [
        {
          "names": ["orders-*"],
          "privileges": ["read", "write"]
        }
      ]
    }
  },
  "metadata": {
    "service": "orders-api",
    "environment": "production"
  }
}
# Response: { "id": "...", "name": "...", "api_key": "...", "encoded": "..." }
# encoded = base64(id:api_key) → use in Authorization header

# Usage:
curl -H "Authorization: ApiKey <encoded>" https://elasticsearch:9200/orders/_search

# List API keys
GET _security/api_key?name=orders-service-key
GET _security/api_key?mine=true        # current user's keys

# Invalidate
DELETE _security/api_key
{ "ids": ["abc123"] }
DELETE _security/api_key { "name": "orders-service-key" }
```

---

## How – Realm Configuration (External Auth)

```yaml
# elasticsearch.yml – realm order
xpack.security.authc.realms:
  native.native1:
    order: 0                           # check native realm first
  ldap.ldap1:
    order: 1
    url: ldaps://ldap.example.com:636
    bind_dn: "cn=elasticsearch,ou=service,dc=example,dc=com"
    bind_password: "secure_password"
    user_search:
      base_dn: "ou=users,dc=example,dc=com"
      filter: "(cn={0})"
    group_search:
      base_dn: "ou=groups,dc=example,dc=com"
    ssl.certificate_authorities: ["/etc/elasticsearch/certs/ldap-ca.crt"]
    role_mapping:
      "cn=es-admins,ou=groups,dc=example,dc=com": superuser
      "cn=es-readers,ou=groups,dc=example,dc=com": orders_analyst

  saml.saml1:
    order: 2
    idp.metadata.path: saml/idp-metadata.xml
    idp.entity_id: "https://sso.example.com/saml2/idp"
    sp.entity_id: "https://kibana.example.com"
    sp.acs: "https://kibana.example.com/api/security/saml/callback"
    sp.logout: "https://kibana.example.com/logout"
    attributes.principal: nameid:persistent
    attributes.groups: groups
    attributes.mail: email
```

---

## How – Audit Logging

```yaml
# elasticsearch.yml
xpack.security.audit.enabled: true
xpack.security.audit.logfile.events.include:
  - authentication_success
  - authentication_failed
  - access_denied
  - connection_denied
  - tampered_request
  - run_as_denied
  - index_created
  - index_deleted
  
xpack.security.audit.logfile.events.exclude:
  - authenticated  # exclude successful reads (too verbose)

# Output location
xpack.security.audit.logfile.emit_node_name: true
xpack.security.audit.logfile.emit_node_host_address: true
```

```bash
# Audit log format (JSON)
{
  "@timestamp": "2024-01-15T10:23:45.123Z",
  "event.type": "rest",
  "event.action": "authentication_failed",
  "user.name": "unknown_user",
  "origin.address": "10.0.1.100",
  "request.id": "abc123",
  "url.path": "/_security/user/_authenticate",
  "request.method": "GET"
}

# Index audit logs to Elasticsearch (for SIEM)
# Configure filebeat to ship audit logs → Elasticsearch/Splunk
```

---

## Why – Security Architecture

```
Why TLS for transport layer?
  Kafka brokers / ES nodes communicate over TCP
  Without TLS: man-in-the-middle can read all data (including cluster credentials)
  With TLS: encrypted, mutual authentication (each node verifies the other)
  → Internal network is not a trust boundary

Why API keys over username/password?
  Password: long-lived, broad scope, hard to rotate
  API key:  scoped to specific permissions, expiration, revokable per service
  → Compromised key: revoke one key, not entire account
  → Best practice: 1 API key per service, rotated regularly

Why FLS + DLS?
  Multi-tenant: different teams/apps sharing same cluster
  Compliance: GDPR, HIPAA → mask PII from non-privileged users
  DLS: row-level security without separate indices per tenant
```

---

## Trade-offs

```
TLS verification modes:
  full:        verify hostname + certificate chain (most secure)
  certificate: verify chain only (accept any hostname matching cert)
  none:        no verification (dev only, never production)
  → Always use full in production

DLS performance:
  DLS adds query overhead to every search
  ✅ Fine-grained access control per document
  ❌ Cannot use shard request cache effectively (different query per user)
  → For high-throughput read paths, consider separate indices per tenant

FLS performance:
  Minimal overhead (field filtering at source level)
  ✅ Safe for high-throughput
  → Prefer over DLS when possible

Native realm vs LDAP/SAML:
  Native: simple, no external dependency
  LDAP:   centralized user management, sync with AD
  SAML:   SSO, Kibana integration, enterprise IdP
  → LDAP for services; SAML for human users via Kibana

API key scoping:
  Too broad: compromised key = too much damage
  Too narrow: many keys to manage
  → Principle of least privilege: 1 key per service per environment
```

---

## Real-world Hardening Checklist

```bash
# 1. Change elastic password
bin/elasticsearch-reset-password -u elastic

# 2. Create service accounts (don't use elastic for apps)
POST _security/user/app_service
{
  "password": "strong_random_password",
  "roles": ["app_specific_role"]
}

# 3. Restrict network access
# elasticsearch.yml:
#   network.host: 10.0.1.1       # bind to internal IP only
#   http.cors.enabled: false      # disable CORS (unless needed)
#   http.cors.allow-origin: "https://kibana.internal"

# 4. Disable HTTP on data/master nodes (use coordinator)
# http.enabled: false  (on dedicated data/master nodes)

# 5. IP filtering
POST _security/ip_filter/allow_internal
{
  "allow": ["10.0.0.0/8", "172.16.0.0/12"],
  "deny": ["0.0.0.0/0"]  # deny all others
}

# 6. Monitor: failed authentications
GET _security/audit/log
# Alert: > N failed authentications from same IP (brute force)

# 7. Rotate API keys periodically
GET _security/api_key?mine=true
# → Revoke old, create new, deploy new to services

# 8. Disable unused features
xpack.watcher.enabled: false        # if not using alerting
xpack.graph.enabled: false          # if not using Graph
xpack.ml.enabled: false             # if not using ML

# 9. Use security_exception logging
# Logs field/document level security denials → detect misconfigurations
```

---

*Cập nhật lần cuối: 2026-05-06*
