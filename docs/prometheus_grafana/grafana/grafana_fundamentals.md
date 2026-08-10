---
title: "Grafana Fundamentals – Từ PromQL đến dashboard điều tra sự cố"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 22
---
# Grafana Fundamentals – Từ PromQL đến dashboard điều tra sự cố

> Thuật ngữ: [Glossary](../glossary.md).

> Phiên bản mục tiêu: **Grafana OSS 13.1.x**.
>
> Điều kiện đầu vào: đã đọc [Prometheus Fundamentals](../prometheus/prometheus_fundamentals.md) và biết PromQL cơ bản.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- giải thích đúng vai trò của Grafana và data source;
- chạy Grafana bằng Docker với dữ liệu cấu hình được persist;
- kết nối Prometheus/Thanos bằng data source;
- phân biệt Range, Instant và Both query;
- chọn visualization theo câu hỏi thay vì theo hình thức;
- cấu hình unit, threshold, value mapping và field override;
- tạo variable Prometheus theo query editor hiện hành;
- dùng `$__rate_interval`, `$__interval` và `$__range` đúng mục đích;
- tạo annotation, dashboard link và data link để điều tra theo ngữ cảnh;
- dùng Explore và panel inspector để chẩn đoán “No data”, query chậm hoặc kết quả sai;
- dựng một dashboard HTTP service có luồng overview → drill-down.

---

## 2. Grafana là gì và không phải là gì?

**Grafana** là lớp query, trực quan hóa và tương tác với dữ liệu từ các backend:

```text
Prometheus / Mimir / Thanos ── metrics ─┐
Loki ────────────────────────── logs ───┤
Tempo / Jaeger ─────────────── traces ──┼──▶ Grafana
PostgreSQL / MySQL ───────────── SQL ───┘       │
                                                ├── Explore
                                                ├── Dashboards
                                                ├── Alerting
                                                └── Links / correlations
```

Grafana thường **không phải nơi lưu telemetry gốc**:

- Prometheus/Thanos/Mimir lưu metrics;
- Loki lưu logs;
- Tempo/Jaeger lưu traces;
- Grafana lưu cấu hình như dashboard, user, data source metadata, alert rules và preferences trong database của Grafana.

Ví dụ đời thường:

- Prometheus là kho số liệu;
- PromQL là ngôn ngữ hỏi kho;
- Grafana là phòng điều khiển;
- dashboard là một bảng điều khiển đã thiết kế;
- panel là một đồng hồ trên bảng;
- Explore là bàn làm việc để điều tra tự do.

### Các nhầm lẫn phổ biến

| Nhầm lẫn | Thực tế |
|---|---|
| “Grafana scrape `/metrics`” | Prometheus hoặc collector scrape; Grafana query backend. |
| “Xóa dashboard làm mất metrics” | Dashboard là cấu hình hiển thị, không phải TSDB. |
| “Threshold đỏ sẽ gửi alert” | Threshold chỉ đổi cách hiển thị; alert rule là cơ chế khác. |
| “Panel không có data nghĩa là service không có data” | Có thể sai time range, variable, query, data source hoặc permission. |
| “Viewer chỉ xem được panel nên query luôn an toàn” | Data-source access và authorization phải được thiết kế riêng. |

---

## 3. Từ query đến pixel: data flow trong một panel

```text
Dashboard context
  ├── time range
  ├── variables
  └── refresh interval
          │
          ▼
Data source query
          │
          ▼
Grafana Data Frames
          │
          ├── transformations
          ▼
Fields
  ├── standard options
  ├── overrides
  ├── thresholds
  └── value mappings
          │
          ▼
Visualization
```

Phân biệt các tầng:

| Tầng | Ví dụ | Có thay dữ liệu backend? |
|---|---|---|
| Query | PromQL `sum(rate(...))` | Không |
| Transformation | Join, rename, reduce kết quả trong Grafana | Không |
| Standard option | Unit `req/s`, decimals | Không |
| Override | Series lỗi màu đỏ | Không |
| Threshold | Trên 5% hiển thị đỏ | Không |
| Value mapping | `0 → DOWN`, `1 → UP` | Không |

Nếu một phép tính có ý nghĩa nghiệp vụ và được nhiều dashboard/alert dùng, ưu tiên recording rule hoặc query tại backend. Transformation phù hợp định dạng/ghép dữ liệu ở presentation layer, không nên trở thành nơi giấu business logic quan trọng.

---

## 4. Chạy Grafana 13.1 bằng Docker

Ví dụ lab tối thiểu:

```yaml
# compose.yaml
services:
  grafana:
    image: grafana/grafana:13.1.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    restart: unless-stopped

volumes:
  grafana_data:
```

Trước khi chạy:

```powershell
$env:GRAFANA_ADMIN_PASSWORD = "mật-khẩu-lab-tạm-thời"
docker compose up -d
```

