---
title: "Data Pipeline & ETL Observability – Từ Dữ liệu nguồn đến Dataset đáng tin cậy"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 12
---
# Data Pipeline & ETL Observability – Từ Dữ liệu nguồn đến Dataset đáng tin cậy

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát dữ liệu qua extract, queue/storage, transform, load,
> publish và consumption. Một DAG xanh chỉ chứng minh các task đã kết thúc theo cách
> orchestrator hiểu; nó không chứng minh dữ liệu đủ, đúng, mới hoặc an toàn để sử dụng.
>
> Baseline tham chiếu: OpenLineage 1.50, Apache Airflow 3.3, Apache Spark 4.2,
> dbt artifacts hiện hành và Great Expectations 1.19. Schema, metric name và tính năng
> có thể đổi theo phiên bản; production phải pin phiên bản và kiểm tra tài liệu tương ứng.
>
> Không log bản ghi thô, khóa, token, query chứa literal nhạy cảm hoặc danh sách đầy đủ
> các giá trị vi phạm. Telemetry của data platform cũng là dữ liệu cần phân loại, giới hạn
> truy cập và retention.
>
> Nên đọc trước:
> [Database Observability](database_observability_performance.md),
> [Messaging & Kafka Observability](messaging_kafka_observability.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md) và
> [Telemetry Governance & FinOps](telemetry_governance_finops.md).

---

## 1. Vì sao data pipeline observability khác?

Application thường có request rõ ràng: nhận, xử lý rồi trả kết quả. Pipeline dữ liệu có thể
chạy hàng giờ, đọc nhiều nguồn, ghi nhiều partition và chỉ được đánh giá khi consumer dùng
output sau đó.

Ba trạng thái phải tách riêng:

```text
Execution healthy ≠ Data healthy ≠ Business outcome healthy
```

Ví dụ:

- task hoàn tất nhưng đọc nhầm partition rỗng;
- đủ số dòng nhưng tỷ lệ `null` tăng đột biến;
- dữ liệu đúng nhưng trễ hơn deadline dashboard;
- bảng đã cập nhật nhưng downstream model vẫn đọc snapshot cũ.

Observability phải trả lời cả **pipeline có chạy không**, **dữ liệu có đáng tin không** và
**ai đang bị ảnh hưởng**.

## 2. Vòng đời end-to-end

```text
Source
  → extract/change capture
  → transport/staging
  → validation
  → transform
  → load
  → publish
  → consumer
  → business decision
```

Mỗi chặng cần:

- identity ổn định;
- thời điểm event và processing;
- input/output count hoặc byte;
- trạng thái, attempt và error class;
- dataset/version/partition;
- quan hệ upstream/downstream;
- data-quality result.

Chỉ đo thời gian chạy ở orchestrator sẽ bỏ sót source delay, publish delay và consumer lag.

## 3. Ba mục tiêu

| Mục tiêu | Câu hỏi |
|---|---|
| Reliability | Pipeline có chạy, retry và phục hồi đúng không? |
| Data quality | Output có đủ, hợp lệ, nhất quán và đúng nghĩa không? |
| Fitness for use | Dataset có đến kịp và phù hợp consumer/business không? |

Thứ tự ưu tiên khi có sự cố:

1. ngăn publish dữ liệu nguy hiểm;
2. xác định blast radius;
3. giữ evidence và checkpoint;
4. phục hồi theo cách idempotent;
5. sửa nguyên nhân và contract.

## 4. Data product và contract

Một dataset production nên được xem như data product có contract:

```yaml
dataset: analytics.orders_daily
owner: data-commerce
grain: one row per order_date and country
freshness_slo: 45m
primary_key: [order_date, country]
schema_version: 7
classification: confidential
consumers: [revenue_dashboard, demand_forecast]
```

Contract cần mô tả:

- grain và semantic;
- schema, nullable, unit, timezone;
- khóa và uniqueness;
- freshness/completeness SLO;
- compatibility policy;
- owner, consumer và escalation;
- retention, privacy và access policy.

Không có contract thì “data quality” dễ trở thành tập rule tùy ý, không gắn nhu cầu consumer.

## 5. SLI và SLO

Một số SLI hữu ích:

```text
freshness      = publish_time - max(event_time)
completeness   = observed_expected_units / expected_units
validity       = valid_rows / checked_rows
run success    = successful_required_runs / scheduled_required_runs
delivery delay = consumer_visible_time - expected_ready_time
```

SLO ví dụ:

- 99% partition theo giờ sẵn sàng trong 20 phút;
- 99.9% record bắt buộc có khóa hợp lệ;
- không publish nếu reconciliation lệch quá 0.1%;
- 99% sự cố critical có lineage blast radius trong 15 phút.

Đừng trộn mọi pipeline vào một SLO. Tier theo criticality và deadline của consumer.

## 6. Batch, streaming và CDC

| Kiểu | Đơn vị tiến độ | Failure thường gặp |
|---|---|---|
| Batch | run, partition, file | missed schedule, partial output |
| Micro-batch | trigger/batch ID | backlog, checkpoint delay |
| Streaming | offset, watermark | lag, out-of-order, state growth |
| CDC | log position/LSN/SCN | connector lag, schema change, snapshot gap |

Batch có điểm kết thúc rõ. Streaming thường chạy lâu dài nên “process up” không đủ; cần đo
progress theo cửa sổ. CDC cần nối source commit position với sink applied position.

## 7. Identity và dimensions

Identity gợi ý:

```text
pipeline_id
job_id
run_id
task_id
attempt
dataset_namespace
dataset_name
partition
environment
code_version
contract_version
```

`run_id`, file path, query text và error message không nên là label metric vì cardinality
không giới hạn. Chúng phù hợp hơn với trace/log. Metric chỉ giữ dimension có tập giá trị
nhỏ và phục vụ aggregation.

## 8. Ba loại thời gian

Phân biệt:

- **event time**: lúc sự kiện xảy ra trong business;
- **ingestion time**: lúc platform nhận dữ liệu;
- **processing time**: lúc engine xử lý;
- **publish time**: lúc output có thể được consumer đọc.

Một record hôm qua được backfill hôm nay có event time cũ nhưng processing time mới.
Nếu chỉ nhìn `updated_at`, dashboard có thể báo “fresh” sai.

Chuẩn hóa UTC trong telemetry; timezone business thuộc contract và phải chuyển đổi rõ ràng.

## 9. Freshness

Freshness nên đo ở boundary mà consumer quan tâm:

```text
data_freshness_seconds =
  now() - max(source_event_time_visible_to_consumer)
```

Không dùng duy nhất `now - table_modified_time`: metadata có thể đổi do compaction, optimize
hoặc permission update mà không có dữ liệu business mới.

Freshness cần dimension bounded như dataset, tier và environment. Partition cụ thể có thể
đưa vào log/trace hoặc chỉ metric cho cửa sổ gần nhất.

## 10. Availability không đồng nghĩa freshness

Bảng tồn tại và query được chưa chắc dữ liệu mới. Ngược lại, partition mới có thể đã publish
nhưng catalog/cache consumer chưa nhận ra.

Kiểm tra tối thiểu:

```text
storage readable
AND expected partition exists
AND partition is committed
AND max event time meets SLO
AND critical quality checks pass
```

Readiness của dataset nên là state machine, không phải boolean suy ra từ một task cuối.

## 11. Completeness

Completeness cần mẫu số có nghĩa:

```text
row completeness = actual rows / expected rows
source coverage   = received sources / expected sources
partition coverage = ready partitions / expected partitions
```

Expected count có thể đến từ:

- source control total;
- manifest/file list;
- business calendar;
- historical band có seasonality;
- reconciliation giữa debit/credit hoặc header/detail.

So với trung bình đơn giản dễ false alert vào cuối tuần, ngày lễ hoặc chiến dịch.

## 12. Volume và throughput

Theo dõi:

- records/bytes read, filtered, rejected, written;
- rows/second và bytes/second;
- batch size;
- compression ratio;
- amplification giữa input và output.

Ví dụ invariant:

```text
input = accepted + rejected + intentionally_filtered
```

Throughput giảm có thể do source ít dữ liệu, pipeline chậm hoặc filter sai. Luôn xem cùng
freshness, queue delay và resource utilization.

## 13. Uniqueness

Uniqueness phải bám vào grain:

```sql
SELECT business_key, COUNT(*) AS n
FROM output
WHERE partition_date = :date
GROUP BY business_key
HAVING COUNT(*) > 1;
```

