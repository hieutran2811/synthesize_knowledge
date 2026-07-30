# Grafana Advanced – Alerting, transformations và observability-as-code

> Phiên bản mục tiêu: **Grafana OSS 13.1.x**.
>
> Điều kiện đầu vào: đã đọc [Grafana Fundamentals](grafana_fundamentals.md), biết PromQL và hiểu dashboard/data source cơ bản.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- xử lý nhiều data frame bằng transformations mà không giấu business logic sai tầng;
- phân biệt Grafana-managed và data source-managed alert rules;
- thiết kế multi-dimensional alert theo label set;
- cấu hình pending, keep firing, No Data và Error theo failure mode;
- route notification qua contact point và notification policy tree;
- phân biệt silence, mute timing và active timing;
- provision dashboard/alerting resource bằng file an toàn;
- hiểu Classic dashboard model và V2 Resource của Grafana 13;
- chọn Git Sync, Terraform, Foundation SDK, HTTP API hoặc file provisioning;
- dùng service account token thay cho user/password trong automation;
- thiết kế CI/CD, promotion, drift detection và rollback cho dashboard/alert;
- nhận ra các anti-pattern như sửa provisioned resource trong UI hoặc provision nửa policy tree.

---

## 2. Mental model: từ prototype đến tài nguyên được quản lý

```text
Explore
  │ thử query
  ▼
Dashboard / Alert UI
  │ preview + review semantics
  ▼
Export definition
  │
  ├── JSON / YAML file provisioning
  ├── Git Sync
  ├── Terraform
  ├── Foundation SDK
  └── HTTP API
          │
          ▼
Git review → validate → deploy → smoke test → observe → rollback
```

Điểm mấu chốt:

```text
UI là nơi prototype tốt.
Git là source of truth tốt.
Pipeline là nơi kiểm soát thay đổi tốt.
Production không nên có hai source of truth cạnh tranh.
```

Grafana Advanced không đồng nghĩa “viết JSON bằng tay”. Dashboard JSON và alert query model có nhiều trường nội bộ, thay đổi theo schema/plugin. Workflow an toàn hơn:

1. tạo use case nhỏ trong UI;
2. kiểm tra query, data shape, alert preview;
3. export đúng format;
4. đưa vào code/tooling;
5. review diff có ngữ nghĩa;
6. deploy qua một cơ chế duy nhất.

---

## 3. Bốn lớp nâng cao cần tách biệt

| Lớp | Trách nhiệm | Ví dụ |
|---|---|---|
| Data shaping | Biến data frame thành shape visualization cần | Join, organize, reduce |
| Alert evaluation | Quyết định mỗi label set có vi phạm không | Query A → Reduce B → Threshold C |
| Notification routing | Quyết định gửi ai, lúc nào, gộp thế nào | Policy tree, contact point |
| Resource lifecycle | Tạo, cập nhật, xóa và version hóa resource | Provisioning, Terraform, Git Sync |

Một lỗi phổ biến là trộn cả bốn:

```text
Panel transformation tính error ratio
  → copy bằng tay sang alert
  → hard-code Slack trong rule
  → sửa trực tiếp ở production UI
```

Hệ quả: dashboard và alert lệch logic, routing không tái sử dụng, không rõ source of truth và không rollback được.

---

## 4. Transformations xử lý data frame

Transformation chạy **sau khi data source trả kết quả** và trước visualization:

```text
Query A ─┐
         ├──▶ Data frames ──▶ Transform 1 ──▶ Transform 2 ──▶ Panel
Query B ─┘
```

Khi có nhiều transformation, Grafana áp dụng đúng theo thứ tự danh sách. Output bước trước là input bước sau.

### Các transformation thường dùng

| Transformation | Dùng để |
|---|---|
| Add field from calculation | Tạo field từ phép tính row/binary/window |
| Concatenate fields | Ghép fields từ nhiều frame nối tiếp nhau |
| Join by field | Join nhiều frame theo key chung |
| Merge series/tables | Merge frame có field dùng chung |
| Labels to fields | Chuyển labels thành columns/fields |
| Reduce | Rút nhiều row/point thành giá trị tổng hợp |
| Group by | Group rows rồi aggregate |
| Organize fields by name | Rename, reorder, ẩn field |
| Filter data by values | Giữ/bỏ rows theo điều kiện |
| Filter fields by name | Giữ/bỏ columns |
| Sort by | Sắp xếp rows |
| Convert field type | Chuyển string/number/time/boolean/enum |
| Extract fields | Parse JSON, key-value hoặc regex |
| Config from query results | Lấy unit/min/max/threshold/mapping từ query khác |

Tên/options JSON nội bộ có thể đổi. Cấu hình từ UI hoặc SDK phù hợp version thay vì copy một mảng transformation JSON cũ.

---

## 5. Ví dụ transformation: bảng service health

Mục tiêu:

```text
Service | Request/s | Error % | p95 | State
```

### Query A – request rate

```promql
sum by (job) (
  rate(http_requests_total[$__rate_interval])
)
```

### Query B – error ratio

```promql
100 *
sum by (job) (
  rate(http_requests_total{status=~"5.."}[$__rate_interval])
)
/
clamp_min(
  sum by (job) (
    rate(http_requests_total[$__rate_interval])
  ),
  1e-9
)
```