Truy cập:

```text
http://localhost:3000
```

Các điểm cần hiểu:

- pin version thay vì dùng `latest`;
- image OSS hiện hành là `grafana/grafana`; repository `grafana/grafana-oss` không còn được cập nhật từ 12.4;
- `/var/lib/grafana` chứa SQLite và dữ liệu Grafana cần persist trong lab;
- bind mount provisioning ở chế độ read-only;
- mật khẩu ví dụ chỉ dùng cho lab, không commit `.env` có secret;
- production database, HA, SSO, TLS và secret management nằm ở bài [Grafana Production](grafana_production.md).

Sau khi container chạy:

```powershell
docker compose ps
docker compose logs grafana
```

Đừng kết luận “port 3000 mở là Grafana sẵn sàng”. Xem log migration/startup và thử đăng nhập/query data source.

---

## 5. Cấu trúc tổ chức cần biết

```text
Grafana instance
└── Organization
    ├── Data sources
    ├── Users / teams / service accounts
    └── Folders
        ├── Dashboards
        │   ├── Variables / filters / annotations / links
        │   ├── Rows hoặc tabs
        │   └── Panels
        │       ├── Queries
        │       └── Visualization
        └── Alert rules
```

Một cấu trúc folder thực dụng:

```text
Platform/
  Kubernetes Overview
  Node Details

Services/
  Checkout Overview
  Checkout Instances

Databases/
  PostgreSQL Overview

On-call/
  Incident Triage
```

Folder không chỉ để tìm kiếm; permission ở folder được dashboard con kế thừa. Tránh đặt mọi dashboard vào `General`.

---

## 6. Data source: kết nối đến backend

Grafana có Prometheus data source built-in, không cần cài plugin.

### Tạo qua UI

Luồng hiện hành:

```text
Connections
  → Add new connection
  → Prometheus
  → Add new data source
  → cấu hình URL/options
  → Save & test
```

Các trường quan trọng:

| Trường | Ý nghĩa |
|---|---|
| Name | Tên con người nhìn thấy. |
| UID | Định danh ổn định để dashboard tham chiếu. |
| Default | Data source mặc định của organization. |
| Prometheus server URL | URL mà **Grafana server** gọi được. |
| Prometheus type | Prometheus, Mimir, Thanos hoặc Cortex. |
| Prometheus version | Giúp Grafana chọn capability tương thích. |
| Scrape interval | Baseline dùng tính step và `$__rate_interval`. |
| Query timeout | Giới hạn thời gian query. |
| HTTP method | `POST` được khuyến nghị và là mặc định hiện hành. |
| Series limit | Guardrail cho metadata/series response. |

### “localhost” trong container

```text
Grafana container → http://localhost:9090
```

Ở đây `localhost` là **container Grafana**, không phải host và không phải container Prometheus.

Với Docker Compose:

```text
http://prometheus:9090
```

Với Kubernetes:

```text
http://prometheus-operated.monitoring.svc:9090
```

URL phải được kiểm tra từ network context của Grafana server.

### Provisioning tối thiểu

```yaml
# grafana/provisioning/datasources/prometheus.yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      prometheusType: Prometheus
      prometheusVersion: 3.13.0
      timeInterval: 30s
```

`timeInterval` nên khớp scrape interval điển hình. Nếu các target có interval khác nhau:

- đặt data source interval theo interval dài nhất có ý nghĩa chung; hoặc
- đặt **Min step** riêng cho panel/query đặc biệt.

Khai báo sai `prometheusType` có thể làm Grafana dùng API/capability không phù hợp. Thanos Query vẫn dùng data source type `prometheus`, nhưng `jsonData.prometheusType` nên là `Thanos`.

### Data source proxy

Với `access: proxy`:

```text
Browser → Grafana server → Prometheus
```

Lợi ích:

- browser không cần route trực tiếp đến Prometheus;
- credentials/TLS config được giữ ở server;
- tránh nhiều vấn đề CORS.

Nó không tự tạo authorization theo label/tenant. User xem được data source có thể query dữ liệu mà backend và Grafana permission cho phép.

---

## 7. Kiểm tra kết nối đúng tầng

`Save & test` thành công chỉ chứng minh Grafana gọi được một API phù hợp. Tiếp tục kiểm:

```promql
up
```

Sau đó:

```promql
count by (job) (up)
```

Checklist:

1. data source health thành công;
2. Explore chạy được `up`;
3. time range chứa sample;
4. label `job`, `instance` đúng kỳ vọng;
5. Grafana server và Prometheus đồng bộ thời gian;
6. query timeout không bị reverse proxy cắt sớm hơn;
7. với Thanos, kiểm tra dedup/partial response/query parameter.

Nếu Prometheus UI query được nhưng Grafana không query được, tập trung vào network/auth giữa **Grafana server và Prometheus**, không phải giữa laptop và Prometheus.

