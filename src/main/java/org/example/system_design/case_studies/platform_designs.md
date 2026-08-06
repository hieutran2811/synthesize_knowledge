# Case Studies – Platform (Object Storage, Typeahead, Payment, Notification)

> Chủ đề bổ sung 2026-07. Bốn bài ở mức nâng cao, mỗi bài đại diện một lớp vấn đề khác nhau: **durability**, **precompute cho đọc**, **đúng đắn tiền tệ**, và **fan-out có bảo đảm**.
>
> Áp dụng RESHADED ([../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md)). Tra cứu nhanh: [System Design Glossary](../glossary.md). Tiếp nối [realtime_scale_designs.md](realtime_scale_designs.md).

---

# 1. Object Storage (S3-like)

Bài này dạy về **durability và tách metadata khỏi dữ liệu** — hai khái niệm áp dụng cho mọi hệ lưu trữ.

## 1.1 Requirements

**Functional**: PUT/GET/DELETE object theo `(bucket, key)`; list theo prefix; multipart upload cho file lớn; versioning.
**Ngoài phạm vi**: chỉnh sửa một phần object (object storage là immutable — ghi lại toàn bộ).

**Non-functional**
- **Durability rất cao** (mốc thường công bố là 11 số 9) — đây là yêu cầu định hình toàn bộ thiết kế.
- Availability 99,99%.
- Object từ vài KB tới vài TB.
- Chi phí lưu trữ phải thấp (đây là sản phẩm cạnh tranh bằng giá).

Điểm cần nói ra ngay: **object storage không phải file system**. Không có rename rẻ, không có append, không có lock; list theo prefix là thao tác đắt. Nhiều thiết kế sai vì coi nó như NFS.

## 1.2 Estimation

```text
100 PB dữ liệu · 1 tỉ object · trung bình 100 KB/object
Read 50K QPS · Write 5K QPS

Metadata: 1 tỉ × ~1 KB = 1 TB → vừa một cụm database phân tán (KHÔNG cần object storage cho metadata)
Dữ liệu:  100 PB → replication 3× = 300 PB, hoặc erasure coding 1,5× = 150 PB
          → chênh lệch 150 PB → erasure coding tiết kiệm khoảng một nửa chi phí
```

Con số cuối là lý do mọi hệ object storage quy mô lớn dùng erasure coding thay vì replication thuần.

## 1.3 Design

```text
Client → LB → API Service (xác thực, kiểm quyền, tính chữ ký)
                │
                ├─→ Metadata Service → Metadata Store (phân tán, có index)
                │      (bucket, key, version) → { size, etag, chunk_ids, storage_class, ... }
                │
                └─→ Data Service → Placement (chọn node/rack) → Storage Nodes (đĩa)
                                                                   ↓
                                            Background: repair, scrubbing, tiering, GC
```

**Tách metadata khỏi dữ liệu** là quyết định kiến trúc trung tâm:

| | Metadata | Dữ liệu |
|---|---|---|
| Kích thước | 1 TB | 100 PB |
| Yêu cầu | Truy vấn được, index prefix, transaction nhẹ | Chỉ cần đọc/ghi theo id, bền |
| Store | Database phân tán (có index, có thứ tự khóa) | Đĩa thô + erasure coding |
| Mở rộng | Sharding theo bucket/key prefix | Thêm node/rack |

Nếu trộn hai thứ, bạn vừa phải gánh yêu cầu truy vấn của metadata cho 100 PB, vừa phải gánh chi phí lưu trữ của dữ liệu cho phần metadata. Tách ra cho phép tối ưu mỗi phần theo đúng đặc tính của nó.

## 1.4 Deep dive – durability

**Replication vs erasure coding**:

```text
Replication 3×:
  cùng dữ liệu ở 3 nơi → chịu mất 2 bản → overhead 200%
  đọc rất đơn giản (đọc bất kỳ bản nào), sửa lỗi = copy lại

Erasure coding (ví dụ 6 data + 3 parity = 9 shard):
  chia object thành 6 phần + tính 3 phần parity
  chịu mất BẤT KỲ 3 shard → overhead chỉ 50%
  đọc cần gom ≥ 6 shard; sửa lỗi cần đọc 6 shard để tính lại 1 shard
```

