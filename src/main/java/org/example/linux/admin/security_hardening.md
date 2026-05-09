# Security Hardening – Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. SSH Hardening

### What – SSH Hardening là gì?
Cấu hình SSH Server (`sshd_config`) để giảm attack surface: tắt root login, force key auth, rate limiting, cipher hardening.

### How – /etc/ssh/sshd_config

```bash
# Backup trước khi sửa
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# /etc/ssh/sshd_config – production hardened
cat > /etc/ssh/sshd_config.d/hardening.conf << 'EOF'
# Network
Port 2222                              # đổi port (security by obscurity)
AddressFamily inet                     # IPv4 only (hoặc inet6)
ListenAddress 0.0.0.0

# Authentication
PermitRootLogin no                     # KHÔNG cho root login
PasswordAuthentication no              # chỉ key-based
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
UsePAM yes

# MFA với 2FA (Google Authenticator)
# AuthenticationMethods publickey,keyboard-interactive

# Connection limits
MaxAuthTries 3                         # tối đa 3 lần thử
MaxSessions 10                         # max sessions per connection
MaxStartups 10:30:60                   # max concurrent unauthenticated: start:rate:full
LoginGraceTime 20s                     # 20s để authenticate

# Idle timeout
ClientAliveInterval 300                # ping client every 300s
ClientAliveCountMax 2                  # disconnect after 2 missed pings
# = disconnect idle session after 10 minutes

# Privilege separation
UsePrivilegeSeparation sandbox

# Forwarding (disable nếu không cần)
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no                  # disable nếu không cần tunneling
PermitTunnel no

# Restrict users/groups
AllowUsers alice bob deploy            # whitelist users
# AllowGroups sshusers                 # whitelist groups
DenyUsers guest test                   # blacklist

# Subsystems
Subsystem sftp /usr/lib/openssh/sftp-server

# Crypto (modern ciphers)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org

# Banner
Banner /etc/ssh/banner.txt
EOF

# Validate config
sshd -t -f /etc/ssh/sshd_config       # test syntax
systemctl reload sshd
```

### How – SSH Keys Best Practices

```bash
# Generate strong keys
ssh-keygen -t ed25519 -C "user@host-$(date +%Y%m%d)"   # Ed25519 (recommended)
ssh-keygen -t rsa -b 4096 -C "legacy-system"            # RSA 4096 (compatibility)

# Passphrase-protected keys (use ssh-agent for convenience)
ssh-add ~/.ssh/id_ed25519              # add to agent
ssh-add -l                             # list loaded keys
ssh-add -t 3600 ~/.ssh/id_ed25519     # add with 1-hour expiry

# authorized_keys options
cat >> ~/.ssh/authorized_keys << 'EOF'
# Restrict: only allow specific commands and from specific IPs
from="192.168.1.0/24",command="/usr/bin/rsync --server ...",no-pty,no-agent-forwarding,no-port-forwarding ssh-ed25519 AAAA...
EOF

# Certificate-based auth (scalable)
# Create CA key
ssh-keygen -t ed25519 -f /etc/ssh/ssh_ca -C "SSH CA"

# Sign user key (valid for 1 week, specific user)
ssh-keygen -s /etc/ssh/ssh_ca -I "alice-2024" -n alice -V "+1w" ~/.ssh/alice_key.pub
# Creates: ~/.ssh/alice_key-cert.pub

# Server: trust the CA
echo "TrustedUserCAKeys /etc/ssh/ssh_ca.pub" >> /etc/ssh/sshd_config
```

---

## 2. fail2ban – Brute Force Protection

### What – fail2ban là gì?
**fail2ban** scan log files và ban IPs thực hiện quá nhiều lần authentication thất bại bằng cách tạo iptables/nftables rules tạm thời.

### How – Cài đặt và Cấu hình

```bash
apt install fail2ban

# /etc/fail2ban/jail.local (KHÔNG sửa jail.conf trực tiếp)
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban settings
bantime  = 3600                        # 1 giờ
findtime = 600                         # window 10 phút
maxretry = 5                           # 5 lần thất bại
banaction = iptables-multiport         # hoặc nftables-multiport

# Whitelist
ignoreip = 127.0.0.1/8 192.168.1.0/24

# Email notification (cần mailutils)
# destemail = admin@example.com
# sendername = Fail2Ban
# action = %(action_mwl)s

# Logging
loglevel = INFO
logtarget = /var/log/fail2ban.log

[sshd]
enabled = true
port    = 2222                         # đổi port như sshd_config
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime  = 86400                       # 24 giờ cho SSH

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 5

[nginx-limit-req]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime  = 300

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2

[postfix]
enabled = true
port    = smtp,ssmtp,submission
logpath = %(postfix_log)s
maxretry = 5
EOF

systemctl enable --now fail2ban

# Management
fail2ban-client status                 # tổng quan
fail2ban-client status sshd            # trạng thái jail sshd
fail2ban-client set sshd unbanip 192.168.1.100  # unban IP
fail2ban-client set sshd banip 10.0.0.100       # manual ban
fail2ban-client reload                 # reload config
```

---

## 3. Firewall với nftables (Production)

