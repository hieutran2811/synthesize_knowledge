# Backup & Recovery – Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. rsync – Efficient File Synchronization

### What – rsync là gì?
**rsync** đồng bộ file bằng **delta algorithm**: chỉ transfer phần thay đổi, rất hiệu quả cho backup incremental. Hỗ trợ local và remote (qua SSH).

### How – rsync Options

```bash
# Core options
rsync -a                               # archive mode = -rlptgoD (recursive, links, perms, times, group, owner, devices)
rsync -v                               # verbose
rsync -z                               # compress during transfer
rsync -h                               # human-readable sizes
rsync -P                               # progress + partial (resume)
rsync -n                               # dry-run (preview)
rsync -e "ssh -p 2222"                 # custom SSH port
rsync --delete                         # delete files not in source
rsync --delete-delay                   # delete after transfer (safer)
rsync --backup                         # backup files before overwriting
rsync --backup-dir=/backup/$(date +%Y%m%d)  # backup location
rsync --checksum                       # compare by checksum (not just time/size)
rsync --ignore-errors                  # continue on errors
rsync --exclude="*.log"                # exclude patterns
rsync --exclude-from=exclude.txt       # exclude list file
rsync --include="*.conf"               # include (after exclude)
rsync --bwlimit=1024                   # bandwidth limit (KB/s)
rsync --timeout=60                     # I/O timeout
rsync --stats                          # transfer statistics
rsync --no-links                       # skip symlinks
```

### How – rsync Patterns

```bash
# Local backup
rsync -avh /source/dir/ /backup/dir/          # trailing slash = contents (not dir itself)
rsync -avh /source/dir /backup/               # no trailing slash = copy dir itself

# Remote backup (via SSH)
rsync -avzh /local/dir/ user@host:/remote/dir/
rsync -avzh user@host:/remote/dir/ /local/dir/

# Remote với custom SSH
rsync -avzh -e "ssh -i ~/.ssh/backup_key -p 2222" \
    /data/ backup@backup-server:/data/

# Incremental backup với hardlinks (backup history)
BACKUP_DIR="/backup"
DATE=$(date +%Y%m%d_%H%M%S)
LATEST="$BACKUP_DIR/latest"

rsync -avh --delete \
    --link-dest="$LATEST" \           # hardlink unchanged files from latest
    /source/ "$BACKUP_DIR/$DATE/"

# Update 'latest' symlink
ln -sfn "$BACKUP_DIR/$DATE" "$LATEST"
# Result: $DATE dir has full backup; unchanged files are hardlinks (no extra space!)

# Three-way mirror (S3-compatible via rclone)
rclone sync /local/data s3://mybucket/data --progress

# Exclude and include rules (order matters!)
rsync -avh \
    --exclude='**/node_modules' \
    --exclude='**/.git' \
    --exclude='*.tmp' \
    --include='*.conf' \
    /app/ /backup/app/
```

### How – rsync Daemon Mode

```bash
# /etc/rsyncd.conf (server-side daemon)
cat > /etc/rsyncd.conf << 'EOF'
uid = rsync
gid = rsync
use chroot = yes
max connections = 4
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid

[backup]
    path = /backup
    comment = Backup storage
    read only = no
    list = yes
    auth users = backupuser
    secrets file = /etc/rsyncd.secrets
    hosts allow = 192.168.1.0/24
    hosts deny = *
EOF

# /etc/rsyncd.secrets
echo "backupuser:secretpassword" > /etc/rsyncd.secrets
chmod 600 /etc/rsyncd.secrets

systemctl enable --now rsync

# Client connect to rsync daemon
rsync -avz /source/ rsync://backupuser@server/backup/
```

---

## 2. tar – Archive & Compression

### How – tar Comprehensive Usage

