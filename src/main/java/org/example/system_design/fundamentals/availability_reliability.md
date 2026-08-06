# Availability & Reliability – Sẵn sàng và tin cậy

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Scalability](scalability.md). Đọc tiếp: [Distributed Systems Theory](distributed_systems_theory.md).

---

## 1. Bốn thuộc tính hay bị gộp làm một

| Thuộc tính | Định nghĩa | Câu hỏi |
|---|---|---|
| **Availability** | `Uptime / (Uptime + Downtime)` — % thời gian phục vụ được | Hệ thống có trả lời không? |
| **Reliability** | Xác suất hoạt động **đúng** trong một khoảng thời gian | Nó trả lời **đúng** không? |
| **Durability** | Xác suất **không mất dữ liệu** | Dữ liệu đã ghi có còn không? |
| **Fault tolerance** | Vẫn hoạt động khi một phần bị lỗi | Mất một node thì sao? |

Phân biệt này không phải chuyện thuật ngữ. Một hệ thống có availability 100% mà trả về dữ liệu sai thì reliability bằng 0. Một hệ thống HA hoàn hảo với replication đồng bộ vẫn mất dữ liệu nếu ai đó `DELETE` sai — vì durability và fault tolerance là hai bài toán khác nhau.

Cách nghĩ đúng: **availability bảo vệ khỏi mất hạ tầng; backup bảo vệ khỏi mất dữ liệu; hai thứ đều cần**.

---

## 2. SLI, SLO, SLA và error budget

```text
SLI (Indicator)  : số đo thực tế       → "99.94% request trả 2xx/3xx trong 30 ngày qua"
SLO (Objective)  : mục tiêu nội bộ     → "≥ 99.9% request thành công, p99 < 300ms"
SLA (Agreement)  : cam kết có chế tài  → "uptime ≥ 99.5%, vi phạm thì hoàn 10% phí"

Luôn: SLO nghiêm ngặt hơn SLA (SLO là hàng rào cảnh báo trước khi vi phạm hợp đồng)
```

### 2.1 Bảng "the nines"

| Availability | Downtime/năm | /tháng | /tuần |
|---|---|---|---|
| 99% | 3,65 ngày | 7,2 giờ | 1,68 giờ |
| 99,9% | 8,76 giờ | 43,8 phút | 10,1 phút |
| 99,95% | 4,38 giờ | 21,9 phút | 5,04 phút |
| 99,99% | 52,6 phút | 4,38 phút | 1,01 phút |
| 99,999% | 5,26 phút | 26,3 giây | 6,05 giây |

Hai điều bảng này ngụ ý mà ít người tính:

1. **99,99% nghĩa là mọi sự cố phải được phát hiện và khắc phục trong dưới 4,4 phút mỗi tháng — tổng cộng.** Với con người trong vòng lặp, điều đó gần như bất khả thi; nó buộc phải có failover tự động.
2. **Availability nhân lên qua chuỗi phụ thuộc.** Một request đi qua 5 thành phần, mỗi thành phần 99,9% → `0.999^5 ≈ 99,5%`. Muốn 99,99% ở đầu ra, từng thành phần phải tốt hơn thế nhiều, hoặc phải có dự phòng để phá vỡ phép nhân.

```text
Chuỗi (nối tiếp):   A_total = A₁ × A₂ × ... × Aₙ        → càng nhiều hop càng tệ
Dự phòng (song song): A_total = 1 - (1-A)ⁿ               → 2 node 99% → 99,99%
```

Đây là lý do kỹ thuật cho hai lời khuyên tưởng như trái ngược: **giảm số hop** (phép nhân) và **thêm dự phòng ở mỗi hop** (phép song song).

### 2.2 Error budget – công cụ quản lý, không chỉ là số

```text
SLO 99,9% trong 30 ngày → error budget = 0,1% × 30 ngày ≈ 43,2 phút

Còn budget  → được deploy nhanh, được thử nghiệm, được chấp nhận rủi ro
Hết budget  → đóng băng feature, dồn lực vào độ tin cậy
```

Error budget biến cuộc tranh luận "đi nhanh hay đi an toàn" từ cảm tính thành một con số mà cả product và engineering đều đồng ý trước. Đó là giá trị lớn nhất của nó — lớn hơn giá trị đo lường.

