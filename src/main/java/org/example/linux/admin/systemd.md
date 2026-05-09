# systemd Deep Dive

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. systemd Architecture

### What – systemd là gì?
**systemd** là init system và service manager cho Linux (PID 1). Thay thế SysV init/Upstart, quản lý toàn bộ lifecycle của system: boot, services, mounts, timers, sockets, devices.

### How – Kiến trúc

```
systemd (PID 1)
├── systemctl          – CLI để control systemd
├── journald           – log collection & storage daemon
├── logind             – login/session management
├── networkd           – network configuration
├── resolved           – DNS resolver
├── timedated          – NTP, timezone
├── hostnamed          – hostname management
└── udevd              – device management

Unit files (/etc/systemd/system/ và /lib/systemd/system/):
├── service    – daemon services
├── socket     – socket-based activation
├── target     – grouping units (như runlevels)
├── timer      – scheduled tasks (cron replacement)
├── mount      – filesystem mounts
├── automount  – automounting
├── path       – path-based activation
├── device     – device-based activation
├── swap       – swap management
└── slice      – cgroup hierarchy
```

### How – Unit File Structure

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application Server
Documentation=https://docs.example.com
After=network.target postgresql.service redis.service
Requires=postgresql.service
Wants=redis.service
PartOf=app.target
ConditionPathExists=/opt/myapp/bin/server
AssertFileNotEmpty=/etc/myapp/config.conf

[Service]
Type=simple
User=appuser
Group=appgroup
WorkingDirectory=/opt/myapp
Environment=NODE_ENV=production
EnvironmentFile=/etc/myapp/env
ExecStartPre=/opt/myapp/bin/migrate
ExecStart=/opt/myapp/bin/server --port 3000
ExecStartPost=/bin/sh -c 'sleep 2 && curl -f http://localhost:3000/health'
ExecStop=/bin/kill -TERM $MAINPID
ExecReload=/bin/kill -HUP $MAINPID
ExecStopPost=/opt/myapp/bin/cleanup.sh
Restart=on-failure
RestartSec=5s
RestartPreventExitStatus=1 2 3
TimeoutStartSec=30s
TimeoutStopSec=30s
KillMode=mixed
KillSignal=SIGTERM
FinalKillSignal=SIGKILL

# Resource limits
MemoryMax=512M
MemoryHigh=400M
CPUQuota=50%
TasksMax=256
LimitNOFILE=65536

# Security hardening
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/myapp /var/log/myapp
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
```

---

## 2. Unit Types Deep Dive

### How – Service Types

```ini
# Type=simple (default)
# systemd assumes service is ready immediately after ExecStart fork
# Use: long-running daemons that don't fork

# Type=exec
# Like simple but systemd waits until ExecStart exec() completes
# Use: programs that take time to initialize exec()