Đừng chạy full-table scan mỗi phút. Có thể:

- kiểm tra partition mới;
- dùng approximate distinct cho cảnh báo sớm;
- chạy exact validation trước publish;
- lưu aggregate, không xuất toàn bộ key vi phạm.

Duplicate thường đến từ retry không idempotent, replay chồng cửa sổ hoặc join many-to-many.

## 14. Validity

Validity kiểm tra dữ liệu tuân contract:

- type và parseability;
- range/domain;
- format;
- enum;
- nullable;
- temporal rules;
- cross-field constraints.

```text
validity_ratio = 1 - invalid_rows / checked_rows
```

Rule cần severity: warning không nên chặn pipeline; critical có thể quarantine output.
Quyết định này thuộc owner và consumer, không để công cụ validation tự suy đoán.

## 15. Accuracy

Accuracy hỏi giá trị có phản ánh thực tế hay không. Đây là chiều khó nhất vì thường cần
nguồn chuẩn hoặc ground truth.

Các kỹ thuật:

- đối soát với system of record;
- control totals và checksum;
- sample audit;
- business invariant;
- delayed reconciliation;
- human review cho trường hợp giá trị cao.

Một giá trị có đúng type/range vẫn có thể sai thực tế. Vì vậy validity không thay thế accuracy.

## 16. Consistency và reconciliation

Ví dụ đối soát:

```text
source_order_count == sink_order_count + quarantined_count
sum(source_amount)  ≈ sum(sink_amount)
opening + movements == closing
```

Luôn ghi:

- cửa sổ và timezone;
- tolerance;
- currency/unit;
- late-arrival policy;
- snapshot/version hai phía.

So sánh hai bảng ở hai thời điểm khác nhau tạo chênh lệch giả.

## 17. Schema observability

Phát hiện:

- thêm/xóa/đổi tên field;
- type hoặc nullability thay đổi;
- field order khi format phụ thuộc vị trí;
- nested schema thay đổi;
- logical type, precision và scale;
- default/semantic đổi mà physical schema không đổi.

Schema fingerprint nên gắn với run và dataset version. Alert chỉ khi thay đổi vi phạm
compatibility policy; additive nullable field có thể hợp lệ nhưng vẫn cần thông báo consumer.

## 18. Distribution observability

Theo dõi phân phối của feature/cột quan trọng:

- quantile;
- histogram có bucket ổn định;
- category share cho top bounded categories;
- min/max;
- zero/negative rate;
- entropy hoặc distance score.

Không biến từng giá trị category thành metric label. Với high-cardinality column, tính sketch
hoặc profile artifact rồi lưu reference vào telemetry.

## 19. Null và missingness

Null rate:

```text
null_rate(column, window) = null_count / row_count
```

Phân biệt:

- null hợp lệ theo business;
- field thiếu do schema/parser;
- empty string;
- sentinel như `-1`, `"unknown"`;
- default bị điền che mất missing.

Theo dõi null theo segment quan trọng, nhưng tránh tạo tổ hợp dataset × column × tenant
không giới hạn trong Prometheus.

## 20. Referential integrity

Kiểm tra orphan:

```sql
SELECT COUNT(*)
FROM fact_order f
LEFT JOIN dim_customer d ON f.customer_id = d.customer_id
WHERE d.customer_id IS NULL;
```

Trong pipeline eventual consistency, orphan tạm thời có thể hợp lệ. Contract phải nêu grace
period và cách recheck. Alert ngay lập tức cho mọi orphan thường gây nhiễu khi dimension
đến muộn.

## 21. Late và out-of-order data

Metric nên có:

- event-time lateness distribution;
- record sau watermark;
- record bị drop/quarantine;
- correction/upsert count;
- phần trăm window phải cập nhật lại.

```text
lateness = ingestion_time - event_time
```

Lateness âm thường chỉ ra clock/timezone lỗi. Late-data policy phải nói rõ update output,
ghi correction hay bỏ qua.

## 22. Duplicate và idempotency

Exactly-once ở một engine không tự bảo đảm exactly-once end-to-end. Sink side effect,
external API hoặc retry ngoài transaction vẫn có thể tạo duplicate.

Mẫu an toàn:

- deterministic idempotency key;
- checkpoint gắn output commit;
- merge/upsert theo business key;
- atomic transaction hoặc write-audit-publish;
- dedup window phù hợp maximum replay.

Theo dõi duplicate detected, suppressed và escaped-to-consumer riêng biệt.

## 23. Watermark và window

Watermark là tuyên bố “không chờ vô hạn dữ liệu cũ hơn mốc này”, không phải bằng chứng mọi
record trước mốc đều đã đến.

Quan sát:

```text
event_time_max
watermark_time
processing_time
watermark_lag = processing_time - watermark_time
state_rows / state_bytes
late_rows_dropped
```

Watermark quá dài làm state lớn và output chậm; quá ngắn làm mất correction hợp lệ.

## 24. Offset, checkpoint và progress

Streaming progress cần nối:

```text
source latest offset
→ consumed offset
→ processed offset
→ committed sink version
```

Checkpoint age, checkpoint duration và restore failure là tín hiệu quan trọng. “Consumer lag
bằng 0” vẫn có thể sai nếu job đã nhảy offset hoặc commit trước khi sink durable.

Không xóa checkpoint production để chữa lỗi khi chưa hiểu delivery semantics và recovery path.

## 25. Retry và failure taxonomy

Phân loại:

- transient infrastructure;
- quota/rate limit;
- source unavailable;
- bad record;
- schema/contract;
- deterministic code bug;
- resource exhaustion;
- permission/security;
- timeout/cancel.

Retry chỉ dành cho lỗi có khả năng hồi phục. Bad record hoặc code bug retry vô hạn vừa tốn
tiền vừa che root cause. Metric cần attempt, terminal state và retry delay.

## 26. Backfill

Backfill phải là workflow hạng nhất:

```text
scope → estimate → approve → isolate → execute
      → validate → publish → reconcile → close
```

Gắn `run_type=scheduled|manual|backfill|recovery`, nhưng không dùng backfill ID ngẫu nhiên
làm metric label. Theo dõi:

- partition planned/completed/failed;
- overlap với scheduled run;
- warehouse cost;
- freshness của live path;
- correction impact đến consumer.

Backfill không được làm starvation workload production.

## 27. Partial write và atomic publish

Consumer không nên nhìn thấy output đang viết dở. Các mẫu:

- write vào staging rồi atomic rename/swap;
- immutable partition + manifest;
- table format có snapshot transaction;
- commit marker chỉ sau validation;
- versioned view/pointer.

Theo dõi `write_complete`, `validation_complete`, `publish_complete` riêng. Task writer success
nhưng publish fail là trạng thái recoverable khác với dữ liệu hỏng.

## 28. Partition observability

Kiểm tra:

- expected partition có tồn tại;
- đúng naming/timezone;
- row/byte distribution giữa partition;
- partition quá nhỏ/lớn;
- partition pruning thực sự xảy ra;
- late partition và overwrite.

Đừng gắn mọi partition lịch sử làm time-series. Export metric cho current window và lưu
chi tiết lịch sử trong warehouse/catalog.

## 29. Small files và compaction

Nhiều file nhỏ làm metadata/listing/query overhead tăng. Theo dõi:

- file count/partition;
- median và p95 file size;
- compaction backlog;
- file-open time;
- metadata request rate.

Compaction thay đổi file layout chứ không nên thay đổi semantic dataset. Reconcile row count
và checksum trước/sau, đồng thời tránh làm `modified_time` giả dạng freshness.

## 30. Format, compression và serialization

Quan sát:

- parse error theo format/version;
- compression ratio;
- schema evolution;
- corrupt block/file;
- unsupported codec;
- reader/writer compatibility.

CSV dễ có delimiter, quote và encoding issue; Parquet/Avro/ORC có schema và block metadata
nhưng vẫn cần contract. “File mở được” không chứng minh giá trị business hợp lệ.

## 31. Source observability

Tại source, đo:

- availability và query latency;
- snapshot timestamp;
- change-log position;
- source row/control count;
- permission/quota;
- schema fingerprint;
- source-side data delay.

Pipeline không nên tự nhận mọi source delay là lỗi của mình. Dashboard cần phân biệt
`source_not_ready`, `extract_late` và `downstream_processing_late`.

## 32. Extract