### Query C – p95

```promql
histogram_quantile(
  0.95,
  sum by (job, le) (
    rate(http_request_duration_seconds_bucket[$__rate_interval])
  )
)
```

Đặt ba query thành **Instant** và Format **Table**, sau đó:

```text
1. Join by field: job
2. Organize fields:
   - Value #A → Request/s
   - Value #B → Error %
   - Value #C → p95
   - ẩn Time dư thừa
3. Sort by: Error % descending
4. Field overrides:
   - Error % → Percent (0-100)
   - p95 → seconds
   - Request/s → reqps
```

Nếu join tạo nhiều row hơn dự kiến, kiểm tra:

- key `job` có duy nhất trong từng query không;
- một query còn label `instance`, `status` hoặc `le` không;
- Instant query có trả đúng một row/label set không;
- field name sau query có trùng nhau không.

Transformation không sửa identity sai từ query. Aggregate PromQL đến đúng grain trước khi join.

---

## 6. Khi nào dùng PromQL, transformation hoặc recording rule?

| Trường hợp | Nên dùng |
|---|---|
| Tính toán dùng cho alert/SLO/nhiều dashboard | PromQL hoặc recording rule |
| Giảm cardinality trước khi gửi data về Grafana | PromQL |
| Rename/reorder/ẩn columns | Transformation |
| Join hai data source khác loại ở presentation layer | Transformation |
| Query rất đắt, chạy lặp lại | Recording rule |
| Logic cần unit test và owner rõ | Recording rule / code |
| Quick exploration một panel | Transformation có thể phù hợp |

Anti-pattern:

```text
Prometheus trả 100.000 series
→ Grafana transformation filter còn 10
```

Backend/network/browser vẫn đã trả và xử lý 100.000 series. Filter/aggregate từ query trước.

### Config from query results

Transformation này có thể lấy min/max/unit/threshold/value mapping từ một query khác. Hữu ích khi threshold được quản lý như data, nhưng:

- panel vẫn có base threshold;
- source query phải có schema ổn định;
- thay data có thể đổi màu/semantics mà không đổi dashboard code;
- không dùng nó để thay alert rule hoặc SLO contract.

---

## 7. Grafana Alerting gồm hai loại rule

| Loại | Rule lưu/evaluate ở đâu? | Điểm mạnh |
|---|---|---|
| Grafana-managed | Grafana Alerting | Query nhiều data source, expressions, No Data/Error control |
| Data source-managed | Prometheus-compatible backend như Prometheus/Mimir/Loki | Rule gần data, dùng semantics/tooling của backend |

Grafana 13 khuyến nghị Grafana-managed cho use case mới, nhưng không có nghĩa phải migrate mọi Prometheus rule.

### Khi giữ rule ở Prometheus/backend

- page quan trọng phải chạy dù Grafana lỗi;
- rule đã được `promtool` test và vận hành ổn;
- recording rule cần ghi series về TSDB;
- muốn rule evaluation gần local scrape data;
- organization đã dùng GitOps cho Prometheus rules.

### Khi dùng Grafana-managed

- cần query data source ngoài Prometheus;
- cần expressions Reduce/Math/Threshold;
- muốn quản lý evaluation và notification trong Grafana;
- cần UI preview/export và lifecycle thống nhất;
- backend hỗ trợ query nhưng không tự quản lý rule theo nhu cầu.

Đừng chạy cùng logical alert ở cả Prometheus và Grafana nếu chưa chủ động deduplicate. Hai rule engine có thể tạo hai notification khác nhau.

---

## 8. Pipeline của Grafana-managed alert

```text
Query A: lấy dữ liệu
   │
   ▼
Expression B: Reduce / Resample / Math
   │
   ▼
Expression C: Threshold hoặc condition
   │
   ▼
Một alert instance cho mỗi label set
   │
   ▼
Pending → Alerting → Recovering → Normal
   │
   ▼
Notification policy → Contact point
```

Alert query không được dùng dashboard template variables như `$job` hoặc `$__rate_interval`. Alert phải evaluate độc lập với người đang mở dashboard:

```promql
# Dashboard query
rate(http_requests_total{job=~"$job"}[$__rate_interval])

# Alert query: selector và window tường minh
rate(http_requests_total{job="checkout"}[5m])
```

Nếu cần rule tái sử dụng cho nhiều service, trả về nhiều series theo label `job` thay vì dashboard variable.

---

## 9. Ví dụ multi-dimensional alert: error ratio

Query A:

```promql
sum by (job) (
  rate(http_requests_total{status=~"5.."}[5m])
)
/
clamp_min(
  sum by (job) (
    rate(http_requests_total[5m])
  ),
  1e-9
)
```

Trong rule editor:

```text
A: Prometheus query, trả một series cho mỗi job
B: Reduce(A, Last)
C: Threshold(B > 0.05)

Evaluation interval: 1m
Pending period: 5m
Keep firing for: 5m
Condition: C
```

Kết quả:

```text
{job="checkout"} → alert instance 1
{job="payment"}  → alert instance 2
{job="search"}   → alert instance 3
```

Không reduce toàn bộ jobs thành một scalar nếu muốn biết service nào lỗi.

### Labels để route, annotations để giải thích

