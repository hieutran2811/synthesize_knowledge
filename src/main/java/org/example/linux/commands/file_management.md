# File Management Advanced – Deep Dive

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. find – Advanced Usage

### What – find là gì?
`find` là command tìm kiếm file/directory theo nhiều tiêu chí (tên, loại, kích thước, thời gian, permissions...) và có thể thực thi action trên kết quả tìm được.

### How – Cú pháp & Tìm kiếm cơ bản

```bash
# Cú pháp: find [PATH] [EXPRESSION]
find /var/log -name "*.log"              # tìm theo tên
find /etc -name "nginx*" -type f        # chỉ regular files
find /etc -name "nginx*" -type d        # chỉ directories
find / -name "passwd" 2>/dev/null       # suppress permission errors

# Tên file (case-sensitive vs insensitive)
find . -name "*.txt"                    # case-sensitive
find . -iname "*.TXT"                   # case-insensitive

# Path matching
find /var -path "*/nginx/*"             # match full path
find /var -path "*/nginx/*.log"
```

### How – Tìm theo thuộc tính

```bash
# Kích thước
find /var -size +100M                   # > 100MB
find /var -size +100M -size -1G        # 100MB - 1GB
find /tmp -size 0                       # file rỗng (empty)
find /var -size +10M -type f           # files > 10MB

# Thời gian
# -mtime: modification time (nội dung thay đổi)
# -atime: access time (lần cuối đọc)
# -ctime: change time (permission/owner thay đổi)
find /var/log -mtime -7                # modified trong 7 ngày gần nhất
find /tmp -mtime +30                   # cũ hơn 30 ngày
find /backup -mtime +7 -delete         # xóa file backup > 7 ngày
find . -newer reference.txt            # newer than reference file
find . -mmin -60                       # modified trong 60 phút gần nhất

# Permissions
find / -perm 777                        # đúng 777
find / -perm /4000                      # có SUID bit (bất kỳ vị trí)
find / -perm /6000                      # có SUID hoặc SGID
find / -perm -u+s 2>/dev/null          # SUID set
find /var/www -not -perm 644 -type f   # files không phải 644

# Owner
find /home -user alice                  # owned by alice
find /tmp -group developers             # owned by group developers
find / -nouser 2>/dev/null             # files không có user (orphaned)
find / -nogroup 2>/dev/null            # files không có group
```

### How – Actions: -exec và xargs

```bash
# -exec: chạy command cho từng kết quả
# {} = placeholder cho tên file
# \; = kết thúc lệnh (chạy 1 process mỗi file)
find /tmp -mtime +7 -exec rm {} \;

# -exec với + = batch (hiệu quả hơn \;)
find /tmp -mtime +7 -exec rm {} +      # gom nhiều files thành 1 lệnh

# Ví dụ thực tế
find . -name "*.py" -exec chmod 644 {} +    # set permissions
find . -name "*.log" -exec gzip {} \;       # compress logs
find /src -name "*.java" -exec grep -l "TODO" {} +  # tìm TODOs

# -ok: như -exec nhưng hỏi trước mỗi lần
find /etc -name "*.conf" -ok cp {} {}.bak \;   # hỏi trước khi backup

# -print0 với xargs -0: safe với tên file có spaces
find . -name "*.txt" -print0 | xargs -0 wc -l

# xargs: build arguments từ stdin
find . -name "*.log" | xargs rm         # xóa (UNSAFE nếu có spaces)
find . -name "*.log" -print0 | xargs -0 rm  # safe version
find . -name "*.java" | xargs -P 4 grep "Pattern"  # parallel với -P
```

### How – Logical Operators trong find

```bash
# AND (mặc định)
find . -name "*.log" -size +1M          # name AND size

# OR (-o)
find . -name "*.log" -o -name "*.txt"  # .log OR .txt

# NOT (!)
find . ! -name "*.log"                  # không phải .log
find /tmp ! -user root -type f         # files không phải của root

# Grouping với ()
find . \( -name "*.log" -o -name "*.tmp" \) -mtime +7 -delete

# Prune (bỏ qua directory)
find / -name "*.log" -not -path "*/proc/*"  # skip /proc
find . -path "./node_modules" -prune -o -name "*.js" -print
```

---

## 2. locate & updatedb – Fast File Lookup

### What – locate là gì?
`locate` tìm file nhanh hơn `find` bằng cách query **database index** thay vì scan filesystem trực tiếp. Trade-off: không real-time (database cần cập nhật).

### How – Sử dụng

