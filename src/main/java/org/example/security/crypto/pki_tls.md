# PKI & TLS Deep Dive

## 1. Public Key Infrastructure (PKI)

### 1.1 PKI Architecture

```
Root CA (offline, air-gapped)
    └── Intermediate CA (online)
            ├── Intermediate CA 2 (optional)
            │       └── End-Entity Certificate (server/client)
            └── End-Entity Certificate

Trust Chain: Root → Intermediate → Leaf
```

**Certificate Authority Hierarchy:**
```
Root CA:
  - Self-signed certificate
  - Kept OFFLINE (HSM in safe)
  - Signs only Intermediate CA certs
  - Validity: 20-40 years

Intermediate CA:
  - Signed by Root CA
  - Online, performs daily operations
  - Signs end-entity certificates
  - Validity: 5-10 years
  - Revocation via CRL/OCSP

End-Entity (Leaf):
  - Server cert, client cert, code signing cert
  - Validity: ≤ 398 days (Chrome enforcement)
  - Must include SAN (Subject Alternative Name)
```

### 1.2 X.509 Certificate Structure

```python
# Parse certificate with Python
from cryptography import x509
from cryptography.hazmat.backends import default_backend
import datetime

def analyze_certificate(cert_path):
    with open(cert_path, 'rb') as f:
        cert = x509.load_pem_x509_certificate(f.read(), default_backend())
    
    print(f"Subject: {cert.subject.rfc4514_string()}")
    print(f"Issuer: {cert.issuer.rfc4514_string()}")
    print(f"Serial: {cert.serial_number}")
    print(f"Valid from: {cert.not_valid_before_utc}")
    print(f"Valid until: {cert.not_valid_after_utc}")
    print(f"Public key type: {type(cert.public_key()).__name__}")
    
    # Extensions
    try:
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        print(f"SANs: {san.value.get_values_for_type(x509.DNSName)}")
    except x509.ExtensionNotFound:
        print("No SAN extension (legacy cert!)")
    
    try:
        bc = cert.extensions.get_extension_for_class(x509.BasicConstraints)
        print(f"Is CA: {bc.value.ca}")
        print(f"Path length: {bc.value.path_length}")
    except x509.ExtensionNotFound:
        pass
    
    try:
        eku = cert.extensions.get_extension_for_class(x509.ExtendedKeyUsage)
        print(f"EKU: {[oid._name for oid in eku.value]}")
    except x509.ExtensionNotFound:
        pass

# Certificate fields breakdown:
# Version: 3 (X.509v3)
# Serial Number: unique per CA
# Signature Algorithm: sha256WithRSAEncryption, ecdsa-with-SHA256
# Validity: NotBefore, NotAfter
# Subject: CN, O, OU, C, ST, L
# Subject Public Key Info: algorithm + public key
# Extensions (critical vs non-critical):
#   - Basic Constraints: cA=TRUE/FALSE, pathLenConstraint
#   - Key Usage: digitalSignature, keyCertSign, cRLSign
#   - Extended Key Usage: serverAuth, clientAuth, codeSigning
#   - Subject Alternative Name: DNS:example.com, IP:1.2.3.4
#   - Authority Key Identifier: key ID of issuer
#   - Subject Key Identifier: key ID of this cert
#   - CRL Distribution Points: where to get CRL
#   - Authority Information Access: OCSP URL, caIssuers URL
#   - Certificate Policies: OID, CPS URL
```

### 1.3 Tạo Private CA với OpenSSL

