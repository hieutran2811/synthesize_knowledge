# Tổng Hợp Kiến Thức Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Linux Overview

### What – Linux là gì?
Linux là **nhân hệ điều hành (kernel)** mã nguồn mở, do Linus Torvalds tạo ra năm 1991. Trong thực tế, "Linux" thường chỉ toàn bộ hệ điều hành gồm **Linux kernel + GNU tools + userspace utilities** (chính xác: GNU/Linux).

### How – Đặc điểm
- **Open Source**: Mã nguồn công khai, cộng đồng đông đảo
- **Multi-user / Multi-tasking**: Nhiều user/process chạy đồng thời
- **Unix-like**: Tuân theo triết lý POSIX
- **Everything is a file**: File thông thường, device, socket, pipe đều là file
- **Monolithic kernel với loadable modules**: Core kernel cộng với module có thể load/unload
- **Security**: Permission model (owner/group/others), SELinux, capabilities

### How – Hoạt động (Boot Process)
```
BIOS/UEFI
    ↓ POST (Power-On Self Test)
Bootloader (GRUB2)
    ↓ load kernel image
Linux Kernel
    ↓ init RAM filesystem (initramfs)
    ↓ mount root filesystem
init/systemd (PID 1)
    ↓ start services, mount filesystems
Login Prompt / GUI
```

### Why – Tại sao dùng Linux?
- **Server dominance**: >96% web servers chạy Linux
- **Cost**: Miễn phí, không license fee
- **Stability & Security**: Uptime năm, bảo mật tốt
- **Performance**: Ít overhead, tùy chỉnh kernel
- **DevOps/Cloud**: Docker, Kubernetes, AWS/GCP/Azure đều Linux-based

### Components – Kiến trúc

```
User Space
├── Applications (web browser, IDE...)
├── Shell (bash, zsh, fish)
├── C Library (glibc)
└── System Utilities (ls, grep, systemd...)

Kernel Space
├── System Call Interface
├── Process Management
├── Memory Management
├── File System (VFS)
├── Network Stack
└── Device Drivers

Hardware
├── CPU, RAM
├── Storage (HDD, SSD, NVMe)
└── Network interfaces
```

### Compare – Linux Distributions

| Distro | Base | Package Manager | Target |
|--------|------|-----------------|--------|
| **Ubuntu** | Debian | apt | Desktop, Server, Cloud |
| **CentOS/RHEL** | Red Hat | yum/dnf | Enterprise Server |
| **Debian** | - | apt | Stable servers |
| **Arch Linux** | - | pacman | Advanced users |
| **Alpine** | - | apk | Containers (tiny image ~5MB) |
| **Amazon Linux** | RHEL-based | yum/dnf | AWS EC2 |

### Trade-offs
- (+) Free, secure, flexible, powerful CLI, dominant in cloud
- (-) Steeper learning curve, driver support (desktop), fragmented ecosystem (nhiều distros)

### Real-world Usage
- **Servers**: 96%+ web servers (Nginx, Apache trên Ubuntu/RHEL)
- **Containers**: Docker images đều Linux-based; Alpine phổ biến vì nhỏ
- **Cloud**: EC2, GKE nodes, Azure VMs đều dùng Linux
- **DevOps tools**: Jenkins, Ansible, Terraform cần Linux environment

### Ghi chú – Chủ đề tiếp theo
> Filesystem Hierarchy Standard (FHS), File types, Inodes, Permissions model

---

## 2. File System Hierarchy (FHS)

### What – FHS là gì?
**Filesystem Hierarchy Standard** định nghĩa cấu trúc thư mục chuẩn trong Linux/Unix. Mọi thứ bắt đầu từ **root `/`** – một cây duy nhất bất kể số lượng physical drive.

### How – Cấu trúc thư mục

```
/
├── bin/        → Essential user binaries (ls, cat, cp) – link đến /usr/bin trên modern distros
├── sbin/       → System binaries (fdisk, ifconfig) – dùng bởi root
├── etc/        → Configuration files (/etc/nginx/nginx.conf, /etc/passwd)
├── home/       → User home directories (/home/alice, /home/bob)
├── root/       → Home directory của root user
├── var/        → Variable data: logs (/var/log), databases, mail, caches
├── tmp/        → Temporary files – xóa khi reboot
├── usr/        → User programs (secondary hierarchy)
│   ├── bin/    → Non-essential user binaries (gcc, python3)
│   ├── sbin/   → Non-essential system binaries
│   ├── lib/    → Libraries
│   └── share/  → Architecture-independent data, man pages
├── lib/        → Essential shared libraries (glibc)
├── dev/        → Device files (/dev/sda, /dev/null, /dev/random)
├── proc/       → Virtual FS: process & kernel info (/proc/cpuinfo, /proc/meminfo)
├── sys/        → Virtual FS: kernel/driver info (sysfs)
├── mnt/        → Temporary mount points
├── media/      → Removable media mounts (USB, CD)
├── opt/        → Optional third-party software
├── srv/        → Service data (web, FTP)
├── run/        → Runtime data (PID files, sockets) – tmpfs, mất khi reboot
└── boot/       → Boot files (vmlinuz, initrd, GRUB config)
```

### How – Inode & File Types

**Inode** lưu metadata của file (không phải tên):
```
Inode chứa: permissions, owner, group, size, timestamps (atime/mtime/ctime), block pointers
Tên file → inode mapping lưu trong directory entry
```

**File types** (ký tự đầu tiên trong `ls -l`):
```
-  Regular file
d  Directory
l  Symbolic link (symlink)
b  Block device (/dev/sda)
c  Character device (/dev/tty)
s  Socket
p  Named pipe (FIFO)
```

```bash
ls -la /dev/
# brw-rw---- 1 root disk 8, 0 /dev/sda  (block device)
# crw-rw-rw- 1 root tty  5, 0 /dev/tty  (char device)
# srwxrwxrwx 1 root root /run/docker.sock (socket)
```

### How – Hard Link vs Symbolic Link

```
Hard Link:
  file.txt ─────────────────→ Inode 1234
  hardlink.txt ──────────────→ Inode 1234  (cùng inode!)
  # Xóa file.txt, hardlink.txt vẫn truy cập được

Symbolic Link (Symlink):
  symlink.txt ─→ "/path/to/file.txt" ─→ Inode 1234
  # Xóa file.txt: symlink trở thành "dangling link"
```

```bash
ln   source.txt hardlink.txt    # hard link
ln -s source.txt symlink.txt    # symbolic link
```

### Why – Tại sao cần FHS?
- Scripts và tools biết tìm config ở `/etc`, logs ở `/var/log`
- **Separation of concerns**: read-only OS (`/usr`) vs variable data (`/var`)
- Cho phép mount `/home`, `/var` trên partition riêng

### Compare – /proc vs /sys

| | /proc | /sys |
|--|-------|------|
| Mục đích | Process info + kernel params | Kernel/driver/hardware info |
| Ví dụ | /proc/cpuinfo, /proc/meminfo | /sys/class/net, /sys/block |
| Writable? | Một số (sysctl via /proc/sys) | Nhiều entries (tuning) |