| | Replication | Erasure coding |
|---|---|---|
| Overhead dung lượng | 200% (3×) | ~50% (6+3) |
| Độ trễ đọc | Thấp nhất | Cao hơn (phải gom nhiều shard) |
| Chi phí sửa lỗi | Thấp (copy) | **Cao** (đọc nhiều shard, tính toán) |
| Phù hợp | Object nhỏ, đọc nóng | Object lớn, dữ liệu lạnh |

Chiến lược thực tế: **replication cho object nhỏ và nóng, erasure coding cho object lớn và lạnh**, chuyển đổi tự động theo tuổi và tần suất truy cập (tiering).

**Placement**: shard phải được đặt trên các **failure domain** khác nhau — khác đĩa, khác node, khác rack, khác nguồn điện, và với durability cao nhất là khác AZ. Đặt 9 shard trên 9 đĩa cùng một rack thì mất rack là mất object, dù toán học nói chịu được 3 lỗi.

**Silent data corruption và scrubbing**: đĩa có thể trả về dữ liệu sai mà không báo lỗi (bit rot). Vì vậy mọi shard được lưu kèm **checksum**, và có tiến trình nền **scrubbing** đọc lại toàn bộ dữ liệu định kỳ để phát hiện và sửa. Đây là phần thường bị bỏ khi thiết kế nhưng lại là điều kiện để đạt được durability cao.

## 1.5 Deep dive – các chi tiết API

**Multipart upload**: file 5 TB không thể là một request. Chia thành part (5 MB–5 GB), upload song song, có thể retry từng part, rồi `CompleteMultipartUpload` gộp lại. Lợi ích phụ: mất mạng chỉ mất một part, không mất cả file.

**Consistency của list**: `PUT` xong rồi `LIST` có thấy ngay không? Đây là câu hỏi hay bị bỏ qua. S3 từng là eventual cho list (gây nhiều bug thực tế) và sau này chuyển sang strong read-after-write. Nếu metadata store có transaction thì đạt được strong; nếu index prefix là cấu trúc bất đồng bộ thì phải chấp nhận eventual — và phải nói rõ với người dùng API.

**Xóa và garbage collection**: xóa object là xóa metadata (nhanh) + đánh dấu chunk để dọn sau (chậm). Với versioning bật, "xóa" là thêm một delete marker chứ không xóa gì. GC phải rất cẩn thận: xóa chunk còn được tham chiếu là mất dữ liệu không thể phục hồi.

**Hot object**: một file được tải đồng thời bởi hàng triệu người (bản cập nhật game, video viral). Object storage không giải quyết việc này — **CDN ở phía trước** giải quyết. Đây là lý do mọi kiến trúc phân phối file đều là object storage + CDN.

## 1.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Replication vs erasure coding | Đọc nhanh, sửa lỗi rẻ ↔ tiết kiệm ~50% dung lượng |
| Metadata trong DB phân tán | Truy vấn tốt ↔ thêm một hệ thống phải scale |
| Strong vs eventual list | API dễ dùng đúng ↔ index đơn giản và nhanh hơn |
| Tiering tự động | Chi phí thấp hơn nhiều ↔ độ trễ tăng cho dữ liệu lạnh, logic phức tạp |
| Scrubbing thường xuyên | Phát hiện bit rot sớm ↔ tốn I/O nền |

---

# 2. Typeahead / Autocomplete

Bài này dạy về **precompute cho đường đọc** và mẫu **filter rẻ trước, xếp hạng đắt sau**.

## 2.1 Requirements

**Functional**: gợi ý top-K từ khóa theo prefix người dùng đang gõ; xếp theo mức phổ biến; cá nhân hóa nhẹ (tùy chọn).

**Non-functional**
- **p99 < 50ms** — người dùng gõ tiếp sau ~200ms, chậm hơn là vô dụng.
- QPS rất cao: mỗi ký tự gõ là một request.
- Dữ liệu gợi ý cập nhật theo giờ/ngày là đủ (**không cần real-time**).

Yêu cầu độ trễ và tần suất cập nhật thấp là hai điều kiện cho phép **precompute mọi thứ** — đó là ý tưởng trung tâm của bài.

## 2.2 Estimation

