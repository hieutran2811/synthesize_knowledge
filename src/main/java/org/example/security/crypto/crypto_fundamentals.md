# Cryptography Fundamentals Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Block Cipher Modes

### What – Block Cipher Modes là gì?
Chỉ định cách encrypt dữ liệu lớn hơn 1 block (AES block = 128 bit = 16 bytes). Chọn mode sai → toàn bộ security sụp đổ dù dùng AES-256.

### How – ECB Mode (Electronic Codebook) – BROKEN

```
ECB: mỗi block encrypt độc lập với cùng key
Plain:  [BLOCK1] [BLOCK2] [BLOCK3]
Cipher: [ENC(K,B1)] [ENC(K,B2)] [ENC(K,B3)]

Vấn đề: cùng plaintext block → cùng ciphertext block!
→ Pattern leakage!

Ví dụ nổi tiếng: ảnh Tux penguin mã hóa bằng ECB
→ Vẫn nhìn thấy outline của penguin trong ciphertext!

ECB Attack – Cut and Paste:
Attacker biết cấu trúc plaintext:
Block 1: "username=Alice---"
Block 2: "role=user-------"

Có ciphertext của "role=admin------" từ trước
→ Thay block 2 bằng ciphertext của "role=admin------"
→ Giải mã → "username=Alice---role=admin------"
→ Privilege escalation!
```

```python
from Crypto.Cipher import AES
import os

# ECB Attack Demo:
key = os.urandom(16)

def encrypt_ecb(plaintext):
    cipher = AES.new(key, AES.MODE_ECB)
    # Pad đến bội số của 16
    padded = plaintext.ljust((len(plaintext) // 16 + 1) * 16, b'\x00')
    return cipher.encrypt(padded)

# Byte-at-a-time ECB decryption:
# Target: encrypt(attacker_controlled + unknown_secret, key)
# Attacker craft input để detect 1 byte at a time
def ecb_oracle(attacker_input, secret):
    plaintext = attacker_input + secret
    return encrypt_ecb(plaintext)

# Detect ECB: gửi 48 bytes giống nhau → 2 blocks giống nhau
test = b'A' * 48
ciphertext = encrypt_ecb(test)
blocks = [ciphertext[i:i+16] for i in range(0, len(ciphertext), 16)]
if blocks[0] == blocks[1]:
    print("ECB mode detected!")
```

### How – CBC Mode (Cipher Block Chaining)

```
CBC: XOR plaintext với previous ciphertext block trước khi encrypt
C[i] = Enc(K, P[i] XOR C[i-1])
C[0] = Enc(K, P[0] XOR IV)    ← IV (Initialization Vector) random

Secure hơn ECB vì cùng plaintext → khác ciphertext
Nhưng: Padding Oracle Attack!
```

```python
# CBC Padding Oracle Attack:
# Server decrypt ciphertext → nếu padding lỗi → 500 error, OK → 200
# Attacker có thể decrypt bất kỳ ciphertext nào!

# PKCS#7 Padding:
# Block = 16 bytes
# Nếu plaintext = 13 bytes → thêm 3 bytes: "\x03\x03\x03"
# Nếu plaintext = 16 bytes → thêm 1 block mới: "\x10" * 16
# Verify: last byte value = số bytes padding, tất cả phải bằng nhau

# Oracle Attack (decrypt 1 byte):
# C[i-1] XOR X → D(K, C[i]) → P[i]
# Thử X từ 0-255: khi padding valid → D(K, C[i]) XOR X = "\x01"
# → D(K, C[i]) = X XOR "\x01"
# → P[i] = D(K, C[i]) XOR C[i-1] = X XOR "\x01" XOR C[i-1]

import requests

def padding_oracle(ciphertext):
    """Returns True if padding is valid"""
    r = requests.post('https://target.com/decrypt',
        data={'ciphertext': ciphertext.hex()})
    return r.status_code == 200  # 200 = valid padding

def decrypt_block(prev_block, curr_block):
    intermediate = bytearray(16)

    for byte_pos in range(15, -1, -1):
        padding_val = 16 - byte_pos

        for guess in range(256):
            modified_prev = bytearray(prev_block)
            modified_prev[byte_pos] = guess

            # Set known bytes để tạo valid padding
            for k in range(byte_pos + 1, 16):
                modified_prev[k] = intermediate[k] ^ padding_val

            if padding_oracle(bytes(modified_prev) + curr_block):
                intermediate[byte_pos] = guess ^ padding_val
                break

    # XOR với real prev_block để get plaintext
    return bytes(i ^ p for i, p in zip(intermediate, prev_block))
```

### How – GCM Mode (Galois/Counter Mode) – Recommended