### Real-world Usage
```bash
# Xem CPU info
cat /proc/cpuinfo | grep "model name" | head -1

# Xem memory
cat /proc/meminfo | grep -E "MemTotal|MemAvailable"

# Xem disk I/O stats
cat /proc/diskstats

# Tuning kernel parameter (sysctl)
echo "net.core.somaxconn=65535" >> /etc/sysctl.conf
sysctl -p
```

### Ghi chú – Chủ đề tiếp theo
> Permissions model (chmod/chown/umask), ACL, Capabilities, File attributes

---

## 3. Basic Commands – Navigation & File Management

### What – Shell là gì?
**Shell** là command-line interpreter, nhận lệnh từ user và giao tiếp với kernel qua **system calls**. Phổ biến: `bash` (Bourne Again Shell), `zsh`, `sh`.

### How – Navigation Commands

```bash
# Xem thư mục hiện tại
pwd                          # /home/user/projects

# List files
ls                           # tên file
ls -l                        # long format (permissions, owner, size, date)
ls -la                       # bao gồm hidden files (.)
ls -lh                       # human-readable sizes (KB, MB)
ls -lt                       # sort by modification time

# Chuyển thư mục
cd /etc                      # absolute path
cd ~/projects                # ~ = home directory
cd ..                        # parent directory
cd -                         # previous directory (toggle)
cd                           # về home directory

# Xem cấu trúc thư mục
tree /etc/nginx -L 2         # depth 2
find . -type d               # list tất cả subdirectories
```

### How – File Operations

```bash
# Tạo
touch file.txt               # tạo file rỗng / cập nhật timestamp
mkdir dir1                   # tạo directory
mkdir -p a/b/c               # tạo nested directories
mkdir -p project/{src,test,docs}  # brace expansion

# Copy
cp source.txt dest.txt       # copy file
cp -r source/ dest/          # copy directory (recursive)
cp -p file.txt backup.txt    # preserve permissions/timestamps
cp -a source/ dest/          # archive mode (preserve everything)

# Move / Rename
mv old.txt new.txt           # rename
mv file.txt /tmp/            # move to directory
mv -i old.txt new.txt        # interactive (hỏi trước khi ghi đè)

# Delete
rm file.txt                  # xóa file
rm -r directory/             # xóa directory recursive
rm -rf directory/            # force (không hỏi) – NGUY HIỂM!
rm -i file.txt               # interactive (hỏi trước khi xóa)

# Xem nội dung
cat file.txt                 # toàn bộ nội dung
cat -n file.txt              # kèm line numbers
less file.txt                # pager (scroll, search với /)
head -n 20 file.txt          # 20 dòng đầu
tail -n 20 file.txt          # 20 dòng cuối
tail -f /var/log/app.log     # follow (real-time)
```

### How – Wildcards & Globbing

```bash
ls *.txt                     # tất cả .txt files
ls log-[0-9][0-9].txt        # log-01.txt, log-23.txt...
ls {*.txt,*.log}             # .txt và .log files
rm -rf temp*                 # xóa tất cả bắt đầu bằng "temp"
cp /var/log/*.log /backup/   # copy tất cả .log files
```

### How – Redirection & Pipes

```bash
# Output redirection
echo "hello" > file.txt      # ghi đè (overwrite)
echo "world" >> file.txt     # append
ls -la 2> error.log          # redirect stderr
ls -la > out.log 2>&1        # redirect cả stdout và stderr
ls -la &> combined.log       # bash shorthand cho 2>&1

# Input redirection
mysql < schema.sql           # đọc input từ file
sort < unsorted.txt > sorted.txt

# Pipes (stdout → stdin)
ls -la | grep ".txt"         # lọc output của ls
cat access.log | grep "ERROR" | wc -l  # đếm dòng lỗi
ps aux | grep nginx | grep -v grep    # tìm nginx process
```

### How – Special Files & Devices

```bash
/dev/null    # "black hole" – discard output
/dev/zero    # nguồn byte 0 vô tận
/dev/random  # random bytes (blocking)
/dev/urandom # random bytes (non-blocking, cryptographically secure)

# Ví dụ
command > /dev/null 2>&1    # chạy lặng lẽ, bỏ qua mọi output
dd if=/dev/zero of=1GB.img bs=1M count=1024  # tạo file 1GB
openssl rand -base64 32     # generate random password
```

### Why – Philosophy "Unix Way"
> "Do one thing and do it well" – mỗi tool làm 1 việc, kết hợp qua pipes.

```bash
# Ví dụ: đếm top 10 IP access nhiều nhất trong log
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
```

### Real-world Usage
```bash
# Deploy script cleanup
rm -rf /opt/app/old_release/
cp -a /opt/app/new_release/ /opt/app/current/

# Backup với timestamp
cp -r /etc /backup/etc_$(date +%Y%m%d_%H%M%S)

# Real-time log monitoring
tail -f /var/log/nginx/access.log | grep --line-buffered "500"

# Disk usage check
du -sh /var/log/* | sort -rh | head -10
```

### Ghi chú – Chủ đề tiếp theo
> File permissions (rwx, octal), chmod, chown, umask, SUID/SGID/Sticky bit

---

## 4. Permissions & Ownership

### What – Permission Model là gì?
Linux dùng **Discretionary Access Control (DAC)**: mỗi file/directory có **owner**, **group**, và **permission bits** kiểm soát ai được đọc/ghi/thực thi.

### How – Permission Format

```
-rwxr-xr--  1  alice  developers  4096  Jan 15 10:30  script.sh
│└──┴──┴──  │   │        │         │                   │
│ u  g  o   │  owner   group      size                 name
│           │
│           link count
│
file type (- = regular, d = dir, l = symlink...)
```

**Permissions:**
| Symbol | Octal | File | Directory |
|--------|-------|------|-----------|
| `r` | 4 | Đọc nội dung | List files (ls) |
| `w` | 2 | Ghi/sửa nội dung | Tạo/xóa files bên trong |
| `x` | 1 | Thực thi | Truy cập (cd) + thực thi trong đó |

### How – chmod

```bash
# Symbolic mode
chmod u+x script.sh          # thêm execute cho owner
chmod g-w file.txt           # bỏ write cho group
chmod o=r file.txt           # set others chỉ read
chmod a+r file.txt           # a = all (u+g+o)
chmod u+x,g+r,o-rwx file.sh  # nhiều thay đổi cùng lúc

# Octal mode
chmod 755 script.sh          # rwxr-xr-x (owner=7, group=5, others=5)
chmod 644 config.txt         # rw-r--r-- (owner=6, group=4, others=4)
chmod 600 ~/.ssh/id_rsa      # rw------- (private key, chỉ owner đọc)
chmod 777 /tmp/shared/       # rwxrwxrwx – TRÁNH dùng

# Recursive
chmod -R 755 /var/www/html/

# Common patterns
# 755: web content (server đọc được), scripts chạy được
# 644: config files, web pages
# 600: private keys, sensitive configs
# 700: personal scripts, home .ssh/
```