```bash
# Cài đặt
apt install mlocate   # Debian/Ubuntu
dnf install mlocate   # RHEL/CentOS

# updatedb – rebuild index
updatedb                    # update database (cần root)
updatedb -v                 # verbose
# Mặc định chạy qua cron hàng ngày

# locate – tìm file
locate nginx.conf           # tìm tất cả nginx.conf
locate -i README            # case-insensitive
locate "*.log"              # pattern matching
locate -c nginx             # đếm số kết quả
locate -l 10 nginx          # giới hạn 10 kết quả
locate -e nginx.conf        # chỉ hiển thị files đang tồn tại (-e = exists check)
locate -r "\.conf$"         # regex pattern

# Cấu hình /etc/updatedb.conf
cat /etc/updatedb.conf
# PRUNEPATHS="/tmp /var/spool /media /home/.ecryptfs"  # bỏ qua những path này
# PRUNEFS="nfs cifs smbfs"   # bỏ qua filesystem types
```

### Compare – find vs locate

| | find | locate |
|--|------|--------|
| Tốc độ | Chậm (scan realtime) | Nhanh (query DB) |
| Realtime? | Có | Không (cần updatedb) |
| Cần root? | Đôi khi | Chỉ updatedb |
| Tìm theo nội dung? | Qua -exec grep | Không |
| Khi dùng | Complex criteria, realtime | Quick filename lookup |

---

## 3. inotify – File System Event Monitoring

### What – inotify là gì?
`inotify` là Linux kernel subsystem cho phép monitor **filesystem events** (tạo, xóa, sửa, truy cập file) theo thời gian thực. Nền tảng của nhiều tools: `fswatch`, `inotifywait`, IDE file watchers, Dropbox sync.

### How – inotifywait

```bash
# Cài đặt
apt install inotify-tools

# Monitor events trên file/directory
inotifywait -m /var/www/html/          # monitor liên tục (-m = monitor)
inotifywait -m -r /var/www/           # recursive
inotifywait -m -e modify,create,delete /etc/  # specific events

# Events
# access    – file được đọc
# modify    – nội dung thay đổi
# attrib    – attributes thay đổi (permissions, owner)
# close_write – file được đóng sau khi ghi
# open      – file được mở
# moved_to  – file được move vào
# moved_from – file được move ra
# create    – file/dir được tạo
# delete    – file/dir bị xóa

# Output format
inotifywait -m --format "%T %w %e %f" --timefmt "%H:%M:%S" /etc/nginx/

# Script: auto reload nginx khi config thay đổi
#!/bin/bash
inotifywait -m -e close_write /etc/nginx/ |
while read dir event file; do
    if [[ "$file" == *.conf ]]; then
        echo "Config changed: $file – reloading nginx"
        nginx -t && systemctl reload nginx
    fi
done
```

### How – inotifywatch (statistics)

```bash
# Đếm events trong khoảng thời gian
inotifywatch -v -t 60 /var/www/html/   # 60 giây
# Output: tổng hợp số lần mỗi loại event xảy ra
```

### How – Kernel limits

```bash
# Xem/set giới hạn inotify watches
cat /proc/sys/fs/inotify/max_user_watches  # mặc định 8192
cat /proc/sys/fs/inotify/max_user_instances  # mặc định 128

# Tăng giới hạn (cần cho IDE, Dropbox, etc.)
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf
sysctl -p
```

---

## 4. lsof – List Open Files

### What – lsof là gì?
`lsof` (List Open Files) liệt kê tất cả files đang được mở bởi processes. Trong Linux, "everything is a file" – bao gồm network sockets, pipes, devices.

### How – Sử dụng cơ bản

```bash
# Cài đặt (thường có sẵn)
apt install lsof

# Liệt kê tất cả (rất nhiều output)
lsof | head -20

# Filter theo process
lsof -p 1234                    # files mở bởi PID 1234
lsof -c nginx                   # files mở bởi process tên "nginx"

# Filter theo user
lsof -u alice                   # files mở bởi alice
lsof -u ^root                   # files KHÔNG mở bởi root (^= NOT)

# Filter theo file/directory
lsof /var/log/nginx/access.log  # process nào đang mở file này
lsof +D /var/www/               # files được mở bên trong directory này

# Network sockets
lsof -i                         # tất cả network connections
lsof -i :80                     # process dùng port 80
lsof -i :80-443                 # range ports
lsof -i tcp                     # tất cả TCP
lsof -i @192.168.1.100          # connections đến IP cụ thể
lsof -i tcp:8080 -s TCP:LISTEN  # process đang listen port 8080

# Xem file descriptors
lsof -p 1234 -d 0,1,2           # stdin, stdout, stderr của process
```