```python
from Crypto.Cipher import AES
import os

# AES-GCM: Authenticated Encryption with Associated Data (AEAD)
# = Confidentiality (CTR mode) + Integrity (GHASH tag)
# → Phát hiện tamper ngay khi decrypt

key = os.urandom(32)  # AES-256

def encrypt_gcm(plaintext: bytes, aad: bytes = b"") -> dict:
    """aad = Additional Authenticated Data (not encrypted but authenticated)"""
    nonce = os.urandom(12)  # 96-bit nonce (recommended for GCM)
    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    cipher.update(aad)      # authenticate but don't encrypt
    ciphertext, tag = cipher.encrypt_and_digest(plaintext)
    return {
        'nonce': nonce,
        'ciphertext': ciphertext,
        'tag': tag,          # 128-bit authentication tag
        'aad': aad
    }

def decrypt_gcm(data: dict) -> bytes:
    cipher = AES.new(key, AES.MODE_GCM, nonce=data['nonce'])
    cipher.update(data['aad'])
    try:
        plaintext = cipher.decrypt_and_verify(data['ciphertext'], data['tag'])
        return plaintext
    except ValueError:
        raise ValueError("Decryption failed: ciphertext tampered!")

# CRITICAL: Nonce phải UNIQUE mỗi encryption!
# Nonce reuse với GCM → KEY RECOVERY ATTACK!
# Nếu encrypt P1 và P2 với cùng nonce:
# C1 XOR C2 = P1 XOR P2 → lộ XOR của plaintexts
# Còn có thể recover authentication key H!
```

---

## 2. Asymmetric Cryptography

### How – RSA Internals & Attacks

```python
# RSA:
# Key generation:
# 1. Choose 2 large primes p, q
# 2. n = p * q (modulus)
# 3. φ(n) = (p-1)(q-1)
# 4. e = 65537 (public exponent, coprime với φ(n))
# 5. d = e^(-1) mod φ(n) (private exponent)
# Public key: (n, e)
# Private key: (n, d)

# Encryption: C = M^e mod n
# Decryption: M = C^d mod n

from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP

# Generate RSA key
key = RSA.generate(2048)    # 2048-bit minimum, 4096 recommended
private_key = key.export_key()
public_key = key.publickey().export_key()

# RSA Attacks:
# 1. Small Private Exponent: nếu d nhỏ → Wiener's Attack
# 2. Small Public Exponent: e=3, encrypt cùng message cho 3 people
#    → Chinese Remainder Theorem → recover plaintext (Håstad's broadcast attack)
# 3. Common Modulus: cùng n, khác e → recover message
# 4. Factoring n: nếu n nhỏ (< 512-bit) → factordb.com
# 5. Timing Attack: measure decryption time → infer d bits

# CTF RSA challenge:
# e, n, c given → factor n → get p, q → compute d → decrypt c
from sympy import factorint
from Crypto.Util.number import inverse

n = 123456789...
e = 65537
c = 987654321...

# Factor n (chỉ với small n hoặc if n = p*q với p,q close)
factors = factorint(n)
p, q = list(factors.keys())
phi = (p - 1) * (q - 1)
d = inverse(e, phi)
m = pow(c, d, n)
print(m.to_bytes((m.bit_length() + 7) // 8, 'big'))
```

### How – Elliptic Curve Cryptography (ECC)

```
ECC:
y² = x³ + ax + b (over finite field)
Point addition: P + Q = R (geometric operation on curve)
Scalar multiplication: n * P = P + P + ... + P (n times)

Private key: random integer d
Public key: Q = d * G  (G = generator point, public parameter)

Security: ECDLP (Elliptic Curve Discrete Logarithm Problem)
Given Q và G, tìm d = "practically impossible" với current computers

Advantages over RSA:
- ECC 256-bit ≈ RSA 3072-bit security
- Smaller key sizes → faster operations, less bandwidth
- Better for IoT, mobile

Common curves:
- P-256 (secp256r1): NIST standard, widely used
- Curve25519: safer implementation, used in Signal, WireGuard
- secp256k1: Bitcoin

Ed25519 (Edwards-curve Digital Signature Algorithm):
- Fast, safe implementation
- Resistant to timing attacks
- Deterministic signatures (no random k needed unlike ECDSA)

ECDSA Vulnerability (Sony PS3 hack):
ECDSA signature: r, s where s = k^(-1)(hash + r*d) mod n
If k (nonce) is reused for 2 signatures:
→ Can recover private key d!
s1 - s2 = k^(-1)(hash1 - hash2) → k = (hash1 - hash2)/(s1 - s2)
d = (s*k - hash) * r^(-1)
→ Sony PS3 dùng k cố định → toàn bộ private key bị lộ!
```