**Octal cheat sheet:**
```
7 = rwx = 4+2+1
6 = rw- = 4+2
5 = r-x = 4+1
4 = r-- = 4
0 = ---
```

### How – chown & chgrp

```bash
# Thay đổi owner
chown alice file.txt
chown alice:developers file.txt  # owner:group
chown :developers file.txt       # chỉ group

# Recursive
chown -R www-data:www-data /var/www/html/
chown -R alice:alice /home/alice/

# Thay đổi group
chgrp developers project/
```

### How – umask

**umask** là mask mặc định áp dụng khi tạo file/directory mới.
```bash
umask            # xem umask hiện tại (thường 022)

# Cách tính: base permissions - umask
# File: 666 - 022 = 644 (rw-r--r--)
# Dir:  777 - 022 = 755 (rwxr-xr-x)

umask 027        # group: không write; others: không gì
# File: 666 - 027 = 640 (rw-r-----)
# Dir:  777 - 027 = 750 (rwxr-x---)

# Set permanently trong ~/.bashrc hoặc /etc/profile
```

### How – Special Permissions (SUID, SGID, Sticky Bit)

```bash
# SUID (Set User ID) - bit 4 trên octal / s trong user execute
# Khi thực thi: chạy với quyền của owner (không phải caller)
chmod u+s /usr/bin/passwd    # passwd chạy với quyền root để đổi /etc/shadow
ls -la /usr/bin/passwd
# -rwsr-xr-x root root /usr/bin/passwd  (s trong user position)

# SGID (Set Group ID) - bit 2 / s trong group execute
# Directory: files tạo ra kế thừa group của directory
chmod g+s /var/www/html/
# -rwxr-sr-x (s trong group position)

# Sticky Bit - bit 1 / t trong others execute
# Directory: chỉ owner của file mới xóa được file đó
chmod +t /tmp/
ls -la / | grep tmp
# drwxrwxrwt root root /tmp (t = sticky bit)

# Octal combined
chmod 4755 /usr/bin/myapp  # SUID + 755
chmod 2755 /var/shared/    # SGID + 755
chmod 1777 /tmp/           # Sticky + 777
```

### How – sudo & su

```bash
# sudo: chạy lệnh với quyền user khác (thường root)
sudo apt update              # chạy với quyền root
sudo -u www-data nginx -t   # chạy với quyền www-data
sudo -i                      # interactive root shell (đọc root's .bashrc)
sudo su -                    # switch sang root login shell

# su: switch user
su - alice                   # switch sang alice (login shell)
su -c "command" alice        # chạy 1 lệnh với quyền alice

# /etc/sudoers (edit bằng visudo)
alice ALL=(ALL:ALL) ALL                    # alice full sudo
alice ALL=(ALL:ALL) NOPASSWD: /bin/systemctl restart nginx  # không cần password
%developers ALL=(ALL) /usr/bin/docker     # group developers dùng docker
```

### Compare – DAC vs MAC vs RBAC

| | DAC (Linux default) | MAC (SELinux/AppArmor) | RBAC |
|--|--------------------|-----------------------|------|
| Mô hình | Owner tự set permissions | Policy trung tâm | Role-based |
| Flexibility | Cao | Thấp (strict policy) | Trung bình |
| Security | Tốt | Rất tốt | Tốt |
| Complexity | Thấp | Cao | Trung bình |
| Ví dụ | chmod/chown | RHEL (SELinux enforcing) | Cloud IAM |

### Trade-offs
- SUID/SGID: tiện nhưng là attack vector (privilege escalation); kiểm tra thường xuyên
- Sticky bit trên `/tmp`: bảo vệ multi-user nhưng không phòng được root
- chmod 777: KHÔNG BAO GIỜ dùng trên production

### Real-world Usage
```bash
# Web server files
chown -R www-data:www-data /var/www/html/
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

# SSH private key – phải 600, nếu không SSH từ chối
chmod 600 ~/.ssh/id_rsa
chmod 700 ~/.ssh/

# Audit SUID/SGID binaries (security check)
find / -perm /4000 -type f 2>/dev/null  # tất cả SUID files
find / -perm /2000 -type f 2>/dev/null  # tất cả SGID files
```

### Ghi chú – Chủ đề tiếp theo
> Process management (ps, top, kill, nice, nohup), Job control, Process states

---

## 5. Process Management

### What – Process là gì?
**Process** là instance của chương trình đang chạy. Mỗi process có **PID (Process ID)**, không gian bộ nhớ riêng, file descriptors, và được quản lý bởi kernel.

### How – Process Hierarchy

```
systemd (PID 1)
├── sshd (PID 234)
│   └── bash (PID 456) ← SSH session
│       └── vim (PID 789)
├── nginx (PID 1001)
│   ├── nginx worker (PID 1002)
│   └── nginx worker (PID 1003)
└── cron (PID 2001)
    └── backup.sh (PID 3456)
```

### How – Process States

```
R  Running / Runnable (on CPU or ready queue)
S  Sleeping (interruptible) – chờ event/I/O
D  Sleeping (uninterruptible) – chờ I/O không thể interrupt (disk I/O)
Z  Zombie – đã kết thúc nhưng parent chưa wait()
T  Stopped (Ctrl+Z hoặc SIGSTOP)
I  Idle kernel thread
```

### How – Xem Processes

```bash
# ps – snapshot
ps aux                       # tất cả processes, format user
  # USER  PID %CPU %MEM VSZ RSS  TTY  STAT  START  TIME  COMMAND
ps -ef                       # POSIX format (PPID hiển thị)
ps aux | grep nginx
ps -p 1234 -o pid,ppid,cmd   # custom output format

# top – real-time interactive
top                          # default
top -u alice                 # chỉ processes của alice
top -p 1234                  # monitor 1 PID cụ thể
# Trong top: q=quit, k=kill, r=renice, 1=show CPUs, M=sort by memory

# htop – enhanced top (cần cài)
htop                         # colorful, F9=kill, F6=sort

# pstree – process tree
pstree                       # cây process
pstree -p                    # kèm PID
pstree alice                 # processes của alice

# pgrep – tìm PID theo tên
pgrep nginx                  # PID của nginx
pgrep -l nginx               # PID + tên
pgrep -a nginx               # PID + full command
```

### How – Signals & kill

```bash
# kill – gửi signal đến process
kill 1234                    # gửi SIGTERM (15) – yêu cầu kết thúc lịch sự
kill -9 1234                 # gửi SIGKILL – force kill (không thể ignore)
kill -STOP 1234              # pause process
kill -CONT 1234              # resume process

# killall – kill theo tên
killall nginx
killall -9 java

# pkill – kill theo pattern
pkill -f "python app.py"     # match full command line
pkill -u alice               # kill tất cả processes của user alice

# Common signals
# SIGHUP  (1)  – reload config (không kill)
# SIGINT  (2)  – Ctrl+C
# SIGQUIT (3)  – Ctrl+\
# SIGKILL (9)  – force kill (không thể catch/ignore)
# SIGTERM (15) – graceful terminate (default)
# SIGSTOP (19) – pause (không thể catch)
# SIGCONT (18) – continue
# SIGUSR1 (10) – user-defined (nginx dùng để reopen logs)
```

