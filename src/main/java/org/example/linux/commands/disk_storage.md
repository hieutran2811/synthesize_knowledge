# Disk & Storage Deep Dive – Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. LVM – Logical Volume Manager

### What – LVM là gì?
**LVM (Logical Volume Manager)** là abstraction layer giữa physical storage và filesystem, cho phép tạo, resize, snapshot volumes một cách linh hoạt mà không cần downtime.

### How – Kiến trúc LVM

```
Physical Storage (HDD/SSD/NVMe/RAID)
         ↓
PV – Physical Volume (toàn bộ disk hoặc partition)
  /dev/sdb, /dev/sdc1, /dev/nvme0n1
         ↓
VG – Volume Group (pool các PVs)
  vg_data (chứa /dev/sdb + /dev/sdc)
         ↓
LV – Logical Volume (virtual partitions từ VG)
  /dev/vg_data/lv_app  (20GB)
  /dev/vg_data/lv_db   (50GB)
  /dev/vg_data/lv_backup (100GB)
         ↓
Filesystem (ext4, xfs, btrfs...)
  mount /dev/vg_data/lv_app /opt/app
```

### How – Tạo LVM

```bash
# Bước 1: Tạo Physical Volumes
pvcreate /dev/sdb /dev/sdc           # tạo PVs từ disks
pvcreate /dev/sdb1 /dev/sdb2         # hoặc từ partitions
pvdisplay                            # xem PVs
pvs                                  # compact summary

# Bước 2: Tạo Volume Group
vgcreate vg_data /dev/sdb /dev/sdc   # tạo VG từ PVs
vgdisplay vg_data                    # xem VG info
vgs                                  # compact summary
vgdisplay vg_data | grep "Free PE"   # free space

# Bước 3: Tạo Logical Volumes
lvcreate -n lv_app -L 20G vg_data    # 20GB volume
lvcreate -n lv_db -L 50G vg_data     # 50GB volume
lvcreate -n lv_backup -l 100%FREE vg_data  # dùng hết space còn lại
lvcreate -n lv_cache -l 50%VG vg_data     # 50% VG
lvdisplay                            # xem LVs
lvs                                  # compact summary

# Bước 4: Tạo Filesystem và Mount
mkfs.ext4 /dev/vg_data/lv_app
mkfs.xfs /dev/vg_data/lv_db

mkdir -p /opt/app /var/lib/postgresql
mount /dev/vg_data/lv_app /opt/app
mount /dev/vg_data/lv_db /var/lib/postgresql

# Thêm vào /etc/fstab
echo "/dev/vg_data/lv_app /opt/app ext4 defaults 0 2" >> /etc/fstab
# Hoặc dùng UUID (ổn định hơn)
blkid /dev/vg_data/lv_app
echo "UUID=xxx /opt/app ext4 defaults 0 2" >> /etc/fstab
```

### How – Resize LVM (không cần downtime!)

```bash
# === Mở rộng LV ===

# 1. Thêm PV vào VG (nếu cần thêm disk)
pvcreate /dev/sdd
vgextend vg_data /dev/sdd

# 2. Mở rộng LV
lvextend -L +10G /dev/vg_data/lv_app          # thêm 10GB
lvextend -L 50G /dev/vg_data/lv_app           # set absolute 50GB
lvextend -l +100%FREE /dev/vg_data/lv_app     # dùng hết free space

# 3. Resize filesystem
resize2fs /dev/vg_data/lv_app                 # ext4 (online!)
xfs_growfs /opt/app                           # xfs (online, dùng mountpoint)
# Hoặc một lệnh duy nhất:
lvextend -r -L +10G /dev/vg_data/lv_app       # -r = resize fs tự động

# === Thu hẹp LV (CẢNH BÁO: nguy hiểm hơn) ===

# ext4: PHẢI unmount trước
umount /opt/app
e2fsck -f /dev/vg_data/lv_app                # check trước
resize2fs /dev/vg_data/lv_app 15G            # shrink fs đến 15GB
lvreduce -L 15G /dev/vg_data/lv_app          # shrink LV
mount /opt/app

# XFS: KHÔNG hỗ trợ shrink
```

### How – LVM Snapshots