```text
10M DAU · 10 lần tìm kiếm/ngày · mỗi lần gõ ~15 ký tự → ~10 request (có debounce)

QPS = 10M × 10 × 10 / 10⁵ = 10.000 → đỉnh 30K QPS
Với debounce 150ms ở client: giảm còn ~1/3 → 10K QPS đỉnh

Từ vựng: 100M truy vấn phân biệt, nhưng chỉ ~1M chiếm 99% lưu lượng (Zipf)
  → precompute top-K cho 1M prefix phổ biến là đủ
  → 1M prefix × 10 gợi ý × 50 B ≈ 500 MB → vừa RAM
```

## 2.3 Design

```text
ĐƯỜNG ĐỌC (nóng, phải rất nhanh):
Client (debounce 150ms) → CDN/edge cache → Suggestion Service
                                             → Redis/in-memory: prefix → [top-K đã sắp]
                                             → trả ngay, KHÔNG tính toán gì

ĐƯỜNG GHI (nguội, chạy theo lô):
Search logs → Kafka → Aggregation job (mỗi giờ)
                        → đếm tần suất theo cửa sổ thời gian
                        → lọc (chặn từ khóa xấu, bỏ truy vấn quá hiếm)
                        → build map prefix → top-K
                        → nạp atomic vào store đọc (đổi version, không sửa tại chỗ)
```

Tách hoàn toàn hai đường là điều làm bài này khả thi: đường đọc **không làm gì ngoài tra cứu**, mọi tính toán đã xong ở đường ghi.

## 2.4 Deep dive – cấu trúc dữ liệu

| Cấu trúc | Cơ chế | Đánh đổi |
|---|---|---|
| **Trie thuần** | Cây theo ký tự, mỗi node lưu top-K của subtree | Tra cứu O(độ dài prefix); tốn RAM; build lại chậm |
| **Trie + top-K cached ở node** | Như trên nhưng top-K sắp sẵn tại mỗi node | Đọc cực nhanh; RAM lớn hơn |
| **Hash map prefix → top-K** | Precompute mọi prefix phổ biến | **Đơn giản nhất, nhanh nhất**; không xử lý prefix lạ |
| **Redis sorted set theo prefix** | `ZREVRANGE prefix:abc 0 9` | Dễ triển khai, cập nhật từng phần được |
| **Elasticsearch completion suggester** | FST (finite state transducer) | Có sẵn, hỗ trợ fuzzy; thêm một hệ thống |

Với yêu cầu ở mục 2.1, **hash map prefix → top-K** thường là câu trả lời đúng và bị đánh giá thấp: nó đơn giản, độ trễ ổn định, và bài toán "prefix lạ không có trong map" xử lý bằng fallback sang Elasticsearch hoặc trả rỗng.

Trie đáng dùng khi cần tiết kiệm RAM (prefix chia sẻ node) hoặc cần hỗ trợ prefix bất kỳ, không chỉ prefix phổ biến.

## 2.5 Deep dive – các vấn đề thực tế

**Cập nhật không downtime**: không sửa store đọc tại chỗ. Build phiên bản mới hoàn chỉnh (`suggest:v42`), rồi đổi con trỏ atomic (`SET suggest:current v42`). Điều này đảm bảo không có thời điểm nào dữ liệu ở trạng thái nửa vời — cùng nguyên tắc với versioned key ở [caching.md](../fundamentals/caching.md) mục 5.1.

**Debounce và cancel ở client**: gõ "iphone" tạo 6 request nếu không debounce. Debounce 150ms + **hủy request cũ** khi có ký tự mới giảm cả tải server và tránh hiển thị kết quả lỗi thời (response của "ipho" về sau response của "iphone").

**Xu hướng và độ mới**: đếm tần suất trên toàn bộ lịch sử làm gợi ý cũ kỹ. Dùng **cửa sổ thời gian có suy giảm** (ví dụ đếm 7 ngày với trọng số giảm dần theo ngày) để từ khóa đang thịnh hành nổi lên.

**Từ khóa cần chặn**: gợi ý là nơi rất dễ gây sự cố về mặt nội dung (autocomplete gợi ý cụm từ xúc phạm). Cần danh sách chặn được áp dụng ở **đường ghi** (không lọc lúc đọc, vì lọc lúc đọc làm chậm và dễ bỏ sót).

**Cá nhân hóa**: đây là nơi mẫu **filter rẻ trước, xếp hạng đắt sau** xuất hiện lại — lấy top-50 từ store chung (rẻ), rồi xếp lại 50 ứng viên theo lịch sử người dùng (đắt hơn nhưng chỉ 50 phần tử). Cùng mẫu với ranking feed và với ETA trong bài geo.