### How – Job Control

```bash
# Chạy background
command &                    # chạy background ngay lập tức
long_process &

# Ctrl+Z – suspend foreground job
# jobs – list background/stopped jobs
jobs                         # [1]+ Stopped  vim file.txt
                             # [2]- Running  ./build.sh &

# fg – bring to foreground
fg                           # job gần nhất
fg %1                        # job số 1

# bg – continue stopped job in background
bg %1

# nohup – chạy không bị kill khi logout
nohup ./server.sh &          # output vào nohup.out
nohup ./server.sh > server.log 2>&1 &

# disown – detach job khỏi terminal
./server.sh &
disown %1                    # terminal có thể đóng, process vẫn chạy
```

### How – Process Priority (nice)

```bash
# nice value: -20 (highest priority) → 19 (lowest)
# Mặc định: 0

nice -n 10 ./backup.sh       # chạy với nice=10 (low priority)
nice -n -5 ./critical.sh     # nice=-5 (cao hơn default, cần sudo)

# renice – đổi priority process đang chạy
renice -n 15 -p 1234         # hạ priority process 1234
renice -n 5 -u alice         # đổi tất cả process của alice

# Kiểm tra nice value
ps -o pid,ni,cmd 1234
top → NI column
```

### How – System Resources

```bash
# Memory usage
free -h                      # RAM và Swap
cat /proc/meminfo            # chi tiết

# CPU info
nproc                        # số CPUs
lscpu                        # CPU architecture info
mpstat 1                     # per-CPU stats mỗi giây

# Disk I/O
iostat -x 1                  # I/O stats mỗi giây
iotop                        # top cho disk I/O (cần cài)

# System load
uptime                       # load average 1/5/15 phút
# Load average: số process chờ CPU + đang dùng CPU
# Load avg < nCPUs: ổn; > nCPUs: quá tải
```

### Compare – kill -9 vs kill -15

| | SIGTERM (-15) | SIGKILL (-9) |
|--|--------------|-------------|
| Có thể catch? | Có | Không |
| Process cleanup | Graceful (đóng file, flush buffer) | Ngay lập tức |
| Zombie risk | Thấp hơn | Có thể để lại zombie |
| Khi dùng | Luôn thử trước | Chỉ khi SIGTERM không đủ |

### Trade-offs
- SIGKILL: nhanh nhưng có thể để lại data corruption, temp files, locks
- Background jobs bằng `nohup &`: đơn giản nhưng không có process management; dùng `systemd` hoặc `supervisor` cho production

### Real-world Usage
```bash
# Graceful nginx reload (không drop connections)
kill -HUP $(cat /var/run/nginx.pid)
# hoặc
nginx -s reload

# Monitor Java app memory
ps aux | grep java | awk '{print $1, $2, $4, $11}'

# Kill zombie processes (kill parent hoặc wait)
ps -A -o stat,ppid,pid,cmd | grep -e '^[Zz]'
kill -CHLD <parent_pid>

# Limit process resources
ulimit -v 1048576            # limit virtual memory 1GB
ulimit -n 65536              # limit open file descriptors
```

### Ghi chú – Chủ đề tiếp theo
> Text processing (grep, sed, awk, cut, sort, uniq), Regular expressions

---

## 6. Text Processing

### What – Text Processing là gì?
Linux cung cấp bộ công cụ mạnh mẽ để xử lý text trên command line: **grep** (tìm kiếm), **sed** (stream editor), **awk** (pattern scanning & processing), và các utilities khác.

### How – grep

```bash
# Cú pháp: grep [OPTIONS] PATTERN [FILE]
grep "error" /var/log/app.log         # case-sensitive
grep -i "error" app.log               # case-insensitive
grep -n "error" app.log               # kèm line number
grep -c "error" app.log               # đếm dòng khớp
grep -v "debug" app.log               # invert (dòng KHÔNG khớp)
grep -r "TODO" /src/                  # recursive search
grep -l "error" /var/log/*.log        # chỉ hiện tên file
grep -w "cat" file.txt                # whole word (không match "catalog")
grep -A 3 "ERROR" app.log            # 3 dòng sau match
grep -B 2 "ERROR" app.log            # 2 dòng trước match
grep -C 2 "ERROR" app.log            # 2 dòng trước + sau

# Extended regex
grep -E "error|warning|critical" app.log   # regex OR
grep -E "^[0-9]{4}-[0-9]{2}" app.log      # dòng bắt đầu bằng date

# Perl regex
grep -P "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" access.log  # IP addresses

# Binary check
grep -a "text" binary.file            # treat binary as text
```

### How – sed (Stream Editor)

```bash
# Cú pháp: sed [OPTIONS] 'command' [FILE]

# Substitution (s/pattern/replacement/flags)
sed 's/foo/bar/'  file.txt           # thay lần xuất hiện đầu tiên mỗi dòng
sed 's/foo/bar/g' file.txt           # global (tất cả trên mỗi dòng)
sed 's/foo/bar/gi' file.txt          # global + case-insensitive
sed -i 's/foo/bar/g' file.txt        # in-place (sửa trực tiếp file)
sed -i.bak 's/foo/bar/g' file.txt    # in-place với backup

# Xóa dòng
sed '/pattern/d' file.txt            # xóa dòng chứa pattern
sed '/^$/d' file.txt                 # xóa dòng trống
sed '5d' file.txt                    # xóa dòng 5
sed '5,10d' file.txt                 # xóa dòng 5-10

# In/hiển thị
sed -n '5,10p' file.txt              # chỉ in dòng 5-10
sed -n '/start/,/end/p' file.txt     # in từ "start" đến "end"

# Thêm dòng
sed '3a\New line after line 3' file.txt  # append after line 3
sed '3i\New line before line 3' file.txt # insert before line 3

# Thực tế
# Sửa config không cần mở editor
sed -i 's/^#MaxAuthTries 6/MaxAuthTries 3/' /etc/ssh/sshd_config

# Xóa comment và dòng trống
sed -e '/^#/d' -e '/^$/d' config.txt
```

### How – awk

```bash
# Cú pháp: awk 'pattern { action }' file
# Mặc định: $0 = toàn dòng, $1 $2 ... = fields (phân tách bởi whitespace)

# In field cụ thể
awk '{print $1}' access.log          # in cột 1 (IP address)
awk '{print $1, $7}' access.log      # in cột 1 và 7
awk '{print NR, $0}' file.txt        # kèm line number (NR)

# Custom delimiter
awk -F: '{print $1}' /etc/passwd     # user names (delimiter=:)
awk -F',' '{print $2}' data.csv      # CSV cột 2

# Pattern matching
awk '/ERROR/ {print}' app.log        # dòng chứa ERROR
awk '$3 > 500 {print $1, $3}' access.log   # status code > 500

# Tính toán
awk '{sum += $5} END {print "Total:", sum}' data.txt
awk 'BEGIN {count=0} /error/ {count++} END {print count}' app.log

# Conditional
awk '{if ($7 >= 400) print $1, $7, $9}' access.log

# Thực tế: parse log
# Đếm request theo status code
awk '{print $9}' access.log | sort | uniq -c | sort -rn

# Tính average response time
awk '{sum+=$10; count++} END {print "Avg:", sum/count "ms"}' access.log

# Top 10 IP
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
```