---

## 8. Dashboard, panel và query

Dashboard là một JSON resource có metadata, layout, controls và panels. Panel là đơn vị hiển thị cơ bản gồm query và visualization.

Luồng tạo dashboard hiện hành:

```text
Dashboards → New dashboard
  → Add visualization
  → chọn data source
  → viết query
  → chọn visualization/options
  → Save dashboard vào folder
```

Khi sửa dashboard lớn, dùng:

- content outline để điều hướng;
- row/tab để nhóm panel;
- save message để ghi lý do thay đổi;
- dashboard version history để so/restore thay đổi UI;
- UID ổn định để link không vỡ.

### Một panel nên trả lời một câu hỏi

Tên yếu:

```text
Requests
```

Tên tốt:

```text
Request rate theo status
```

Description tốt:

```text
Tổng request/giây từ counter http_requests_total.
5xx tăng sau deploy: mở dashboard instance và runbook checkout.
Owner: checkout-team.
```

---

## 9. Prometheus query editor

Grafana có hai mode:

| Mode | Phù hợp |
|---|---|
| Builder | Học metric/label và tạo query cơ bản bằng UI. |
| Code | Viết PromQL trực tiếp, autocomplete và syntax highlighting. |

Có thể chuyển qua lại, nhưng query phức tạp không phải lúc nào cũng biểu diễn đẹp trong Builder.

### Query Type

| Type | API/shape | Dùng cho |
|---|---|---|
| Range | Nhiều sample theo thời gian | Time series, heatmap, trend |
| Instant | Một giá trị gần thời điểm đánh giá cho mỗi series | Stat, gauge, table hiện trạng |
| Both | Chạy cả Range và Instant | Khi panel/editor cần cả hai; tốn hai query |

Đừng để `Both` theo thói quen. Dashboard nhiều panel có thể tăng gấp đôi request không cần thiết.

### Format

| Format | Ý nghĩa |
|---|---|
| Time series | Data theo thời gian |
| Table | Kết quả dạng bảng |
| Heatmap | Chuyển cumulative histogram buckets cho Heatmap |

### Legend

Ví dụ:

```text
{{status}}
{{job}} / {{instance}}
```

Legend phải ngắn nhưng đủ phân biệt series. Nếu query trả 500 series thì rút gọn legend không giải quyết cardinality; cần filter hoặc aggregate query.

---

## 10. Step, resolution và `$__rate_interval`

Giả sử dashboard xem 24 giờ trên panel rộng 1.000 pixel. Grafana không cần lấy một điểm mỗi 15 giây nếu màn hình không thể hiển thị hết:

```text
time range + panel width + max data points
                │
                ▼
             $__interval
                │
                ▼
Prometheus query_range step
```

### Ba khái niệm dễ nhầm

| Khái niệm | Vai trò |
|---|---|
| `$__interval` | Khoảng nhóm/step tự tính theo time range và panel width. |
| Min step | Sàn cho step của Prometheus query và input tính rate interval. |
| `$__rate_interval` | Range window an toàn hơn cho `rate()`/`increase()`. |

Grafana tính gần đúng:

```text
$__rate_interval
= max($__interval + scrape_interval, 4 × scrape_interval)
```

Dùng:

```promql
sum by (job) (
  rate(http_requests_total{job=~"$job"}[$__rate_interval])
)
```

Không dùng:

```promql
rate(http_requests_total[15s])
```

Nếu scrape mỗi 30 giây, range 15 giây có thể không chứa đủ hai sample. `$__interval` cũng có thể quá nhỏ cho `rate()`, nên không thay `$__rate_interval`.

### Các built-in variable hữu ích

| Variable | Giá trị |
|---|---|
| `$__range` | Toàn bộ duration đang xem, ví dụ `6h`. |
| `$__range_s` | Duration tính bằng giây. |
| `$__range_ms` | Duration tính bằng mili giây. |
| `$__from`, `$__to` | Mốc đầu/cuối, mặc định epoch milliseconds. |
| `$__interval` | Interval tự tính. |
| `$__rate_interval` | Window cho Prometheus counter rate/increase. |

Ví dụ tổng request trong time range:

```promql
sum(increase(http_requests_total[$__range]))
```

Đây trả lời câu hỏi khác `rate()`: tổng tăng trong cửa sổ, không phải tốc độ mỗi giây.

---

## 11. Chọn visualization theo câu hỏi

| Câu hỏi | Visualization phù hợp |
|---|---|
| Giá trị thay đổi thế nào theo thời gian? | Time series |
| Giá trị hiện tại là bao nhiêu? | Stat |
| So với min/max cố định? | Gauge hoặc Bar gauge |
| So sánh category tại một thời điểm? | Bar chart hoặc Table |
| Phân phối latency thay đổi theo thời gian? | Heatmap |
| Trạng thái UP/DOWN chuyển khi nào? | State timeline / Status history |
| Cần xem nhiều trường, sort/filter? | Table |
| Tỷ trọng ít category, tổng có ý nghĩa? | Pie chart, dùng tiết chế |
| Log lines? | Logs visualization/Explore với Loki |
| Vị trí địa lý thực sự có tọa độ? | Geomap |

