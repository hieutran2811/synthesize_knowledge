---
title: "SQL Server Glossary"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# SQL Server Glossary

> Bảng tra cứu nhanh thuật ngữ dùng trong learning path SQL Server. Ưu tiên cách hiểu thực hành với **SQL Server 2022 (16.x)** và **2025 (17.x)**.
>
> Quay lại [roadmap](roadmap.md).

| Thuật ngữ | Nghĩa ngắn gọn | Điểm cần nhớ |
|---|---|---|
| **ACID** | Atomicity, Consistency, Isolation, Durability của transaction | Consistency là ràng buộc kỹ thuật, không đảm bảo dữ liệu nghiệp vụ đúng |
| **ADR** (Accelerated Database Recovery) | Cơ chế recovery/rollback nhanh dùng persistent version store | Từ 2019; điều kiện cho Optimized Locking; giúp log truncate dù có transaction dài |
| **Adaptive Join** | Optimizer chọn Hash hay Nested Loops lúc runtime | IQP từ 2017; dấu hiệu tốt, engine tự phòng estimate sai |
| **AG** (Availability Group) | Nhóm database được nhân bản giữa các replica trong Always On | Không replicate login/job ở mức instance, trừ contained AG |
| **AG Listener** | Tên/IP ảo trỏ tới primary hiện tại của AG | Ứng dụng phải kết nối qua listener, không qua tên server |
| **Algebrizer** | Bước phân giải tên object, kiểm quyền, gắn kiểu sau khi parse | Nằm giữa Parser và Optimizer |
| **Aligned index** | Index dùng cùng partition scheme với bảng | Bắt buộc nếu muốn `SWITCH` partition |
| **Always Encrypted** | Mã hóa ở tầng client, server chỉ thấy ciphertext | DBA không đọc được; mất `LIKE`/range/aggregate trên cột đã mã hóa |
| **ANN** (Approximate Nearest Neighbor) | Tìm vector gần đúng thay vì chính xác | DiskANN index đổi độ chính xác lấy tốc độ |
| **APPLY** | `CROSS`/`OUTER APPLY`: subquery tham chiếu được cột bảng ngoài | Công cụ chuẩn cho top-N mỗi nhóm và gọi TVF theo row |
| **ASYNC_NETWORK_IO** | Wait khi server chờ client đọc hết dữ liệu | Hầu như luôn là vấn đề phía ứng dụng, không phải mạng chậm |
| **Autogrowth** | Cấu hình tự nới file khi hết chỗ | Đặt theo MB tuyệt đối, không theo phần trăm |
| **Batch mode** | Xử lý ~900 row mỗi lần thay vì từng row | Đi cùng columnstore; từ 2019 có cả trên rowstore |
| **bcp** | Công cụ dòng lệnh import/export khối lượng lớn | `-n` (native) nhanh nhất nhưng chỉ SQL Server đọc được |
| **BCM / DCM** | Bulk-Changed Map / Differential-Changed Map | DCM là cơ chế đằng sau differential backup |
| **Buffer Pool** | Vùng RAM cache data/index page | Vùng bộ nhớ lớn nhất của instance; mọi đọc đi qua nó |
| **BULK_LOGGED** | Recovery model ghi log tối thiểu cho bulk operation | Mất PITR trong khoảng đó; phải bọc bằng hai `BACKUP LOG` |
| **CDC** (Change Data Capture) | Ghi lại thay đổi kèm giá trị trước/sau vào bảng `cdc.*` | Bất đồng bộ qua job; job dừng thì log không truncate được |
| **CE** (Cardinality Estimation) | Ước lượng số row của optimizer | Sai CE là gốc của phần lớn plan tệ |
| **CES** (Change Event Streaming) | Engine tự publish sự kiện thay đổi ra endpoint ngoài | Tính năng 2025; thay thế tiềm năng cho CDC + Debezium |
| **Change Tracking** | Chỉ ghi khóa chính của row đã đổi | Đồng bộ, rẻ; chỉ lấy được trạng thái hiện tại |
| **Checkpoint** | Đẩy dirty page xuống data file định kỳ | Giới hạn công việc recovery, không liên quan durability của commit |
| **Clustered index** | Index mà leaf level chính là dữ liệu bảng | Tối đa một cái; key được nhân bản vào mọi nonclustered index |
| **Columnstore** | Lưu dữ liệu theo cột, nén rất cao | Rowgroup ~1.048.576 row; tốt cho phân tích, kém cho point lookup |
| **Compatibility level** | Mức tương thích của database với version engine | Nâng level là **thay đổi hiệu năng**, không chỉ cú pháp |
| **Contained AG** | AG có `master`/`msdb` riêng ở phạm vi AG | 2022+; login/job đi cùng khi failover |
| **Contained database user** | User xác thực trong phạm vi database | Sống sót qua failover/restore, không thành orphaned |
| **Covering index** | Index chứa đủ mọi cột query cần | Dấu hiệu: plan không có Key Lookup |
| **CXPACKET / CXCONSUMER** | Wait trao đổi giữa thread song song | Triệu chứng, không phải nguyên nhân; xem estimate và MAXDOP |
| **DBCC CHECKDB** | Kiểm tra toàn vẹn vật lý và logic của database | Không thể thay thế; phải có lịch **và** alert khi lỗi |
| **DEK** (Database Encryption Key) | Khóa mã hóa dữ liệu của TDE, nằm trong database | Được bảo vệ bởi certificate/khóa bất đối xứng ở `master` hoặc EKM |
| **Delta store** | Vùng rowstore tạm cho insert nhỏ vào columnstore | Batch < 102.400 row đi qua delta store, nén kém |
| **DENY** | Từ chối quyền tường minh | Luôn thắng `GRANT`, trừ `sysadmin` |
| **Differential backup** | Backup mọi page đổi từ full backup gần nhất | Chỉ cần full + diff mới nhất khi restore; phình dần theo tuần |
| **DiskANN** | Thuật toán vector index của SQL Server 2025 | Cho ANN search trên cột `vector` |
| **DDM** (Dynamic Data Masking) | Che giá trị cột ở tầng trả kết quả | **Không phải mã hóa**; có thể dò được bằng predicate |
| **DMV / DMF** | Dynamic Management View/Function | Số liệu tích lũy reset khi restart instance |
| **DOP feedback** | Engine tự giảm MAXDOP nếu song song không giúp | IQP 2022, compat 160 |
| **EKM** (Extensible Key Management) | Khóa gốc nằm trong HSM/Key Vault thay vì `master` | Cho phép rotate và revoke khóa tập trung |
| **ESR** | Equality → Sort → Range: thứ tự cột trong index | Sort trước Range vì range làm mất thứ tự sort |
| **Extent** | 8 page liên tiếp = 64KB | Uniform (một object) hoặc mixed (tối đa 8 object) |
| **Extended Events (XEvents)** | Cơ chế tracing hiện tại, thay SQL Trace/Profiler | Predicate hẹp là điều quan trọng nhất để không tự gây sự cố |
| **FCI** (Failover Cluster Instance) | Một instance di chuyển giữa các node, dùng shared storage | Không có readable secondary; storage là SPOF cho dữ liệu |
| **Filegroup** | Nhóm data file; đơn vị đặt bảng/index/partition | Lý do thật để dùng: piecemeal restore và vòng đời dữ liệu |
| **Filtered index** | Index chỉ trên tập con row theo `WHERE` | Query phải có predicate khớp; unique bỏ qua NULL là ca luôn thắng |
| **FILLFACTOR** | Phần trăm chỗ dùng trên leaf page khi build index | Thấp = ít page split nhưng nhiều page hơn |
| **GAM / SGAM / IAM / PFS** | Các page bản đồ cấp phát | Điểm nóng tranh chấp `PAGELATCH` trong tempdb |
| **Heap** | Bảng không có clustered index | Chỉ hợp cho staging; gây forwarded record |
| **HADR_SYNC_COMMIT** | Wait ở primary khi chờ secondary ack | Tăng đột biến = mạng hoặc log disk của secondary có vấn đề |
| **Implicit conversion** | Engine tự convert kiểu để so sánh | Nguyên nhân #1 của "có index mà vẫn scan" |
| **In-Memory OLTP** | Bảng memory-optimized, lock-free và latch-free | MVCC; ứng dụng **phải** retry 41302/41305/41325/41301 |
| **Incremental statistics** | Statistics riêng theo partition | Làm việc cập nhật rẻ hơn, không làm estimate mịn hơn |
| **Intent lock** (IS/IX/SIX) | Lock ở tầng cao báo hiệu có lock ở tầng dưới | Lý do `SELECT` đang chạy chặn được `ALTER TABLE` |
| **IQP** (Intelligent Query Processing) | Tập tính năng engine tự sửa lỗi kinh điển của optimizer | Phần lớn cần compatibility level tương ứng |
| **Key Lookup** | Quay lại clustered index lấy cột thiếu | Chi phí ẩn lớn nhất trong OLTP; khử bằng `INCLUDE` |
| **LAQ** (Lock After Qualification) | Chỉ lock row thực sự khớp predicate | Một nửa của Optimized Locking (2025) |
| **Ledger table** | Bảng có bằng chứng mật mã chống sửa lịch sử | 2022+; cần digest lưu ngoài mới có giá trị chứng minh |
| **Linked server** | Tham chiếu tới server dữ liệu bên ngoài | Dùng `OPENQUERY` để đẩy predicate; là bề mặt tấn công |
| **Lock escalation** | Chuyển nhiều row lock thành table lock | Phòng bằng chia batch; `LOCK_ESCALATION = AUTO` nếu đã partition |
| **Logical read** | Đọc một page từ buffer pool | Chỉ số tuning ổn định nhất, không dao động theo cache |
| **LSN** (Log Sequence Number) | Số thứ tự tăng đơn điệu của log record | Nền tảng của recovery, differential/log backup, replication, AG |
| **MAXDOP** | Số thread tối đa cho một query | Đặt theo core mỗi NUMA node, tối đa 8 cho OLTP |
| **Memory grant** | Bộ nhớ xin trước cho sort/hash | Quá lớn → `RESOURCE_SEMAPHORE`; quá nhỏ → spill tempdb |
| **MERGE** | Insert/update/delete trong một statement | Source phải unique theo key; cần `HOLDLOCK` |
| **Minimal logging** | Ghi log tối thiểu cho bulk operation | Cần SIMPLE/BULK_LOGGED + `TABLOCK` |
| **mssql-conf** | Công cụ cấu hình SQL Server trên Linux | Thay cho SQL Server Configuration Manager |
| **Nonclustered index** | B-tree riêng, leaf chứa key + row locator | Row locator là clustered key (hoặc RID nếu heap) |
| **OPPO** (Optional Parameter Plan Optimization) | Xử lý query catch-all nhiều tham số tùy chọn | IQP 2025, compat 170 |
| **Optimized Locking** | TID locking + LAQ, giảm mạnh số lock | 2025; cần ADR, khuyến nghị kèm RCSI |
| **Outbox pattern** | Ghi sự kiện nghiệp vụ cùng transaction với dữ liệu | Giải bài toán dual write giữa database và message broker |
| **Page** | Đơn vị I/O 8KB của SQL Server | ~8060 byte khả dụng; mọi đọc/ghi theo page, không theo row |
| **PAGEIOLATCH vs PAGELATCH** | Chờ đọc page từ disk vs chờ latch trên page đã ở RAM | Hai wait rất khác nhau, cách chữa khác nhau hoàn toàn |
| **Page split** | Chèn vào page đầy → chia page | Gây fragmentation và log; nguyên nhân điển hình là clustered key random |
| **Parameter sniffing** | Plan compile theo giá trị tham số lần đầu | Vấn đề số một của tuning; PSP (2022) giảm bớt |
| **Partition elimination** | Bỏ qua partition không liên quan | Chỉ hoạt động khi predicate trực tiếp trên cột partition |
| **Partition function / scheme** | Chia miền giá trị / map khoảng vào filegroup | Với thời gian: luôn `RANGE RIGHT`, biên là mốc đầu kỳ |
| **Piecemeal restore** | Restore theo filegroup, đưa phần nóng online trước | Cách hiệu quả nhất cắt RTO của database rất lớn |
| **PITR** (Point-in-Time Recovery) | Restore về một thời điểm cụ thể | Cần FULL recovery model và chuỗi log backup liên tục |
| **PLE** (Page Life Expectancy) | Số giây kỳ vọng một page còn trong buffer pool | Giá trị tuyệt đối ít nghĩa; **xu hướng** mới là tín hiệu |
| **Plan cache** | Vùng cache execution plan | Nhiều single-use ad-hoc plan = lấy RAM của buffer pool |
| **Plan Guide** | Áp hint cho query không sửa được code | Từ 2022 nên dùng Query Store hints thay thế |
| **PSP** (Parameter Sensitive Plan) optimization | Nhiều plan cho cùng statement theo dải tham số | IQP 2022, compat 160 |
| **PVS** (Persistent Version Store) | Version store của ADR, nằm trong user database | Khác version store của RCSI (nằm ở tempdb) |
| **Query Store** | Lịch sử plan + runtime + wait theo query, lưu bền | Bật `SIZE_BASED_CLEANUP_MODE = AUTO` để không âm thầm thành READ_ONLY |
| **Query Store hints** | Áp hint theo `query_id` không sửa câu SQL | 2022+; công cụ giá trị nhất cho SQL do ORM sinh |
| **RANGE vs ROWS** (window frame) | Theo giá trị vs theo số row vật lý | Luôn viết frame tường minh; mặc định là `RANGE` |
| **RCSI** (Read Committed Snapshot Isolation) | READ COMMITTED thực hiện bằng row versioning | Thay đổi cấu hình có tỷ lệ lợi ích/công sức cao nhất cho OLTP |
| **Recovery model** | SIMPLE / FULL / BULK_LOGGED | FULL mà không có job `BACKUP LOG` là sự cố chờ xảy ra |
| **Replication** (transactional) | Phân phối tập con dữ liệu tới nhiều subscriber | Không phải HA; chặn truncate log như CDC |
| **RESOURCE_SEMAPHORE** | Wait khi chờ memory grant | Query khác đang giữ grant quá lớn |
| **RESUMABLE index** | Rebuild/create có thể `PAUSE`/`RESUME` | 2017+/2019+; rất giá trị cho cửa sổ bảo trì ngắn |
| **RID** (Row Identifier) | `file:page:slot`, định vị row trong heap | Row locator của nonclustered index khi bảng là heap |
| **RLS** (Row-Level Security) | Lọc/chặn row theo ngữ cảnh người dùng | Luôn cặp `FILTER` với `BLOCK` predicate |
| **ROWVERSION** | Kiểu nhị phân 8 byte tự tăng khi row bị sửa | Token optimistic concurrency; **không phải** timestamp |
| **RPO / RTO** | Lượng dữ liệu / thời gian tối đa được phép mất | RPO quyết định tần suất backup; RTO quyết định chiến lược restore |
| **SARGable** | Predicate dùng được index seek | Hàm bọc quanh cột phá SARGability |
| **Savepoint** | Điểm lùi từng phần trong transaction | Không dùng được với distributed transaction hay transaction doomed |
| **Segment elimination** | Bỏ qua column segment ngoài dải min/max | Nguồn tốc độ của columnstore, cùng với nén và batch mode |
| **SESSION_CONTEXT** | Cặp key-value theo session | Dùng với RLS; đặt `@read_only = 1` để chống ghi đè |
| **Signal wait** | Thời gian chờ **CPU** sau khi đã có resource | Tỉ lệ signal/resource cao = CPU pressure |
| **Sliding window** | Mẫu thêm partition mới + bỏ partition cũ nhất | Chỉ SPLIT/MERGE partition rỗng |
| **SQLOS** | Lớp điều phối riêng của SQL Server (cooperative scheduling) | Giải thích RUNNING/SUSPENDED/RUNNABLE và mọi wait stats |
| **SQLPAL** | Lớp ánh xạ Windows API sang Linux | Lý do engine trên Linux giống hệt Windows về hành vi |
| **Statistics** | Phân bố dữ liệu để optimizer estimate | Histogram chỉ có cho **cột đầu tiên** của key |
| **SWITCH** (partition) | Tráo partition với bảng khác, chỉ metadata | Mili giây thay cho `DELETE` hàng giờ; cần aligned index |
| **Tail-log backup** | Backup phần log chưa được backup trước khi restore | Bỏ qua = mất dữ liệu một cách không cần thiết |
| **TDE** (Transparent Data Encryption) | Mã hóa data/log file và backup | Bảo vệ file bị lấy, **không** bảo vệ khỏi DBA; mã hóa cả tempdb |
| **tempdb** | Không gian tạm dùng chung toàn instance | Nhiều file bằng nhau; version store nằm ở đây |
| **THROW** | Ném lỗi giữ nguyên error number gốc | Dùng `THROW;` không tham số, không `RAISERROR` |
| **TID locking** | Lock trên transaction ID thay vì từng row | Một nửa của Optimized Locking (2025) |
| **Tuple mover** | Nén delta store đầy thành rowgroup | Có thể ép bằng `REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON)` |
| **TVP** (Table-Valued Parameter) | Truyền một bảng làm tham số | Cách đúng để truyền danh sách id từ ứng dụng |
| **U lock** (Update) | Lock ở bước tìm-để-sửa | Tồn tại để chống deadlock chuyển đổi S→X |
| **UNMASK** | Quyền xem dữ liệu thật của cột bị mask | 2022+: cấp được theo từng cột |
| **VECTOR_DISTANCE** | Hàm tính khoảng cách giữa hai vector | 2025; metric phải khớp model sinh embedding |
| **VLF** (Virtual Log File) | Đơn vị chia nhỏ trong transaction log | Hàng nghìn VLF nhỏ làm chậm khởi động, log backup, recovery |
| **WAL** (Write-Ahead Logging) | Log xuống disk trước khi commit trả về | Durability đến từ log, **không** từ data file |
| **Wait stats** | Thống kê thời gian chờ theo loại | Tích lũy từ lần restart; chụp hai lần lấy hiệu để đo cửa sổ |
| **WINDOW clause** | Đặt tên định nghĩa window dùng lại | 2022+; cải thiện tính đọc được, không phải hiệu năng |
| **WRITELOG** | Wait chờ log xuống disk | Log storage chậm hoặc quá nhiều commit nhỏ |
| **WSFC** | Windows Server Failover Cluster | Trên Linux thay bằng Pacemaker (`CLUSTER_TYPE = EXTERNAL`) |
| **XACT_ABORT** | `SET XACT_ABORT ON`: lỗi runtime làm transaction doomed | Nên bật ở đầu mọi procedure có transaction |
| **XACT_STATE()** | Trạng thái transaction: 1 / -1 / 0 | Dùng thay cho `@@TRANCOUNT` trong `CATCH` |