```text
Labels:
  severity = warning
  team = platform
  environment = production

Annotations:
  summary = Tỷ lệ 5xx cao ở {{ $labels.job }}
  description = Error ratio hiện tại là {{ $values.B.Value }}
  runbook_url = https://runbooks.example.com/high-error-ratio
  dashboard_url = https://grafana.example.com/d/service-overview
```

Nếu muốn route theo đội sở hữu từng dịch vụ, label `team` phải có sẵn trong
kết quả query/metric hoặc nên tách rule theo ranh giới ownership. Không nên
gán cứng `team=checkout` cho một query đang trả về nhiều `job`.

Nguyên tắc:

- label ổn định và cardinality hữu hạn;
- annotation có nội dung con người đọc;
- không đặt giá trị động như timestamp/current value thành label;
- routing match label, không match annotation text;
- mọi page phải có owner/runbook hoặc đường escalation rõ.

---

## 10. Evaluation lifecycle

Ba tham số:

| Tham số | Câu hỏi |
|---|---|
| Evaluation interval | Bao lâu đánh giá một lần? |
| Pending period | Điều kiện phải vi phạm liên tục bao lâu trước khi firing? |
| Keep firing for | Sau khi hết vi phạm, giữ firing bao lâu để chống flapping? |

Ví dụ:

```text
interval = 1m
pending = 5m
keep firing = 3m

Normal
  → điều kiện true
Pending
  → true đủ 5m
Alerting
  → điều kiện false
Recovering
  → false đủ 3m
Normal + resolved notification
```

Pending không phải delay tùy ý:

- quá ngắn gây noise;
- quá dài làm tăng detection time;
- phải phù hợp SLO, scrape interval và failure duration;
- thay rule logic có thể reset alert instances về Normal.

`Keep firing for` giảm firing/resolved/firing do dao động quanh threshold. Nó không sửa threshold thiết kế sai.

---

## 11. No Data, Error và Missing Series

Ba trường hợp khác nhau:

| Trường hợp | Ý nghĩa |
|---|---|
| Error | Query timeout/thất bại, data source không trả kết quả hợp lệ |
| No Data | Query thành công nhưng không trả data point nào |
| Missing Series | Query vẫn trả một số series, nhưng một label set trước đó biến mất |

Với Grafana-managed rule, No Data và Error có thể:

- tạo state/alert riêng mặc định;
- chuyển thành Alerting;
- chuyển thành Normal;
- Keep Last State.

Mặc định, Grafana tạo alert riêng:

```text
alertname="DatasourceNoData"
alertname="DatasourceError"
```

Chúng có labels khác alert gốc, nên silence/policy match alert gốc có thể không áp dụng.

### Cách chọn semantics

| Use case | No Data gợi ý |
|---|---|
| Metric phải luôn tồn tại | Alert hoặc alert thiếu dữ liệu riêng |
| Batch chạy không liên tục | Normal hoặc query theo cửa sổ phù hợp |
| Exporter chập chờn ngắn | Pending/Keep Last có thể giảm noise |
| Billing/audit | Không dựa duy nhất vào monitoring alert |

`Keep Last State` tránh dao động tạm thời nhưng có thể giữ Normal trong outage data source kéo dài. Cần alert riêng cho datasource health.

Không dùng:

```promql
metric_query or on() vector(0)
```

theo phản xạ. Nó có thể biến “metric biến mất” thành “giá trị bình thường bằng 0”. Chỉ dùng khi zero thật sự đúng nghĩa nghiệp vụ.

---

## 12. Notification architecture

```text
Alert instances
      │ labels
      ▼
Notification policy tree
  ├── route theo team
  ├── route theo severity
  ├── group
  ├── timing
  └── mute/active intervals
      │
      ▼
Contact point
  ├── Email
  ├── Slack / Teams
  ├── PagerDuty / IRM
  └── Webhook / Alertmanager
```

### Contact point

Contact point là danh sách integrations/destinations. Trước khi nối rule:

1. tạo contact point;
2. gửi test notification;
3. xác minh firing và resolved;
4. kiểm tra template với một và nhiều alerts;
5. xác minh secret rotation.

### Notification policy

Policy là cây, không phải danh sách độc lập:

```text
Default → platform-default
├── team=checkout → checkout-slack
│   └── severity=critical → checkout-pager
├── team=database → dba
└── alertname=DatasourceError → observability
```

Matcher cùng policy được kết hợp bằng AND. Mặc định, deepest matching child xử lý alert; bật “continue matching siblings” khi muốn nhiều sibling cùng nhận.

Root default phải là đường bắt mọi alert không match child.

---

## 13. Grouping và notification timings

| Timer | Ý nghĩa |
|---|---|
| Group wait | Chờ trước notification đầu để gom alerts mới |
| Group interval | Chờ trước notification khi group có thay đổi |
| Repeat interval | Gửi nhắc lại nếu group không đổi và vẫn firing |

Ví dụ:

```text
group_by: [grafana_folder, alertname, cluster]
group_wait: 30s
group_interval: 5m
repeat_interval: 4h
```

Trade-off:

- group theo `instance` có thể tạo quá nhiều notification;
- group quá rộng làm notification khổng lồ, khó biết owner;
- repeat quá ngắn gây spam;
- repeat quá dài có thể làm incident bị quên.