### How – Hardened Server Firewall

```nft
#!/usr/sbin/nft -f
# /etc/nftables.conf – Production hardened firewall

flush ruleset

table inet filter {
    # Define sets for better organization
    set trusted_ips {
        type ipv4_addr
        flags interval
        elements = { 192.168.1.0/24, 10.0.0.0/8 }
    }

    set blocked_countries {
        type ipv4_addr
        flags interval
        # Populated by external script/ipset
    }

    chain input {
        type filter hook input priority filter; policy drop;

        # Track connections
        ct state invalid drop
        ct state { established, related } accept

        # Loopback
        iif "lo" accept

        # ICMP (rate limited)
        ip protocol icmp icmp type { echo-request } limit rate 10/second accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH (trusted IPs only, rate limited)
        tcp dport 2222 ip saddr @trusted_ips accept
        tcp dport 2222 ct state new limit rate 3/minute burst 5 packets log prefix "SSH-ratelimit: " accept
        tcp dport 2222 log prefix "SSH-blocked: " drop

        # Web
        tcp dport { 80, 443 } accept
        udp dport 443 accept       # QUIC/HTTP3

        # Custom app port (from trusted only)
        tcp dport 8080 ip saddr @trusted_ips accept

        # Log and drop everything else
        limit rate 5/second log prefix "nft-dropped: " flags all
        drop
    }

    chain output {
        type filter hook output priority filter; policy accept;

        # Prevent DNS leaks (optional: only use specific DNS)
        # udp dport 53 ip daddr != { 8.8.8.8, 1.1.1.1 } drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }
}

table inet nat {
    chain prerouting {
        type nat hook prerouting priority dstnat;
        # Port forwarding example:
        # tcp dport 80 dnat ip to 192.168.1.100:8080
    }

    chain postrouting {
        type nat hook postrouting priority srcnat;
        # Masquerade for VPN/containers
        oifname "eth0" masquerade
    }
}
```

---

## 4. SELinux Basics

### What – SELinux là gì?
**SELinux (Security-Enhanced Linux)** là Mandatory Access Control (MAC) framework của NSA. Mọi process và file có **security context (label)**, và policy quyết định ai được làm gì.

### How – SELinux Concepts

```bash
# Context format: user:role:type:level
# user_u:user_r:user_t:s0
# system_u:system_r:httpd_t:s0   (nginx running)
# system_u:object_r:httpd_sys_content_t:s0  (nginx files)

# Modes
getenforce                             # Enforcing / Permissive / Disabled
setenforce 0                          # set Permissive (temporary)
setenforce 1                          # set Enforcing (temporary)
# Permanent: /etc/selinux/config → SELINUX=enforcing

# Xem contexts
ls -Z /var/www/html/                   # file contexts
ps auxZ | grep nginx                   # process context

# Xem booleans (on/off switches for common scenarios)
getsebool -a                           # list all
getsebool httpd_can_network_connect    # can nginx connect to network?
setsebool httpd_can_network_connect on # allow
setsebool -P httpd_can_network_connect on  # persistent (-P)

# Common booleans
setsebool -P httpd_can_connect_ftp on
setsebool -P httpd_execmem on
setsebool -P httpd_use_nfs on
setsebool -P httpd_enable_homedirs on
setsebool -P allow_httpd_anon_write on
```

### How – Fix SELinux Issues

```bash
# Xem denials
ausearch -m avc -ts recent             # recent denials
ausearch -m avc -c nginx               # denials for nginx
sealert -a /var/log/audit/audit.log    # user-friendly analysis
grep "denied" /var/log/audit/audit.log

# Fix: thay đổi file context
chcon -t httpd_sys_content_t /var/www/myapp/    # temporary
semanage fcontext -a -t httpd_sys_content_t "/var/www/myapp(/.*)?"  # permanent
restorecon -R /var/www/myapp/          # apply

# Fix: tạo custom policy từ denials
audit2allow -a                         # xem suggested allows
audit2allow -a -M mypolicy             # tạo module
semodule -i mypolicy.pp                # install module

# Relabel filesystem
touch /.autorelabel && reboot          # full relabel on next boot
```

---

## 5. AppArmor Basics

### What – AppArmor là gì?
**AppArmor** là MAC system dựa trên **profiles** (dễ dùng hơn SELinux). Default trên Ubuntu/Debian. Profiles chỉ định quyền truy cập của từng process.

### How – AppArmor

```bash
# Status
aa-status                              # xem tất cả profiles
apparmor_status

# Modes
aa-enforce /usr/sbin/nginx             # enforce mode
aa-complain /usr/sbin/nginx            # complain (log only, không block)
aa-disable /usr/sbin/nginx             # disable profile

# Reload
apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx

# Xem violations
dmesg | grep "apparmor"
cat /var/log/syslog | grep "apparmor"
journalctl -k | grep apparmor

# Profile syntax (/etc/apparmor.d/usr.sbin.nginx)
cat /etc/apparmor.d/usr.sbin.nginx
```