### Không chọn theo thẩm mỹ

- Gauge không tốt cho số không có min/max có nghĩa.
- Pie chart với hàng chục category khó so sánh.
- Stat không cho thấy spike đã xảy ra 10 phút trước.
- Time series của 200 pod tạo “mì spaghetti”.
- Heatmap từ histogram cần bucket đúng và query/format đúng.

Grafana 13 có visualization suggestion, nhưng suggestion không biết SLO, audience hoặc quyết định vận hành của đội.

---

## 12. Dashboard thực hành: HTTP service

Giả sử có:

```text
http_requests_total{job, instance, status}
http_request_duration_seconds_bucket{job, instance, le}
up{job, instance}
```

Dashboard có hai tầng:

```text
HTTP Service Overview
├── Traffic
│   ├── Request rate
│   └── Error ratio
├── Latency
│   └── p95 latency
└── Availability
    └── Target state
```

### Panel 1 – Request rate

```promql
sum by (status) (
  rate(
    http_requests_total{
      job=~"$job",
      instance=~"$instance"
    }[$__rate_interval]
  )
)
```

Thiết lập:

```text
Visualization: Time series
Query type: Range
Unit: requests/sec (reqps)
Legend: {{status}}
Tooltip: All
```

### Panel 2 – Error ratio

```promql
100 *
sum(
  rate(
    http_requests_total{
      job=~"$job",
      instance=~"$instance",
      status=~"5.."
    }[$__rate_interval]
  )
)
/
clamp_min(
  sum(
    rate(
      http_requests_total{
        job=~"$job",
        instance=~"$instance"
      }[$__rate_interval]
    )
  ),
  1e-9
)
```

Thiết lập:

```text
Visualization: Stat cho hiện tại hoặc Time series cho lịch sử
Query type: Instant với Stat; Range với Time series
Unit: Percent (0-100)
No value: N/A
```

`clamp_min` tránh chia cho zero. Khi traffic bằng zero, tỷ lệ được hiển thị 0 thay vì vô hạn; đội phải quyết định 0 traffic là bình thường hay là một availability signal khác.

### Panel 3 – p95 latency

```promql
histogram_quantile(
  0.95,
  sum by (le) (
    rate(
      http_request_duration_seconds_bucket{
        job=~"$job",
        instance=~"$instance"
      }[$__rate_interval]
    )
  )
)
```

Thiết lập:

```text
Visualization: Time series
Query type: Range
Unit: seconds (s)
Legend: p95
```

Phải giữ label `le` trong aggregation của classic histogram. Nếu cần p95 theo job:

```promql
histogram_quantile(
  0.95,
  sum by (job, le) (
    rate(http_request_duration_seconds_bucket{job=~"$job"}[$__rate_interval])
  )
)
```

### Panel 4 – Target state

```promql
up{
  job=~"$job",
  instance=~"$instance"
}
```

Thiết lập:

```text
Visualization: State timeline
Query type: Range
Value mapping:
  0 → DOWN (red)
  1 → UP (green)
Legend: {{instance}}
```

Stat chỉ nói target hiện đang thế nào; State timeline cho biết nó down từ lúc nào và có flapping không.

---

## 13. Standard options, threshold, mapping và override

### Standard options

Áp dụng mặc định cho mọi field:

- unit;
- min/max;
- decimals;
- display name;
- color scheme;
- no-value text.

Chọn unit theo dữ liệu gốc:

```text
0.25 ratio       → Percent (0.0-1.0) → 25%
25 percentage    → Percent (0-100)   → 25%
0.250 seconds    → seconds           → 250 ms tùy auto scale
250 milliseconds → milliseconds      → 250 ms
```

Sai unit tạo dashboard nhìn hợp lý nhưng sai nghĩa.

### Threshold

Ví dụ error ratio:

```text
green:  0
yellow: 1
red:    5
```

Threshold:

- chỉ tác động visualization;
- có mode absolute hoặc percentage;
- không tự tạo Grafana alert;
- nên bám SLO/capacity, không chọn màu tùy cảm giác.

### Value mapping

Biến raw value thành trạng thái dễ đọc:

```text
0    → DOWN
1    → UP
null → NO DATA
```

Value mapping có thể bypass unit formatting, nên kiểm tra kết quả hiển thị sau khi thêm mapping.

### Field override

Standard option áp dụng mọi field; override chỉ áp dụng field match:

```text
Fields matching regex /5..|error/
  → color red
  → line width 2

Field named "latency"
  → unit seconds
```