```bash
# Tạo snapshot (read-write, CoW – Copy on Write)
lvcreate -n lv_app_snap -L 5G -s /dev/vg_data/lv_app
# -s = snapshot; -L = size of snapshot space (CoW space)

# Mount snapshot (read-only)
mount -o ro /dev/vg_data/lv_app_snap /mnt/snap

# Restore từ snapshot
umount /opt/app
lvconvert --merge /dev/vg_data/lv_app_snap   # merge snapshot back
# hoặc
dd if=/dev/vg_data/lv_app_snap of=/dev/vg_data/lv_app

# Xóa snapshot
lvremove /dev/vg_data/lv_app_snap

# Thin provisioning (tiết kiệm space, over-allocate)
lvcreate -T -n pool -L 100G vg_data          # tạo thin pool
lvcreate -T -n lv1 -V 50G vg_data/pool       # thin volume 50GB (virtual)
lvcreate -T -n lv2 -V 50G vg_data/pool       # thêm 50GB nữa (tổng 100GB virtual từ 100GB pool)
```

---

## 2. RAID – Redundant Array of Independent Disks

### What – RAID là gì?
**RAID** kết hợp nhiều physical disks thành 1 logical unit để tăng **performance**, **redundancy**, hoặc cả hai.

### How – RAID Levels

```
RAID 0 – Striping (NO redundancy)
  Disk1: A1 A3 A5   Disk2: A2 A4 A6
  ✓ Performance: 2x read/write speed
  ✗ Mất 1 disk = mất tất cả data
  Use: temp storage, render farms (speed > reliability)

RAID 1 – Mirroring
  Disk1: A A A A     Disk2: A A A A (copy)
  ✓ Redundancy: mất 1 disk OK
  ✗ Usable = 50% (N/2 disks)
  Use: OS disk, boot drives

RAID 5 – Striping with Parity
  Cần ít nhất 3 disks
  Disk1: A1 B1 P3   Disk2: A2 P2 C1   Disk3: P1 B2 C2
  ✓ Redundancy: chịu mất 1 disk
  ✓ Usable = (N-1)/N capacity
  ✗ Write penalty (tính parity)
  ✗ Rebuild time dài, "RAID 5 write hole"
  Use: NAS, small file servers

RAID 6 – Striping with Double Parity
  Cần ít nhất 4 disks
  ✓ Chịu mất 2 disks
  ✓ Usable = (N-2)/N capacity
  ✗ Write penalty cao hơn RAID 5
  Use: Large storage arrays, high availability

RAID 10 (1+0) – Mirror then Stripe
  Cần ít nhất 4 disks (cặp mirrors, striped)
  ✓ Redundancy: mất 1 disk mỗi mirror OK
  ✓ Performance: stripe
  ✗ Usable = 50%
  Use: Databases, high I/O workloads (BEST choice cho production DB)
```

### How – Software RAID với mdadm

```bash
# Cài đặt
apt install mdadm

# Tạo RAID array
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdb /dev/sdc
mdadm --create /dev/md0 --level=5 --raid-devices=3 /dev/sdb /dev/sdc /dev/sdd
mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Xem status
cat /proc/mdstat                      # real-time status
mdadm --detail /dev/md0               # chi tiết
mdadm --examine /dev/sdb              # xem RAID metadata trên disk

# Thêm disk (hot spare)
mdadm /dev/md0 --add /dev/sde

# Fail và remove disk
mdadm /dev/md0 --fail /dev/sdb
mdadm /dev/md0 --remove /dev/sdb

# Replace disk
mdadm /dev/md0 --fail /dev/sdb && mdadm /dev/md0 --remove /dev/sdb
mdadm /dev/md0 --add /dev/sdf         # tự động rebuild

# Monitor rebuild progress
watch cat /proc/mdstat
mdadm --monitor --mail=admin@example.com --daemonise /dev/md0

# Save config
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u                   # update initramfs

# Grow array (thêm disk vào RAID 5)
mdadm --grow /dev/md0 --raid-devices=4 --add /dev/sde
```

---

## 3. Filesystems Deep Dive

### How – ext4