Grouping không deduplicate hai alert có label identity khác. Cần thiết kế labels trước.

---

## 14. Silence, mute timing và active timing

| Cơ chế | Dùng khi | Rule còn evaluate? |
|---|---|---|
| Silence | Một maintenance/incident cụ thể theo matcher và thời hạn | Có |
| Mute timing | Lịch lặp lại không gửi notification | Có |
| Active timing | Chỉ route trong khoảng thời gian được phép | Có |
| Disable/pause rule | Tạm ngừng evaluation | Không |

Ví dụ:

- deploy maintenance 30 phút → silence;
- notification business-hours lặp hàng tuần → mute/active timing;
- rule sai gây overload → pause trong khi rollback;
- không xóa rule để “tắt tạm”.

Silence/mute chỉ chặn notification, không làm alert state biến mất. Đây là ưu điểm khi cần audit nhưng không muốn page.

---

## 15. File provisioning cho Grafana Alerting

Self-managed Grafana đọc file trong:

```text
/etc/grafana/provisioning/alerting/
```

File provisioning:

- tạo/update/delete resource khi startup hoặc hot reload;
- không có trong Grafana Cloud;
- resource được file-provision không edit được trong UI;
- import trùng resource hiện có có thể conflict;
- nên export từ UI/API thay vì tự đoán `data.model`.

### Workflow an toàn

```text
1. Tạo rule ở dev UI
2. Preview query + condition
3. Test notification
4. Export YAML/JSON provisioning
5. Review và thay UID/folder/data source UID có chủ đích
6. Đưa file vào Git
7. Deploy dev/canary
8. Hot reload hoặc restart
9. Kiểm tra rule health/state/routing
10. Promote production
```

### Vì sao không viết tay `data.model`?

Outer contract tương đối dễ đọc:

```text
apiVersion
groups[]
  orgId
  name
  folder
  interval
  rules[]
    uid
    title
    condition
    data[]
    noDataState
    execErrState
    for
    annotations
    labels
```

Nhưng `data[].model` chứa model của query editor/data source/expression. Nó là phần nên lấy từ **Export rule definition** hoặc export endpoint tương ứng, sau khi rule đã chạy đúng.

Provisioning format và HTTP API request format không giống nhau. Không lấy JSON từ GET thường rồi đặt thẳng vào file provisioning; dùng endpoint `/export` hoặc UI export.

---

## 16. Contact point và policy provisioning

Ví dụ contact point webhook:

```yaml
# provisioning/alerting/contact-points.yaml
apiVersion: 1

contactPoints:
  - orgId: 1
    name: platform-webhook
    receivers:
      - uid: platform_webhook
        type: webhook
        disableResolveMessage: false
        settings:
          url: $ALERT_WEBHOOK_URL
```

Nếu `ALERT_WEBHOOK_URL` không tồn tại, provisioning thay bằng chuỗi rỗng. Pipeline phải kiểm secret/env trước khi start Grafana.

Ví dụ policy tree:

```yaml
# provisioning/alerting/policies.yaml
apiVersion: 1

policies:
  - orgId: 1
    receiver: platform-default
    group_by: [grafana_folder, alertname, cluster]
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      - receiver: checkout-slack
        matchers:
          - team = checkout
        routes:
          - receiver: checkout-pager
            matchers:
              - severity = critical

      - receiver: observability
        matchers:
          - alertname =~ "DatasourceError|DatasourceNoData"
```

`receiver` phải tham chiếu contact point tồn tại.

### Cảnh báo quan trọng

Notification policy tree được xem là **một resource duy nhất**. Provision file policy sẽ overwrite toàn cây, không merge một nhánh nhỏ. Vì vậy:

- một repository/owner quản lý toàn cây;
- export backup trước thay đổi;
- diff toàn cây;
- test default route;
- không cho hai pipeline cùng PUT/provision policy tree.

### Escape `$` trong provisioning

Grafana thay `$VARIABLE` bằng environment variable ở phần lớn provisioning properties. Nếu contact-point template thực sự muốn giữ `$labels`, escape:

```yaml
settings:
  subject: '{{ $$labels }}'
```

Sau interpolation, Grafana nhận:

```text
{{ $labels }}
```

Một số field như alert annotations, query model và notification template content được loại khỏi env interpolation, nhưng đừng giả định mọi field đều như vậy.

---

## 17. Dashboard file provisioning

Provider:

```yaml
# provisioning/dashboards/providers.yaml
apiVersion: 1

providers:
  - name: team-dashboards
    orgId: 1
    type: file
    disableDeletion: false
    allowUiUpdates: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

Filesystem:

```text
/var/lib/grafana/dashboards/
├── Platform/
│   ├── kubernetes-overview.json
│   └── nodes.json
└── Services/
    ├── checkout.json
    └── payment.json