Extract cần record:

```text
requested window
actual source snapshot/version
cursor start/end
rows/bytes read
rows rejected
duration
```

Cursor chỉ theo timestamp có thể bỏ sót record cùng timestamp hoặc update muộn. Dùng tuple
ổn định như `(updated_at, primary_key)` hoặc native log position khi có thể.

## 33. Transform

Theo dõi từng transform:

- input/output count;
- filter/join/aggregate amplification;
- shuffle/spill;
- skew;
- rejected rows;
- code/query fingerprint;
- dependency và contract version.

Join amplification bất thường thường quan trọng hơn task duration. Ví dụ output tăng 100 lần
vì khóa dimension không unique dù query vẫn chạy nhanh và thành công.

## 34. Load

Load observability gồm:

- rows inserted/updated/deleted;
- merge match/not-match;
- commit duration;
- constraint violation;
- deadlock/lock wait;
- bytes scanned/written;
- target snapshot/version.

Tách `write` và `publish`. Với warehouse, query thành công nhưng `rows_affected=-1` có thể là
“không biết”, không được diễn giải thành zero.

## 35. Orchestrator observability

Quan sát hai lớp:

```text
control plane: scheduler, metadata DB, queue, worker, triggerer
data plane: DAG/task/run, source, dataset, validation, publish
```

Metric:

- schedule delay;
- queued duration;
- task duration;
- retry/failure;
- worker capacity;
- scheduler heartbeat;
- orphan/stuck tasks;
- callback/alert delivery failure.

Orchestrator khỏe không bảo đảm data plane khỏe và ngược lại.

## 36. Apache Airflow

Airflow hiện cung cấp metric cho task/DAG duration, scheduling/queue delay, executor/pool
capacity, heartbeat và nhiều trạng thái control plane; Airflow cũng có thể xuất trace qua
OpenTelemetry.

Thực hành:

- dùng `dag_id`, `task_id` có taxonomy ổn định;
- nối `run_id` vào trace/log, không phải metric;
- kiểm tra scheduler độc lập với web/API health;
- lưu task log remote có retention;
- emit data-quality/publish result từ task business.

HTTP 200 của health endpoint chỉ nói request health check thành công; phải đọc trạng thái
component trong payload.

## 37. Spark và distributed compute

Quan sát:

- job/stage/task duration;
- executor lost;
- shuffle read/write và spill;
- skewed partitions;
- GC/heap;
- input/output records;
- speculative/retried tasks;
- query progress.

Với Structured Streaming, `StreamingQueryProgress` cung cấp rate, latency và source/sink
progress. Processing rate cao vẫn có thể tụt lại nếu input rate cao hơn trong thời gian dài.

## 38. Kafka và stream processor

Nối các tín hiệu:

```text
broker/source lag
→ processor input rate
→ watermark/state
→ sink commit
→ consumer-visible freshness
```

Không chỉ alert consumer lag. Một processor đọc nhanh rồi ghi sink chậm hoặc drop record có
thể giữ lag thấp nhưng output sai. Xem thêm
[Messaging & Kafka Observability](messaging_kafka_observability.md).

## 39. dbt observability

Các artifact quan trọng:

- `manifest.json`: graph, node, source, dependency và configuration;
- `run_results.json`: status/timing của node đã thực thi;
- `sources.json`: kết quả source freshness;
- catalog artifacts: metadata relation/column.

Join artifact bằng `unique_id` và kiểm tra schema version của artifact. Không suy ra node
không xuất hiện trong `run_results.json` là thành công; nó có thể đơn giản là không được chọn.

## 40. Warehouse và lakehouse

Theo dõi:

- query queue/compile/execute time;
- bytes/partitions scanned;
- slots/warehouse utilization;
- spill và cache;
- transaction/snapshot conflict;
- compaction/optimization;
- storage và compute cost;
- failed/aborted query.

Tách cost do scheduled, ad hoc, backfill và recovery. Query rẻ nhưng tạo dataset sai không
phải tối ưu; query đúng nhưng scan toàn bảng mỗi giờ cũng không bền vững.

## 41. Lineage

Lineage trả lời:

- output dùng input nào;
- job/run nào tạo output;
- thay đổi này ảnh hưởng consumer nào;
- cột nhạy cảm đi qua transformation nào;
- cần backfill những dataset nào.