```bash
# ext4 features
# - Journaling (metadata integrity)
# - Extents (contiguous blocks, ít fragmentation)
# - Delayed allocation (batches writes)
# - Online resize (extend, không shrink!)
# - Max file size: 16TB; Max volume: 1EB

# Tạo với options
mkfs.ext4 -L "mydata" /dev/sdb1              # label
mkfs.ext4 -b 4096 -m 1 /dev/sdb1            # block size, 1% reserved
mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 /dev/sdb1  # immediate init (slower)

# Tune
tune2fs -l /dev/sdb1                          # filesystem info
tune2fs -L "newlabel" /dev/sdb1              # set label
tune2fs -m 1 /dev/sdb1                        # set reserved blocks to 1%
tune2fs -r 0 /dev/sdb1                        # no reserved blocks
tune2fs -c 100 /dev/sdb1                      # fsck every 100 mounts

# Check và repair
e2fsck -f /dev/sdb1                           # force check
e2fsck -p /dev/sdb1                           # auto repair
```

### How – XFS

```bash
# XFS features
# - High performance (parallel I/O, delayed logging)
# - Online resize (chỉ extend, không shrink!)
# - Sparse files, large directories
# - Project quotas
# - Max file size: 8EB; Max volume: 8EB

mkfs.xfs -L "fastdata" /dev/sdb1
mkfs.xfs -b size=4096 /dev/sdb1              # block size
mkfs.xfs -d agcount=8 /dev/sdb1             # 8 allocation groups (parallel I/O)

# Grow (online)
xfs_growfs /mountpoint

# Info
xfs_info /mountpoint
xfs_db -r /dev/sdb1                          # debug tool

# Backup (XFS-specific)
xfsdump -l 0 -f /backup/data.dump /mountpoint    # full dump
xfsrestore -f /backup/data.dump /restore/         # restore
```

### How – Btrfs

```bash
# Btrfs features
# - Copy-on-Write (CoW)
# - Built-in RAID (0,1,10,5,6)
# - Snapshots (instant, space-efficient)
# - Transparent compression
# - Checksums (data integrity)
# - Subvolumes

mkfs.btrfs /dev/sdb                          # single device
mkfs.btrfs -d raid1 /dev/sdb /dev/sdc       # RAID1 data
mkfs.btrfs -m raid1 /dev/sdb /dev/sdc       # RAID1 metadata

# Subvolumes (như partitions nhưng linh hoạt hơn)
btrfs subvolume create /data/app
btrfs subvolume list /data
btrfs subvolume delete /data/app

# Snapshots (instant!)
btrfs subvolume snapshot /data/app /data/app_snapshot_$(date +%Y%m%d)
btrfs subvolume snapshot -r /data/app /data/app_readonly_snap  # read-only

# Send/Receive (incremental backup)
btrfs send /data/app_snap | btrfs receive /backup/
btrfs send -p /data/app_old_snap /data/app_new_snap | btrfs receive /backup/

# Compression
mount -o compress=zstd /dev/sdb /data       # zstd compression
btrfs filesystem defrag -r -czstd /data/    # compress existing files

# Scrub (data integrity check, online!)
btrfs scrub start /data
btrfs scrub status /data
```

---

## 4. NFS & CIFS Mount

### How – NFS (Network File System)

```bash
# === NFS Server ===
apt install nfs-kernel-server

# /etc/exports – define exported directories
/var/nfs/general   192.168.1.0/24(rw,sync,no_subtree_check)
/home              192.168.1.100(rw,sync,no_root_squash)
# rw = read-write
# ro = read-only
# sync = write synchronously (safe)
# async = async (faster, risk of data loss)
# no_subtree_check = disable subtree checking (performance)
# no_root_squash = root on client = root on server (CAUTION!)
# root_squash = root on client = anonymous on server (default, safer)
# all_squash = tất cả users mapped to anonymous

exportfs -a                              # apply exports
exportfs -r                              # re-export
exportfs -v                              # verbose list
systemctl enable --now nfs-server

# === NFS Client ===
apt install nfs-common

# Mount
mount -t nfs 192.168.1.10:/var/nfs/general /mnt/nfs
mount -t nfs4 192.168.1.10:/share /mnt/share  # NFSv4

# /etc/fstab entry
192.168.1.10:/var/nfs/general /mnt/nfs nfs defaults,timeo=900,retrans=5,_netdev 0 0

# NFSv4 options quan trọng
mount -t nfs4 -o rw,soft,timeo=30,retrans=3 server:/share /mnt

# Kiểm tra
showmount -e 192.168.1.10             # xem exports của NFS server
nfsstat -m                             # NFS client stats
nfsstat -s                             # NFS server stats
```