```

Với `foldersFromFilesStructure: true`:

- không đặt `folder` hoặc `folderUid` trong provider;
- Grafana tái tạo nested folder từ filesystem;
- độ sâu folder tối đa hiện tại là bốn;
- file ở root path vào root dashboard level.

### Watch hay poll?

```text
updateIntervalSeconds <= 10 → filesystem watch
updateIntervalSeconds > 10  → polling
```

Một số bind mount/network filesystem không truyền watch event. Dùng giá trị trên 10 giây để ép polling nếu thay đổi file không được phát hiện.

---

## 18. `allowUiUpdates` và `disableDeletion`

### `allowUiUpdates: false`

- có thể xem provisioned dashboard;
- không save UI changes;
- source file là nguồn duy nhất.

Đây là lựa chọn rõ ràng cho GitOps.

### `allowUiUpdates: true`

- UI save vào Grafana database;
- không ghi ngược về provisioning file;
- lần file thay đổi, Grafana overwrite UI version;
- dễ tạo drift và mất thay đổi.

Nếu cho phép UI prototype:

```text
Edit → Export → commit source → deploy
```

Không để UI edit trở thành source of truth thứ hai.

### `disableDeletion`

Khi source file bị xóa:

- `disableDeletion: false` → Grafana có thể xóa dashboard trong DB;
- `disableDeletion: true` → dashboard được giữ lại.

Chọn theo lifecycle:

- Git muốn quản lý cả delete → `false`, nhưng PR phải review deletion;
- chỉ muốn bootstrap/create → có thể `true`, chấp nhận orphan/drift.

Grafana bỏ qua `version` thấp hơn trong provisioning source khi reconcile; source file vẫn có thể overwrite database dashboard.

---

## 19. Classic dashboard và V2 Resource

Grafana 13.1 cho phép export:

| Model | Khi dùng |
|---|---|
| Classic | Tương thích Grafana 12.4 trở xuống và tooling cũ |
| V2 Resource | Schema mới, JSON hoặc YAML, resource-style |

V2 Resource có envelope:

```yaml
kind: Dashboard
apiVersion: dashboard.grafana.app/v1
metadata:
  name: service-overview
spec:
  title: Service Overview
  # panels, variables, layout...
```

File provisioning dashboard v2/dynamic dashboard phải dùng Kubernetes resource format.

Không trộn hai format trong pipeline mà không biết tool nào nhận format nào:

```text
UI export format
≠ legacy dashboard API payload
≠ new dashboard API resource
≠ alerting provisioning format
```

Luôn ghi rõ contract ở tên thư mục hoặc README:

```text
dashboards/classic/
dashboards/v2/
alerting/file-provisioning/
```

---

## 20. Chọn observability-as-code workflow

| Cách | Phù hợp | Trade-off |
|---|---|---|
| File provisioning | Self-managed, đơn giản, read-only GitOps | Không có trong Cloud; UI không ghi ngược |
| Git Sync | Muốn sync hai chiều UI ↔ Git | Cần governance cho commit/conflict/branch |
| Terraform provider | Đã dùng Terraform, quản lý nhiều resource | State, provider upgrades và large JSON diff |
| Foundation SDK | Muốn typed code, reuse component | Build dependency và SDK/schema upgrades |
| HTTP API | Custom automation/integration | Tự xử lý idempotency, auth, conflict, rollback |
| Grafonnet/Jsonnet | Đội đã có library/pipeline ổn định | Pin library; kiểm compatibility panel/schema mới |
| Grafana Operator | Kubernetes-native resource lifecycle | Capability phụ thuộc operator/version |

Không có lựa chọn tốt nhất cho mọi đội.

### Decision guide

```text
Một Grafana self-managed, dashboard JSON có sẵn?
  → File provisioning

Muốn người dùng edit UI và commit ngược Git?
  → Git Sync

Đã quản lý folders/data sources/alerts bằng Terraform?
  → Terraform provider

Muốn reusable typed dashboard components?
  → Foundation SDK

Tích hợp từ một platform/controller riêng?
  → HTTP API hoặc Operator
```

---

## 21. Git Sync trong Grafana 13.1

Git Sync hiện GA cho Grafana Cloud, OSS và Enterprise. Nó đồng bộ hai chiều:

```text
Git repository
      ▲     │
      │     ▼
Grafana Git Sync
      ▲     │
UI edit     │ Git edit
```

Luồng:

1. Grafana theo dõi repository/branch/path;
2. tạo dashboard từ JSON;
3. UI edit có thể được commit lại Git;
4. Git edit được pull vào Grafana;
5. sync theo interval hoặc webhook.

Hai mode:

| Mode | Layout |
|---|---|
| Folder sync | Tạo wrapper folder theo repository |
| Folderless sync | Đặt resource ngay top-level/path tương ứng |

Governance cần chốt:

- branch protected hay Grafana commit trực tiếp;
- commit identity;
- ai review UI-generated diff;
- conflict resolution;
- dev/prod dùng branch, path hay repo khác nhau;
- token/GitHub App scope;
- webhook authentication;
- behavior khi Git provider outage.

Bidirectional sync tiện, nhưng production UI write không tự động đồng nghĩa thay đổi đã được peer review.

---

## 22. Foundation SDK

Grafana Foundation SDK cho phép định nghĩa dashboard bằng typed builders và hiện hỗ trợ nhiều ngôn ngữ gồm Go, TypeScript, Python, PHP và Java.

```text
Typed source
  → compile/build validation
  → dashboard JSON
  → file provisioning / API / Git Sync