### How – Output Fields

```
COMMAND  PID  USER  FD  TYPE  DEVICE  SIZE/OFF  NODE  NAME
nginx   1234  root  3u  IPv4   12345      0t0   TCP  *:80 (LISTEN)

FD: file descriptor
  cwd = current working directory
  txt = program text (executable)
  mem = memory-mapped file
  0r/1w/2u = stdin(r)/stdout(w)/both(u)
  3u, 4r = file descriptor numbers

TYPE:
  REG = regular file
  DIR = directory
  IPv4/IPv6 = network socket
  FIFO = named pipe
  unix = unix domain socket
```

### Real-world: Debug "device is busy"

```bash
# Khi umount báo lỗi "device is busy"
lsof +D /mnt/data/              # tìm process đang dùng mountpoint
# hoặc
fuser -vm /mnt/data/            # fuser: tìm processes dùng file/socket
fuser -km /mnt/data/            # kill các processes đó
```

---

## 5. fuser – Identify Processes Using Files

### What – fuser là gì?
`fuser` xác định **process nào đang sử dụng** file hoặc network socket. Nhẹ và nhanh hơn `lsof` khi chỉ cần biết process dùng resource cụ thể.

### How – Sử dụng

```bash
# File/directory
fuser /var/log/nginx/access.log  # PID các process dùng file này
fuser -v /var/log/               # verbose (kèm user, access type)
fuser -m /mnt/usb/               # tất cả processes dùng filesystem

# Network ports
fuser 80/tcp                     # process dùng TCP port 80
fuser 53/udp                     # process dùng UDP port 53
fuser -v 8080/tcp                # verbose

# Kill processes
fuser -k /var/log/app.log        # kill tất cả process đang dùng file
fuser -k -SIGTERM 8080/tcp       # graceful kill
fuser -k 9 8080/tcp             # SIGKILL

# Access types (trong verbose mode)
# c = current directory
# e = executable
# f = open file
# F = open file for writing
# r = root directory
# m = mmap'ed file
```

---

## 6. Advanced File Operations

### How – dd – Low-level Data Copy

```bash
# dd: byte-level copy (disk image, zero fill, benchmark)
dd if=/dev/zero of=/tmp/1GB.img bs=1M count=1024  # tạo file 1GB
dd if=/dev/urandom of=/dev/sdb bs=4M              # wipe disk với random data
dd if=/dev/sda of=/backup/sda.img bs=4M           # disk image backup
dd if=/dev/sda of=/dev/sdb bs=4M                  # clone disk
dd if=/dev/sda1 | gzip > /backup/sda1.img.gz      # compressed backup

# Monitoring progress (dd status)
dd if=/dev/zero of=/tmp/test bs=1M count=1024 status=progress

# Benchmark disk write speed
dd if=/dev/zero of=/tmp/benchmark bs=1M count=1024 oflag=dsync
```

### How – stat – File Detailed Info

```bash
stat file.txt
# File: file.txt
# Size: 1234      Blocks: 8       IO Block: 4096  regular file
# Device: 803h    Inode: 123456   Links: 1
# Access: (0644/-rw-r--r--)  Uid: (1000/alice)  Gid: (1000/alice)
# Access: 2024-01-15 10:30:00  (atime)
# Modify: 2024-01-14 09:00:00  (mtime)
# Change: 2024-01-14 09:00:00  (ctime)

stat -c "%n %s %U %G %A" file.txt   # custom format: name size user group perms
stat -c "%y" file.txt               # chỉ mtime
stat -f /var/log/                   # filesystem stats
```

### How – file – Determine File Type

```bash
file /usr/bin/ls                    # ELF 64-bit LSB executable
file /etc/passwd                    # ASCII text
file /var/log/auth.log.1.gz         # gzip compressed data
file /dev/sda                       # block special
file -i /etc/nginx/nginx.conf       # MIME type: text/plain; charset=utf-8
file -b /usr/bin/bash               # brief (không in tên file)

# Kiểm tra loại trước khi xử lý
for f in /tmp/*; do
    if file "$f" | grep -q "gzip"; then
        gunzip "$f"
    fi
done
```

### How – truncate – Resize Files

```bash
truncate -s 0 /var/log/app.log      # empty file (giữ inode)
truncate -s 100M large_file.txt     # set kích thước chính xác 100MB
truncate -s +50M file.txt           # tăng thêm 50MB (sparse file)
truncate -s -10M file.txt           # giảm 10MB (XÓA DATA từ cuối)
```

### How – Sparse Files