### How – CIFS/SMB (Windows Shares)

```bash
# Mount Windows/Samba share
apt install cifs-utils

# Mount
mount -t cifs //server/share /mnt/windows \
    -o username=user,password=pass,domain=DOMAIN

# Tốt hơn: dùng credentials file
cat > /etc/samba/credentials << 'EOF'
username=myuser
password=mypassword
domain=MYDOMAIN
EOF
chmod 600 /etc/samba/credentials

mount -t cifs //server/share /mnt/windows \
    -o credentials=/etc/samba/credentials,uid=1000,gid=1000

# /etc/fstab entry
//server/share /mnt/win cifs credentials=/etc/samba/creds,uid=1000,gid=1000,iocharset=utf8,_netdev 0 0

# Mount options quan trọng
# vers=3.0 – SMB version (1.0=legacy,2.0,2.1,3.0,3.11)
# sec=ntlmssp – authentication method
# cache=strict – caching mode
```

---

## 5. ZFS Basics

### What – ZFS là gì?
**ZFS** (Zettabyte File System) là enterprise filesystem với RAID, snapshots, compression, checksums tất-cả-trong-một. Từ Sun/Oracle, available trên Linux qua OpenZFS.

### How – ZFS Setup

```bash
# Cài đặt (Ubuntu)
apt install zfsutils-linux

# Tạo pool
zpool create mypool /dev/sdb                        # single disk
zpool create mypool mirror /dev/sdb /dev/sdc        # RAID-1
zpool create mypool raidz /dev/sdb /dev/sdc /dev/sdd  # RAID-5 equivalent
zpool create mypool raidz2 /dev/sd{b,c,d,e}          # RAID-6 equivalent

# Xem status
zpool status                                         # pool status
zpool list                                           # pool capacity
zfs list                                             # datasets

# Datasets (subvolumes)
zfs create mypool/data                               # tạo dataset
zfs create mypool/data/app                           # nested
zfs set mountpoint=/opt/app mypool/data/app          # set mountpoint
zfs set compression=lz4 mypool/data                  # enable compression
zfs set quota=50G mypool/data/app                    # quota

# Snapshots
zfs snapshot mypool/data@backup_20240115             # create snapshot
zfs list -t snapshot                                 # list snapshots
zfs rollback mypool/data@backup_20240115             # revert to snapshot
zfs send mypool/data@snap | ssh backup_server "zfs receive tank/data"  # replicate
zfs destroy mypool/data@backup_20240115              # delete snapshot

# ZFS RAID add cache/log
zpool add mypool cache /dev/sde                      # L2ARC (read cache, SSD)
zpool add mypool log /dev/sdf                        # ZIL/SLOG (write log, SSD)
```

---

## 6. Disk Performance & Monitoring

### How – Benchmarking

```bash
# hdparm – disk parameters
hdparm -I /dev/sda                   # disk info
hdparm -t /dev/sda                   # read speed (direct)
hdparm -T /dev/sda                   # cache read speed

# fio – flexible I/O tester (chuẩn nhất)
apt install fio

# Sequential read
fio --name=seqread --rw=read --bs=4M --size=1G --ioengine=libaio --iodepth=32

# Sequential write
fio --name=seqwrite --rw=write --bs=4M --size=1G --ioengine=libaio --iodepth=32

# Random read/write (4K blocks – database-like)
fio --name=randwrite --rw=randwrite --bs=4k --size=1G \
    --ioengine=libaio --iodepth=32 --numjobs=4

# dd benchmark
dd if=/dev/zero of=/tmp/test.img bs=1M count=1024 oflag=dsync  # write speed
dd if=/tmp/test.img of=/dev/null bs=1M                          # read speed
```

### How – iostat & Monitoring

```bash
# iostat – I/O statistics
iostat -x 1                          # extended stats mỗi 1 giây
iostat -x /dev/sda 1                 # chỉ sda

# Columns quan trọng
# %util    – disk utilization (gần 100% = bottleneck)
# r/s w/s  – read/write operations per second
# rkB/s wkB/s – read/write throughput
# await    – average wait time (ms)
# r_await w_await – separate read/write latency
# svctm    – service time (ms, deprecated)
# avgqu-sz – average queue length

# iotop – disk I/O per process
iotop -b -n 5 -d 2                   # batch mode, 5 iterations, 2 second interval
iotop -a                             # accumulated I/O
iotop -o                             # chỉ processes đang làm I/O

# dstat – combined disk + network + CPU
dstat -drnc 1                        # disk, net, disk io, cpu mỗi giây

# blktrace – block layer tracing (low-level)
blktrace -d /dev/sda -o trace        # capture
blkparse trace.sda.blktrace.0        # parse
```

