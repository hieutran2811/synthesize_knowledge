# Tổng Hợp Kiến Thức SQL Server

> 📖 Tra cứu nhanh: [SQL Server Glossary](glossary.md) · Mục lục đầy đủ: [roadmap.md](roadmap.md)
>
> Phạm vi: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**, chạy trên Windows và Linux/container.

---

## 1. SQL Server là gì, và nó phù hợp ở đâu

SQL Server là RDBMS của Microsoft: engine quan hệ, giao thức TDS, ngôn ngữ T-SQL. Từ phiên bản 2017 nó chạy trên Linux và container với **cùng engine** như Windows, nên lựa chọn nền tảng giờ là quyết định vận hành, không phải quyết định về năng lực.

Điểm mạnh thực tế khiến nó được chọn:

| Điểm mạnh | Chi tiết |
|---|---|
| Optimizer và công cụ chẩn đoán chín | Query Store, IQP, execution plan chi tiết — mức trưởng thành hàng đầu trong nhóm RDBMS |
| HA/DR đầy đủ trong một sản phẩm | Always On AG với readable secondary, FCI, log shipping |
| Bảo mật nhiều lớp có sẵn | TDE, Always Encrypted, RLS, DDM, Ledger, Audit |
| HTAP thực dụng | Rowstore + columnstore trên cùng bảng, batch mode |
| Hệ sinh thái enterprise | Tích hợp tốt với .NET/Java, AD/Entra ID, Azure |

Điểm cần cân nhắc: license theo core là chi phí đáng kể, và một số tính năng quan trọng chỉ có ở Enterprise Edition (nhưng ít hơn nhiều so với trước 2016 SP1 — partitioning, columnstore, In-Memory OLTP đã có ở Standard).

---

## 2. Kiến trúc ở mức bản đồ

```text
Client (JDBC / ODBC / ADO.NET / sqlcmd)
   │  TDS trên TCP 1433, bọc TLS
   ▼
SNI → SQLOS (cooperative scheduling: scheduler / worker / task)
   │
   ├── Relational Engine
   │      Parser → Algebrizer → Optimizer (cost-based) → Execution
   │      ↑ plan cache, statistics, Query Store
   │
   └── Storage Engine
          Access Methods → Buffer Manager → Transaction Manager → Lock Manager
                  │                                 │
                  ▼                                 ▼
        Data files (.mdf/.ndf)              Log file (.ldf)  ← WAL: durability ở đây
                  │
                  └── tempdb: sort, hash spill, #temp, version store
```

Ba câu chốt để nhớ toàn bộ sơ đồ này:

1. **Durability đến từ transaction log, không từ data file.** Commit trả về khi log đã bền; data file cập nhật sau, bởi checkpoint.
2. **Mọi I/O theo page 8KB, không theo row.** Vì thế row hẹp, index hẹp và nén đều là đòn bẩy hiệu năng.
3. **Optimizer là cost-based, dựa trên statistics.** Sai estimate là gốc của phần lớn plan tệ — không phải "SQL viết dở".

Chi tiết: [architecture.md](fundamentals/architecture.md).

---

## 3. Bản đồ 14 chủ đề

| Nhóm | Chủ đề | Trả lời câu hỏi |
|---|---|---|
| **Fundamentals** | [architecture](fundamentals/architecture.md) | Engine hoạt động thế nào? Nghẽn ở đâu? |
| | [tsql_advanced](fundamentals/tsql_advanced.md) | Viết SQL diễn đạt được bài toán mà không thành cursor? |
| | [indexing](fundamentals/indexing.md) | Index nào là đúng, và đọc plan thế nào? |
| | [transactions](fundamentals/transactions.md) | Nhiều người ghi cùng lúc thì đảm bảo gì? |
| **Performance** | [query_optimization](performance/query_optimization.md) | Vì sao query này chậm *lúc này*? |
| | [monitoring_troubleshooting](performance/monitoring_troubleshooting.md) | Bình thường là thế nào, và giờ khác ở đâu? |
| | [partitioning](performance/partitioning.md) | Quản lý bảng hàng tỉ row thế nào? |
| **Administration** | [backup_recovery](administration/backup_recovery.md) | Mất dữ liệu thì lấy lại được không, trong bao lâu? |
| | [ha_dr](administration/ha_dr.md) | Mất node/site thì hệ thống còn chạy không? |
| | [security](administration/security.md) | Ai thấy được gì, và có bằng chứng không? |
| **Platform** | [linux_containers](platform/linux_containers.md) | Chạy trên Linux/Docker/K8s thế nào? |
| **Integration** | [data_movement](integration/data_movement.md) | Dữ liệu vào/ra và phát sự kiện thế nào? |
| | [jdbc_java](integration/jdbc_java.md) | Từ Java/Spring Boot dùng cho đúng? |
| **Modern** | [sqlserver_2025](modern/sqlserver_2025.md) | Version mới đáng nâng cấp vì gì? |

