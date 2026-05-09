# Roadmap Tổng Hợp Kiến Thức Linux

## Cấu trúc thư mục
```
linux/
├── roadmap.md                      ← file này
├── linux_knowledge.md              ← overview tổng quan (10 topics)
├── commands/                       ← deep dive từng nhóm lệnh
│   ├── file_management.md          ← ls, cp, mv, rm, find, locate
│   ├── text_processing.md          ← grep, sed, awk, cut, sort, uniq, tr
│   ├── process_management.md       ← ps, top, kill, nice, systemd, cgroups
│   ├── networking.md               ← ip, ss, curl, ssh, iptables, tcpdump
│   └── disk_storage.md             ← fdisk, lvm, mount, raid
├── scripting/                      ← Bash scripting deep dive
│   ├── bash_basics.md              ← variables, conditions, loops, functions
│   ├── bash_advanced.md            ← arrays, regex, getopts, traps
│   └── script_patterns.md         ← templates, best practices, CI/CD
├── admin/                          ← System administration
│   ├── systemd.md                  ← units, timers, targets, journald
│   ├── security_hardening.md       ← SSH config, firewall, fail2ban, SELinux
│   ├── performance_tuning.md       ← kernel params, sysctl, profiling
│   └── backup_recovery.md         ← rsync, tar, LVM snapshots
└── containers/                     ← Container-related Linux
    ├── namespaces_cgroups.md       ← kernel primitives cho containers
    └── docker_internals.md         ← cách Docker dùng Linux features
```

---

## Mục lục đã hoàn thành ✅

### Nền tảng Linux
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Linux Overview – kernel, boot process, distributions, architecture | linux_knowledge.md | ✅ |
| 2 | File System Hierarchy (FHS) – /etc, /var, /proc, /sys, inodes, hard/symlinks | linux_knowledge.md | ✅ |
| 3 | Basic Commands – navigation, file operations, redirection, pipes, wildcards | linux_knowledge.md | ✅ |
| 4 | Permissions & Ownership – chmod (octal/symbolic), chown, umask, SUID/SGID/Sticky | linux_knowledge.md | ✅ |
| 5 | Process Management – ps, top, kill, signals, job control, nice, /proc | linux_knowledge.md | ✅ |
| 6 | Text Processing – grep, sed, awk, cut, sort, uniq, wc, tr, xargs | linux_knowledge.md | ✅ |
| 7 | Networking Commands – ip, ss, curl, wget, scp, rsync, ssh, ufw | linux_knowledge.md | ✅ |
| 8 | Package Management – apt, dnf/yum, snap, build from source | linux_knowledge.md | ✅ |
| 9 | Shell Scripting – variables, conditionals, loops, functions, error handling | linux_knowledge.md | ✅ |
| 10 | System Administration – systemd, journalctl, cron, disk management, monitoring | linux_knowledge.md | ✅ |

---

## Chủ đề đã hoàn thành ✅

### Commands Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 11.1 | File Management Advanced – find (exec, xargs), locate/updatedb, inotify, lsof, fuser | commands/file_management.md | ✅ |
| 11.2 | Text Processing Advanced – regex deep dive, awk one-liners, sed chaining, jq (JSON) | commands/text_processing.md | ✅ |
| 11.3 | Process & Resource Management – cgroups v2, namespaces, ulimit, strace, ltrace | commands/process_management.md | ✅ |
| 11.4 | Networking Deep Dive – tcpdump, iptables/nftables, netfilter, conntrack, VPN basics | commands/networking.md | ✅ |
| 11.5 | Disk & Storage – LVM (PV/VG/LV), RAID levels, NFS/CIFS mount, ZFS basics | commands/disk_storage.md | ✅ |

### Bash Scripting Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 12.1 | Bash Basics – variable types, string ops, arrays, math, here-docs | scripting/bash_basics.md | ✅ |
| 12.2 | Bash Advanced – process substitution, subshell, coprocess, regex matching, getopts | scripting/bash_advanced.md | ✅ |
| 12.3 | Script Patterns – idempotent scripts, locking, logging, CI/CD integration, testing | scripting/script_patterns.md | ✅ |

### System Administration Deep Dive
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | systemd Deep Dive – unit types, dependencies, targets, socket activation, timers | admin/systemd.md | ✅ |
| 13.2 | Security Hardening – SSH hardening, fail2ban, firewall rules, SELinux/AppArmor basics | admin/security_hardening.md | ✅ |
| 13.3 | Performance Tuning – CPU/memory/network/disk tuning, sysctl, profiling tools | admin/performance_tuning.md | ✅ |
| 13.4 | Backup & Recovery – rsync strategies, LVM snapshots, disaster recovery | admin/backup_recovery.md | ✅ |

### Container Internals (Linux layer)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | Namespaces & cgroups – PID/net/mnt/uts/user/ipc namespaces, cgroups v2 resource limits | containers/namespaces_cgroups.md | ✅ |
| 14.2 | Docker Internals – overlay fs, veth pairs, iptables NAT, seccomp, capabilities | containers/docker_internals.md | ✅ |

---

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có file deep dive
- 🔄 Đang làm
- ⬜ Chưa làm

---

*Cập nhật lần cuối: 2026-05-09 – Hoàn thành toàn bộ 14 topics Linux deep dive*