```bash
# Sparse file: file lớn nhưng không chiếm disk thực sự
dd if=/dev/zero of=sparse.img bs=1 count=0 seek=1G  # 1GB sparse file
ls -lh sparse.img                   # hiển thị 1GB
du -sh sparse.img                   # thực tế: 0 bytes!

# Sao chép sparse file đúng cách
cp --sparse=always source.img dest.img
rsync --sparse source.img dest.img
```

---

## 7. File Attributes (chattr / lsattr)

### What – File Attributes là gì?
Ngoài permissions thông thường, ext2/ext3/ext4 filesystem có **extended attributes** kiểm soát thêm hành vi của file.

### How – chattr & lsattr

```bash
# lsattr – xem attributes
lsattr /etc/passwd              # ----i--------e-- /etc/passwd
lsattr -R /etc/                 # recursive

# chattr – set attributes
chattr +i /etc/passwd           # immutable: không ai xóa/sửa/rename (kể cả root!)
chattr -i /etc/passwd           # bỏ immutable
chattr +a /var/log/app.log      # append-only (chỉ append, không xóa/ghi đè)
chattr +d /home/alice/tmp/      # no-dump: skip khi backup với dump

# Attribute flags
# i = immutable
# a = append only
# d = no dump
# e = extents format (thường tự set)
# S = synchronous updates (write ngay, không cache)
# s = secure deletion (overwrite khi xóa)
# u = undeletable (undelete khi xóa)
```

### Real-world Security

```bash
# Bảo vệ critical system files
chattr +i /etc/passwd
chattr +i /etc/shadow
chattr +i /etc/group

# Bảo vệ log file khỏi bị xóa
chattr +a /var/log/audit/audit.log

# Kiểm tra khi có thể bị hack
find /etc -name "*.conf" | xargs lsattr | grep "\-\-i\-"
```

---

## 8. Practical Workflows

### Real-world: Cleanup Scripts

```bash
# Xóa files cũ hơn 30 ngày trong /tmp
find /tmp -maxdepth 1 -mtime +30 -delete

# Xóa logs cũ, giữ lại 10 bản mới nhất
ls -t /var/log/app/*.log | tail -n +11 | xargs rm -f

# Tìm duplicate files (by size + checksum)
find . -type f | xargs md5sum | sort | awk 'seen[$1]++ {print $2}' > duplicates.txt

# Tìm files lớn nhất
find / -type f -printf '%s %p\n' 2>/dev/null | sort -rn | head -20
```

### Real-world: Security Audit

```bash
# Tìm SUID/SGID files
find / -type f \( -perm /4000 -o -perm /2000 \) 2>/dev/null

# Tìm world-writable files (nguy hiểm)
find / -type f -perm -o+w 2>/dev/null | grep -v /proc | grep -v /sys

# Tìm files không có owner (orphaned)
find / -nouser -o -nogroup 2>/dev/null

# Tìm files modified gần đây (có thể bị compromise)
find /etc /bin /sbin /usr/bin -mtime -1 -type f
```

### Real-world: Deployment

```bash
# Deploy với find + exec
find /var/www/html -name "*.php" -exec chmod 644 {} +
find /var/www/html -type d -exec chmod 755 {} +

# Sync files loại trừ một số pattern
rsync -avz --exclude="*.log" --exclude=".git" /src/ /dest/

# Verify file integrity sau deploy
find /opt/app -type f -newer /opt/app/DEPLOY_TIMESTAMP
```

### Compare – find vs fd (modern alternative)

```bash
# fd – modern find replacement (faster, user-friendly)
apt install fd-find   # hoặc: cargo install fd-find

fd nginx              # tìm "nginx" (tên file)
fd -e conf            # extension .conf
fd -t f nginx         # chỉ regular files
fd -H nginx           # bao gồm hidden files
fd -x rm {}           # exec (như find -exec)

# So sánh
find . -name "*.conf" -type f        # find
fd -e conf -t f                      # fd (ngắn hơn, mặc định ignore .git)
```

### Trade-offs

| Tool | Ưu điểm | Nhược điểm |
|------|---------|------------|
| `find` | Universal, cực mạnh | Cú pháp phức tạp |
| `locate` | Rất nhanh | Không realtime |
| `inotify` | Realtime events | Chỉ Linux, limit watches |
| `lsof` | Chi tiết, network | Output nhiều, cần root |
| `fuser` | Nhanh, đơn giản | Ít thông tin hơn lsof |

---

### Ghi chú – Chủ đề tiếp theo
> **11.2 Text Processing Advanced**: regex deep dive, awk one-liners, sed chaining, jq (JSON processing)