### How – Other Text Tools

```bash
# cut – cắt cột từ text
cut -d: -f1,3 /etc/passwd            # field 1 và 3, delimiter ":"
cut -c1-10 file.txt                  # 10 ký tự đầu mỗi dòng

# sort – sắp xếp
sort file.txt                        # alphabetical
sort -n numbers.txt                  # numeric sort
sort -rn numbers.txt                 # reverse numeric
sort -k2 -t: /etc/passwd             # sort theo field 2, delimiter ":"
sort -u file.txt                     # unique (bỏ trùng)

# uniq – loại bỏ trùng lặp (cần sort trước)
sort file.txt | uniq                 # loại dòng trùng
sort file.txt | uniq -c              # kèm count
sort file.txt | uniq -d              # chỉ hiện dòng trùng
sort file.txt | uniq -u              # chỉ hiện dòng unique

# wc – đếm
wc -l file.txt                       # số dòng
wc -w file.txt                       # số từ
wc -c file.txt                       # số bytes
ls /var/log/ | wc -l                 # đếm số files

# tr – translate / delete characters
echo "Hello World" | tr 'a-z' 'A-Z' # uppercase
echo "hello world" | tr -d 'aeiou'  # xóa vowels
cat file.txt | tr -s ' '             # squeeze multiple spaces

# xargs – build command từ stdin
find . -name "*.tmp" | xargs rm      # xóa tất cả .tmp files
cat urls.txt | xargs -n 1 curl -O   # download từng URL
echo "1 2 3" | xargs -n 1           # in mỗi số 1 dòng
find . -name "*.java" | xargs grep "TODO"  # tìm TODO trong Java files
```

### Compare – grep vs sed vs awk

| | grep | sed | awk |
|--|------|-----|-----|
| Mục đích | Tìm kiếm/lọc | Biến đổi text | Xử lý, tính toán |
| Syntax | Pattern | s/old/new/g | { print $1 } |
| Fields | Không | Không | Có |
| Arithmetic | Không | Không | Có |
| Khi dùng | Filter dòng | Thay thế text | Parse cột, tính toán |

### Real-world Usage
```bash
# Parse Apache/Nginx access log
# Top 10 URLs với 500 errors
awk '$9 == 500 {print $7}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn | head -10

# Tìm config có thể có vấn đề
grep -rn "password" /etc/ 2>/dev/null | grep -v "^Binary"

# Sửa hàng loạt config files
find /etc/nginx/sites-enabled/ -name "*.conf" \
  -exec sed -i 's/worker_connections 768/worker_connections 1024/' {} \;

# Extract unique IPs từ log
awk '{print $1}' /var/log/nginx/access.log | sort -u

# Monitor log real-time với filter
tail -f /var/log/app.log | grep --line-buffered "ERROR\|CRITICAL"
```

### Ghi chú – Chủ đề tiếp theo
> Networking commands (ip, ss, netstat, curl, wget, ssh, scp, rsync)

---

## 7. Networking Commands

### What – Networking Tools
Linux cung cấp đầy đủ tools để quản lý mạng: cấu hình interfaces, kiểm tra kết nối, transfer files, port scanning, packet capture.

### How – Network Configuration

```bash
# ip – modern replacement cho ifconfig/route (iproute2)
ip addr show                         # xem tất cả interfaces và IPs
ip addr show eth0                    # xem interface cụ thể
ip addr add 192.168.1.10/24 dev eth0 # gán IP (tạm thời)
ip addr del 192.168.1.10/24 dev eth0 # xóa IP

ip link show                         # xem trạng thái interfaces
ip link set eth0 up                  # bật interface
ip link set eth0 down                # tắt interface

ip route show                        # xem routing table
ip route add default via 192.168.1.1 # thêm default gateway
ip route add 10.0.0.0/8 via 10.0.0.1 dev eth1  # add specific route

# ifconfig – legacy (deprecated, nhưng còn phổ biến)
ifconfig                             # tất cả interfaces
ifconfig eth0                        # interface cụ thể
ifconfig eth0 192.168.1.10 netmask 255.255.255.0
```

### How – Connectivity Testing

```bash
# ping – kiểm tra kết nối (ICMP)
ping google.com                      # ping mãi
ping -c 4 8.8.8.8                   # ping 4 lần
ping -i 0.5 host                    # interval 0.5s
ping6 ::1                           # IPv6

# traceroute / tracepath – route đến host
traceroute google.com               # đường đi qua các hops
tracepath google.com                # không cần root
mtr google.com                      # ping + traceroute real-time (cần cài)

# dig / nslookup – DNS lookup
dig google.com                      # full DNS info
dig google.com A                    # chỉ A record
dig google.com MX                   # MX records
dig @8.8.8.8 google.com            # dùng DNS server cụ thể
dig -x 8.8.8.8                      # reverse DNS lookup
nslookup google.com                 # interactive DNS
host google.com                     # đơn giản hơn

# telnet / nc – test port connectivity
telnet host 80                      # test TCP port 80
nc -zv host 80                      # test port (không kết nối)
nc -zv host 80-90                   # test range of ports
nc -l 8080                          # listen on port 8080 (server mode)
```

### How – Port & Socket Information

```bash
# ss – modern replacement cho netstat
ss -tlnp                            # TCP listening ports + process
  # -t = TCP, -u = UDP, -l = listening, -n = numeric, -p = process
ss -tulnp                           # TCP + UDP listening
ss -tnp                             # tất cả TCP connections + process
ss -s                               # statistics summary

# netstat – legacy
netstat -tlnp                       # TCP listening
netstat -an | grep ESTABLISHED      # established connections
netstat -i                          # interface statistics

# lsof – list open files (bao gồm network sockets)
lsof -i :80                        # process dùng port 80
lsof -i :80-443                    # range of ports
lsof -i tcp                        # tất cả TCP
lsof -u alice -i                   # network files của alice
lsof -p 1234 -i                    # network files của PID 1234
```

### How – File Transfer

```bash
# curl – HTTP client
curl https://api.example.com/data   # GET request
curl -X POST -H "Content-Type: application/json" \
     -d '{"key":"value"}' \
     https://api.example.com/submit  # POST with JSON
curl -O https://example.com/file.zip # download với tên gốc
curl -o output.txt https://url       # download với tên tùy
curl -L url                          # follow redirects
curl -u user:pass https://url        # basic auth
curl -k https://self-signed.example/ # skip SSL verification (dev)
curl -s url | jq '.'                 # pipe to jq for JSON

# wget – download
wget https://example.com/file.zip   # download
wget -r -np https://site.com/docs/ # recursive download
wget -c https://url/largefile       # resume interrupted download
wget --limit-rate=100k https://url  # throttle

# scp – secure copy (SSH)
scp file.txt user@host:/path/       # local → remote
scp user@host:/path/file.txt .      # remote → local
scp -r /local/dir user@host:/remote/ # directory
scp -P 2222 file.txt user@host:/path # custom SSH port

# rsync – efficient sync
rsync -avz /src/ user@host:/dest/   # sync với compression
rsync -avz --delete /src/ /backup/  # sync + xóa files không có ở src
rsync -avz --exclude='*.log' /src/ /dest/  # exclude logs
rsync -avzn /src/ /dest/            # dry run (preview)
rsync -e "ssh -p 2222" /src/ user@host:/dest/  # custom SSH port
```