```bash
# === Root CA ===
mkdir -p /opt/ca/{root,intermediate}/{certs,crl,newcerts,private,csr}
chmod 700 /opt/ca/root/private

# Root CA config
cat > /opt/ca/root/openssl.cnf << 'EOF'
[ca]
default_ca = CA_default

[CA_default]
dir               = /opt/ca/root
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca.key.pem
certificate       = $dir/certs/ca.cert.pem
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha256
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 3650
preserve          = no
policy            = policy_strict

[policy_strict]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[req]
default_bits        = 4096
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[req_distinguished_name]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[v3_intermediate_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[usr_cert]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[server_cert]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = example.com
DNS.2 = *.example.com

[crl_ext]
authorityKeyIdentifier=keyid:always
EOF

# Init database
echo 1000 > /opt/ca/root/serial
echo 1000 > /opt/ca/root/crlnumber
touch /opt/ca/root/index.txt

# Generate Root CA key (keep private!)
openssl genrsa -aes256 -out /opt/ca/root/private/ca.key.pem 4096
chmod 400 /opt/ca/root/private/ca.key.pem

# Self-sign Root CA cert
openssl req -config /opt/ca/root/openssl.cnf \
    -key /opt/ca/root/private/ca.key.pem \
    -new -x509 -days 7300 -sha256 -extensions v3_ca \
    -out /opt/ca/root/certs/ca.cert.pem

# === Intermediate CA ===
# Generate Intermediate key
openssl genrsa -aes256 -out /opt/ca/intermediate/private/intermediate.key.pem 4096

# Create CSR
openssl req -config /opt/ca/intermediate/openssl.cnf \
    -new -sha256 \
    -key /opt/ca/intermediate/private/intermediate.key.pem \
    -out /opt/ca/intermediate/csr/intermediate.csr.pem

# Root CA signs Intermediate CA
openssl ca -config /opt/ca/root/openssl.cnf -extensions v3_intermediate_ca \
    -days 3650 -notext -md sha256 \
    -in /opt/ca/intermediate/csr/intermediate.csr.pem \
    -out /opt/ca/intermediate/certs/intermediate.cert.pem

# Create chain file
cat /opt/ca/intermediate/certs/intermediate.cert.pem \
    /opt/ca/root/certs/ca.cert.pem > /opt/ca/intermediate/certs/ca-chain.cert.pem

# === Issue Server Certificate ===
# Generate server key
openssl genrsa -out /opt/ca/intermediate/private/example.com.key.pem 2048

# Generate CSR with SANs
openssl req -config /opt/ca/intermediate/openssl.cnf \
    -key /opt/ca/intermediate/private/example.com.key.pem \
    -new -sha256 \
    -out /opt/ca/intermediate/csr/example.com.csr.pem \
    -subj "/C=VN/ST=HCM/O=ExampleCorp/CN=example.com"

# Sign with Intermediate CA
openssl ca -config /opt/ca/intermediate/openssl.cnf \
    -extensions server_cert -days 397 -notext -md sha256 \
    -in /opt/ca/intermediate/csr/example.com.csr.pem \
    -out /opt/ca/intermediate/certs/example.com.cert.pem

# Verify chain
openssl verify -CAfile /opt/ca/intermediate/certs/ca-chain.cert.pem \
    /opt/ca/intermediate/certs/example.com.cert.pem
```

---

## 2. TLS Protocol Deep Dive

### 2.1 TLS 1.3 Handshake

```
Client                                           Server
  |                                                |
  |-------- ClientHello -------------------------->|
  |  (TLS versions, cipher suites, key_share,     |
  |   supported_groups, signature_algorithms)      |
  |                                                |
  |<------- ServerHello ---------------------------|
  |  (chosen version, cipher, server key_share)   |
  |                                                |
  |  [1-RTT: derive handshake keys]               |
  |                                                |
  |<------- {EncryptedExtensions} ----------------|
  |<------- {CertificateRequest} -----------------|  (optional mTLS)
  |<------- {Certificate} ------------------------|
  |<------- {CertificateVerify} ------------------|
  |<------- {Finished} ----------------------------|
  |                                                |
  |-------- {Certificate} ------------------------>|  (optional mTLS)
  |-------- {CertificateVerify} ------------------>|  (optional mTLS)
  |-------- {Finished} --------------------------->|
  |                                                |
  |  [Application Data] <========================>|
```

**Key differences TLS 1.3 vs 1.2:**
- 1-RTT vs 2-RTT (faster)
- 0-RTT (early data) for resumed sessions
- Forward Secrecy mandatory (ephemeral keys only)
- Removed: RSA key exchange, DH static, RC4, 3DES, MD5/SHA-1
- All cipher suites use AEAD: AES-128-GCM, AES-256-GCM, ChaCha20-Poly1305
- Encrypted handshake earlier (CertificateVerify is encrypted)

### 2.2 TLS 1.2 Handshake (Legacy)