### 2.3 Chọn SLI đúng

SLI tệ đo cái dễ đo; SLI tốt đo cái người dùng cảm nhận.

| SLI tệ | Vì sao tệ | SLI tốt hơn |
|---|---|---|
| CPU < 80% | Người dùng không quan tâm CPU | Tỉ lệ request thành công |
| Uptime của host | Host sống nhưng app trả 500 | Tỉ lệ request 2xx/3xx trên tổng |
| Latency trung bình | Trung bình che tail | p99 latency dưới ngưỡng |
| "Service khả dụng" | Không đo được | Tỉ lệ **request tốt / request hợp lệ** trong cửa sổ trượt |

Với hệ thống theo lô hoặc hàng đợi, SLI hợp lý là **độ mới của dữ liệu (freshness)** và **tỉ lệ job hoàn thành trong SLA**, không phải uptime.

---

## 3. CAP và PACELC

### 3.1 CAP nói gì và không nói gì

```text
Khi có network partition (P), phải chọn:
  C – Consistency: từ chối trả lời nếu không chắc dữ liệu mới nhất
  A – Availability: vẫn trả lời, chấp nhận có thể trả dữ liệu cũ
```

Ba điều CAP **không** nói, nhưng thường bị hiểu sai:

1. **Không phải "chọn 2 trong 3".** Partition không phải lựa chọn — mạng sẽ phân mảnh. Nên thực chất chỉ có CP hoặc AP. "CA" chỉ tồn tại trong hệ một node.
2. **Không phải thuộc tính của cả hệ thống.** Cùng một database có thể cấu hình theo từng operation: Cassandra với `ALL` là CP cho thao tác đó, với `ONE` là AP.
3. **Không phải phổ liên tục.** "C" của CAP là linearizability — mức mạnh nhất. Giữa nó và eventual có nhiều mức trung gian, xem [distributed_systems_theory.md](distributed_systems_theory.md) mục 2.

### 3.2 PACELC – phần quan trọng hơn trong thực tế

```text
IF Partition  → chọn Availability hay Consistency
ELSE (bình thường) → chọn Latency hay Consistency
```

PACELC hữu ích hơn CAP vì **phần lớn thời gian không có partition**, và đánh đổi thật hằng ngày là latency vs consistency:

| Hệ thống | Khi partition | Bình thường | Nhãn |
|---|---|---|---|
| DynamoDB, Cassandra | A | L | PA/EL |
| MySQL với async replica | A | L | PA/EL |
| MongoDB (mặc định) | A | C | PA/EC |
| HBase, etcd, ZooKeeper | C | C | PC/EC |
| Spanner, CockroachDB | C | C | PC/EC |

Ý nghĩa vận hành: chọn strong consistency là **trả giá latency mỗi request, mọi ngày**, không chỉ khi có sự cố. Đó là lý do nhiều hệ thống chọn strong consistency chỉ cho các đường đi thật cần (thanh toán, tồn kho) và eventual cho phần còn lại (feed, đếm view, gợi ý).

---

## 4. Failure mode – hiểu cái gì có thể sai

Trước khi bàn pattern, cần biết các dạng lỗi, vì mỗi dạng cần biện pháp khác nhau:

| Dạng lỗi | Đặc điểm | Vì sao khó |
|---|---|---|
| **Crash** | Node dừng hẳn | Dễ nhất — health check phát hiện được |
| **Omission** | Mất message | Cần retry + idempotency |
| **Timing** | Phản hồi quá chậm | **Khó hơn crash**: node "còn sống" nên vẫn nhận traffic |
| **Byzantine** | Trả kết quả sai/độc hại | Cần checksum, xác thực; hiếm trong hệ nội bộ |
| **Gray failure** | Suy giảm một phần, monitoring vẫn xanh | Khó nhất: hệ thống "khỏe" theo mọi chỉ số nhưng người dùng thấy lỗi |
| **Cascading** | Lỗi lan theo chuỗi phụ thuộc | Một service chậm làm cạn thread pool của service gọi nó |

**Node chậm nguy hiểm hơn node chết.** Node chết bị loại khỏi pool ngay; node chậm vẫn nhận request, giữ kết nối, làm cạn thread pool của caller, và kéo cả hệ thống xuống. Đây là lý do timeout và circuit breaker quan trọng hơn health check.