### How – SSH

```bash
# Kết nối cơ bản
ssh user@host                       # mặc định port 22
ssh -p 2222 user@host               # custom port
ssh -i ~/.ssh/mykey.pem user@host   # specific private key
ssh -X user@host                    # X11 forwarding (GUI apps)

# SSH keys
ssh-keygen -t ed25519 -C "email"    # tạo key pair (ed25519 = modern)
ssh-keygen -t rsa -b 4096           # RSA 4096-bit (legacy compat)
ssh-copy-id user@host               # copy public key lên server
cat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys  # manual

# SSH config (~/.ssh/config)
# Host myserver
#     HostName 192.168.1.100
#     User alice
#     Port 2222
#     IdentityFile ~/.ssh/id_ed25519
#     ServerAliveInterval 60
ssh myserver                        # dùng alias

# SSH tunneling
ssh -L 8080:localhost:80 user@host  # local port forward (local:8080 → remote:80)
ssh -R 8080:localhost:80 user@host  # remote port forward
ssh -D 1080 user@host               # SOCKS proxy
ssh -N -f -L 5432:db-host:5432 jump-host  # tunnel to DB via bastion
```

### How – Firewall (iptables / ufw / firewalld)

```bash
# ufw – Uncomplicated Firewall (Ubuntu)
ufw status                          # xem trạng thái
ufw enable                          # bật firewall
ufw allow 22                        # allow SSH
ufw allow 80/tcp                    # allow HTTP
ufw deny 8080                       # deny port
ufw allow from 192.168.1.0/24 to any port 3306  # MySQL từ subnet

# firewalld (RHEL/CentOS)
firewall-cmd --list-all
firewall-cmd --add-service=http --permanent
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --reload
```

### Real-world Usage
```bash
# Kiểm tra service có đang listen không
ss -tlnp | grep :8080

# Debug HTTP service
curl -v -H "Host: myapp.com" http://localhost/health

# Tunnel đến DB qua bastion host
ssh -fN -L 5432:prod-db.internal:5432 bastion-user@bastion.example.com
psql -h localhost -p 5432 -U appuser appdb  # kết nối qua tunnel

# Monitor network traffic
tcpdump -i eth0 -n port 80          # capture HTTP traffic
tcpdump -i eth0 -w capture.pcap     # save to file
```

### Ghi chú – Chủ đề tiếp theo
> Package management (apt, yum/dnf), Shell scripting (bash variables, loops, functions)

---

## 8. Package Management

### What – Package Manager là gì?
**Package manager** tự động hóa việc cài đặt, cập nhật, cấu hình, và gỡ bỏ phần mềm. Giải quyết **dependency hell** và quản lý phần mềm nhất quán.

### How – apt (Debian/Ubuntu)

```bash
# Cập nhật package index
apt update                           # sync với repository
apt upgrade                          # upgrade tất cả packages

# Cài đặt
apt install nginx                    # cài nginx
apt install -y nginx curl wget       # cài nhiều packages, auto yes
apt install ./local-package.deb      # cài từ local .deb file

# Gỡ cài đặt
apt remove nginx                     # gỡ nhưng giữ config
apt purge nginx                      # gỡ + xóa config files
apt autoremove                       # gỡ orphan dependencies

# Tìm kiếm
apt search "text editor"             # tìm trong mô tả
apt list --installed                 # packages đã cài
apt list --upgradeable               # packages có thể upgrade
apt show nginx                       # thông tin chi tiết

# Sources
cat /etc/apt/sources.list            # repository list
add-apt-repository ppa:user/ppa      # thêm PPA (Ubuntu)
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -  # add external repo

# apt-cache (read-only queries)
apt-cache search nginx
apt-cache show nginx
apt-cache depends nginx              # dependencies
apt-cache rdepends nginx             # reverse dependencies
```

### How – yum / dnf (RHEL/CentOS/Fedora)

```bash
# dnf (modern) / yum (legacy – dùng chung nhiều lệnh)
dnf update                           # update tất cả
dnf install nginx                    # cài
dnf remove nginx                     # gỡ
dnf search nginx                     # tìm
dnf info nginx                       # thông tin
dnf list installed                   # đã cài
dnf list available                   # có thể cài
dnf autoremove                       # gỡ orphans

# Groups
dnf grouplist                        # danh sách group
dnf groupinstall "Development Tools" # cài cả group

# History
dnf history                          # lịch sử transactions
dnf history undo 15                  # rollback transaction 15

# Repositories
dnf repolist                         # list repos
dnf config-manager --add-repo URL    # thêm repo
```

### How – Snap / Flatpak

```bash
# snap (Canonical)
snap find vscode                     # tìm
snap install code --classic          # cài VS Code
snap list                            # đã cài
snap refresh code                    # cập nhật
snap remove code                     # gỡ
snap info code                       # thông tin + channels

# flatpak
flatpak install flathub org.gimp.GIMP
flatpak run org.gimp.GIMP
flatpak update
flatpak uninstall org.gimp.GIMP
```

### How – Build from Source

```bash
# Generic flow
wget https://example.com/source-1.0.tar.gz
tar -xzf source-1.0.tar.gz
cd source-1.0/

./configure --prefix=/usr/local      # kiểm tra dependencies, generate Makefile
make -j$(nproc)                     # compile (parallel jobs)
sudo make install                   # cài vào system

# Uninstall
sudo make uninstall                 # nếu Makefile hỗ trợ
# hoặc
xargs rm < install_manifest.txt     # nếu có manifest
```

### Compare – apt vs dnf vs snap

| | apt | dnf/yum | snap |
|--|-----|---------|------|
| Distro | Debian/Ubuntu | RHEL/CentOS/Fedora | Cross-distro |
| Package format | .deb | .rpm | .snap |
| Sandbox | Không | Không | Có (Snap confinement) |
| Auto-update | Không (default) | Không | Có (background) |
| Repo type | Centralized | Centralized | Snap Store |

### Trade-offs
- Snap/Flatpak: portable nhưng lớn hơn, startup chậm hơn
- Build from source: mới nhất nhưng không có dependency management
- PPA/external repos: cần trust, tiềm ẩn security risk

### Real-world Usage
```bash
# Server setup script (Ubuntu)
apt update && apt upgrade -y
apt install -y \
    nginx \
    postgresql \
    redis-server \
    certbot \
    fail2ban \
    ufw

# Pin package version (tránh auto upgrade)
apt-mark hold nginx
apt-mark unhold nginx

# Security updates only
unattended-upgrades --dry-run
dpkg-reconfigure --priority=low unattended-upgrades
```