```bash
# Create archives
tar -czf archive.tar.gz /source/dir/          # gzip compressed
tar -cjf archive.tar.bz2 /source/dir/         # bzip2 (better compression)
tar -cJf archive.tar.xz /source/dir/          # xz (best compression, slow)
tar -czf archive.tar.gz --exclude="*.log" /dir/
tar -czf - /dir/ | ssh host "cat > /remote/backup.tar.gz"  # pipe to remote

# Extract
tar -xzf archive.tar.gz                       # extract in current dir
tar -xzf archive.tar.gz -C /destination/       # extract to specific dir
tar -xzf archive.tar.gz --one-top-level=/dest/ # extract to subdir
tar -xzf archive.tar.gz path/to/specific/file  # extract single file

# List contents
tar -tzf archive.tar.gz                        # list all files
tar -tzf archive.tar.gz | grep "\.conf$"       # find config files

# Incremental backup với tar
# Full backup
tar --create --file=/backup/full.tar \
    --listed-incremental=/backup/snapshot.snar \
    /source/

# Incremental (changes since last backup)
tar --create --file=/backup/inc_$(date +%Y%m%d).tar \
    --listed-incremental=/backup/snapshot.snar \
    /source/

# Restore incremental
tar --extract --file=/backup/full.tar \
    --listed-incremental=/dev/null \
    --directory=/restore/
tar --extract --file=/backup/inc_20240115.tar \
    --listed-incremental=/dev/null \
    --directory=/restore/

# Parallel compression
tar cf - /source/ | pigz -9 > archive.tar.gz     # parallel gzip
tar cf - /source/ | pbzip2 > archive.tar.bz2      # parallel bzip2
tar cf - /source/ | pxz > archive.tar.xz          # parallel xz
```

---

## 3. LVM Snapshots cho Backup

### What – LVM Snapshots cho backup
LVM snapshots tạo **point-in-time copy** của logical volume sử dụng **Copy-on-Write (CoW)**. Cho phép backup consistent database state mà không cần downtime dài.

### How – Database Backup với Snapshots

```bash
# === Backup PostgreSQL via LVM snapshot ===

# 1. Freeze I/O (PostgreSQL online backup mode)
psql -c "SELECT pg_start_backup('lvm_backup', false, false);"

# 2. Tạo snapshot (nhanh, sub-second)
lvcreate -n pg_snap -L 10G -s /dev/vg_data/pg_data

# 3. Kết thúc freeze
psql -c "SELECT pg_stop_backup(false, true);"

# 4. Mount và backup snapshot
mkdir /mnt/pg_snap
mount -o ro /dev/vg_data/pg_snap /mnt/pg_snap
rsync -avh /mnt/pg_snap/ /backup/postgres/$(date +%Y%m%d)/

# 5. Cleanup
umount /mnt/pg_snap
lvremove -f /dev/vg_data/pg_snap

# === Backup MySQL via LVM snapshot ===
mysql -e "FLUSH TABLES WITH READ LOCK;"
mysql -e "FLUSH LOGS;"
mysql -e "SHOW MASTER STATUS\G" > /backup/binlog-position.txt

lvcreate -n mysql_snap -L 5G -s /dev/vg_data/mysql_data

mysql -e "UNLOCK TABLES;"

mount -o ro,norecovery /dev/vg_data/mysql_snap /mnt/mysql_snap
tar -czf /backup/mysql_$(date +%Y%m%d).tar.gz /mnt/mysql_snap/
umount /mnt/mysql_snap
lvremove -f /dev/vg_data/mysql_snap
```

---

## 4. Backup Strategies

### How – 3-2-1 Backup Rule

```
3 copies of data
  - 1 production copy
  - 2 backup copies

2 different media/storage types
  - Local disk + remote server
  - NAS + cloud storage

1 offsite copy
  - Different physical location
  - Cloud (S3, GCS, Azure Blob)
```

### How – Backup Types

```bash
# Full backup – tất cả data
tar -czf /backup/full_$(date +%Y%m%d).tar.gz /data/

# Incremental – chỉ thay đổi kể từ last backup (any type)
rsync -avh --link-dest=/backup/latest /data/ /backup/$(date +%Y%m%d)/

# Differential – thay đổi kể từ last FULL backup
# (lớn hơn incremental nhưng restore đơn giản hơn)

# Continuous (WAL archiving) – PostgreSQL
archive_command = 'cp %p /backup/wal/%f'
archive_mode = on
```