Gray failure đáng nói riêng: dashboard xanh nhưng khách hàng báo lỗi. Cách phòng duy nhất hiệu quả là **đo từ góc nhìn người dùng** (synthetic probe đi qua đúng đường đi thật, client-side metric), không chỉ đo từ bên trong.

---

## 5. Resilience pattern

### 5.1 Timeout – nền tảng của mọi thứ khác

```text
Không có timeout = chờ vô hạn = một dependency chậm làm cạn toàn bộ thread pool.
Đây là nguyên nhân gốc của phần lớn sự cố cascading.
```

| Loại timeout | Ý nghĩa | Đặt thế nào |
|---|---|---|
| Connect timeout | Thời gian thiết lập kết nối | Ngắn (1–3s) — mạng nội bộ nhanh hoặc không có |
| Read/request timeout | Chờ phản hồi | Theo p99 của dependency, không theo cảm giác |
| Overall/deadline | Toàn bộ chuỗi xử lý | Nhỏ hơn timeout của caller |

**Deadline propagation** là kỹ thuật quan trọng nhưng ít được áp dụng: truyền deadline còn lại xuống các hop sau, thay vì mỗi hop có timeout riêng độc lập.

```text
✗ Không propagate: client timeout 1s, nhưng service C vẫn xử lý 5s
   → công việc vô ích, tài nguyên bị chiếm cho một request đã bị hủy

✓ Propagate: client gửi deadline = now+1s
   → A còn 900ms, B còn 700ms, C thấy chỉ còn 100ms → fail fast, không làm vô ích
```

gRPC hỗ trợ sẵn qua deadline; với HTTP thường phải tự truyền header và tôn trọng nó.

### 5.2 Retry – cần thiết nhưng dễ gây hại

```java
// Backoff mũ CÓ jitter — jitter là bắt buộc, không phải tinh chỉnh
long base = 100, cap = 5_000;
long delay = Math.min(cap, base * (1L << attempt));
long sleep = ThreadLocalRandom.current().nextLong(delay / 2, delay + 1);  // full-ish jitter
```

Không có jitter, mọi client cùng retry đúng cùng thời điểm — tạo ra chính đợt sóng vừa làm sập hệ thống (thundering herd).

Khi nào **không** retry:

| Tình huống | Vì sao |
|---|---|
| Lỗi 4xx (trừ 429) | Client sai — retry cũng sai |
| Thao tác không idempotent, chưa có idempotency key | Có thể trừ tiền hai lần |
| Đã hết deadline | Retry vô nghĩa, chỉ thêm tải |
| Dependency đang quá tải | Retry làm nó tệ hơn — cần backpressure, không phải retry |

**Retry budget / retry amplification** là điểm hay bị bỏ qua: nếu mỗi tầng retry 3 lần và có 3 tầng, một request lỗi tạo ra tối đa 27 request thật. Cách chữa: chỉ retry ở **một** tầng (thường tầng ngoài cùng hoặc tầng gần dependency nhất), và giới hạn retry theo tỉ lệ (ví dụ tối đa 10% tổng lưu lượng được là retry).

### 5.3 Circuit breaker

```text
CLOSED   → gọi bình thường, đếm tỉ lệ lỗi
   │ tỉ lệ lỗi vượt ngưỡng trong cửa sổ
   ▼
OPEN     → fail fast ngay, KHÔNG gọi dependency (cho nó thời gian hồi phục)
   │ hết thời gian chờ
   ▼
HALF-OPEN → cho qua vài request thăm dò
   ├─ thành công → CLOSED
   └─ thất bại   → OPEN
```

```java
CircuitBreakerConfig cfg = CircuitBreakerConfig.custom()
    .slidingWindowType(SlidingWindowType.TIME_BASED)
    .slidingWindowSize(60)                  // cửa sổ 60 giây
    .minimumNumberOfCalls(20)               // không mở circuit vì 2/3 lỗi
    .failureRateThreshold(50)
    .slowCallRateThreshold(50)              // gọi CHẬM cũng tính là lỗi — quan trọng
    .slowCallDurationThreshold(Duration.ofSeconds(2))
    .waitDurationInOpenState(Duration.ofSeconds(30))
    .permittedNumberOfCallsInHalfOpenState(5)
    .build();
```