Có ba mức:

1. pipeline/task lineage;
2. dataset lineage;
3. column-level lineage.

Lineage phải có version/time; graph “hiện tại” không đủ điều tra một run cũ.

## 42. OpenLineage

Object model cốt lõi:

```text
Job(namespace, name)
Run(runId)
Dataset(namespace, name)
RunEvent(eventType, eventTime, inputs, outputs, facets)
```

Facets bổ sung schema, parent run, processing engine, quality assertions và metadata khác.
Custom facet phải có prefix riêng và `_schemaURL` immutable để tránh collision/migration mơ hồ.

Không nhét payload business vào facet. Emit event cũng cần reliability metric và dead-letter
path; lineage mất âm thầm tạo cảm giác an toàn giả.

## 43. Column-level lineage

Column lineage giúp impact analysis chính xác hơn, nhưng chi phí và độ phức tạp cao.

Phân biệt:

- direct identity/transformation/aggregation;
- indirect join/filter/group/sort/window;
- masking.

Không suy đoán column lineage từ SQL text khi parser không hiểu dynamic SQL/UDF rồi coi kết
quả là chắc chắn. Gắn confidence/source và cho phép “unknown”.

## 44. Data contract và schema registry

Schema registry quản lý cấu trúc serialization; data contract rộng hơn và bao gồm semantic,
quality, ownership và SLO.

Compatibility:

| Kiểu | Ý nghĩa thực tế |
|---|---|
| Backward | reader mới đọc được data cũ |
| Forward | reader cũ đọc được data mới |
| Full | cả hai hướng |

Một thay đổi additive vẫn có thể phá consumer dùng `SELECT *`, positional mapping hoặc quota
cứng. Contract test nên chạy cả producer và representative consumers.

## 45. Catalog, ownership và metadata

Mỗi production dataset cần:

- owner kỹ thuật và business;
- description/grain;
- classification;
- SLO/tier;
- upstream/downstream;
- schema/contract version;
- last successful publish;
- deprecation date;
- runbook.

Catalog thiếu owner biến alert thành “không ai nhận”. Kiểm tra metadata completeness như một
policy, nhưng không tự gán owner từ người commit cuối.

## 46. Telemetry model

Mô hình đề xuất:

```text
Metric: aggregate health/trend
Trace: run/task/dependency critical path
Log: diagnostic event và error
Lineage event: job-run-dataset relationship
Quality result: assertion, scope, observed value, threshold
Profile artifact: distribution/sketch/sample-safe summary
```

Không ép mọi thứ thành metric. Run history, test result và lineage thường phù hợp store truy
vấn metadata hơn Prometheus.

## 47. Metrics

Ví dụ metric contract:

```text
data_pipeline_runs_total{pipeline,outcome,run_type}
data_pipeline_run_duration_seconds{pipeline}
data_pipeline_schedule_delay_seconds{pipeline}
data_dataset_freshness_seconds{dataset,tier}
data_quality_checks_total{dataset,check,severity,outcome}
data_records_total{pipeline,stage,outcome}
data_pipeline_backlog_units{pipeline}
data_pipeline_cost_units_total{pipeline,run_type}
```

Không label theo `run_id`, raw partition, query, file, customer hoặc error message.

## 48. Traces

Trace hierarchy:

```text
pipeline run
├─ wait for source
├─ extract
├─ transform
│  ├─ read
│  ├─ join
│  └─ write staging
├─ validate
└─ publish
```

Attributes nên gồm code version, dataset identity, contract version, run type và bounded
outcome. Link thay vì parent-child khi batch fan-out/fan-in hoặc xử lý bất đồng bộ.

## 49. Logs và events

Structured event:

```json
{
  "event": "dataset_publish_completed",
  "pipeline": "orders_hourly",
  "run_id": "scheduled__2026-07-30T10:00:00Z",
  "dataset": "analytics.orders_hourly",
  "contract_version": 7,
  "source_watermark": "2026-07-30T09:58:12Z",
  "rows": 128402,
  "quality_gate": "passed"
}
```

Log không chứa row sample mặc định. Nếu cần forensic sample, dùng kho riêng, mã hóa, audit
access và TTL ngắn.

## 50. Data profiling

Profile hữu ích:

- count/null/distinct;
- quantiles;
- top-k đã giới hạn;
- histogram/sketch;
- pattern/type inference;
- correlation cho subset quan trọng.

Profile là tín hiệu khám phá, không tự động là contract. Chuyển profile thành rule chỉ sau khi
owner xác nhận seasonality, business change và tolerance.

## 51. Privacy

Nguy cơ:

- unexpected values chứa PII;
- SQL/query log chứa literal;
- lineage làm lộ tên dataset nhạy cảm;
- profile/top-k tái nhận diện nhóm nhỏ;
- debug dump không có retention.

Controls:

- allowlist field;
- hash/tokenize identifier khi thật sự cần correlation;
- aggregate và minimum cohort size;
- RBAC/ABAC;
- encryption và audit;
- deletion propagation.

## 52. Cardinality

Ước lượng trước:

```text
series ≈ pipelines × tasks × outcomes × environments × run_types
```

Nếu thêm dataset, partition, column và check name không kiểm soát, số series tăng theo tích.
Giải pháp:

- registry tên check;
- roll-up task ít quan trọng;
- profile chi tiết ở metadata store;
- current-state metric;
- exemplar nối trace.

## 53. Cost observability

Phân bổ:

- compute time/slot/GPU;
- bytes scanned/written;
- storage và retention;
- network egress;
- orchestrator/metadata;
- validation/profile;
- retries và backfill.

Unit economics:

```text
cost per successful publish
cost per million valid records
cost per fresh consumer-hour
waste from retries/backfills
```

Không giảm validation critical chỉ để hạ bill. Tối ưu scan, incremental strategy và retention
trước khi giảm safety.

## 54. Dashboard

Dashboard theo thứ tự quyết định:

1. data products vi phạm SLO;
2. freshness/completeness/quality;
3. failed/late runs và backlog;
4. upstream/downstream blast radius;
5. stage latency/resource;
6. cost và waste;
7. links đến trace, lineage và runbook.

Dashboard orchestrator riêng khỏi dashboard data product, nhưng liên kết hai chiều.

## 55. Alerting

Alert theo symptom consumer:

- critical dataset quá freshness SLO;
- expected partition chưa publish sau grace period;
- completeness/quality gate fail;
- reconciliation breach;
- backlog/watermark lag tăng liên tục;
- lineage emission hoặc alert delivery mất;
- cost runaway do retry/backfill.

Tránh alert mọi task failure nếu retry tự phục hồi trước deadline. Page khi cần hành động ngay;
ticket cho degradation chưa ảnh hưởng SLO.

## 56. Incident triage

Trình tự:

```text
consumer impact
→ affected datasets/partitions
→ last known good publish
→ lineage blast radius
→ source readiness
→ pipeline critical path
→ quality/reconciliation
→ recent code/schema/config change
```

Không “clear task rồi xem sao” trước khi giữ run state, attempt log, offsets và output version.
Thao tác đó có thể phá evidence hoặc tạo duplicate.

## 57. Blast radius

Blast radius cần trả lời:

- dashboard/report nào;
- ML feature/model nào;
- API/export nào;
- tenant/region/time window nào;
- quyết định business nào;
- data đã được external consumer tải chưa.

Kết hợp lineage với access/query logs và catalog. Lineage tĩnh chỉ cho dependency tiềm năng;
usage cho biết consumer thực tế trong khoảng sự cố.

## 58. Replay và recovery

Recovery plan:

1. đóng băng publish hoặc chuyển consumer về snapshot tốt;
2. xác định window và last good checkpoint;
3. sửa source/code/contract;
4. chạy replay isolated;
5. validate và reconcile;
6. atomic publish;
7. thông báo consumer và theo dõi correction.

Gắn correction version để consumer biết dữ liệu đã thay đổi. Không overwrite âm thầm khi
output đã dùng cho báo cáo tài chính hoặc quyết định quan trọng.

## 59. Testing

Các lớp test:

- unit test transformation;
- schema/contract test;
- data-quality test;
- integration với source/sink;
- idempotency/retry;
- backfill/replay;
- failure injection;
- performance/cost regression;
- representative consumer test.

Test bằng sample “đẹp” không bắt được skew, late data, duplicate hoặc partition boundary.

## 60. Canary và shadow