Không match override bằng display name dễ thay đổi nếu có thể dùng field/label ổn định hơn.

---

## 14. Variables theo Grafana 13

Variable biến dashboard cứng:

```promql
up{job="checkout", instance="checkout-1:8080"}
```

thành dashboard tái sử dụng:

```promql
up{job=~"$job", instance=~"$instance"}
```

### Các variable type

| Type | Dùng khi |
|---|---|
| Query | Option lấy từ data source. |
| Custom | Danh sách tĩnh nhỏ như `prod,staging`. |
| Text box | Cho nhập tự do; cần cẩn thận syntax/query cost. |
| Constant | Giá trị ẩn, cố định theo dashboard. |
| Data source | Chuyển backend giữa các environment/cluster. |
| Interval | Chọn khoảng group theo thời gian. |
| Switch | Bật/tắt một hành vi query/display. |
| Filter and Group by | Áp filter/grouping động cho Prometheus/Loki. |

Trong Grafana 13.1, ad hoc filter được mở rộng/đổi tên thành **Filter and Group by**; dashboard schema vẫn có thể dùng tên `AdhocVariable`.

### Query variable hiện hành

Với Prometheus, chọn query type rõ ràng:

| Query type | Ví dụ |
|---|---|
| Label names | Các label của `http_requests_total` |
| Label values | Giá trị label `job` hoặc `instance` |
| Metrics | Metric name khớp `http_.*_total` |
| Query result | Kết quả PromQL, ví dụ top-k |
| Series query | Series theo selector |
| Classic query | Cú pháp cũ như `label_values(...)`, đã deprecated |

Không tạo variable mới bằng Classic query nếu editor mới đã hỗ trợ use case.

### Variable `job`

```text
Name: job
Type: Query
Data source: Prometheus
Query type: Label values
Label: job
Metric: up
Refresh: On dashboard load
Multi-value: On
Include All: On
Custom all value: .+
```

### Chained variable `instance`

```text
Name: instance
Type: Query
Data source: Prometheus
Query type: Label values
Label: instance
Metric/selector: up{job=~"$job"}
Refresh: On dashboard load
Multi-value: On
Include All: On
Custom all value: .+
```

Thứ tự variable quan trọng:

```text
$job ──▶ query options của $instance ──▶ panel queries
```

Variable phụ thuộc phải đứng sau variable cha.

### Multi-value phải dùng regex matcher

Đúng:

```promql
up{job=~"$job", instance=~"$instance"}
```

Sai:

```promql
up{job="$job"}
```

Khi chọn nhiều giá trị, Grafana nối thành regex như:

```text
api|worker|checkout
```

Exact matcher `=` sẽ tìm literal đó thay vì ba giá trị.

### `${variable}` khi đứng cạnh text

```text
${env}-cluster
```

`$env-cluster` có thể bị parse thành tên variable khác. Syntax `[[env]]` là legacy, chỉ giữ để đọc dashboard cũ.

### Filter and Group by

Filter được áp vào **mọi query dùng data source đã chọn**. Điều này tiện cho điều tra:

```text
namespace = production
team != batch
```

Nhưng không thể chọn “chỉ áp filter cho panel A”. Nếu cần scope khác, dùng query variables tường minh.

---

## 15. Time range và refresh

Dashboard context gồm:

```text
time range + timezone + refresh interval + now delay
```

Gợi ý:

| Dashboard | Default time range | Refresh |
|---|---|---|
| Incident triage | Last 1h | 30s–1m |
| Service overview | Last 6h | 1m–5m |
| Capacity | Last 7d/30d | Off hoặc 15m+ |
| SLO report | 28d/30d | Off hoặc chậm |

Không đặt auto-refresh 5 giây cho dashboard 30 ngày. Mỗi refresh chạy lại variables và panel queries tùy cấu hình.

Khi chia sẻ incident:

- dùng absolute time range để người nhận thấy cùng cửa sổ;
- giữ variable values trong URL;
- ghi timezone nếu ảnh/chụp báo cáo được trao đổi ngoài Grafana.

---

## 16. Annotations: đặt sự kiện cạnh metric

Annotation trả lời:

```text
“Điều gì đã xảy ra tại thời điểm đường metric thay đổi?”
```

Ví dụ hiển thị alert firing từ Prometheus:

```promql
ALERTS{
  alertstate="firing",
  job=~"$job"
}
```

Ví dụ triển khai tốt hơn là ứng dụng/CI phát một metric event có label ổn định, hoặc dùng annotation API/integration phù hợp.

Annotation hữu ích cho:

- deployment;
- feature flag change;
- incident;
- alert firing/resolved;
- maintenance window.

Không dùng một gauge thay đổi liên tục như event mà không hiểu semantics; annotation query có thể tạo nhiều marker lặp trên toàn khoảng firing.

Trong Grafana 13, annotation là dashboard control và có thể chọn:

- hiển thị trên mọi panel;
- chỉ một số panel;
- ẩn khỏi controls;
- dùng variable trong query.

---

## 17. Drill-down bằng links

### Dashboard link

Đưa người dùng từ overview đến dashboard liên quan:

```text
Service Overview
  ├── Node Details
  ├── JVM Details
  └── Runbook
```

Nên bật:

- Include current time range;
- Include current template variable values.

### Panel link

Link cố định theo panel, ví dụ:

```text
Error ratio → Runbook lỗi 5xx
```

### Data link

Link theo field/value người dùng click:

```text
instance="api-7:8080"
  → dashboard instance với var-instance=api-7:8080
```

Giữ time context bằng:

```text
/d/target-dashboard?${__url_time_range}

# Nếu URL đã có query parameter:
/d/target-dashboard?orgId=1&${__url_time_range}
```

Kiểm tra URL encode và permission của destination. Link chứa label/user input không được coi là dữ liệu tin cậy để tạo action nguy hiểm.

---

## 18. Explore: nơi điều tra trước khi đóng gói dashboard

Explore phù hợp:

- thử PromQL;
- duyệt metrics/labels;
- zoom vào spike;
- so production và staging;
- split view metrics/logs;
- xem exemplar và chuyển đến trace;
- kiểm tra query trước khi tạo panel.

Workflow:

```text
1. Chọn Prometheus data source
2. Query overview
3. Thu hẹp time range quanh bất thường
4. Thêm label filter
5. Split view
6. So backend/cluster hoặc mở Loki
7. Đồng bộ time picker hai pane
8. Chỉ lưu thành panel khi query có mục đích lặp lại
```

Ví dụ:

```promql
# Pane trái: error ratio
sum(rate(http_requests_total{status=~"5.."}[$__rate_interval]))
/
sum(rate(http_requests_total[$__rate_interval]))
```

Pane phải có thể là cùng query ở staging, hoặc Loki logs cùng service/time range nếu đã cấu hình data source.

Explore không thay runbook. Một investigation lặp đi lặp lại nên được biến thành dashboard link, recording rule hoặc runbook step.

---

## 19. Panel inspector: nhìn request thật

Khi panel “trông sai”, mở panel menu → **Inspect**.

Các tab hữu ích:

| Tab | Dùng để |
|---|---|
| Data | Xem data frame/kết quả sau transformation. |
| Stats | Query duration, số row/request. |
| JSON | Panel JSON, data JSON và frame structure. |
| Query | Request/response gửi tới data source. |
| Error | Lỗi khi query thất bại. |

Inspector giúp trả lời:

- Grafana đã interpolate variable thành gì?
- start/end/step thực tế là bao nhiêu?
- Prometheus trả data hay transformation làm mất?
- query gọi mấy lần?
- response lớn/chậm ở đâu?

Đừng chỉ nhìn query text trong editor; request sau interpolation mới là request thực.

---

## 20. Chẩn đoán “No data”

Làm theo thứ tự:

```text
1. Data source Save & test
2. Explore: up
3. Mở rộng time range
4. Chạy selector không variable
5. Kiểm tra variable preview/current value
6. So = với =~
7. So Instant với Range
8. Inspect request: start/end/step/query
9. Kiểm tra transformation/field filter
10. Kiểm tra backend logs/limits/permission
```

### Case 1 – Multi-value nhưng dùng `=`

```promql
up{job="$job"}       # sai khi $job = api|worker
up{job=~"$job"}      # đúng
```

### Case 2 – Rate window quá ngắn

```promql
rate(counter_total[15s])                 # có thể không đủ sample
rate(counter_total[$__rate_interval])    # phù hợp hơn
```

### Case 3 – Stat dùng Range rồi reduce ngoài ý muốn

Stat phải biến nhiều điểm thành một giá trị bằng calculation như Last/Last not null/Mean. Nếu câu hỏi là “hiện tại”, cân nhắc Instant query để semantics rõ và response nhỏ hơn.

### Case 4 – Query có data nhưng panel trống

Kiểm tra:

- visualization có nhận đúng data shape không;
- Format có đúng Time series/Table/Heatmap;
- transformation có filter hết field;
- override có ẩn series;
- timezone/time field có đúng.

### Case 5 – Grafana không gọi được `localhost:9090`

Nếu Grafana chạy trong container, đổi sang service DNS hoặc hostname mà container resolve/route được.

---

## 21. Thiết kế dashboard cho vận hành

### Dùng hierarchy

```text
Fleet/Platform overview
        │ click service
        ▼
Service overview: RED + dependencies
        │ click instance/error
        ▼
Instance/JVM/DB detail
        │
        └── runbook / logs / traces
```

Một dashboard không cần chứa mọi metric.

### Overview theo RED