**Lỗi chính tả**: fuzzy matching (edit distance) đắt hơn nhiều so với prefix match. Cách thực tế: thử prefix match trước; nếu không có kết quả thì mới fallback sang fuzzy (Elasticsearch/SymSpell).

## 2.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Precompute vs tính lúc đọc | p99 rất thấp, ổn định ↔ dữ liệu trễ theo chu kỳ build |
| Hash map vs trie | Đơn giản, nhanh nhất ↔ RAM và hỗ trợ prefix bất kỳ |
| Debounce dài | Ít request hơn ↔ cảm giác chậm hơn |
| Cá nhân hóa | Liên quan hơn ↔ không cache chung được, đường đọc nặng hơn |
| Fuzzy mặc định | Chịu lỗi chính tả ↔ chậm và có gợi ý lạ |

---

# 3. Payment / Ledger

Bài này dạy về **đúng đắn tiền tệ**: idempotency, exactly-once nghiệp vụ, và đối soát.

## 3.1 Requirements

**Functional**: khởi tạo thanh toán; gọi payment provider; ghi nhận kết quả; hoàn tiền; xem lịch sử giao dịch.

**Non-functional — khác hoàn toàn các bài trên**
- **Không được trừ tiền hai lần** (đây là yêu cầu tuyệt đối, không phải "cố gắng").
- Không được mất giao dịch.
- Phải **đối soát được** với provider và với sổ sách nội bộ.
- Availability quan trọng nhưng **thấp hơn tính đúng đắn** — thà từ chối giao dịch còn hơn xử lý sai.

Câu cuối là điều phải nói ra: với thanh toán, đánh đổi mặc định của system design bị đảo. Ở mọi bài khác ta chọn availability; ở đây ta chọn correctness.

## 3.2 Nguyên tắc cốt lõi: idempotency

```text
Vấn đề: client gửi "trừ 100.000đ", mạng timeout.
        Client KHÔNG BIẾT server đã xử lý chưa. Retry → nguy cơ trừ hai lần.

Giải: client sinh idempotency key (UUID) và gửi kèm MỌI lần thử của CÙNG một ý định.
      Server: key đã thấy → trả lại kết quả CŨ, không xử lý lại.
```

```sql
-- Bảng idempotency là hợp đồng, không phải cache
CREATE TABLE payment_requests (
    idempotency_key  VARCHAR(64) PRIMARY KEY,
    request_hash     VARCHAR(64) NOT NULL,   -- chống dùng cùng key cho payload khác
    status           VARCHAR(20) NOT NULL,   -- IN_PROGRESS / SUCCEEDED / FAILED
    payment_id       BIGINT NULL,
    response_body    TEXT NULL,
    created_at       TIMESTAMP NOT NULL,
    expires_at       TIMESTAMP NOT NULL
);
```

```text
Luồng xử lý:
1. INSERT idempotency_key với status=IN_PROGRESS
   → nếu vi phạm unique:
       • bản ghi cũ SUCCEEDED/FAILED → trả response_body cũ (KHÔNG xử lý lại)
       • bản ghi cũ IN_PROGRESS      → trả 409 "đang xử lý, hãy thử lại sau"
   → nếu request_hash khác bản ghi cũ → trả 422 (dùng sai key)
2. Xử lý nghiệp vụ trong transaction
3. UPDATE status = SUCCEEDED/FAILED, lưu response_body
```

Ba chi tiết làm nên sự khác biệt giữa idempotency đúng và gần đúng:

1. **`request_hash`**: chống việc client tái sử dụng key cho một payload khác — nếu không kiểm tra, một bug ở client có thể khiến giao dịch B trả về kết quả của giao dịch A.
2. **Trạng thái `IN_PROGRESS`**: xử lý đúng ca hai request đồng thời cùng key.
3. **Bản ghi được ghi trước khi xử lý**, không phải sau — nếu ghi sau, crash giữa hai bước làm mất tính idempotent.

## 3.3 Design