---

## 7. Disk Management Commands

### How – Partitioning

```bash
# parted (GPT + MBR, recommended)
parted /dev/sdb
  (parted) mklabel gpt              # GPT partition table
  (parted) mkpart primary ext4 1MiB 50GiB
  (parted) mkpart primary xfs 50GiB 100GiB
  (parted) print
  (parted) quit

# Tự động alignment
parted -a optimal /dev/sdb mkpart primary ext4 0% 50%

# gdisk – GPT-specific (chuẩn hơn cho EFI)
gdisk /dev/sdb
  n = new partition
  t = type (83=Linux, 82=swap, ef=EFI)
  w = write

# Xem/verify
lsblk -f /dev/sdb                    # filesystem info
blkid /dev/sdb1                      # UUID và filesystem type
fdisk -l                             # list all partitions
```

### How – SMART – Disk Health Monitoring

```bash
# Cài đặt
apt install smartmontools

# Xem SMART status
smartctl -i /dev/sda                 # disk info
smartctl -H /dev/sda                 # health status
smartctl -a /dev/sda                 # tất cả SMART data

# Run tests
smartctl -t short /dev/sda           # short test (~2 phút)
smartctl -t long /dev/sda            # long test (~hours)
smartctl -l selftest /dev/sda        # xem kết quả

# Attributes quan trọng
# ID 5 - Reallocated Sectors Count (> 0 = BAD!)
# ID 197 - Current Pending Sectors
# ID 198 - Uncorrectable Sectors
# ID 187 - Reported Uncorrectable Errors

# smartd daemon – giám sát tự động
systemctl enable --now smartd
cat /etc/smartd.conf
```

---

## 8. Compare & Trade-offs

### Compare – Filesystems

| | ext4 | XFS | Btrfs | ZFS |
|--|------|-----|-------|-----|
| Stability | Rất ổn định | Rất ổn định | Khá ổn định | Rất ổn định |
| Snapshots | Via LVM | Via LVM | Built-in | Built-in |
| RAID | Via mdadm/LVM | Via mdadm/LVM | Built-in | Built-in |
| Compression | Không | Không | Built-in | Built-in |
| Max file | 16TB | 8EB | 16EB | 16EB |
| Shrink | Có (offline) | Không | Có | Không |
| Memory | Thấp | Thấp | Trung bình | Cao (ARC cache) |
| Khi dùng | General purpose | Large files, databases | Desktop, snapshots | Enterprise |

### Compare – RAID Levels

| RAID | Min Disks | Usable | Fault Tolerance | Performance |
|------|-----------|--------|-----------------|-------------|
| 0 | 2 | 100% | 0 disk | Read+Write 2x |
| 1 | 2 | 50% | 1 disk | Read 2x, Write 1x |
| 5 | 3 | (N-1)/N | 1 disk | Read fast, Write ~1x |
| 6 | 4 | (N-2)/N | 2 disks | Read fast, Write slow |
| 10 | 4 | 50% | 1 per mirror | Read+Write fast |

**Production recommendation**: RAID 10 cho databases, RAID 6 cho cold storage.

### Trade-offs

- **LVM**: linh hoạt nhưng complexity cao; snapshot CoW có thể ảnh hưởng performance
- **Software RAID (mdadm)**: tiết kiệm, flexible, nhưng dùng CPU; rebuild chậm trên disk lớn
- **NFS**: đơn giản, portable, nhưng không có file locking tốt; NFS v4 cải thiện đáng kể
- **ZFS**: tính năng đầy đủ nhất nhưng cần nhiều RAM (ARC cache); không phải mainline kernel
- **Btrfs**: tính năng tốt, nhưng RAID 5/6 vẫn chưa production-ready (as of 2024)

---

### Ghi chú – Chủ đề tiếp theo
> **12.1 Bash Scripting Deep Dive**: variable types, string operations, arrays, arithmetic, here-docs