| Signal | Câu hỏi |
|---|---|
| Rate | Traffic hiện tại và xu hướng? |
| Errors | Lỗi tuyệt đối và tỷ lệ? |
| Duration | p50/p95/p99 có thay đổi? |

Resource dashboard theo USE:

| Signal | Câu hỏi |
|---|---|
| Utilization | Tài nguyên bận bao nhiêu? |
| Saturation | Có queue/wait/throttling không? |
| Errors | Hardware/kernel/runtime báo lỗi gì? |

### Màu sắc

- màu đỏ dành cho trạng thái cần hành động;
- cùng semantics dùng cùng màu giữa dashboard;
- không dùng đỏ/xanh chỉ để phân biệt hai series bình thường;
- kèm text/shape, không phụ thuộc màu vì accessibility;
- threshold phải ghi rõ absolute hay percentage.

### Panel density

Màn hình on-call cần ưu tiên:

```text
Top: SLO / traffic / error / latency
Middle: dependencies / saturation
Bottom: instance breakdown / diagnostic detail
```

Rows/tabs giúp nhóm nội dung; collapse không làm query chắc chắn biến mất trong mọi trường hợp/version, nên vẫn đo số request.

---

## 22. Performance và query cost

Dashboard chậm có thể gây áp lực ngược lên Prometheus:

```text
panels
× queries mỗi panel
× repeated values
× refreshes
× viewers
= query workload
```

Ví dụ:

```text
20 panels × 2 queries × 30 instances × refresh 30s
```

Repeating panel có thể biến thành hàng trăm query.

Giảm cost:

- aggregate/filter ở PromQL trước khi trả về;
- dùng recording rules cho query đắt và lặp lại;
- tránh variable options từ label có hàng chục nghìn values;
- đặt refresh theo tốc độ thay đổi thực;
- dùng Range/Instant đúng mục đích, tránh Both;
- giới hạn default time range;
- xem Stats/Query inspector;
- không để mọi panel load raw per-pod series;
- dùng dashboard link để chuyển detail thay vì nhồi một dashboard;
- đo query ở backend, không chỉ thời gian render browser.

Transformation không làm giảm dữ liệu đã được Prometheus gửi đến Grafana. Nếu query trả 100.000 series rồi transformation giữ 10, network/backend cost đã phát sinh.

---

## 23. Community dashboard: template, không phải production contract

Trước khi import:

- kiểm tra dashboard revision và Grafana version;
- đọc toàn bộ data source/plugin dependency;
- kiểm tra metric name/label khớp exporter đang chạy;
- kiểm tra variable query có dùng Classic syntax cũ;
- review PromQL query cost;
- xóa panel không có owner/use case;
- đổi data source reference sang UID ổn định;
- kiểm tra links không trỏ ra domain lạ;
- lưu bản đã review vào source control.

Dashboard ID phổ biến có thể đổi revision hoặc assumptions. Không hard-code một danh sách “dashboard tốt nhất” rồi coi như baseline.

---

## 24. Save, version và share

### Save

Khi lưu:

- đặt title rõ;
- chọn folder/team owner;
- dùng UID ổn định;
- ghi change summary;
- thêm tags có chủ đích;
- đặt default time range/refresh.

Version history trong Grafana hữu ích để khôi phục sửa nhầm, nhưng không thay dashboard-as-code/backup của Grafana database.

### Share

Internal link vẫn yêu cầu người nhận có permission. Chọn absolute time range khi chia sẻ một sự cố đã xảy ra.

Snapshot chứa dữ liệu đang hiển thị và có thể truy cập công khai bởi người có URL. Dù query bị loại khỏi snapshot, metric values và series names vẫn có thể nhạy cảm. Không publish snapshot ra dịch vụ ngoài nếu chưa review:

- hostname;
- customer/tenant label;
- topology;
- incident data;
- expiration và quyền xóa.

Externally shared dashboard có thể tạo nhiều query từ người xem; cần cân nhắc rate limit, caching và data exposure.

---

## 25. Bài lab hoàn chỉnh

### Yêu cầu

1. Chạy Grafana 13.1 với volume.
2. Provision Prometheus data source UID `prometheus`.
3. Dùng Explore xác nhận `up`.
4. Tạo folder `Services`.
5. Tạo dashboard `HTTP Service Overview`.
6. Tạo variable `$job`, `$instance` bằng Query type `Label values`.
7. Thêm bốn panel ở phần 12.
8. Dùng `$__rate_interval` cho counter.
9. Thêm value mapping cho `up`.
10. Thêm annotation alert/deploy.
11. Thêm dashboard/panel link giữ time range.
12. Dùng Inspector ghi lại query, step và response size.
13. Save với change summary.

### Acceptance criteria