---

## 4. Mười điều quan trọng nhất trong toàn bộ tài liệu

Nếu chỉ nhớ được mười điều, đây là mười điều có tác động lớn nhất trong thực tế:

1. **Bật RCSI** cho database OLTP production. Reader không còn block writer, và không cần sửa một dòng code ứng dụng. → [transactions.md](fundamentals/transactions.md) mục 4.3
2. **Bật Query Store**. Không có nó, mọi câu hỏi "hôm qua nhanh hơn" đều không trả lời được. → [query_optimization.md](performance/query_optimization.md) mục 4
3. **FULL recovery model thì phải có job `BACKUP LOG`**. Đây là sự cố hết đĩa log phòng được 100%. → [backup_recovery.md](administration/backup_recovery.md) mục 2
4. **Implicit conversion là nguyên nhân #1 của "có index mà vẫn scan"**. Với Java, thường là `sendStringParametersAsUnicode`. → [jdbc_java.md](integration/jdbc_java.md) mục 3
5. **Thiết kế index từ query shape theo ESR**, không từ danh sách cột. → [indexing.md](fundamentals/indexing.md) mục 2
6. **Transaction phải ngắn và không bao trọn lời gọi bên ngoài.** Đây là nguyên nhân blocking phổ biến nhất. → [transactions.md](fundamentals/transactions.md) mục 2.2
7. **Ứng dụng phải retry 1205/1222/3960 với backoff có jitter.** Deadlock không loại bỏ được hoàn toàn. → [transactions.md](fundamentals/transactions.md) mục 7.4
8. **Đo restore, không chỉ đo backup.** RTO công bố phải dựa trên thời gian restore đã đo. → [backup_recovery.md](administration/backup_recovery.md) mục 8
9. **Always On không thay thế backup.** `DELETE` sai được replicate trong vài mili giây. → [ha_dr.md](administration/ha_dr.md) mục 1
10. **Tuning theo tổng thời gian, không theo thời gian trung bình.** Query 5ms chạy 2000 lần/giây tốn nhiều hơn query 60s chạy một lần. → [query_optimization.md](performance/query_optimization.md) mục 10

---

## 5. Bảng tra sự cố → chủ đề

| Triệu chứng | Nghi phạm đầu tiên | Đọc |
|---|---|---|
| Query chậm dần theo thời gian | Statistics cũ, fragmentation, dữ liệu tăng vượt index | [indexing](fundamentals/indexing.md), [query_optimization](performance/query_optimization.md) |
| Cùng procedure, tham số này nhanh tham số kia chậm | Parameter sniffing | [query_optimization](performance/query_optimization.md) mục 3 |
| "Hôm qua chạy 2 giây, hôm nay 3 phút" | Plan hồi quy | [query_optimization](performance/query_optimization.md) mục 4 |
| Nhiều session `suspended` với `LCK_M_*` | Blocking | [transactions](fundamentals/transactions.md) mục 5, 12 |
| Deadlock lặp lại | Thứ tự truy cập object, thiếu index | [transactions](fundamentals/transactions.md) mục 7 |
| Transaction log tăng không dừng | Thiếu `BACKUP LOG`, transaction dài, CDC/replication dừng | [architecture](fundamentals/architecture.md) mục 7.2, [backup_recovery](administration/backup_recovery.md) |
| tempdb đầy | Version store do transaction đọc dài, hoặc hash/sort spill | [architecture](fundamentals/architecture.md) mục 8 |
| `ASYNC_NETWORK_IO` cao | Ứng dụng xử lý chậm hoặc fetch size sai | [jdbc_java](integration/jdbc_java.md) mục 5 |
| Kết nối reset ngẫu nhiên | `max-lifetime` của pool > timeout firewall | [jdbc_java](integration/jdbc_java.md) mục 6.2 |
| Rất nhiều query nhỏ giống nhau | Hibernate N+1 | [jdbc_java](integration/jdbc_java.md) mục 8.3 |
| Xóa dữ liệu cũ mất hàng giờ | Chưa partition | [partitioning](performance/partitioning.md) mục 8 |
| Pod SQL Server bị restart lúc tải cao | `MSSQL_MEMORY_LIMIT_MB` quá gần container limit | [linux_containers](platform/linux_containers.md) mục 4.2 |
| Restore thất bại trên server mới | Thiếu certificate TDE | [backup_recovery](administration/backup_recovery.md) mục 4.2 |
| Secondary AG tụt hậu hàng giờ | Query dài trên secondary chặn redo | [ha_dr](administration/ha_dr.md) mục 2.4 |
| Dữ liệu đích lệch dần so với nguồn | Version Change Tracking đã bị cleanup | [data_movement](integration/data_movement.md) mục 3 |