### Ghi chú – Chủ đề tiếp theo
> System administration (systemd, journalctl, cron, disk management, monitoring)

---

## 9. Shell Scripting – Bash

### What – Shell Script là gì?
**Shell script** là file text chứa các lệnh shell thực thi tuần tự, cho phép tự động hóa tasks, cấu hình hệ thống, deployment pipelines.

### How – Cơ bản

```bash
#!/bin/bash
# Shebang: chỉ định interpreter

# Biến
NAME="Alice"
echo "Hello, $NAME"
echo "Hello, ${NAME}World"           # dùng {} khi nối chuỗi

# Command substitution
DATE=$(date +%Y-%m-%d)
FILES=$(ls -la | wc -l)
echo "Today: $DATE, Files: $FILES"

# Arithmetic
NUM=$((10 + 5))
echo $((2 ** 10))                    # 1024
let "x = 5 * 3"

# Special variables
$0   # tên script
$1 $2 ... $9   # positional arguments
$#   # số arguments
$@   # tất cả arguments (như array)
$?   # exit code của lệnh vừa chạy (0 = success)
$$   # PID của script hiện tại
$!   # PID của background process vừa chạy
```

### How – Conditionals

```bash
# if-elif-else
if [ $1 -gt 10 ]; then
    echo "Greater than 10"
elif [ $1 -eq 10 ]; then
    echo "Equal to 10"
else
    echo "Less than 10"
fi

# [[ ]] – extended test (bash-specific, preferred)
if [[ "$NAME" == "Alice" ]]; then echo "Hi Alice"; fi
if [[ "$NAME" =~ ^A ]]; then echo "Starts with A"; fi  # regex

# File tests
if [[ -f /etc/nginx/nginx.conf ]]; then
    echo "File exists"
fi
# -f: regular file   -d: directory   -e: exists   -r: readable
# -w: writable       -x: executable  -s: non-empty

# String tests
[[ -z "$VAR" ]]      # empty string
[[ -n "$VAR" ]]      # non-empty string
[[ "$A" == "$B" ]]   # string equal

# Numeric tests (cần số, không dùng cho string)
[[ $A -eq $B ]]      # equal
[[ $A -ne $B ]]      # not equal
[[ $A -lt $B ]]      # less than
[[ $A -gt $B ]]      # greater than

# Logic
[[ -f file && -r file ]]  # AND
[[ -z "$A" || -z "$B" ]]  # OR
[[ ! -d dir ]]             # NOT
```

### How – Loops

```bash
# for loop
for i in 1 2 3 4 5; do
    echo "Number: $i"
done

for file in /var/log/*.log; do
    echo "Processing: $file"
    gzip "$file"
done

# C-style for
for ((i=0; i<10; i++)); do
    echo $i
done

# while loop
COUNT=0
while [[ $COUNT -lt 5 ]]; do
    echo "Count: $COUNT"
    ((COUNT++))
done

# Read file line by line
while IFS= read -r line; do
    echo "Line: $line"
done < input.txt

# until loop (ngược lại while)
until [[ $COUNT -ge 5 ]]; do
    ((COUNT++))
done

# break and continue
for i in {1..10}; do
    [[ $i -eq 5 ]] && break      # thoát loop
    [[ $i -eq 3 ]] && continue   # skip iteration
    echo $i
done
```

### How – Functions

```bash
# Định nghĩa function
greet() {
    local name="$1"                  # local variable
    local greeting="${2:-Hello}"     # default value
    echo "$greeting, $name!"
    return 0                         # exit code (0 = success)
}

# Gọi function
greet "Alice"                        # Hello, Alice!
greet "Bob" "Hi"                     # Hi, Bob!

# Capture return value qua command substitution
result=$(greet "Charlie")

# Error handling in function
deploy() {
    local env="$1"
    if [[ -z "$env" ]]; then
        echo "Error: environment required" >&2  # stderr
        return 1
    fi
    echo "Deploying to $env..."
}

deploy || exit 1  # exit script nếu function fail
```

### How – Error Handling & Best Practices

```bash
#!/bin/bash
set -euo pipefail
# -e: exit on error (bất kỳ lệnh nào fail thì thoát)
# -u: error on undefined variable
# -o pipefail: pipe fail nếu bất kỳ pipe component nào fail

# Trap – cleanup khi exit
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT           # xóa khi script kết thúc
trap "echo 'Interrupted!'; rm -f $TMPFILE; exit 1" INT TERM  # Ctrl+C

# Kiểm tra exit code
if ! command -v nginx &>/dev/null; then
    echo "nginx is not installed" >&2
    exit 1
fi

# Verbose mode
if [[ "${VERBOSE:-0}" == "1" ]]; then
    set -x  # in lệnh trước khi chạy
fi

# Heredoc
cat << 'EOF'
This is a multiline
string without variable expansion
EOF

# Arrays
SERVERS=("web1.example.com" "web2.example.com" "web3.example.com")
for server in "${SERVERS[@]}"; do
    ssh "$server" "sudo systemctl restart nginx"
done
echo "Total servers: ${#SERVERS[@]}"
```

### How – Practical Script Template

```bash
#!/usr/bin/env bash
set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/deploy.log"

# Logging
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Usage
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] ENV

Arguments:
  ENV         Environment (dev|staging|prod)

Options:
  -h          Show this help
  -v          Verbose mode
EOF
}

# Parse args
VERBOSE=0
while getopts ":hv" opt; do
    case $opt in
        h) usage; exit 0;;
        v) VERBOSE=1; set -x;;
        *) usage; exit 1;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 1 ]] || error "ENV argument required"
ENV="$1"

# Main
main() {
    log "Starting deployment to $ENV"
    # ... deployment logic ...
    log "Deployment complete"
}

main
```

### Real-world Usage
```bash
# Auto backup script
#!/bin/bash
BACKUP_DIR="/backup/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
pg_dump mydb | gzip > "$BACKUP_DIR/mydb.sql.gz"
find /backup -mtime +30 -delete  # xóa backup > 30 ngày

# Health check script
#!/bin/bash
URL="http://localhost:8080/health"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
if [[ "$RESPONSE" != "200" ]]; then
    echo "Health check FAILED: $RESPONSE" | mail -s "Alert" admin@example.com
    systemctl restart myapp
fi
```

### Ghi chú – Chủ đề tiếp theo
> System Administration: systemd, journalctl, cron, disk management, monitoring tools

---

## 10. System Administration

### What – System Administration là gì?
Quản trị hệ thống Linux gồm: quản lý **services (systemd)**, **logs (journalctl)**, **scheduled tasks (cron)**, **disk/storage**, và **monitoring**.

### How – systemd & Services