Hai chi tiết cấu hình quyết định circuit breaker có hữu ích hay gây hại:

- **`minimumNumberOfCalls`**: không có nó, service ít traffic sẽ mở circuit vì một vài lỗi ngẫu nhiên.
- **`slowCallRateThreshold`**: xử lý đúng dạng lỗi timing ở mục 4 — dependency trả 200 OK nhưng mất 10 giây vẫn là hỏng.

### 5.4 Bulkhead – cách ly tài nguyên

```text
Không có bulkhead:                Có bulkhead:
┌──────────────────────┐          ┌─────────┐ ┌─────────┐ ┌─────────┐
│ thread pool chung 200│          │ pool 60 │ │ pool 60 │ │ pool 80 │
│ svc A (chậm) chiếm hết│          │ svc A   │ │ svc B   │ │ svc C   │
│ svc B, C bị đói      │          │ (chậm)  │ │ OK      │ │ OK      │
└──────────────────────┘          └─────────┘ └─────────┘ └─────────┘
```

Bulkhead biến "một dependency chậm làm sập cả service" thành "một tính năng bị suy giảm". Đây là pattern có tỉ lệ lợi ích/công sức cao nhất trong nhóm này, và thường chỉ là cấu hình thread pool riêng cho từng dependency.

### 5.5 Load shedding và backpressure

Khi tải vượt công suất, có hai lựa chọn: **giảm tải có chọn lọc** hoặc **sập toàn bộ**.

```java
// Load shedding: từ chối sớm khi hàng đợi quá sâu, ưu tiên theo lớp request
if (queue.size() > SHED_THRESHOLD && request.priority() == Priority.LOW) {
    return Response.status(503).header("Retry-After", "5").build();
}
```

| Kỹ thuật | Cơ chế | Dùng khi |
|---|---|---|
| **Load shedding** | Từ chối một phần request ngay ở cửa | Đỉnh tải đột biến |
| **Backpressure** | Báo ngược lên producer để nó chậm lại | Pipeline có producer kiểm soát được |
| **Priority queue** | Request quan trọng được phục vụ trước | Có phân lớp nghiệp vụ rõ |
| **Adaptive concurrency limit** | Tự điều chỉnh giới hạn theo latency đo được | Không biết trước công suất |

Điểm mấu chốt: **từ chối 10% request nhanh gọn tốt hơn làm 100% request timeout**. Một hệ thống trả 503 kèm `Retry-After` vẫn đang hoạt động đúng; một hệ thống nhận hết rồi timeout tất cả thì đã sập.

### 5.6 Graceful degradation và fallback

```java
try {
    return recommendationService.forUser(userId);     // cá nhân hóa
} catch (Exception e) {
    return cache.topProductsFallback();              // danh sách chung, luôn có
}
```

Nguyên tắc thiết kế: **phân loại tính năng theo mức thiết yếu** từ trước, không phải lúc sự cố.

| Lớp | Ví dụ | Khi quá tải |
|---|---|---|
| Thiết yếu | Đăng nhập, thanh toán, xem đơn hàng | Bảo vệ bằng mọi giá |
| Quan trọng | Tìm kiếm, danh sách sản phẩm | Suy giảm (bớt cá nhân hóa, tăng TTL cache) |
| Bổ trợ | Gợi ý, "người khác cũng xem", badge | Tắt hoàn toàn |

Fallback phải **rẻ hơn và ít phụ thuộc hơn** đường chính. Fallback gọi một service khác cũng có thể chết là fallback vô nghĩa.

---

## 6. HA pattern ở tầng hạ tầng

### 6.1 Active-passive vs active-active

| | Active-passive | Active-active |
|---|---|---|
| Cách hoạt động | Một node phục vụ, một node chờ và nhận replication | Mọi node đều phục vụ |
| RTO | 30 giây–5 phút (phát hiện + promote) | Gần bằng 0 |
| RPO | Theo replication lag (0 nếu đồng bộ) | 0 hoặc gần 0 |
| Tài nguyên | Node chờ không sinh giá trị | Dùng hết công suất |
| Phức tạp | Thấp hơn | Cao: xung đột ghi, split-brain |
| Rủi ro chính | Failover chưa từng được thử → thất bại đúng lúc cần | Xung đột write-write, cần chiến lược hòa giải |