---

## Mã lỗi thường gặp và cách xử lý

| Error | Nghĩa | Xử lý |
|---|---|---|
| **601** | Scan bị hủy do dữ liệu di chuyển (`NOLOCK`) | Bỏ `NOLOCK`, bật RCSI |
| **1205** | Transaction là deadlock victim | Retry với backoff **có jitter** |
| **1222** | Hết `LOCK_TIMEOUT` | Retry, hoặc giảm phạm vi transaction |
| **823 / 824 / 825** | Lỗi I/O / checksum sai / đọc lại mới thành công | Corruption: kiểm tra `suspect_pages`, CHECKDB, storage |
| **3960** | Snapshot isolation update conflict | Retry ở ứng dụng |
| **8672** | `MERGE` gặp nhiều row khớp cùng key | Gộp/khử trùng source trước |
| **9002** | Transaction log đầy | Xem `log_reuse_wait_desc`, chạy `BACKUP LOG` |
| **41302 / 41305 / 41325 / 41301** | Validation failure của In-Memory OLTP | Retry ở ứng dụng |
| **PKIX path building failed** (driver) | Không xác minh được certificate server | Cài certificate vào truststore; không dùng `trustServerCertificate=true` trên production |

---

*Cập nhật lần cuối: 2026-07-30*