---

## 3. Diffie-Hellman Key Exchange

### How – DH & Attacks

```python
# Diffie-Hellman:
# Public parameters: prime p, generator g
# Alice: a (private) → A = g^a mod p (public)
# Bob: b (private) → B = g^b mod p (public)
# Shared secret: Alice: B^a mod p = g^(ab) mod p
#                Bob: A^b mod p = g^(ab) mod p

# Man-in-the-Middle Attack (nếu không authenticate):
# Alice → [A=g^a] → Mallory
# Mallory → [M=g^m] → Bob
# Bob → [B=g^b] → Mallory
# Mallory → [M=g^m] → Alice
# → Alice và Bob mỗi người share secret với Mallory, không phải nhau!

# Phòng thủ: Authenticated DH (certificate + signature)
# TLS: DH/ECDH key exchange + certificate authentication → ECDHE

# Logjam Attack (2015): 
# Export-grade DH keys (512-bit) → precompute discrete logs
# FREAK attack: force RSA_EXPORT cipher suite → 512-bit RSA
# Phòng thủ: 2048-bit+ DH groups, disable export ciphers

# Safe DH groups:
# RFC 3526 Group 14 (2048-bit), Group 16 (4096-bit)
# RFC 7919 ffdhe2048, ffdhe4096

# Python implementation
import secrets

# DH parameters (thực tế dùng library như cryptography)
p = 0xFFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74...  # 2048-bit prime
g = 2

# Alice
a = secrets.randbelow(p - 2) + 2  # random private key
A = pow(g, a, p)                   # public key

# Bob
b = secrets.randbelow(p - 2) + 2
B = pow(g, b, p)

# Shared secret (same on both sides)
alice_shared = pow(B, a, p)
bob_shared = pow(A, b, p)
assert alice_shared == bob_shared  # ✓
```

---

## 4. Hashing Attacks

### How – Hash Attacks

```python
import hashlib

# Length Extension Attack:
# SHA-256, SHA-512, MD5, SHA-1 dùng Merkle-Damgård construction
# Nếu biết H(secret || message), có thể tính H(secret || message || extra)
# mà không cần biết secret!

# Attack scenario:
# Server: MAC = SHA256(secret + data)
# Server verify: SHA256(secret + data) == MAC
# Attacker biết: H("some_data"), len(secret)
# → Forge: H("some_data" + padding + "extra_data")

# Tool: hash_extender
# hash_extender -d "original_data" -a "admin=true" -l 16 --secret-len 16 \
#   --out-data-format hex --signature "original_hash"

# CTF: hashpump library
import hashpumpy
forged_hash, forged_message = hashpumpy.hashpump(
    original_hash,    # hex string
    original_message, # known message
    "admin=true",     # extra data to append
    secret_length     # length of secret
)

# Phòng thủ: Dùng HMAC!
import hmac
mac = hmac.new(key, msg, hashlib.sha256).hexdigest()
# HMAC = H(key XOR opad || H(key XOR ipad || message))
# → Không vulnerable to length extension

# Hash Collision:
# MD5: chosen-prefix collision attack tạo 2 files khác nhau cùng MD5
# SHA-1: SHAttered attack (2017) → 2 PDFs cùng SHA-1
# SHA-256: no known collision attacks

# Birthday Paradox:
# Với n-bit hash → cần ~2^(n/2) attempts để tìm collision
# MD5 (128-bit) → 2^64 attempts → feasible!
# SHA-256 (256-bit) → 2^128 attempts → not feasible
```

---

## 5. Classical Cipher Attacks (CTF)

### How – Common CTF Crypto Challenges