```
# AppArmor profile example
/usr/sbin/nginx {
    #include <abstractions/base>
    #include <abstractions/nameservice>

    capability net_bind_service,
    capability setgid,
    capability setuid,

    /var/log/nginx/ rw,
    /var/log/nginx/** rw,
    /etc/nginx/ r,
    /etc/nginx/** r,
    /var/www/html/ r,
    /var/www/html/** r,
    /run/nginx.pid rw,
    /usr/sbin/nginx mr,
    /tmp/ rw,
    /tmp/** rw,

    # Network
    network inet tcp,
    network inet udp,
}
```

---

## 6. Linux Audit Framework (auditd)

### What – auditd là gì?
**auditd** là Linux audit daemon, ghi lại **security-relevant events**: file access, syscalls, authentication, privilege escalation.

### How – Cấu hình và Rules

```bash
apt install auditd audispd-plugins

# Xem logs
ausearch -ts recent                    # recent events
ausearch -k file_deletion -i           # events tagged "file_deletion"
ausearch -ua 1000 -ts today            # user UID 1000, today
aureport                               # summary report
aureport --failed                      # failed events
aureport --auth                        # authentication report

# Audit rules (/etc/audit/rules.d/)
# Format: -w path -p permissions -k key

# Monitor file changes
auditctl -w /etc/passwd -p wa -k passwd_changes
auditctl -w /etc/sudoers -p wa -k sudoers_changes
auditctl -w /var/log/ -p wa -k log_changes

# Monitor system calls
auditctl -a always,exit -F arch=b64 -S execve -k exec_commands
auditctl -a always,exit -F arch=b64 -S open,openat -F exit=-EACCES -k access_denied

# Monitor privilege escalation
auditctl -a always,exit -F arch=b64 -S setuid -S setgid -k priv_esc

# /etc/audit/rules.d/custom.rules
cat > /etc/audit/rules.d/custom.rules << 'EOF'
# Immutable (prevent auditctl changes while running)
-e 2

# Watch critical files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config

# Watch authentication
-w /var/run/faillock/ -p wa -k auth_failure
-w /var/log/auth.log -p wa -k auth_log

# Privilege escalation
-a always,exit -F arch=b64 -S setuid -k privilege_escalation

# Network activity
-a always,exit -F arch=b64 -S socket -k network_socket
EOF

augenrules --load                      # load rules
```

---

## 7. CIS Benchmark Hardening

### How – Automated Hardening

```bash
# lynis – security audit tool
apt install lynis
lynis audit system                     # full audit
lynis audit system --tests-from-group authentication  # specific tests

# OpenSCAP – compliance scanning
apt install libopenscap8 openscap-daemon
oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_standard \
    /usr/share/xml/scap/ssg/content/ssg-ubuntu2004-xccdf.xml

# Ansible hardening role
# ansible-galaxy install dev-sec.os-hardening

# Key hardening checklist:
# ✓ Disable unused services
# ✓ Remove unused packages
# ✓ SSH hardening (no root, key-only)
# ✓ Firewall rules (default deny)
# ✓ Automatic security updates
# ✓ /tmp mounted with noexec
# ✓ Core dumps disabled
# ✓ IP forwarding disabled (unless router)
# ✓ ICMP redirects disabled
# ✓ Source routing disabled
# ✓ sysctl hardening

# sysctl security settings
cat > /etc/sysctl.d/99-security.conf << 'EOF'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0

# Log martians (packets with impossible source)
net.ipv4.conf.all.log_martians = 1

# Disable IP forwarding (unless router/NAT)
net.ipv4.ip_forward = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# Time wait reuse
net.ipv4.tcp_tw_reuse = 1

# Disable ICMP ping
# net.ipv4.icmp_echo_ignore_all = 1  # (comment out unless needed)

# Randomize virtual address space (ASLR)
kernel.randomize_va_space = 2

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict kernel pointer leaks
kernel.kptr_restrict = 2

# Core dumps disabled
fs.suid_dumpable = 0
kernel.core_pattern = /dev/null
EOF

sysctl -p /etc/sysctl.d/99-security.conf
```

---

## 8. Compare & Trade-offs

### Compare – MAC Systems

| | SELinux | AppArmor |
|--|---------|----------|
| Default trên | RHEL/CentOS/Fedora | Ubuntu/Debian |
| Model | Label-based (context) | Path-based (profile) |
| Complexity | Cao | Trung bình |
| Granularity | Rất cao | Cao |
| Debugging | Khó hơn | Dễ hơn |
| Performance overhead | ~5% | ~3% |
| Khi dùng | Enterprise security | Application isolation |

### Trade-offs

- **SSH key-only**: secure nhưng cần quy trình quản lý key; certificate auth scalable hơn
- **fail2ban**: hiệu quả nhưng không chống được distributed attacks; cần rate limiting ở upstream (load balancer)
- **SELinux Enforcing**: bảo mật tốt nhất nhưng có thể break apps; Permissive mode trước khi Enforcing
- **auditd**: cần thiết cho compliance nhưng tạo nhiều I/O; tune với rate limiting

---

### Ghi chú – Chủ đề tiếp theo
> **13.3 Performance Tuning**: CPU/memory/network/disk tuning, sysctl deep dive, profiling tools (perf, eBPF)