```
Client                                           Server
  |-------- ClientHello -------------------------->|
  |  (TLS 1.2, cipher suites, random)             |
  |                                                |
  |<------- ServerHello ---------------------------|
  |<------- Certificate  --------------------------|
  |<------- ServerKeyExchange  -------------------|  (DHE/ECDHE only)
  |<------- ServerHelloDone  ---------------------|
  |                                                |
  |-------- ClientKeyExchange ------------------->|
  |  (RSA: encrypt PMS with server pubkey)         |
  |  (DHE: client DH public value)                 |
  |-------- ChangeCipherSpec  ------------------->|
  |-------- Finished  --------------------------->|
  |                                                |
  |<------- ChangeCipherSpec  ---------------------|
  |<------- Finished  -----------------------------|
  |                                                |
  |  [Application Data] <========================>|
```

### 2.3 TLS Key Derivation

```python
# TLS 1.3 key derivation (simplified)
import hashlib
import hmac

def hkdf_extract(salt, ikm, hash_algo='sha256'):
    if salt is None:
        salt = bytes(hashlib.new(hash_algo).digest_size)
    return hmac.new(salt, ikm, hash_algo).digest()

def hkdf_expand(prk, info, length, hash_algo='sha256'):
    hash_len = hashlib.new(hash_algo).digest_size
    n = (length + hash_len - 1) // hash_len
    okm = b''
    t = b''
    for i in range(1, n + 1):
        t = hmac.new(prk, t + info + bytes([i]), hash_algo).digest()
        okm += t
    return okm[:length]

# TLS 1.3 Secret Schedule:
# Early Secret = HKDF-Extract(0, PSK or 0)
# Handshake Secret = HKDF-Extract(Derive-Secret(ES, "derived"), ECDHE)
# Master Secret = HKDF-Extract(Derive-Secret(HS, "derived"), 0)
#
# From HS: client_handshake_traffic_secret, server_handshake_traffic_secret
# From MS: client_application_traffic_secret, server_application_traffic_secret
#          exporter_master_secret, resumption_master_secret
```

---

## 3. Certificate Revocation

### 3.1 CRL (Certificate Revocation List)

```bash
# Generate CRL
openssl ca -config /opt/ca/intermediate/openssl.cnf \
    -gencrl -out /opt/ca/intermediate/crl/intermediate.crl.pem

# Convert to DER (for distribution)
openssl crl -in intermediate.crl.pem -outform DER -out intermediate.crl

# Revoke a certificate
openssl ca -config /opt/ca/intermediate/openssl.cnf \
    -revoke /opt/ca/intermediate/certs/compromised.cert.pem \
    -crl_reason keyCompromise  # unspecified|keyCompromise|cACompromise|affiliationChanged|superseded|cessationOfOperation|certificateHold

# Check CRL
openssl crl -in intermediate.crl.pem -text -noout

# Verify cert against CRL
openssl verify -crl_check \
    -CAfile /opt/ca/intermediate/certs/ca-chain.cert.pem \
    -CRLfile /opt/ca/intermediate/crl/intermediate.crl.pem \
    /opt/ca/intermediate/certs/example.com.cert.pem

# CRL Distribution Point extension in cert:
# CRL Distribution Points:
#   Full Name: URI:http://crl.example.com/intermediate.crl
```

**CRL limitations:**
- Large files (millions of entries)
- Not real-time (updated periodically, e.g., every 24h)
- Clients must download and cache

### 3.2 OCSP (Online Certificate Status Protocol)

```bash
# Run OCSP responder
openssl ocsp \
    -index /opt/ca/intermediate/index.txt \
    -port 2560 \
    -rsigner /opt/ca/intermediate/certs/intermediate.cert.pem \
    -rkey /opt/ca/intermediate/private/intermediate.key.pem \
    -CA /opt/ca/intermediate/certs/ca-chain.cert.pem \
    -text -out /var/log/ocsp.log

# Query OCSP for cert status
openssl ocsp \
    -issuer /opt/ca/intermediate/certs/intermediate.cert.pem \
    -cert /opt/ca/intermediate/certs/example.com.cert.pem \
    -url http://ocsp.example.com:2560 \
    -resp_text

# OCSP Stapling (nginx config):
# ssl_stapling on;
# ssl_stapling_verify on;
# resolver 8.8.8.8 8.8.4.4 valid=300s;
# ssl_trusted_certificate /path/to/ca-chain.cert.pem;
```