### How – Automated Backup Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
BACKUP_ROOT="/backup"
RETENTION_DAYS=30
RETENTION_WEEKLY=12  # weeks
SOURCE_DIRS=("/etc" "/var/lib/postgresql" "/opt/app")
REMOTE_DEST="backup@backup-server:/backups/$(hostname)"

# Logging
LOG="/var/log/backup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
error() { log "ERROR: $*" >&2; }

# Lock
LOCKFILE="/var/run/backup.lock"
exec 9>"$LOCKFILE"
flock -n 9 || { error "Backup already running"; exit 1; }

# Create dated directory
DATE=$(date +%Y%m%d_%H%M%S)
DAILY_DIR="$BACKUP_ROOT/daily/$DATE"
LATEST="$BACKUP_ROOT/latest"

log "Starting backup: $DATE"

# Incremental backup with hardlinks
mkdir -p "$DAILY_DIR"
for dir in "${SOURCE_DIRS[@]}"; do
    dest_subdir="$DAILY_DIR${dir}"
    mkdir -p "$(dirname "$dest_subdir")"

    rsync -avh --delete \
        ${LATEST:+--link-dest="$LATEST${dir}"} \
        "$dir/" "$dest_subdir/"
done

# Update latest symlink
ln -sfn "$DAILY_DIR" "$LATEST"

# Database dump
if systemctl is-active postgresql &>/dev/null; then
    log "Dumping PostgreSQL"
    sudo -u postgres pg_dumpall | gzip > "$DAILY_DIR/postgres_$(date +%Y%m%d).sql.gz"
fi

# Sync to remote
log "Syncing to remote"
rsync -avzh --delete "$BACKUP_ROOT/daily/" "$REMOTE_DEST/daily/"

# Cleanup old backups
log "Cleaning up backups older than $RETENTION_DAYS days"
find "$BACKUP_ROOT/daily" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} +

# Weekly backup (keep Sunday's backup)
if [[ "$(date +%u)" == "7" ]]; then
    WEEKLY_DIR="$BACKUP_ROOT/weekly/$(date +%Y_W%V)"
    cp -al "$DAILY_DIR" "$WEEKLY_DIR"
    log "Created weekly backup: $WEEKLY_DIR"
    find "$BACKUP_ROOT/weekly" -maxdepth 1 -type d -mtime +"$((RETENTION_WEEKLY * 7))" -exec rm -rf {} +
fi

# Verify backup integrity
BACKUP_SIZE=$(du -sh "$DAILY_DIR" | cut -f1)
log "Backup complete: size=$BACKUP_SIZE, path=$DAILY_DIR"

# Alert if backup is too small (possible failure)
BACKUP_BYTES=$(du -sb "$DAILY_DIR" | cut -f1)
MIN_EXPECTED=104857600  # 100MB
if [[ $BACKUP_BYTES -lt $MIN_EXPECTED ]]; then
    error "Backup may be incomplete! Size: $BACKUP_BYTES bytes"
    exit 1
fi
```

---

## 5. Disaster Recovery

### How – Recovery Testing

```bash
# Test restore procedure (CRITICAL: practice regularly!)

# 1. Setup test environment
lxc launch ubuntu:22.04 restore-test
# hoặc: vagrant up, docker run, etc.

# 2. Restore files
rsync -avh backup-server:/backups/$(hostname)/latest/ /restore-test/

# 3. Restore database
zcat /backup/postgres_20240115.sql.gz | psql -U postgres

# 4. Verify application starts
cd /restore-test && ./start.sh
curl -f http://localhost:8080/health