- đổi `$job` làm mọi panel đổi đúng scope;
- chọn nhiều instance không trả No data vì sai matcher;
- zoom 15 phút → 24 giờ không tạo gap do rate window;
- Stat và Time series dùng đúng Instant/Range;
- error ratio hiển thị đúng unit;
- target state nhìn được lịch sử flapping;
- annotation xuất hiện đúng panel/time;
- link giữ nguyên time và variable context;
- reload container không làm mất dashboard;
- một người khác có folder permission phù hợp mở được dashboard.

---

## 26. Checklist fundamentals

### Data source

- [ ] Grafana server route được tới backend.
- [ ] Data source UID ổn định.
- [ ] `prometheusType` và version đúng backend.
- [ ] Scrape interval khớp thực tế.
- [ ] HTTP method/query timeout/series limit có chủ đích.
- [ ] Save & test và query `up` đều thành công.
- [ ] Không chứa secret plaintext trong Git.

### Query và panel

- [ ] Mỗi panel trả lời một câu hỏi.
- [ ] Range/Instant/Both được chọn có chủ đích.
- [ ] Counter dùng `rate`/`increase` với `$__rate_interval`.
- [ ] Legend không che cardinality cao.
- [ ] Unit đúng scale của dữ liệu.
- [ ] Threshold không bị nhầm là alert.
- [ ] Value mapping/override có semantics nhất quán.
- [ ] Panel description có owner/context khi cần.

### Variables và navigation

- [ ] Query variable mới không dùng Classic syntax deprecated.
- [ ] Multi/All dùng regex matcher `=~`.
- [ ] Chained variable đúng thứ tự.
- [ ] Variable preview không quá lớn/chậm.
- [ ] Links giữ time/variable context.
- [ ] Annotation không tạo marker lặp vô nghĩa.

### Operations

- [ ] Default time range và refresh hợp lý.
- [ ] Dashboard nằm đúng folder/permission.
- [ ] Inspector được dùng để đo query cost.
- [ ] Community dashboard đã được review.
- [ ] Snapshot/external sharing được xem là hành động công khai dữ liệu.
- [ ] Dashboard quan trọng có version/backup ngoài UI.

---

## 27. Câu hỏi tự kiểm tra

1. Grafana lưu gì và Prometheus lưu gì?
2. Data source khác dashboard thế nào?
3. Vì sao `localhost:9090` thường sai khi Grafana chạy container?
4. `prometheusType` ảnh hưởng gì?
5. Range, Instant và Both khác nhau thế nào?
6. Vì sao không nên để mọi query ở Both?
7. `$__interval` khác `$__rate_interval` ở đâu?
8. Min step ảnh hưởng rate interval thế nào?
9. Stat panel Range query phải reduce nhiều điểm ra sao?
10. Threshold có gửi notification không?
11. Standard option khác override thế nào?
12. Vì sao multi-value variable cần `=~`?
13. `label_values()` hiện thuộc query type nào?
14. Filter and Group by áp vào những panel nào?
15. Annotation khác time series thông thường thế nào?
16. Panel link và data link khác nhau ở đâu?
17. Inspector cho biết variable đã interpolate thành gì ở đâu?
18. Transformation có giảm tải Prometheus không?
19. Repeating panel có thể nhân query cost như thế nào?
20. Snapshot có thể lộ thông tin gì dù không chứa query?

---

## 28. Tài liệu chính thức

- [Grafana OSS download và phiên bản](https://grafana.com/grafana/download?edition=oss)
- [Run Grafana Docker image](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Grafana data sources](https://grafana.com/docs/grafana/latest/datasources/)
- [Configure Prometheus data source](https://grafana.com/docs/grafana/latest/datasources/prometheus/configure/)
- [Prometheus query editor](https://grafana.com/docs/grafana/latest/datasources/prometheus/query-editor/)
- [Prometheus template variables](https://grafana.com/docs/grafana/latest/datasources/prometheus/template-variables/)
- [Create dashboards](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/create-dashboard/)
- [Panels and visualizations](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/)
- [Standard options](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-standard-options/)
- [Field overrides](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-overrides/)
- [Value mappings](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/configure-value-mappings/)
- [Prometheus annotations](https://grafana.com/docs/grafana/latest/datasources/prometheus/annotations/)
- [Explore](https://grafana.com/docs/grafana/latest/visualizations/explore/get-started-with-explore/)
- [Panel inspector](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/panel-inspector/)
- [Dashboard links](https://grafana.com/docs/grafana/latest/visualizations/dashboards/build-dashboards/manage-dashboard-links/)
- [Manage dashboards và folders](https://grafana.com/docs/grafana/latest/visualizations/dashboards/manage-dashboards/)
- [Share dashboards and panels](https://grafana.com/docs/grafana/latest/dashboards/share-dashboards-panels/)

---

## Chủ đề tiếp theo

[Grafana Advanced – alerting, transformations, provisioning và dashboard-as-code](grafana_advanced.md)

---

*Cập nhật lần cuối: 2026-07-29*