```

Lợi ích:

- autocomplete và type checking;
- component hóa panel/row/variables;
- sinh nhiều dashboard từ một convention;
- review logic nguồn thay vì raw JSON khổng lồ.

Trade-off:

- generated JSON vẫn cần kiểm tra;
- SDK version phải pin;
- Grafana/SDK upgrade cần compatibility test;
- abstraction quá cao có thể che query và panel semantics.

Pattern thư mục:

```text
grafana/
├── src/
│   ├── components/
│   │   ├── red-signals.ts
│   │   └── variables.ts
│   └── dashboards/
│       ├── checkout.ts
│       └── payment.ts
├── generated/
│   ├── checkout.json
│   └── payment.json
└── tests/
```

Không sửa file trong `generated/`; sửa typed source rồi build lại.

---

## 23. Terraform

Terraform phù hợp khi cần quản lý cùng lúc:

- folders;
- data sources;
- dashboards;
- teams/permissions tùy edition;
- alert rule groups;
- contact points/policies;
- cloud resources.

Ví dụ tối thiểu, cần đối chiếu schema provider version đã pin:

```hcl
provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_service_account_token
}

resource "grafana_folder" "services" {
  title = "Services"
}

resource "grafana_dashboard" "checkout" {
  folder      = grafana_folder.services.id
  config_json = file("${path.module}/dashboards/checkout.json")
}
```

Nguyên tắc:

- pin provider version và commit lock file;
- backend state có encryption/locking;
- token qua secret manager/CI variable;
- `terraform plan` là artifact review;
- không import toàn production mù quáng;
- hiểu resource nào là nguyên khối, đặc biệt notification policy tree;
- canary ở environment riêng trước apply production.

Raw dashboard JSON vẫn tạo diff khó đọc. Có thể generate bằng Foundation SDK/Grafonnet rồi dùng Terraform deploy.

---

## 24. HTTP API và service account

Service account thay API key như cách chính cho automation:

```text
CI job → service account token → Grafana HTTP API
```

Không dùng:

```text
http://admin:password@grafana/api/...
```

Dùng:

```bash
curl --request POST \
  --url "${GRAFANA_URL}/apis/dashboard.grafana.app/v1/namespaces/default/dashboards" \
  --header "Authorization: Bearer ${GRAFANA_TOKEN}" \
  --header "Content-Type: application/json" \
  --data-binary @dashboard-resource.json
```

New Dashboard API dùng resource endpoint:

```text
POST /apis/dashboard.grafana.app/v1/namespaces/:namespace/dashboards
PUT  /apis/dashboard.grafana.app/v1/namespaces/:namespace/dashboards/:uid
```

Body là Dashboard resource có `metadata` và `spec`.

Checklist:

- service account theo environment;
- least privilege folder/dashboard scope nếu edition hỗ trợ;
- token expiration và rotation;
- không log header/token;
- xử lý `409 Conflict` bằng resource version/idempotency contract;
- kiểm response/status, không chỉ exit code curl;
- lưu commit message/annotation khi API hỗ trợ;
- không đưa token Grafana Cloud telemetry vào API quản trị và ngược lại.

Alerting Provisioning HTTP API có format riêng. Một số endpoint contact point/policy/template/mute timing cũ đã deprecated để chuyển sang App Platform APIs; kiểm tài liệu đúng Grafana version trước khi xây integration mới.

---

## 25. CI/CD pipeline cho dashboard và alert

```text
Pull request
  │
  ├── lint source
  ├── build generated definitions
  ├── parse JSON/YAML
  ├── policy checks
  ├── PromQL/rule tests nếu tách được
  ├── render/smoke trên Grafana canary
  └── plan/diff artifact
          │ approve
          ▼
Deploy dev → smoke → deploy prod → observe → rollback nếu lỗi
```

### Static checks

- UID hợp lệ và duy nhất;
- data source UID tồn tại;
- không chứa secret;
- không dùng datasource name dễ đổi nếu UID dùng được;
- không dùng Classic variable query mới;
- query không có unbounded regex tùy tiện;
- dashboard có owner/tags;
- alert có `team`, `severity`, `runbook_url`;
- policy có default receiver;
- mọi receiver reference tồn tại;
- generated files khớp source.

### Runtime smoke checks

- dashboard API trả resource;
- panels không `No data` ngoài chủ đích;
- variables load được;
- query count/latency trong budget;
- alert rule health OK;
- contact point test thành công;
- label test route đến đúng policy;
- DatasourceError/NoData có route riêng;
- rollback version được chứng minh.

JSON parse thành công không chứng minh PromQL đúng hoặc panel hữu ích.

---

## 26. Promotion giữa environments

Tránh copy dashboard rồi sửa hard-code:

```text
dev-prometheus
staging-prometheus
prod-prometheus
```

Hai pattern:

### Cùng data source UID

Mỗi Grafana environment provision:

```text
uid = prometheus
url = endpoint riêng của environment
```

Dashboard dùng UID `prometheus`, không cần generate khác.

### Data source variable

Một Grafana có nhiều clusters:

```text
prometheus-dev
prometheus-staging
prometheus-prod
```

Dùng data source variable khi người xem cần chuyển. Không dùng nó trong Grafana alert rule; alert cần data source cố định.

Promotion:

```text
same source commit
  → build một lần
  → deploy dev
  → promote chính artifact đó
  → prod