# Type=forking
# Process forks; parent exits; child becomes main process
# systemd uses PIDFile to track the child
[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStart=/usr/sbin/nginx

# Type=notify
# Service sends sd_notify() when ready
# Use: services with proper systemd integration (like nginx, postgresql)
[Service]
Type=notify
ExecStart=/usr/sbin/nginx -g 'daemon off;'

# Type=dbus
# Service is ready when it acquires a D-Bus name
[Service]
Type=dbus
BusName=org.freedesktop.NetworkManager

# Type=oneshot
# Short-lived task; systemd waits for it to complete
# RemainAfterExit=yes: unit stays "active" after process exits
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /opt/setup.sh

# Type=idle
# Like simple but waits until all jobs are dispatched (avoids boot noise)
```

### How – Dependencies & Ordering

```ini
# Ordering (khi nào start)
After=network.target    # start AFTER network.target
Before=shutdown.target  # start BEFORE shutdown.target

# Dependencies (có start không)
Requires=postgresql.service   # MUST have; if postgresql fails → this fails
Wants=redis.service           # NICE to have; if redis fails → this continues
Requisite=db.service          # Like Requires but db must ALREADY be active
PartOf=app.target             # If app.target stopped/restarted → this too
BindsTo=storage.service       # If storage stops → this stops immediately

# Conflict
Conflicts=old-app.service     # Cannot run simultaneously

# Conditions (không tạo dependency, chỉ check trước khi start)
ConditionPathExists=/etc/myapp/config.conf      # file phải tồn tại
ConditionFileNotEmpty=/etc/myapp/config.conf
ConditionHost=prod-server-01                    # chỉ chạy trên host này
ConditionVirtualization=no                      # không chạy trong VM
ConditionKernelCommandLine=systemd.debug        # chỉ nếu kernel param set

# Assertions (như Condition nhưng failure = error)
AssertFileNotEmpty=/etc/ssl/certs/myapp.pem
```

---

## 3. Targets – System States

### What – Targets là gì?
**Targets** là grouping units, tương đương runlevels trong SysV. Dùng để đạt trạng thái hệ thống mong muốn.

### How – Targets

```bash
# Tương đương runlevels
ls -la /lib/systemd/system/runlevel*.target

# Main targets
# poweroff.target    = halt (runlevel 0)
# rescue.target      = single-user mode (runlevel 1)
# multi-user.target  = text mode, network (runlevel 3)
# graphical.target   = GUI (runlevel 5)
# reboot.target      = reboot (runlevel 6)

# Xem default target
systemctl get-default
systemctl set-default multi-user.target     # headless server

# Switch target
systemctl isolate multi-user.target         # switch ngay

# Emergency/rescue
systemctl isolate emergency.target          # minimal, read-only root
systemctl isolate rescue.target             # single-user

# Xem dependencies của target
systemctl list-dependencies multi-user.target
systemd-analyze critical-chain multi-user.target

# Tạo custom target
cat > /etc/systemd/system/app.target << 'EOF'
[Unit]
Description=Application Services
After=multi-user.target
Wants=myapp.service nginx.service postgresql.service
EOF

systemctl enable app.target
systemctl start app.target
```

---

## 4. Socket Activation

### What – Socket Activation là gì?
**Socket Activation**: systemd tạo socket và listen, chỉ start service khi có connection đến. Cải thiện startup time và resource usage.

### How – Socket Unit

```ini
# /etc/systemd/system/myapp.socket
[Unit]
Description=My Application Socket
PartOf=myapp.service

[Socket]
ListenStream=3000                     # TCP port
# ListenStream=/run/myapp.sock        # Unix socket
# ListenDatagram=514                  # UDP
Accept=no                             # pass socket to service (not per-connection)
# Accept=yes                          # spawn new service instance per connection

[Install]
WantedBy=sockets.target
```

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
Requires=myapp.socket

[Service]
Type=simple
ExecStart=/opt/myapp/bin/server
# Service nhận socket từ systemd qua file descriptor (SD_LISTEN_FDS)
# Dùng libsystemd hoặc sd_listen_fds() trong code

[Install]
WantedBy=multi-user.target
```

```bash
# Enable socket (service sẽ start on-demand)
systemctl enable --now myapp.socket
systemctl status myapp.socket          # LISTENING
# myapp.service chưa chạy cho đến khi có connection
```

### How – D-Bus Activation

```ini
[Service]
Type=dbus
BusName=org.example.MyApp
```

---

## 5. Timers – cron Replacement

### What – systemd Timers
**Timers** là cron replacement với logging, dependencies, error handling tốt hơn.

### How – Timer Units

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily Database Backup
Requires=backup.service

[Timer]
# Calendar expressions
OnCalendar=daily                      # = *-*-* 00:00:00
OnCalendar=weekly                     # = Mon *-*-* 00:00:00
OnCalendar=monthly                    # = *-*-01 00:00:00
OnCalendar=*-*-* 02:30:00             # 2:30 AM daily
OnCalendar=Mon,Wed,Fri 08:00:00       # specific days
OnCalendar=*-*-* *:00/15:00           # every 15 minutes

# Relative timers
OnActiveSec=5min                      # 5 min after activation
OnBootSec=10min                       # 10 min after boot
OnUnitActiveSec=1h                    # 1h after last activation
OnUnitInactiveSec=30min               # 30 min after last deactivation

# Randomized delay (spread load)
RandomizedDelaySec=300                # ±5 minute random delay

# Persistent (catch up if system was off)
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Database Backup Job
After=postgresql.service

[Service]
Type=oneshot
User=backup
ExecStart=/opt/scripts/backup.sh
```

```bash
# Enable timer
systemctl enable --now backup.timer

# Check timers
systemctl list-timers                  # all active timers
systemctl list-timers --all            # including inactive

# Manual trigger
systemctl start backup.service         # run immediately (not timer)
```

---

## 6. journald – Logging

### How – journald Configuration

```ini
# /etc/systemd/journald.conf
[Journal]
Storage=persistent                     # auto, volatile, persistent, none
Compress=yes                           # compress stored logs
SystemMaxUse=500M                      # max disk usage
SystemKeepFree=500M                    # min free space to keep
SystemMaxFileSize=50M                  # max single file size
RuntimeMaxUse=100M                     # max volatile storage
MaxRetentionSec=1month                 # max age
MaxFileSec=1week                       # max age per file
ForwardToSyslog=no                     # don't forward to syslog
ForwardToKMsg=no
RateLimitIntervalSec=30s
RateLimitBurst=10000                   # max messages per interval
```

### How – journalctl Advanced

```bash
# Basic usage
journalctl -u nginx                    # service logs
journalctl -u nginx -f                 # follow
journalctl -u nginx -n 50              # last 50 lines
journalctl -u nginx --since "1 hour ago"
journalctl -u nginx --since "2024-01-01" --until "2024-01-02"

# Priority filter
journalctl -p err                      # error and above (err, crit, alert, emerg)
journalctl -p warning..err             # range: warning to error
# 0=emerg 1=alert 2=crit 3=err 4=warning 5=notice 6=info 7=debug

# Field filters
journalctl _SYSTEMD_UNIT=nginx.service
journalctl _PID=1234
journalctl _UID=1000                   # logs from specific user
journalctl _COMM=bash                  # logs from bash processes
journalctl _TRANSPORT=kernel           # kernel messages only
journalctl SYSLOG_IDENTIFIER=myapp    # by syslog identifier

# Output formats
journalctl -u nginx -o json            # JSON per line
journalctl -u nginx -o json-pretty     # pretty JSON
journalctl -u nginx -o short-iso       # ISO timestamps
journalctl -u nginx -o cat             # only message (no metadata)
journalctl -u nginx -o verbose         # all fields

# Export and import
journalctl --export > journal.bin
journalctl --import journal.bin

# Remote journal
# /etc/systemd/journal-remote.conf

# Disk usage
journalctl --disk-usage
journalctl --vacuum-size=500M          # reduce to 500MB
journalctl --vacuum-time=2weeks        # remove entries older than 2 weeks
journalctl --verify                    # verify journal integrity
```

---

## 7. Security Hardening trong Unit Files

### How – Sandboxing Options

```ini
[Service]
# Filesystem isolation
PrivateTmp=yes                         # private /tmp
PrivateDevices=yes                     # no device access
PrivateNetwork=yes                     # no network access
PrivateUsers=yes                       # user namespace isolation

ProtectSystem=strict                   # read-only /usr /boot /etc
ProtectSystem=full                     # + read-only /etc
ProtectSystem=yes                      # read-only /usr /boot
ProtectHome=yes                        # no access to /home /root /run/user
ProtectHome=read-only                  # read-only /home
ProtectKernelTunables=yes              # no /proc/sys, /sys writing
ProtectKernelModules=yes               # no kernel module loading
ProtectControlGroups=yes               # no cgroup modifications
ProtectClock=yes                       # no clock changes
ProtectHostname=yes                    # no hostname changes

# Capability restrictions
CapabilityBoundingSet=                 # remove ALL capabilities
CapabilityBoundingSet=CAP_NET_BIND_SERVICE  # only bind ports <1024
AmbientCapabilities=CAP_NET_BIND_SERVICE    # give capability without root
NoNewPrivileges=yes                    # cannot gain privileges

# Writable paths (khi ProtectSystem=strict)
ReadWritePaths=/var/lib/myapp
ReadWritePaths=/var/log/myapp
ReadOnlyPaths=/etc/myapp

# Syscall filtering
SystemCallFilter=@system-service        # whitelist: typical service syscalls
SystemCallFilter=~@debug                # blacklist: block debug syscalls
SystemCallFilter=~@mount               # blacklist: no mount
SystemCallArchitectures=native          # only native arch syscalls

# Network namespace
IPAddressDeny=any                      # deny all IPs
IPAddressAllow=localhost               # allow only localhost
IPAddressAllow=192.168.1.0/24          # allow subnet
```

---

## 8. Real-world Patterns

### How – Multi-instance Services

```ini
# Template unit: myapp@.service
[Unit]
Description=My App Instance %i
After=network.target

[Service]
Type=simple
User=appuser
ExecStart=/opt/myapp/bin/server --port %i
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
# Start multiple instances
systemctl start myapp@3000.service
systemctl start myapp@3001.service
systemctl start myapp@3002.service
systemctl enable myapp@{3000,3001,3002}.service
```

### How – Health Checks & Auto-restart

```ini
[Service]
Restart=on-failure                     # restart nếu non-zero exit
RestartSec=5s                          # wait 5s trước khi restart
StartLimitInterval=60s                 # trong 60s
StartLimitBurst=5                      # chỉ restart tối đa 5 lần
StartLimitAction=reboot                # reboot hệ thống nếu vượt limit

# Watchdog (service gửi heartbeat)
WatchdogSec=30s                        # expect heartbeat every 30s
# Code: sd_notify(0, "WATCHDOG=1")

ExecStartPost=/bin/sh -c 'until curl -sf http://localhost:3000/health; do sleep 1; done'
```

### Real-world: systemd-analyze

```bash
# Boot time analysis
systemd-analyze                        # tổng boot time
systemd-analyze blame                  # time per unit
systemd-analyze critical-chain         # critical path
systemd-analyze plot > boot.svg        # visual timeline

# Unit analysis
systemd-analyze verify /etc/systemd/system/myapp.service  # validate unit file
systemd-analyze security myapp.service  # security score
```

---

### Ghi chú – Chủ đề tiếp theo
> **13.2 Security Hardening**: SSH hardening, fail2ban, nftables/iptables rules, SELinux/AppArmor basics, audit framework