**OCSP Stapling:**
- Server caches OCSP response and staples it to TLS handshake
- Client doesn't need to contact OCSP responder separately
- Privacy-preserving (OCSP responder doesn't learn which sites client visits)
- Must-Staple extension forces OCSP stapling requirement

---

## 4. Certificate Transparency (CT)

### 4.1 CT Log Architecture

```
Certificate Authority
        |
        | submits pre-certificate
        ↓
CT Log Server (append-only, Merkle tree)
        |
        | returns Signed Certificate Timestamp (SCT)
        ↓
CA embeds SCT in final certificate
        |
        ↓
Browser verifies SCT via:
  1. SCT embedded in certificate extension
  2. SCT in TLS extension (server sends)
  3. SCT in OCSP response
```

```python
# Check CT logs for domain
import requests

def check_crt_sh(domain):
    url = f"https://crt.sh/?q=%.{domain}&output=json"
    response = requests.get(url, timeout=30)
    certs = response.json()
    
    print(f"Found {len(certs)} certificates for *.{domain}")
    for cert in certs[:20]:
        print(f"ID: {cert['id']}")
        print(f"Logged: {cert['entry_timestamp']}")
        print(f"Not After: {cert['not_after']}")
        print(f"Common Name: {cert['common_name']}")
        print(f"Name Value: {cert['name_value']}")
        print("---")
    
    # Find subdomains
    subdomains = set()
    for cert in certs:
        names = cert['name_value'].split('\n')
        for name in names:
            if name.endswith(f'.{domain}') and name != domain:
                subdomains.add(name.strip())
    
    return subdomains

# Recon: crt.sh reveals all issued certs (subdomains!)
subdomains = check_crt_sh('example.com')
print("Discovered subdomains:", subdomains)

# Tools for CT-based recon:
# subfinder -d example.com   (uses CT logs)
# amass enum -d example.com  (uses CT logs + DNS)
# ct-exposer
# certspotter
```

### 4.2 CT Attack Scenarios

```
Attack: Certificate Misissuance Detection
- Attacker compromises CA or uses social engineering
- Issues fraudulent cert for victim domain
- CT log reveals the fraudulent cert within 24h (MMD - Maximum Merge Delay)
- Domain owner monitors CT logs for unexpected certs

Monitoring with certspotter:
certspotter -watchlist watchlist.txt -script /usr/local/bin/notify.sh

watchlist.txt:
.example.com
.company.org

notify.sh receives cert info via environment:
CERTSPOTTER_ISSUANCES (JSON with cert details)
```

---

## 5. HSTS (HTTP Strict Transport Security)

### 5.1 HSTS Implementation

```nginx
# Nginx HSTS configuration
server {
    listen 443 ssl http2;
    server_name example.com *.example.com;
    
    # Strict Transport Security
    # max-age: 1 year (63072000 seconds)
    # includeSubDomains: all subdomains must use HTTPS
    # preload: eligible for HSTS preload list
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    
    # HSTS preload requirements:
    # 1. Valid HTTPS on root domain
    # 2. All subdomains served over HTTPS
    # 3. max-age >= 31536000 (1 year)
    # 4. includeSubDomains
    # 5. preload directive
    # Submit: hstspreload.org
}

# Redirect HTTP to HTTPS (required before HSTS kicks in)
server {
    listen 80;
    server_name example.com *.example.com;
    return 301 https://$host$request_uri;
}
```

### 5.2 HSTS Bypass Attacks

```
Attack 1: HSTS Stripping (sslstrip / bettercap)
============================================
- Works only if user has NEVER visited the site (no HSTS cached)
- Intercept first HTTP→HTTPS redirect
- Serve HTTP to victim, relay HTTPS to server
- Prevention: HSTS preloading (hardcoded in browser)

Attack 2: Subdomain Takeover
===========================
- If includeSubDomains is set, ALL subdomains must use HTTPS
- Attacker takes over orphaned subdomain (CNAME to deleted cloud resource)
- Can intercept traffic for that subdomain
- If subdomain uses HTTP, violates HSTS policy

Attack 3: NTP Attack (time manipulation)
========================================
- HSTS has max-age (expiry)
- Attacker advances system clock past max-age
- HSTS protection expires
- Victim vulnerable to stripping
- Prevention: NTP authentication

Attack 4: New Device / Incognito
================================
- HSTS is per-browser, not per-user
- New browser/incognito has no HSTS cache
- Only preloaded domains protected from day 1
```

---

## 6. Mutual TLS (mTLS)

### 6.1 mTLS Configuration

```nginx
# Nginx mTLS server config
server {
    listen 443 ssl http2;
    server_name api.example.com;
    
    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_trusted_certificate /etc/nginx/certs/ca-chain.crt;
    
    # Require client certificate
    ssl_verify_client on;
    ssl_verify_depth 2;
    ssl_client_certificate /etc/nginx/certs/ca-chain.crt;
    
    # Pass client cert info to upstream
    location /api/ {
        proxy_pass http://backend;
        proxy_set_header X-SSL-Client-Cert $ssl_client_escaped_cert;
        proxy_set_header X-SSL-Client-DN $ssl_client_s_dn;
        proxy_set_header X-SSL-Client-Serial $ssl_client_serial;
        proxy_set_header X-SSL-Client-Verify $ssl_client_verify;  # SUCCESS/FAILED
    }
}
```

```python
# Python mTLS client
import requests
import ssl

# Client certificate authentication
response = requests.get(
    'https://api.example.com/data',
    cert=('/path/to/client.crt', '/path/to/client.key'),
    verify='/path/to/ca-chain.crt'
)

# Using ssl context directly
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.load_cert_chain('/path/to/client.crt', '/path/to/client.key')
context.load_verify_locations('/path/to/ca-chain.crt')
context.minimum_version = ssl.TLSVersion.TLSv1_3
```

```go
// Go mTLS server
package main

import (
    "crypto/tls"
    "crypto/x509"
    "net/http"
    "os"
)

func main() {
    caCert, _ := os.ReadFile("/path/to/ca-chain.crt")
    caCertPool := x509.NewCertPool()
    caCertPool.AppendCertsFromPEM(caCert)

    tlsConfig := &tls.Config{
        ClientCAs:  caCertPool,
        ClientAuth: tls.RequireAndVerifyClientCert,
        MinVersion: tls.VersionTLS13,
    }

    server := &http.Server{
        Addr:      ":8443",
        TLSConfig: tlsConfig,
        Handler:   http.HandlerFunc(handler),
    }

    server.ListenAndServeTLS("/path/to/server.crt", "/path/to/server.key")
}

func handler(w http.ResponseWriter, r *http.Request) {
    // Client cert is verified by TLS layer
    // Access client cert info:
    if r.TLS != nil && len(r.TLS.PeerCertificates) > 0 {
        clientCert := r.TLS.PeerCertificates[0]
        cn := clientCert.Subject.CommonName
        // Use CN for authorization
        _ = cn
    }
}
```

### 6.2 mTLS Use Cases

```
Service Mesh (Istio/Linkerd):
  - Automatic mTLS between services
  - SPIFFE/SPIRE for workload identity
  - Certificate rotation every 24h
  - Zero-trust internal networking

API Gateway:
  - Partner APIs requiring certificate auth
  - Machine-to-machine authentication
  - Eliminates shared API keys

Zero Trust:
  - Device certificates (corporate devices)
  - User certificates (client auth certs)
  - BeyondCorp model: trust device, not network
```

---

## 7. TLS Attacks & Vulnerabilities

### 7.1 Downgrade Attacks

```
POODLE (Padding Oracle On Downgraded Legacy Encryption):
- CVE-2014-3566
- Downgrade TLS to SSL 3.0
- CBC padding oracle in SSL 3.0
- Fixed: disable SSL 3.0 entirely
- TLS_FALLBACK_SCSV prevents downgrade to lower TLS version

DROWN (Decrypting RSA with Obsolete and Weakened eNcryption):
- CVE-2016-0800
- Server supporting SSLv2 (even just for key exchange)
- Export-grade RSA (512-bit keys)
- Attack TLS connections using SSLv2 side-channel
- 33% of HTTPS servers affected at disclosure
- Fixed: disable SSLv2 completely

BEAST (Browser Exploit Against SSL/TLS):
- CVE-2011-3389
- TLS 1.0 CBC predictable IV
- MITM can decrypt chosen plaintext
- Fixed: upgrade to TLS 1.1+, use RC4 (temporary), 1/n-1 split

CRIME / BREACH:
- CRIME: TLS compression oracle (CVE-2012-4929)
- BREACH: HTTP compression oracle
- Both leak secrets via length oracle
- Fixed: disable TLS compression; BREACH harder (no universal fix)
  - Vary secret per request (CSRF tokens)
  - Disable HTTP compression for sensitive endpoints
  - Use chunked encoding
```

### 7.2 Implementation Attacks

```bash
# Heartbleed (CVE-2014-0160)
# OpenSSL 1.0.1 - 1.0.1f, 1.0.2-beta
# TLS Heartbeat extension: echo payload back
# Bug: no bounds check on payload length
# Read up to 64KB of server memory
# Exposed: private keys, session tokens, passwords

# Test with nmap:
nmap --script ssl-heartbleed -p 443 target.com

# BEAST (check TLS version):
nmap --script ssl-enum-ciphers -p 443 target.com | grep "TLSv1.0"

# POODLE (check SSL 3.0):
nmap --script ssl-poodle -p 443 target.com

# DROWN (check SSLv2):
nmap --script sslv2 -p 443 target.com

# LOGJAM (check DH key size):
nmap --script ssl-dh-params -p 443 target.com

# ROBOT (Bleichenbacher RSA):
# Server uses RSA key exchange (not ECDHE)
# Timing oracle in RSA decryption
# Test: github.com/robotattack/robot-detect

# Full TLS analysis:
testssl.sh https://example.com
sslyze --regular example.com
```

### 7.3 Certificate Pinning

```python
# Certificate Pinning in Python
import ssl
import hashlib
import socket
import base64

def get_cert_fingerprint(hostname, port=443):
    ctx = ssl.create_default_context()
    with socket.create_connection((hostname, port)) as sock:
        with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert_der = ssock.getpeercert(binary_form=True)
            # Pin the leaf certificate
            sha256 = hashlib.sha256(cert_der).digest()
            return base64.b64encode(sha256).decode()

# Public Key Pinning (better than cert pinning - survives cert renewal)
def get_pubkey_fingerprint(hostname, port=443):
    ctx = ssl.create_default_context()
    with socket.create_connection((hostname, port)) as sock:
        with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert = ssock.getpeercert(binary_form=True)
            from cryptography import x509
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import serialization
            
            cert_obj = x509.load_der_x509_certificate(cert, default_backend())
            pubkey_der = cert_obj.public_key().public_bytes(
                serialization.Encoding.DER,
                serialization.PublicFormat.SubjectPublicKeyInfo
            )
            sha256 = hashlib.sha256(pubkey_der).digest()
            return base64.b64encode(sha256).decode()

class PinnedHTTPSAdapter(requests.adapters.HTTPAdapter):
    def __init__(self, pinned_pubkeys, **kwargs):
        self.pinned_pubkeys = pinned_pubkeys
        super().__init__(**kwargs)
    
    def send(self, request, **kwargs):
        response = super().send(request, **kwargs)
        # Verify pin against actual cert
        return response

# HPKP (HTTP Public Key Pinning) - DEPRECATED
# Was: Public-Key-Pins: pin-sha256="base64=="; max-age=5184000; includeSubDomains
# Problem: misconfiguration could lock users out permanently
# Removed from browsers in 2018-2019
```

### 7.4 TLS Certificate Attacks

```
Attack 1: CA Compromise
========================
DigiNotar (2011): Iranian hackers compromised Dutch CA
- 531 fraudulent certs issued, including *.google.com
- Used to MITM Iranian Gmail users
- DigiNotar bankrupt within weeks
- Response: browsers hardcoded distrust of DigiNotar

ANSSI (2013): French CA issued fake Google certs
- Used for corporate TLS inspection (proxy)
- Google detected via certificate transparency
- ANSSI intermediate CA distrusted

Prevention:
- CAA records (DNS): specify which CAs can issue for your domain
- DANE (DNS-based Authentication of Named Entities): pin certs via DNSSEC
- Certificate Transparency monitoring

Attack 2: BGP Hijacking + Cert Issuance
========================================
- Attacker hijacks BGP routes for target IP range
- ACME HTTP-01 challenge: CA sends request to target domain
- Hijacked routes redirect to attacker
- Attacker passes challenge, gets valid cert
- Prevention: ACME DNS-01 challenge, CAA records, multi-perspective validation

Attack 3: Wildcard Certificate Abuse
=====================================
- One wildcard cert (*.example.com) covers all subdomains
- If one subdomain compromised, attacker has valid cert for all
- Private key must be shared across all wildcard uses
- Prevention: individual SAN certs per service, shorter validity
```

---

## 8. CAA (Certification Authority Authorization) Records

```bash
# DNS CAA records restrict which CAs can issue certs
# RFC 6844

# Check CAA records
dig CAA example.com
nslookup -type=CAA example.com

# CAA record format:
# example.com.  IN  CAA  0 issue "letsencrypt.org"
# example.com.  IN  CAA  0 issue "digicert.com"
# example.com.  IN  CAA  0 issuewild ";"  # No wildcard certs
# example.com.  IN  CAA  0 iodef "mailto:security@example.com"

# In zone file:
example.com.    3600 IN CAA 0 issue "letsencrypt.org"
example.com.    3600 IN CAA 0 issue "digicert.com"
example.com.    3600 IN CAA 0 issuewild "letsencrypt.org"
example.com.    3600 IN CAA 0 iodef "mailto:security@example.com"

# Flags:
# 0 = non-critical (CA may ignore)
# 128 = critical (CA must understand or refuse to issue)

# Tags:
# issue: authorize CA for non-wildcard certs
# issuewild: authorize CA for wildcard certs
# issuewild overrides issue for wildcards
# iodef: report policy violations to this URL/email

# CAA inheritance: if no CAA on subdomain, inherits from parent
# If ANY CAA record exists, CAs must check it
```

---

## 9. DANE (DNS-Based Authentication)

```bash
# DANE: use DNSSEC-signed DNS records to pin TLS certificates
# RFC 6698 - TLSA records

# TLSA record format:
# _port._proto.host. TLSA usage selector mtype cert-data

# Usage:
# 0 = PKIX-TA: CA constraint (trust anchor)
# 1 = PKIX-EE: End entity constraint (leaf cert)
# 2 = DANE-TA: Trust anchor assertion (custom CA)
# 3 = DANE-EE: End entity assertion (pinned cert, no PKI validation)

# Selector:
# 0 = Full certificate (DER encoded)
# 1 = SubjectPublicKeyInfo only

# Matching Type:
# 0 = Exact match (full data)
# 1 = SHA-256 hash
# 2 = SHA-512 hash

# Generate TLSA record:
openssl s_client -connect example.com:443 < /dev/null 2>/dev/null \
    | openssl x509 -pubkey -noout \
    | openssl pkey -pubin -outform DER \
    | openssl dgst -sha256 -binary \
    | xxd -p -c 32

# Add to DNS:
_443._tcp.example.com. IN TLSA 3 1 1 <sha256-of-pubkey>

# Requires DNSSEC on zone
# Check: https://dane.sys4.de/ or dane-test.nlnetlabs.nl
```

---

## 10. Let's Encrypt & ACME Protocol

```bash
# ACME (Automatic Certificate Management Environment) - RFC 8555

# Certbot - most popular Let's Encrypt client
# Install
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# HTTP-01 challenge (port 80 must be accessible)
sudo certbot --nginx -d example.com -d www.example.com

# DNS-01 challenge (no port 80 needed, supports wildcard)
sudo certbot certonly --dns-cloudflare \
    --dns-cloudflare-credentials ~/.secrets/cloudflare.ini \
    -d example.com -d *.example.com

# Standalone mode (no web server)
sudo certbot certonly --standalone -d example.com

# Webroot mode
sudo certbot certonly --webroot -w /var/www/html -d example.com

# Auto-renewal (systemd timer)
sudo systemctl enable certbot.timer
sudo certbot renew --dry-run

# Wildcard cert requires DNS-01 challenge!

# ACME protocol flow:
# 1. Client creates account (ECDSA key)
# 2. Client submits order for domain
# 3. CA provides challenges (http-01 / dns-01 / tls-alpn-01)
# 4. Client completes challenge (prove domain control)
# 5. CA issues certificate
# 6. Client downloads certificate

# Rate limits (Let's Encrypt):
# 50 certificates per domain per week
# 5 failed validations per account per hour
# 5 duplicate certificate orders per week
# Use staging for testing: --staging
```

---

## 11. TLS Configuration Best Practices

```nginx
# Nginx modern TLS config (2024)
ssl_protocols TLSv1.2 TLSv1.3;

# Cipher suites for TLS 1.2 (TLS 1.3 ciphers are handled separately)
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;  # Let client choose (better for mobile)

# ECDH curves
ssl_ecdh_curve X25519:prime256v1:secp384r1;

# DH params for TLS 1.2 DHE
openssl dhparam -out /etc/nginx/dhparam.pem 4096
ssl_dhparam /etc/nginx/dhparam.pem;

# Session resumption
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;  # Disable for Forward Secrecy (ticket key rotation needed)

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/nginx/certs/ca-chain.crt;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;

# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline';" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
```

```python
# Test TLS config programmatically
import ssl
import socket

def check_tls_config(hostname, port=443):
    results = {}
    
    # Check which TLS versions are supported
    for version_name, version in [
        ('SSL3', ssl.PROTOCOL_TLS),  # Will negotiate
        ('TLS1.0', ssl.PROTOCOL_TLS),
        ('TLS1.1', ssl.PROTOCOL_TLS),
        ('TLS1.2', ssl.PROTOCOL_TLS),
        ('TLS1.3', ssl.PROTOCOL_TLS),
    ]:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        try:
            ctx.minimum_version = ssl.TLSVersion.TLSv1_2
            ctx.maximum_version = ssl.TLSVersion.TLSv1_2
            with socket.create_connection((hostname, port), timeout=5) as sock:
                with ctx.wrap_socket(sock, server_hostname=hostname) as ssock:
                    results[version_name] = ssock.version()
        except Exception as e:
            results[version_name] = f"Failed: {e}"
    
    return results
```

---

## 12. PKI Attack Scenarios (Red Team)

### 12.1 Subdomain Cert Discovery

```bash
# Enumerate certs via CT logs
python3 -c "
import requests, json

def ct_recon(domain):
    url = f'https://crt.sh/?q=%.{domain}&output=json'
    r = requests.get(url, timeout=30)
    certs = r.json()
    
    subdomains = set()
    for c in certs:
        for name in c['name_value'].split('\n'):
            name = name.strip()
            if name and not name.startswith('*'):
                subdomains.add(name)
    return sorted(subdomains)

for sub in ct_recon('example.com'):
    print(sub)
"

# More aggressive CT recon
subfinder -d example.com -all -recursive -silent | sort -u
amass enum -passive -d example.com -o amass_output.txt

# Find expired/old certs that may reveal legacy subdomains
curl -s "https://crt.sh/?q=example.com&output=json" | \
    python3 -c "
import json, sys
from datetime import datetime

certs = json.load(sys.stdin)
now = datetime.now()
for c in certs:
    exp = datetime.strptime(c['not_after'][:10], '%Y-%m-%d')
    if exp < now:
        print('EXPIRED:', c['common_name'], '|', c['not_after'])
"
```

### 12.2 Self-Signed Certificate Risks

```python
# Attack: MITM when client doesn't verify cert
import requests

# Disable SSL verification (BAD, but common in misconfigured code)
response = requests.get('https://api.example.com', verify=False)

# Attacker's MITM proxy intercepts with self-signed cert
# Client happily connects

# Detection: check if code has verify=False or similar

# Proper fix:
response = requests.get(
    'https://api.example.com',
    verify='/path/to/ca-bundle.crt'  # or True for system CAs
)
```

### 12.3 Internal CA Compromise

```
Scenario: Corporate Internal CA Compromise

Attacker Goal: Issue fraudulent certs for internal services
Steps:
1. Compromise build server / CI system
2. Extract CA private key from HSM (if poorly configured)
3. Issue cert for internal app (e.g., internal.corp.local)
4. Launch MITM against employees

Defense:
- CA private key in dedicated HSM with access controls
- Root CA always offline
- Monitor CA issuance logs (cert transparency for internal)
- Short validity periods (90 days max)
- CA key ceremony with witnesses and audit trail
- Immutable audit logging for every issuance
```

---

## Quick Reference

| Concept | Tool/Command |
|---------|-------------|
| View cert | `openssl x509 -in cert.pem -text -noout` |
| Check remote cert | `openssl s_client -connect host:443 -servername host` |
| Verify chain | `openssl verify -CAfile chain.pem cert.pem` |
| Generate CSR | `openssl req -new -key private.key -out cert.csr` |
| TLS test | `testssl.sh https://example.com` |
| CT search | `crt.sh/?q=%.example.com` |
| CAA check | `dig CAA example.com` |
| OCSP query | `openssl ocsp -issuer issuer.pem -cert cert.pem -url <ocsp-url>` |
| Pin check | Compare `sha256(SubjectPublicKeyInfo)` with expected |
| Revoke | `openssl ca -revoke cert.pem -crl_reason keyCompromise` |