```

Không rebuild từ branch thay đổi giữa các environment.

---

## 27. Drift và ownership

Các nguồn drift:

- UI edit trên provisioned dashboard;
- Terraform và file provisioning cùng quản lý một UID;
- Git Sync và API pipeline cùng ghi;
- đổi data source UID;
- import community dashboard đè UID;
- production hotfix không backport Git;
- policy tree sửa UI trong khi Terraform quản lý.

Mỗi resource cần ownership metadata:

```text
managed_by: file-provisioning | git-sync | terraform | api
owner: team
source_repo: URL/path
environment: prod
```

Có thể lưu một phần dưới tags/annotations/README tùy resource.

Drift detection:

1. định kỳ export/current-state;
2. normalize field runtime như version/id;
3. so với generated desired state;
4. alert hoặc tạo PR;
5. không tự overwrite khi chưa hiểu nguồn drift.

---

## 28. Rollback

### Dashboard

- revert commit/generated artifact;
- redeploy qua cùng mechanism;
- xác minh UID không đổi;
- smoke variables/panels/links.

### Alert rule

- revert rule definition;
- hiểu thay condition có thể reset alert instance state;
- kiểm notification không firing giả sau rollback;
- không xóa rồi recreate nếu UID/state continuity quan trọng.

### Policy tree

- giữ export backup toàn cây;
- rollback cả resource;
- test default route và critical routes;
- không rollback riêng một child YAML nếu deploy mechanism overwrite toàn tree.

### Contact point

- rotate secret độc lập khi có thể;
- test resolved notification;
- tránh rollback về credential đã revoke.

Rollback không chỉ “API trả 200”; cần chứng minh behavior đã trở lại.

---

## 29. Advanced panel patterns

### Repeating panels

Repeating panel/row/tab tạo bản sao theo variable:

```text
1 base panel × 30 instances = 30 rendered panels
```

Dùng cho số option nhỏ. Với hàng trăm pod:

- dùng overview aggregate;
- table top-k;
- data link sang instance dashboard;
- không repeat toàn fleet.

### Dynamic config

`Config from query results` cho phép threshold/min/max/value mapping theo data. Dùng khi contract threshold nằm trong một backend được quản lý; ghi rõ source/owner vì người sửa data có thể thay dashboard semantics.

### Cross-source join

Ví dụ Prometheus health + SQL ownership:

```text
Prometheus: job, error_ratio
SQL:        job, team, tier
        │
        └── Join by job → operations table