```text
Client → Payment API (idempotency key bắt buộc)
           → INSERT payment_requests + payments(status=PENDING)  [một transaction]
           → publish "payment.initiated" → queue
           ↓
       Payment Worker
           → gọi provider (Stripe/VNPay...) với idempotency key TRUYỀN TIẾP
           → cập nhật payments theo kết quả
           → publish "payment.succeeded|failed"
           ↓
       Consumer: cập nhật đơn hàng, gửi thông báo, ghi ledger

Provider → Webhook → Webhook Handler (xác thực chữ ký, idempotent theo event_id)
                       → cập nhật trạng thái (nguồn sự thật cuối cùng)

Reconciliation Job (mỗi giờ / mỗi ngày)
   → so sánh giao dịch nội bộ với báo cáo của provider
   → phát hiện lệch → cảnh báo cho người xử lý
```

Điểm quan trọng: **truyền idempotency key xuống provider**. Mọi payment provider lớn đều hỗ trợ; không truyền thì retry ở tầng worker có thể tạo giao dịch trùng ở phía provider — nơi bạn không kiểm soát được.

## 3.4 Deep dive – ledger double-entry

```sql
-- Mỗi biến động tiền là một cặp bút toán; tổng luôn bằng 0
CREATE TABLE ledger_entries (
    entry_id     BIGINT PRIMARY KEY,
    txn_id       VARCHAR(64) NOT NULL,        -- nhóm các bút toán của một giao dịch
    account_id   BIGINT NOT NULL,
    direction    CHAR(1) NOT NULL,            -- 'D' debit / 'C' credit
    amount       DECIMAL(19,4) NOT NULL,      -- KHÔNG dùng float
    currency     CHAR(3) NOT NULL,
    created_at   TIMESTAMP NOT NULL
);
-- Bất biến: với mọi txn_id, SUM(credit) - SUM(debit) = 0
```

Ba quy tắc bất di bất dịch của ledger:

| Quy tắc | Vì sao |
|---|---|
| **Append-only, không bao giờ UPDATE/DELETE** | Sửa lịch sử là mất khả năng đối soát; sai thì ghi bút toán đảo (reversal) |
| **`DECIMAL`, không `FLOAT`** | `0.1 + 0.2 != 0.3` với số thực nhị phân; tiền phải chính xác tuyệt đối |
| **Số dư là kết quả tính từ ledger** | Có thể cache số dư, nhưng ledger là nguồn sự thật; số dư cache phải kiểm chứng được lại |

Quy tắc "ghi bút toán đảo thay vì sửa" là điều phân biệt hệ thống tài chính với hệ thống thường: bạn không xóa một sai sót, bạn ghi lại việc sửa nó. Đó là cách duy nhất để trả lời được "tại thời điểm đó số dư là bao nhiêu và vì sao".

## 3.5 Deep dive – các vấn đề khác

**Webhook không đáng tin**: provider có thể gửi trùng, gửi sai thứ tự, hoặc không gửi. Xử lý: xác thực chữ ký; idempotent theo `event_id`; **không tin thứ tự** (dùng timestamp/version của event để bỏ qua event cũ hơn trạng thái hiện tại); và **có job polling dự phòng** để lấy trạng thái với những giao dịch treo quá lâu.

**Trạng thái treo**: giao dịch `PENDING` mãi vì worker crash hoặc provider không phản hồi. Cần job quét giao dịch `PENDING` quá N phút → chủ động query provider → cập nhật hoặc đưa vào hàng đợi xử lý tay. Không có job này, tiền của khách hàng "biến mất" theo cảm nhận của họ.

**Không dùng distributed transaction với provider**: không thể có 2PC với Stripe. Mẫu đúng là Saga với bước bù trừ (refund/void) — xem `advanced/distributed_transactions.md`.

**Đối soát là bắt buộc, không phải tùy chọn**: mọi hệ thống thanh toán sẽ lệch tại một thời điểm nào đó (webhook mất, timeout mơ hồ, lỗi con người). Job đối soát so sánh ba nguồn — giao dịch nội bộ, ledger, và báo cáo provider — và cảnh báo khi lệch. Không có nó, lệch sẽ được phát hiện bởi kế toán hoặc khách hàng, muộn hơn nhiều.

**Xử lý tiền tệ và làm tròn**: lưu số nguyên đơn vị nhỏ nhất (xu) hoặc `DECIMAL` với scale đủ; quy tắc làm tròn phải được viết ra và nhất quán; giao dịch đa tiền tệ phải lưu cả tỉ giá đã dùng và thời điểm.