Canary pipeline:

- chạy code mới trên subset thời gian/tenant;
- ghi output version riêng;
- so sánh row count, checksum, distribution và business KPI;
- không publish cho consumer chính;
- promote khi gate đạt.

Shadow giúp phát hiện semantic regression mà không ảnh hưởng production. Cần tính chi phí
double compute và không sao chép PII sang môi trường ít bảo vệ hơn.

## 61. Capacity planning

Capacity dựa trên:

- input growth;
- peak/backfill overlap;
- state size;
- shuffle/spill;
- storage/file count;
- warehouse concurrency;
- deadline/SLO;
- recovery throughput.

Hệ thống có thể xử lý steady state nhưng không catch up sau outage. Đo:

```text
catch_up_ratio = sustainable_processing_rate / peak_input_rate
```

Tỷ lệ chỉ hơi lớn hơn 1 làm recovery rất lâu.

## 62. Security và governance

Controls:

- least privilege cho source/sink;
- workload identity thay static secret;
- secret rotation;
- signed/verified artifact;
- environment isolation;
- approval cho backfill và destructive overwrite;
- audit read/write/publish;
- retention và deletion policy;
- supply-chain scan cho connector/image/package.

Observability không được tạo đường bypass để tải dữ liệu raw hoặc chạy arbitrary query.

## 63. Runbook

Mỗi critical data product cần runbook:

```text
owner và escalation
SLO/deadline và consumers
last-good lookup
source readiness checks
quality/reconciliation queries
pause/publish/rollback procedure
safe replay/backfill
privacy constraints
communication template
```

Runbook phải được diễn tập. Lệnh cũ không còn tương thích nguy hiểm hơn việc không có lệnh.

## 64. Workshop, checklist và câu hỏi

Workshop:

1. chọn một dataset critical;
2. vẽ source → consumer;
3. định nghĩa grain, event time và deadline;
4. thêm freshness/completeness/reconciliation;
5. emit run trace và lineage;
6. làm hỏng một partition;
7. đo detect, blast-radius và recovery time.

Checklist:

- [ ] Có owner, contract, tier và consumer?
- [ ] Phân biệt event/processing/publish time?
- [ ] Có last-known-good và atomic publish?
- [ ] Retry/replay idempotent?
- [ ] Quality result không lộ dữ liệu?
- [ ] Metric cardinality có budget?
- [ ] Lineage có version và emission health?
- [ ] Backfill không làm đói live workload?

Câu hỏi phỏng vấn:

1. Vì sao DAG success không chứng minh dataset đúng?
2. Đo freshness theo timestamp nào?
3. Làm sao replay không duplicate?
4. Watermark khác checkpoint thế nào?
5. Dataset và column lineage dùng khi nào?
6. Tại sao row-count anomaly cần seasonality?
7. Làm sao tìm blast radius của một partition sai?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### OpenLineage

- [Object model](https://openlineage.io/docs/spec/object-model/)
- [Run cycle](https://openlineage.io/docs/spec/run-cycle/)
- [Facets and extensibility](https://openlineage.io/docs/spec/facets/)
- [Column-level lineage facet](https://openlineage.io/docs/spec/facets/dataset-facets/column_lineage_facet/)

### Orchestration và processing

- [Apache Airflow metrics](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/logging-monitoring/metrics.html)
- [Apache Airflow traces](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/logging-monitoring/traces.html)
- [Apache Airflow health checks](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/logging-monitoring/check-health.html)
- [Apache Spark Structured Streaming monitoring](https://spark.apache.org/docs/latest/streaming/structured-streaming-programming-guide.html#monitoring-streaming-queries)

### Transformation và quality

- [dbt manifest artifact](https://docs.getdbt.com/reference/artifacts/manifest-json)
- [dbt run results artifact](https://docs.getdbt.com/reference/artifacts/run-results-json)
- [dbt source freshness artifact](https://docs.getdbt.com/reference/artifacts/sources-json)
- [Great Expectations validations](https://docs.greatexpectations.io/docs/core/run_validations/)

Chủ đề tiếp theo:
[Machine Learning Model Observability](machine_learning_model_observability.md) – training,
serving, data quality, drift, ground truth, performance, fairness và retraining.

---

*Cập nhật lần cuối: 2026-07-30*