```bash
# systemctl – kiểm soát systemd
systemctl status nginx               # trạng thái service
systemctl start nginx                # start
systemctl stop nginx                 # stop
systemctl restart nginx              # restart (dừng + start)
systemctl reload nginx               # reload config (không dừng)
systemctl enable nginx               # auto-start khi boot
systemctl disable nginx              # không auto-start
systemctl is-active nginx            # active/inactive
systemctl is-enabled nginx           # enabled/disabled

# Xem tất cả services
systemctl list-units --type=service  # active services
systemctl list-units --all           # tất cả
systemctl list-unit-files            # enabled/disabled status

# Tạo custom service (/etc/systemd/system/myapp.service)
# [Unit]
# Description=My Application
# After=network.target
#
# [Service]
# Type=simple
# User=appuser
# WorkingDirectory=/opt/myapp
# ExecStart=/opt/myapp/bin/server
# ExecReload=/bin/kill -HUP $MAINPID
# Restart=always
# RestartSec=5
# Environment=ENV=production
#
# [Install]
# WantedBy=multi-user.target

systemctl daemon-reload              # reload sau khi sửa file unit
systemctl enable --now myapp         # enable + start ngay
```

### How – journalctl (Logs)

```bash
# Xem logs
journalctl                           # tất cả logs
journalctl -n 100                    # 100 dòng gần nhất
journalctl -f                        # follow (giống tail -f)
journalctl -u nginx                  # logs của nginx
journalctl -u nginx -f               # follow nginx logs
journalctl -u nginx --since "1 hour ago"
journalctl -u nginx --since "2024-01-01" --until "2024-01-02"

# Filter theo priority
journalctl -p err                    # error và cao hơn
journalctl -p warning..err           # warning đến error

# Output format
journalctl -u nginx -o json          # JSON format
journalctl -u nginx -o short-iso     # ISO timestamp
journalctl --no-pager                # không pager

# Kernel logs
journalctl -k                        # kernel messages
journalctl -k --since "today"
dmesg                                # kernel ring buffer (tương tự)
dmesg -T                            # với human-readable timestamps
dmesg -l err,crit                   # filter level
```

### How – Cron & Scheduled Tasks

```bash
# crontab – user-level cron
crontab -l                           # list crontab hiện tại
crontab -e                           # edit (mở editor)
crontab -r                           # xóa tất cả
crontab -u alice -l                  # crontab của alice

# Cron syntax: MIN HOUR DOM MON DOW COMMAND
# ┌─── minute (0-59)
# │ ┌─── hour (0-23)
# │ │ ┌─── day of month (1-31)
# │ │ │ ┌─── month (1-12)
# │ │ │ │ ┌─── day of week (0-7, 0&7=Sunday)
# │ │ │ │ │
# * * * * * command

0 2 * * *    /backup.sh             # 2:00 AM hàng ngày
*/5 * * * *  /healthcheck.sh        # mỗi 5 phút
0 9 * * 1    /weekly-report.sh      # 9:00 AM thứ Hai
0 0 1 * *    /monthly-cleanup.sh    # 00:00 ngày 1 hàng tháng
30 4 1,15 * * /bi-monthly.sh        # ngày 1 và 15

# System cron
ls /etc/cron.d/                     # system cron jobs
ls /etc/cron.daily/                 # scripts chạy hàng ngày
ls /etc/cron.hourly/                # scripts chạy hàng giờ

# systemd timers (modern alternative to cron)
systemctl list-timers               # active timers
# Xem ví dụ timer unit: /etc/systemd/system/backup.timer
```

### How – Disk Management

```bash
# df – disk free
df -h                                # disk usage các filesystem
df -h /                              # chỉ root filesystem
df -i                                # inode usage (không phải bytes)

# du – disk usage
du -sh /var/log/                     # size của thư mục
du -sh /var/log/* | sort -rh         # sort by size
du -sh --max-depth=1 /var/           # depth 1

# lsblk – list block devices
lsblk                                # cây block devices
lsblk -f                             # kèm filesystem info

# fdisk / parted – partition management
fdisk -l                             # list partitions
fdisk /dev/sdb                       # interactive partition editor
parted /dev/sdb print                # parted format
parted /dev/sdb mklabel gpt          # tạo GPT partition table

# mkfs – tạo filesystem
mkfs.ext4 /dev/sdb1                  # format ext4
mkfs.xfs /dev/sdb1                   # format XFS
mkfs.vfat /dev/sdb1                  # format FAT32

# mount / umount
mount /dev/sdb1 /mnt/data            # mount
mount -t ext4 /dev/sdb1 /mnt/data   # specify filesystem type
umount /mnt/data                     # unmount
umount -l /mnt/data                  # lazy unmount

# /etc/fstab – auto mount khi boot
# /dev/sdb1  /mnt/data  ext4  defaults  0  2
# UUID=xxx   /mnt/data  ext4  defaults  0  2  (dùng UUID thay device name)
blkid /dev/sdb1                     # lấy UUID

# LVM (Logical Volume Manager)
pvdisplay                            # physical volumes
vgdisplay                            # volume groups
lvdisplay                            # logical volumes
lvextend -L +10G /dev/vg0/data      # mở rộng LV
resize2fs /dev/vg0/data             # resize filesystem (ext4)
xfs_growfs /mnt/data                # resize XFS
```

### How – Monitoring Tools

```bash
# vmstat – virtual memory stats
vmstat 1 5                           # 5 samples mỗi 1 giây
# r=running, b=blocked, si/so=swap in/out, bi/bo=block i/o

# sar – System Activity Reporter (sysstat)
sar -u 1 5                           # CPU utilization
sar -r 1 5                           # memory
sar -d 1 5                           # disk I/O
sar -n DEV 1 5                       # network

# Tổng hợp monitoring
htop                                 # interactive process viewer
glances                              # all-in-one monitoring (cần cài)
netdata                              # web-based real-time monitoring

# Performance profiling
perf top                             # real-time CPU profiling
strace -p 1234                       # trace system calls
ltrace -p 1234                       # trace library calls
lsof -p 1234                         # open files của process

# /proc/sys tuning (kernel parameters)
sysctl net.ipv4.tcp_fin_timeout      # xem giá trị
sysctl -w net.ipv4.tcp_fin_timeout=15  # set tạm thời
echo "net.ipv4.tcp_fin_timeout=15" >> /etc/sysctl.conf  # persistent
sysctl -p                            # reload sysctl.conf
```

### Real-world Usage
```bash
# Kiểm tra service fail nguyên nhân gì
systemctl status myapp --no-pager -l
journalctl -u myapp -n 50 --no-pager

# Quick server health check
echo "=== CPU ===" && uptime
echo "=== Memory ===" && free -h
echo "=== Disk ===" && df -h
echo "=== Load ===" && top -bn1 | head -5

# Rotate logs ngay (logrotate)
logrotate -f /etc/logrotate.d/nginx

# Tìm process ăn nhiều CPU/Memory
ps aux --sort=-%cpu | head -10    # sort by CPU
ps aux --sort=-%mem | head -10    # sort by memory
```

### Ghi chú – Chủ đề tiếp theo
> Environment variables, Shell configuration (.bashrc/.zshrc), SSH key management, Security hardening

---

*Cập nhật lần cuối: 2026-05-06*