---

## 6. Checklist instance production

Bản tổng hợp; chi tiết từng mục ở file tương ứng.

```text
Cấu hình engine
□ max server memory đặt tường minh, chừa cho OS
□ MAXDOP theo core mỗi NUMA node; cost threshold for parallelism 30–50
□ tempdb: nhiều file bằng nhau, pre-size, trên storage nhanh
□ Autogrowth theo MB tuyệt đối
□ Instant File Initialization bật

Độ bền
□ Recovery model đúng ý định; FULL thì CÓ job BACKUP LOG
□ PAGE_VERIFY CHECKSUM; backup WITH CHECKSUM
□ DBCC CHECKDB có lịch VÀ có alert khi lỗi
□ Certificate TDE/backup đã backup ra ngoài, mật khẩu trong Vault
□ DR drill hàng tháng (tự động) + hàng quý (có người)

Concurrency
□ RCSI bật
□ Cân nhắc ADR nếu có transaction dài hoặc cần RTO ổn định
□ Ứng dụng có retry cho 1205/1222/3960

Quan sát
□ Query Store bật, SIZE_BASED_CLEANUP_MODE = AUTO
□ Baseline wait stats / file I/O thu định kỳ vào bảng
□ XEvents: deadlock + blocked process report ghi ra file
□ Alert: backup trễ, log reuse wait, transaction mở lâu, suspect_pages, failed login

Bảo mật
□ sa disabled; không ứng dụng nào chạy bằng sysadmin/db_owner
□ TLS bắt buộc, client verify certificate
□ TDE bật cho production
□ xp_cmdshell / OLE Automation / Ad Hoc Distributed Queries tắt
□ Audit sự kiện quyền hạn, log chuyển ra SIEM ngoài server

Ứng dụng (Java)
□ applicationName đặt tên service
□ sendStringParametersAsUnicode khớp schema
□ socketTimeout, queryTimeout, cancelQueryTimeout đặt tường minh
□ open-in-view = false; pool size dựa trên đo lường
□ Integration test dùng Testcontainers với image SQL Server thật
```

---

## 7. So sánh nhanh với engine khác

| | SQL Server | PostgreSQL | Oracle | MySQL (InnoDB) |
|---|---|---|---|---|
| MVCC mặc định | Không (locking); bật RCSI | Có | Có | Có |
| Undo/version ở đâu | tempdb, hoặc PVS (ADR) | Trong heap + vacuum | UNDO tablespace | Undo tablespace |
| Công cụ lịch sử plan | Query Store (rất mạnh) | `pg_stat_statements` + extension | AWR/ASH | Performance Schema |
| Columnstore tích hợp | Có | Extension | Có (In-Memory) | Không |
| HA tích hợp | Always On AG | Streaming replication + tooling ngoài | Data Guard/RAC | Group Replication |
| Mã hóa client-side | Always Encrypted | Extension | TDE + Data Redaction | Không tương đương |
| Chi phí license | Theo core, đáng kể | Miễn phí | Cao | Miễn phí / thương mại |

Khác biệt tư duy quan trọng nhất khi port ứng dụng: **PostgreSQL/Oracle mặc định MVCC, SQL Server mặc định locking**. Một ứng dụng chuyển từ PostgreSQL sang SQL Server mà không bật RCSI sẽ gặp blocking chưa từng thấy ở nguồn.

---

## 8. Ghi chú – phương pháp học

Thứ tự đề xuất và lối đi theo vai: xem [roadmap.md](roadmap.md) mục Learning path.

Ba nguyên tắc xuyên suốt toàn bộ tài liệu:

1. **Đo trước, sửa sau.** Ghi `logical reads`, `CPU time`, `elapsed time` trước và sau mỗi thay đổi. "Nhanh hơn" không phải một kết luận kiểm chứng được.
2. **Sửa một thứ mỗi lần.** Bật ba tính năng cùng lúc rồi thấy hiệu năng đổi thì không biết cái nào có tác dụng.
3. **Biện pháp tạm phải có ngày review.** Force plan, hint, `OPTION (RECOMPILE)` đều là nợ kỹ thuật nếu không ai biết vì sao chúng ở đó.

---

*Cập nhật lần cuối: 2026-07-30*