```python
# 1. Caesar Cipher (ROT-n)
def caesar_brute(ciphertext):
    for shift in range(26):
        result = ''.join(
            chr((ord(c) - ord('A') - shift) % 26 + ord('A'))
            if c.isalpha() else c
            for c in ciphertext.upper()
        )
        print(f"Shift {shift}: {result}")

# 2. Vigenere Cipher
# Key: repeating keyword
# Attack: Index of Coincidence + Kasiski test
# → find key length → frequency analysis per segment

def vigenere_decrypt(ciphertext, key):
    result = []
    for i, c in enumerate(ciphertext):
        if c.isalpha():
            shift = ord(key[i % len(key)].upper()) - ord('A')
            if c.isupper():
                result.append(chr((ord(c) - ord('A') - shift) % 26 + ord('A')))
            else:
                result.append(chr((ord(c) - ord('a') - shift) % 26 + ord('a')))
        else:
            result.append(c)
    return ''.join(result)

# 3. XOR Cipher (very common in CTF)
def xor_crack_single_byte(ciphertext):
    """Brute force single-byte XOR"""
    for key in range(256):
        plaintext = bytes(b ^ key for b in ciphertext)
        # Check if printable ASCII
        if all(32 <= c < 127 or c in (9, 10, 13) for c in plaintext):
            score = sum(1 for c in plaintext if chr(c) in ' etaoinshrdlu')
            print(f"Key: {key} ({chr(key)}) → Score: {score}")
            print(f"  → {plaintext[:50]}")

# Repeating XOR brute force:
from itertools import cycle

def xor_encrypt(plaintext, key):
    return bytes(p ^ k for p, k in zip(plaintext, cycle(key)))

# Hamming distance để tìm key length:
def hamming_distance(b1, b2):
    return bin(int.from_bytes(b1, 'big') ^ int.from_bytes(b2, 'big')).count('1')

# Test key lengths 2-40:
for keylen in range(2, 41):
    blocks = [ciphertext[i:i+keylen] for i in range(0, min(len(ciphertext), keylen*8), keylen)]
    distances = [hamming_distance(blocks[i], blocks[i+1]) / keylen
                 for i in range(len(blocks)-1)]
    avg = sum(distances) / len(distances)
    print(f"keylen {keylen}: normalized distance = {avg:.3f}")
# → Nhỏ nhất là likely key length

# 4. Frequency Analysis
from collections import Counter

def freq_analysis(text):
    text = text.upper().replace(' ', '')
    counts = Counter(text)
    total = len(text)
    english_freq = 'ETAOINSHRDLCUMWFGYPBVKJXQZ'
    print("Frequency analysis:")
    for char, count in sorted(counts.items(), key=lambda x: -x[1]):
        print(f"  {char}: {count/total*100:.1f}%")
```

---

### Compare – Symmetric Cipher Modes

| Mode | IV needed | Authentication | Parallel encrypt | Parallelism decrypt | Vulnerable to |
|------|-----------|---------------|-----------------|---------------------|---------------|
| **ECB** | No | No | Yes | Yes | Pattern leakage, Cut-paste |
| **CBC** | Yes (random) | No | No | Yes | Padding Oracle, Bit-flip |
| **CTR** | Yes (nonce) | No | Yes | Yes | Nonce reuse |
| **GCM** | Yes (nonce) | Yes (AEAD) | Yes | Yes | Nonce reuse |
| **SIV** | No | Yes (nonce-misuse resistant) | No | No | More complex |

### Trade-offs
- RSA vs ECC: RSA cần key 2048-bit, ECC 256-bit cho cùng security → ECC preferred nhưng implementation complexity cao hơn
- GCM nonce: 96-bit nonce sinh ngẫu nhiên → sau 2^32 messages → 50% collision chance → dùng counter thay random, hoặc AES-SIV
- Argon2 vs bcrypt: Argon2 tốt hơn (memory-hard) nhưng bcrypt được hỗ trợ rộng rãi hơn

### Real-world Usage
```python
# Secure implementation checklist:
from cryptography.fernet import Fernet          # high-level symmetric
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, hmac
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import os, base64

# Password hashing: Argon2
from argon2 import PasswordHasher
ph = PasswordHasher(time_cost=2, memory_cost=65536, parallelism=2, hash_len=32)
hash = ph.hash("user_password")
ph.verify(hash, "user_password")   # raises if wrong

# Key derivation from password (for file encryption)
password = b"user_password"
salt = os.urandom(16)
kdf = PBKDF2HMAC(algorithm=hashes.SHA256(), length=32, salt=salt, iterations=480000)
key = base64.urlsafe_b64encode(kdf.derive(password))

# Symmetric encryption (AES-256-GCM via Fernet)
f = Fernet(key)
encrypted = f.encrypt(b"sensitive data")
decrypted = f.decrypt(encrypted)

# Asymmetric: RSA-OAEP (sign+verify, not encrypt large data)
private_key = rsa.generate_private_key(public_exponent=65537, key_size=4096)
signature = private_key.sign(data, padding.PSS(
    mgf=padding.MGF1(hashes.SHA256()),
    salt_length=padding.PSS.MAX_LENGTH
), hashes.SHA256())

# HMAC
h = hmac.HMAC(key, hashes.SHA256())
h.update(b"message")
mac = h.finalize()
```

### Ghi chú – Chủ đề tiếp theo
> PKI & TLS – Certificate chain, CA attacks, HSTS, certificate transparency, mutual TLS, TLS 1.3 handshake

---

*Cập nhật lần cuối: 2026-05-06*