Với active-active nhiều region, câu hỏi quyết định là: **cùng một bản ghi có bị ghi từ hai region không?** Nếu có, phải có chiến lược hòa giải (LWW mất dữ liệu, CRDT, hoặc phân vùng theo khóa). Nếu không (mỗi khách hàng "thuộc" một region), bài toán đơn giản hơn nhiều — và đó là thiết kế nên nhắm tới.

### 6.2 Multi-AZ vs multi-region

| | Multi-AZ | Multi-region |
|---|---|---|
| RTT giữa các vùng | < 2ms | 30–200ms |
| Replication đồng bộ khả thi? | Có | Không thực tế cho đường đi nóng |
| Bảo vệ khỏi | Mất một datacenter | Mất cả region, thảm họa vùng |
| Chi phí | Thấp (thường trong cùng giá) | Cao (hạ tầng ×N + egress) |
| Độ phức tạp | Thấp | Cao: routing, dữ liệu, tuân thủ dữ liệu theo vùng |

Lời khuyên thực dụng: **multi-AZ gần như luôn đáng làm; multi-region chỉ khi có yêu cầu rõ ràng** (tuân thủ, RTO rất chặt, người dùng phân bố toàn cầu). Rất nhiều đội xây multi-region rồi chưa bao giờ failover, và độ phức tạp thêm vào lại chính là nguyên nhân sự cố.

### 6.3 Split-brain và quorum

```text
Cluster 4 node bị chia 2–2 → mỗi nửa tưởng nửa kia đã chết
→ cả hai nửa nhận write → dữ liệu phân nhánh → không thể hòa giải tự động

Phòng: quorum số LẺ (3, 5, 7) → chỉ một nửa có đa số → chỉ nửa đó được phục vụ
       hoặc witness/tiebreaker ở vùng thứ ba
       hoặc fencing (STONITH) — chặn hẳn node cũ khỏi storage
```

Đây là lý do mọi cluster dựa trên consensus dùng số node lẻ, và là lý do một cụm 2 node **không** có HA thật — không có cách nào phân biệt "node kia chết" và "mạng tới node kia bị đứt". Chi tiết consensus: [distributed_systems_theory.md](distributed_systems_theory.md) mục 3.

---

## 7. Chaos engineering

```text
Giả thuyết → giới hạn blast radius → thực nghiệm → quan sát → cải thiện
     ↑                                                              │
     └──────────────────────────────────────────────────────────────┘
```

Chaos engineering không phải "phá cho vui". Nó là cách **kiểm chứng giả định** — đặc biệt là giả định "failover của chúng ta hoạt động", thứ mà không ai biết chắc cho tới khi thử.

```bash
# Xóa một pod ngẫu nhiên
kubectl delete pod -l app=payment --field-selector=status.phase=Running \
  -o name | shuf -n1 | xargs kubectl delete

# Thêm độ trễ mạng (mô phỏng node chậm — dạng lỗi khó hơn node chết)
tc qdisc add dev eth0 root netem delay 200ms 50ms distribution normal

# Chiếm CPU
stress-ng --cpu 8 --timeout 60s
```

Điều kiện tiên quyết trước khi làm chaos, theo thứ tự:

1. Có monitoring đủ để **thấy** ảnh hưởng (nếu không thấy thì thí nghiệm vô nghĩa).
2. Có cách dừng thí nghiệm ngay lập tức.
3. Có giả thuyết cụ thể ("mất một AZ thì p99 tăng dưới 20% và không có lỗi 5xx"), không phải "xem sao".
4. Bắt đầu ở môi trường staging, rồi production ở giờ thấp điểm, blast radius nhỏ.

Thí nghiệm giá trị nhất và thường bị bỏ qua: **tiêm độ trễ**, không phải giết process. Vì như mục 4 đã nói, node chậm là dạng lỗi khó hơn và phổ biến hơn node chết.

---