## 3.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Idempotency key bắt buộc | An toàn tuyệt đối ↔ client phải sinh và giữ key |
| Xử lý bất đồng bộ qua queue | Chịu tải, retry được ↔ trạng thái eventual, cần UI "đang xử lý" |
| Webhook làm nguồn sự thật | Phản ánh đúng phía provider ↔ phải xử lý trùng/sai thứ tự/mất |
| Double-entry ledger | Đối soát được, audit được ↔ nhiều bản ghi hơn, code phức tạp hơn |
| Cache số dư | Đọc nhanh ↔ phải có cách kiểm chứng lại từ ledger |
| Chọn correctness > availability | Không sai tiền ↔ có lúc từ chối giao dịch |

---

# 4. Notification System

Bài này dạy về **fan-out có bảo đảm** qua nhiều kênh với độ tin cậy khác nhau.

## 4.1 Requirements

**Functional**: gửi thông báo qua push (APNs/FCM), email, SMS, in-app; theo tuỳ chọn của người dùng; hỗ trợ template và đa ngôn ngữ; gửi theo lô (campaign).

**Non-functional**
- At-least-once + **dedup** (thà chậm hơn là mất; nhưng không được spam trùng).
- Chịu được đột biến (một campaign gửi 10M thông báo).
- Tôn trọng rate limit của từng nhà cung cấp.
- Không gửi cho người đã tắt kênh đó (yêu cầu tuân thủ, không chỉ UX).

## 4.2 Estimation

```text
Hằng ngày: 50M push · 5M email · 500K SMS
QPS trung bình push = 50M / 10⁵ = 500 → nhưng CAMPAIGN tạo đột biến:
  10M thông báo trong 10 phút = 16.700 QPS  ← đây là con số phải thiết kế theo

Rate limit nhà cung cấp: giả sử FCM cho 10K/s, provider SMS cho 100/s
  → SMS: 500K / 100 = 5.000 giây ≈ 1,4 giờ để gửi hết
  → PHẢI có hàng đợi riêng theo kênh, với tốc độ khác nhau
```

Nhận xét cuối là điều làm bài này thú vị: các kênh có **thông lượng chênh nhau hai bậc độ lớn**, nên không thể dùng một hàng đợi chung.

## 4.3 Design

```text
Producer (service nghiệp vụ) → Notification API → validate + tra preference
                                                 → INSERT notification (dedup key)
                                                 → publish vào Kafka theo KÊNH
                                                       ↓
   ┌───────────────────┬───────────────────┬──────────────────┐
   │ topic: push       │ topic: email      │ topic: sms       │  ← hàng đợi riêng mỗi kênh
   ▼                   ▼                   ▼
Push Workers        Email Workers       SMS Workers            ← scale và rate limit độc lập
   │ APNs/FCM          │ SES/SendGrid      │ Twilio/nhà mạng
   ▼                   ▼                   ▼
Delivery tracking (đã gửi / đã nhận / mở / lỗi) → analytics + retry
   │
   └─ lỗi vĩnh viễn → DLQ → xử lý tay hoặc tắt kênh (token không hợp lệ)
```

## 4.4 Deep dive

**Ba tầng dedup**: đây là nơi hệ thống thông báo hay gây sự cố (gửi 5 lần cùng một tin).

```text
1. Dedup theo dedup_key ở tầng API
   key = hash(user_id, event_type, entity_id, cửa_sổ_thời_gian)
   → INSERT ... ON CONFLICT DO NOTHING → cùng sự kiện gửi lại không tạo thông báo mới

2. Idempotent ở worker
   → worker retry (do crash, do rebalance Kafka) không gửi lại nếu đã có bản ghi "đã gửi"

3. Gộp và làm mượt ở tầng nghiệp vụ (throttling)
   → "5 người đã thích bài của bạn" thay vì 5 thông báo
   → giới hạn số thông báo mỗi user mỗi giờ
```

Tầng thứ ba không phải kỹ thuật mà là sản phẩm, nhưng nó là nơi giá trị lớn nhất: người dùng tắt thông báo vì bị spam, và một khi đã tắt thì kênh đó mất vĩnh viễn.

**Preference và tuân thủ**: bảng `user_channel_preference (user_id, channel, category, enabled)`. Kiểm tra ở **tầng API**, trước khi vào hàng đợi — không kiểm ở worker, vì thông báo có thể nằm trong hàng đợi hàng giờ và người dùng đã tắt trong lúc đó. Với email marketing còn phải có unsubscribe link và tôn trọng nó ngay.