```

Rủi ro:

- key không duy nhất;
- refresh/caching khác nhau;
- một source chậm làm panel chậm;
- authorization có thể khác;
- alert rule không nhất thiết tái sử dụng được transformation này.

Đừng dùng browser-side join làm CMDB quan trọng duy nhất.

---

## 30. Anti-patterns

### Alert dùng dashboard variable

Alert evaluation không có người chọn `$job`. Trả multi-series hoặc tạo rule cụ thể.

### Một rule trả hàng chục nghìn alert instances

Đây là cardinality/noise incident. Aggregate theo user impact và đặt guardrail.

### `No Data = OK` cho mọi rule

Data source outage có thể làm toàn hệ thống “xanh”. Chọn theo use case và alert datasource health.

### Provision từng nhánh policy từ nhiều repo

Policy tree là một resource; pipeline sau có thể xóa nhánh pipeline trước.

### `allowUiUpdates=true` nhưng không có export workflow

UI change sẽ bị source file overwrite.

### Viết tay alert `data.model`

Model dễ lệch plugin/version. Prototype và export.

### API dùng admin password

Dùng service account token least privilege, có rotation.

### Transformation thay recording rule

Nhiều dashboard lặp cùng phép tính nặng sẽ làm backend tốn tài nguyên và logic phân kỳ.

### Generated JSON được sửa trực tiếp

Lần build tiếp theo sẽ mất thay đổi. Sửa source/generator.

### Deploy “latest” SDK/provider/Grafonnet

Pin version và test output với Grafana mục tiêu.

---

## 31. Bài lab

### Phần A – Transformation

1. Tạo ba Instant query request rate, error ratio và p95 theo `job`.
2. Join theo `job`.
3. Rename, reorder và đặt unit.
4. Sort error ratio giảm dần.
5. Dùng Inspector kiểm input/output từng bước.

### Phần B – Alerting

1. Tạo Grafana-managed error-ratio alert.
2. Giữ một alert instance mỗi `job`.
3. Pending 5 phút, keep firing 3 phút.
4. Thêm labels `team`, `severity`, `environment`.
5. Chọn semantics No Data/Error.
6. Tạo/test contact point.
7. Tạo route theo team/severity.
8. Test DatasourceError route.
9. Export rule/contact/policy.

### Phần C – As code

1. Commit exported dashboard và alert resources.
2. Provision dashboard với polling 30 giây.
3. Đặt `allowUiUpdates: false`.
4. Validate UID/data source references.
5. Deploy Grafana lab/canary.
6. Sửa query qua Git và xác minh reconcile.
7. Revert commit và đo rollback.

### Acceptance criteria

- join không nhân rows;
- transformation order có giải thích;
- alert tạo đúng số instances;
- pending/keep-firing behavior được quan sát;
- No Data không bị coi nhầm là Error;
- default policy bắt alert không match;
- contact point nhận firing và resolved;
- file-provisioned resource không sửa được ở UI;
- dashboard giữ UID qua deploy/rollback;
- Git không chứa token/webhook secret.

---

## 32. Checklist advanced

### Transformations

- [ ] Query đã aggregate đến đúng grain.
- [ ] Transformation order được review.
- [ ] Join key duy nhất ở mỗi input.
- [ ] Inspector xác minh data shape.
- [ ] Logic dùng lại đã chuyển về backend/recording rule.
- [ ] Response cardinality được giới hạn trước transformation.

### Alert rules

- [ ] Rule engine được chọn có chủ đích.
- [ ] Không duplicate logical alert giữa Grafana/Prometheus.
- [ ] Không dùng dashboard variable.
- [ ] Alert instance labels hữu hạn và ổn định.
- [ ] Pending/keep firing dựa trên SLO/failure mode.
- [ ] No Data, Error và Missing Series được phân biệt.
- [ ] Có owner, severity, summary và runbook.
- [ ] Rule query/model được export từ version mục tiêu.

### Notifications

- [ ] Default receiver hoạt động.
- [ ] Policy tree có một owner/source of truth.
- [ ] Group labels/timers đã load-test.
- [ ] Continue siblings chỉ bật có chủ đích.
- [ ] DatasourceError/NoData có route.
- [ ] Contact point test firing/resolved.
- [ ] Silence/mute không bị nhầm với pause evaluation.
- [ ] Secret được inject và rotate.

### As code

- [ ] Một resource chỉ có một manager.
- [ ] UID/data source UID ổn định.
- [ ] Classic/V2/API format được ghi rõ.
- [ ] Tool/SDK/provider version được pin.
- [ ] CI parse, policy-check và smoke-test.
- [ ] Artifact được promote, không rebuild khác nhau.
- [ ] Drift detection và rollback được diễn tập.
- [ ] Service account token least privilege.

---

## 33. Câu hỏi tự kiểm tra

1. Transformation chạy trước hay sau data source query?
2. Vì sao transformation không giảm dữ liệu backend đã trả?
3. Join theo label không duy nhất gây gì?
4. Khi nào nên dùng recording rule thay transformation?
5. Grafana-managed khác data source-managed rule ở đâu?
6. Vì sao alert không dùng được `$job` dashboard variable?
7. Một multi-dimensional rule tạo alert instances thế nào?
8. Labels và annotations trong alert khác trách nhiệm gì?
9. Pending khác keep firing thế nào?
10. No Data khác Missing Series thế nào?
11. `DatasourceError` có cùng labels alert gốc không?
12. Contact point khác notification policy thế nào?
13. Group wait, group interval và repeat interval khác nhau ở đâu?
14. Silence khác mute timing và pause rule thế nào?
15. Vì sao không nên viết tay `data.model`?
16. File-provisioned alert có edit được trong UI không?
17. Provision policy tree có merge một child route không?
18. Khi nào cần escape `$$labels`?
19. `allowUiUpdates=true` có ghi ngược source file không?
20. `disableDeletion=false` có tác động gì khi xóa source?
21. Grafana 13.1 có những dashboard export model nào?
22. Git Sync khác file provisioning ở khả năng UI edit ra sao?
23. Foundation SDK giải quyết vấn đề gì?
24. Vì sao service account tốt hơn admin basic auth cho CI?
25. Hai pipeline cùng quản lý một UID tạo failure mode nào?

---

## 34. Tài liệu chính thức

- [Grafana Alerting](https://grafana.com/docs/grafana/latest/alerting/)
- [Configure alert rules](https://grafana.com/docs/grafana/latest/alerting/alerting-rules/)
- [Queries and conditions](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rules/queries-conditions/)
- [Alert rule evaluation](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rule-evaluation/)
- [No Data and Error states](https://grafana.com/docs/grafana/latest/alerting/fundamentals/alert-rule-evaluation/nodata-and-error-states/)
- [Notifications](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/)
- [Notification policies](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/notification-policies/)
- [Group alert notifications](https://grafana.com/docs/grafana/latest/alerting/fundamentals/notifications/group-alert-notifications/)
- [File provisioning alerting resources](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/file-provisioning/)
- [Export alerting resources](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/export-alerting-resources/)
- [Transform data](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/query-transform-data/transform-data/)
- [Provision Grafana](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Grafana as code](https://grafana.com/docs/grafana/latest/as-code/)
- [Git Sync key concepts](https://grafana.com/docs/grafana/latest/as-code/observability-as-code/git-sync/key-concepts/)
- [Foundation SDK](https://grafana.com/docs/grafana/latest/as-code/observability-as-code/foundation-sdk/)
- [Grafana Terraform provider](https://grafana.com/docs/grafana/latest/as-code/infrastructure-as-code/terraform/)
- [Grafana HTTP API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/)
- [Dashboard HTTP API](https://grafana.com/docs/grafana/latest/developer-resources/api-reference/http-api/dashboard/)
- [Service accounts](https://grafana.com/docs/grafana/latest/administration/service-accounts/)

---

## Chủ đề tiếp theo

[Grafana Production – HA, database, SSO, security và operations](grafana_production.md)

---

*Cập nhật lần cuối: 2026-07-29*