## 8. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| SLO cao hơn (99,99% thay vì 99,9%) | Khách hàng ít bị ảnh hưởng | Chi phí và độ phức tạp tăng phi tuyến | Chỉ cho đường đi thật quan trọng |
| Replication đồng bộ | RPO = 0 | Mỗi write chờ round-trip | Cùng AZ/region, dữ liệu không được mất |
| Replication bất đồng bộ | Write nhanh | RPO > 0 | Cross-region |
| Circuit breaker | Chặn cascading failure | Cấu hình sai → mở circuit oan | Mọi dependency ngoài |
| Retry | Vượt qua lỗi tạm thời | Amplification, làm nặng thêm khi quá tải | Có jitter, chỉ một tầng, có budget |
| Bulkhead | Lỗi không lan | Tổng tài nguyên dùng kém hiệu quả hơn | Có nhiều dependency với độ tin cậy khác nhau |
| Load shedding | Hệ thống sống sót qua đỉnh | Một phần người dùng bị từ chối | Luôn nên có ở tầng ngoài |
| Active-active multi-region | RTO ~0 | Xung đột ghi, chi phí, phức tạp | Có yêu cầu rõ; mỗi khóa thuộc một region |
| Chaos engineering | Biết chắc thay vì giả định | Cần chuẩn bị, có rủi ro | Sau khi có monitoring và runbook |

---

## 9. Checklist độ tin cậy

```text
Định nghĩa & đo lường
□ SLI đo từ góc nhìn người dùng (tỉ lệ request tốt, p99), không chỉ CPU/uptime
□ SLO có con số, có cửa sổ thời gian, được product đồng ý
□ Error budget được theo dõi và có quy tắc khi cạn
□ Synthetic probe đi qua đúng đường đi thật (chống gray failure)

Chống lỗi lan
□ MỌI lời gọi ngoài có connect timeout và read timeout tường minh
□ Deadline được truyền xuống các hop sau
□ Retry có jitter, có budget, chỉ ở một tầng
□ Circuit breaker có minimumNumberOfCalls và slowCallRateThreshold
□ Bulkhead: thread pool/connection pool riêng theo dependency
□ Load shedding ở tầng ngoài, trả 503 + Retry-After
□ Tính năng đã được phân lớp thiết yếu/quan trọng/bổ trợ, có fallback rẻ

Hạ tầng
□ Multi-AZ cho tầng dữ liệu; số node quorum là số lẻ
□ Không có cụm 2 node nào được coi là HA
□ Failover đã được diễn tập, có ghi lại RTO thực đo
□ Backup độc lập với replication (xem sqlserver/backup_recovery.md làm ví dụ)

Vận hành
□ Runbook cho từng lớp sự cố, đã được người chưa quen đọc thử
□ Alert dựa trên triệu chứng người dùng, không chỉ nguyên nhân hạ tầng
□ Postmortem không quy lỗi cá nhân, có hành động cụ thể có chủ sở hữu
□ Chaos experiment định kỳ, ưu tiên tiêm độ trễ
```

---

## 10. Real-world

| Ví dụ | Điểm đáng học |
|---|---|
| **AWS RDS Multi-AZ** | Replication đồng bộ sang AZ khác, failover 60–120s. RPO ≈ 0, RTO ≈ 2 phút — mốc tham chiếu tốt cho "HA quản lý sẵn" |
| **Google Spanner** | Đạt strong consistency phân tán nhờ TrueTime (GPS + atomic clock, sai số < 7ms) — chứng minh CAP không cấm CP hiệu năng cao, chỉ đòi hạ tầng đặc biệt |
| **Netflix** | Active-active nhiều region + chaos engineering như thực hành thường xuyên; giả định luôn được kiểm chứng |
| **Google SRE** | Error budget như cơ chế quản trị: hết budget thì đóng băng feature — biến độ tin cậy thành mục tiêu chung, không phải việc riêng của ops |

---

## 11. Ghi chú – chủ đề tiếp theo

- [distributed_systems_theory.md](distributed_systems_theory.md): consistency model, consensus, quorum, split-brain chi tiết.
- [load_balancing.md](load_balancing.md): health check, connection draining.
- [caching.md](caching.md): cache như lớp phòng thủ khi tầng dưới lỗi.
- [interview_framework_estimation.md](interview_framework_estimation.md): p99, tail latency amplification.
- `advanced/distributed_transactions.md`: idempotency — điều kiện để retry an toàn.

Từ khóa mở rộng: MTBF/MTTR, error budget policy, toil, hedged request, tail tolerance, adaptive concurrency (Netflix concurrency-limits), STONITH/fencing, witness node, blast radius, postmortem không quy lỗi, DiRT (disaster recovery testing).

---

*Cập nhật lần cuối: 2026-07-30*