# 5. Verify data integrity
md5sum /restore-test/data/*.db
diff <(ls /original/data/) <(ls /restore-test/data/)
```

### How – GRUB Recovery

```bash
# Khi system không boot được
# Boot từ live USB

# 1. Mount partitions
mount /dev/sda2 /mnt          # root partition
mount /dev/sda1 /mnt/boot     # boot partition (nếu có)
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# 2. Chroot vào system
chroot /mnt

# 3. Fix GRUB
grub-install /dev/sda
update-grub

# 4. Fix initramfs
update-initramfs -u

# 5. Exit và reboot
exit
umount -R /mnt
reboot
```

### How – Filesystem Recovery

```bash
# ext4 filesystem repair
# Phải unmount trước (hoặc boot từ recovery media)
e2fsck -y /dev/sda2            # auto-fix (dangerous!)
e2fsck -n /dev/sda2            # check only (no fix)

# Recover deleted files (ext4)
apt install testdisk
testdisk /dev/sda              # interactive recovery

# photorec (file carving)
photorec /dev/sda              # recover files by signature

# Recover LVM
vgchange -ay                   # activate all VGs
pvck /dev/sdb                  # check PV
vgck vg_data                   # check VG

# Recover RAID
# Xem degraded array
cat /proc/mdstat

# Re-add disk sau khi replace
mdadm /dev/md0 --add /dev/sdc  # auto rebuild

# Force assemble (sau power failure)
mdadm --assemble --force /dev/md0 /dev/sdb /dev/sdc
```

---

## 6. Backup Tools Ecosystem

### How – Restic – Modern Backup

```bash
# Cài đặt
apt install restic

# Initialize repository
restic init --repo /backup/restic-repo
restic init --repo s3:s3.amazonaws.com/my-bucket/restic

# Backup
restic -r /backup/restic-repo backup /data /etc /home
RESTIC_PASSWORD="secret" restic -r /backup/ backup /data

# List snapshots
restic -r /backup/restic-repo snapshots

# Restore
restic -r /backup/restic-repo restore latest --target /restore/
restic -r /backup/restic-repo restore abc123 --target /restore/ --include "/etc/nginx"

# Mount as filesystem
restic -r /backup/restic-repo mount /mnt/restic-backup

# Cleanup old backups
restic -r /backup/restic-repo forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# Verify integrity
restic -r /backup/restic-repo check
restic -r /backup/restic-repo check --read-data    # verify data too (slower)
```

### How – Borgbackup – Deduplication

```bash
# Cài đặt
apt install borgbackup

# Initialize (with encryption)
borg init --encryption=repokey /backup/borg-repo

# Create backup (with deduplication!)
borg create --stats --compression zstd \
    /backup/borg-repo::$(hostname)-$(date +%Y%m%d) \
    /data /etc

# List archives
borg list /backup/borg-repo

# Extract
borg extract /backup/borg-repo::archive-name
borg extract /backup/borg-repo::archive-name etc/nginx/  # specific path

# Prune
borg prune /backup/borg-repo \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6

# Compact (free space from deleted archives)
borg compact /backup/borg-repo
```

---

## 7. Compare & Trade-offs

### Compare – Backup Solutions

| Tool | Dedup | Encryption | Remote | Resume | Verify |
|------|-------|------------|--------|--------|--------|
| rsync | No | Via SSH | SSH/rsync daemon | Partial | No |
| tar | No | No (use gpg) | Via SSH pipe | No | No |
| restic | Yes (content) | Yes (built-in) | S3/SFTP/etc | Yes | Yes |
| borgbackup | Yes (chunks) | Yes (built-in) | Via SSH | Yes | Yes |
| LVM snapshot | N/A | No | No | N/A | N/A |

### Compare – Backup Types

| Type | Storage needed | Restore complexity | Recovery point |
|------|----------------|-------------------|----------------|
| Full | 100% | Simple (1 step) | Snapshot time |
| Incremental | ~5% per day | Complex (full + all inc) | Last incremental |
| Differential | ~20-50% per day | Medium (full + last diff) | Last differential |
| Continuous (WAL) | Variable | Complex | Any point in time |

### Trade-offs

- **rsync hardlinks**: tiết kiệm space nhưng hardlinks không protect against corruption; cần regular full verification
- **LVM snapshots**: nhanh và consistent nhưng CoW overhead tăng khi snapshot cũ; xóa sớm sau backup
- **Restic vs Borg**: Restic hỗ trợ nhiều backends hơn (S3, Azure, GCS); Borg có dedup tốt hơn (chunk-based vs content-hash)
- **Encrypted backups**: bảo mật tốt nhưng nếu mất key = mất data; key management critical

---

### Ghi chú – Chủ đề tiếp theo
> **14.1 Namespaces & cgroups**: kernel primitives cho containers – PID/net/mnt/uts/user/ipc namespaces, cgroups v2 resource management