**Retry theo loại lỗi** — không phải lỗi nào cũng retry:

| Loại lỗi | Ví dụ | Xử lý |
|---|---|---|
| Tạm thời | Timeout, 503, rate limit | Retry với backoff + jitter |
| Vĩnh viễn | Token không hợp lệ, email bounce cứng, số không tồn tại | **Không retry**; vô hiệu hóa token/địa chỉ |
| Nghiệp vụ | Người dùng đã tắt kênh | Bỏ, ghi log |

Xử lý bounce cứng đúng cách quan trọng cho email: tiếp tục gửi tới địa chỉ không tồn tại làm giảm uy tín domain gửi (sender reputation) và cuối cùng làm mọi email của bạn vào spam.

**Điều tiết theo rate limit nhà cung cấp**: worker phải tự giới hạn tốc độ, không phụ thuộc nhà cung cấp trả 429. Dùng token bucket dùng chung (xem [foundational_designs.md](foundational_designs.md) mục 3) với `capacity` và `refill` theo hợp đồng với nhà cung cấp.

**Campaign vs transactional**: đây là phân biệt quan trọng cần thiết kế từ đầu.

| | Transactional | Campaign/marketing |
|---|---|---|
| Ví dụ | OTP, xác nhận đơn hàng | Khuyến mãi, thông báo tính năng |
| Độ ưu tiên | **Cao nhất** | Thấp |
| Độ trễ chấp nhận | Giây | Giờ |
| Hàng đợi | Riêng, ưu tiên cao | Riêng, tốc độ có kiểm soát |

Không tách hai loại là sai lầm kinh điển: một campaign 10M thông báo sẽ làm OTP của khách hàng đến sau 40 phút — và OTP đến sau 40 phút là OTP vô dụng.

**Thông báo có thời hạn**: "xe của bạn đã tới" gửi sau 30 phút là vô nghĩa và gây khó chịu. Mọi thông báo nên có `expires_at`; worker bỏ qua thông báo đã hết hạn thay vì gửi muộn.

## 4.5 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Hàng đợi riêng theo kênh | Rate limit và scale độc lập ↔ nhiều topic/consumer group phải quản |
| Tách transactional/campaign | OTP không bị campaign chặn ↔ thêm hạ tầng |
| At-least-once + dedup | Không mất thông báo ↔ phải có khóa dedup và store cho nó |
| Gộp thông báo | Người dùng không bị spam ↔ độ trễ tăng, logic nghiệp vụ phức tạp |
| Kiểm preference ở API | Đúng tại thời điểm gửi vào hàng đợi ↔ có thể lệch nếu hàng đợi rất dài (dùng expires_at) |
| Nhiều nhà cung cấp cho một kênh | Chịu được nhà cung cấp chết | Phức tạp: chuẩn hóa lỗi, theo dõi tỉ lệ gửi thành công theo từng nhà cung cấp |

---

## Ghi chú – chủ đề tiếp theo

- [foundational_designs.md](foundational_designs.md), [realtime_scale_designs.md](realtime_scale_designs.md): các bài trước.
- [../fundamentals/storage_retrieval.md](../fundamentals/storage_retrieval.md): checksum, erasure coding liên quan tới durability.
- [../fundamentals/availability_reliability.md](../fundamentals/availability_reliability.md): retry, backoff, phân lớp tính năng.
- [../fundamentals/caching.md](../fundamentals/caching.md): precompute và versioned key trong bài typeahead.
- `advanced/distributed_transactions.md`: Saga, idempotency — nền của bài payment.
- `advanced/event_driven_architecture.md`: Outbox, event-driven fan-out.
- [kafka event-driven](../../kafka/patterns/event_driven_architecture.md), [elasticsearch package](../../elasticsearch/roadmap.md).

Từ khóa mở rộng: 11 nines durability, erasure coding (Reed-Solomon), failure domain, bit rot và scrubbing, multipart upload, read-after-write consistency, FST/completion suggester, debounce + request cancellation, decay window ranking, idempotency key + request hash, double-entry ledger, reversal entry, reconciliation, hard vs soft bounce, sender reputation, DLQ, expires_at cho thông báo.

---

*Cập nhật lần cuối: 2026-07-30*
