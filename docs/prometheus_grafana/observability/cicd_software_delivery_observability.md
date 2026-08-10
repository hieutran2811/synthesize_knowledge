---
title: "CI/CD & Software Delivery Observability – Từ Commit đến Production Outcome"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 9
---
# CI/CD & Software Delivery Observability – Từ Commit đến Production Outcome

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát toàn bộ dòng chảy thay đổi từ commit, review, build,
> test, artifact, deployment đến tác động production; nhờ đó biết thay đổi đang ở đâu,
> vì sao chậm hoặc thất bại, bản nào đang chạy và nên tiếp tục hay rollback.
>
> Baseline tham chiếu: DORA metrics hiện hành, OpenTelemetry CI/CD Semantic Conventions,
> CDEvents 0.5.0, SLSA 1.2 và các mô hình progressive delivery phổ biến. Semantic convention
> ở trạng thái Development hoặc Release Candidate phải được pin schema trước khi production.
>
> Delivery telemetry có thể chứa source path, danh tính người dùng, nội dung commit, secret,
> artifact URL và thông tin lỗ hổng. Chỉ thu thập metadata cần thiết, che dữ liệu nhạy cảm,
> giới hạn quyền truy cập và không đưa credential vào log, span hay metric label.
>
> Nên đọc trước:
> [Telemetry Governance & FinOps](telemetry_governance_finops.md),
> [Incident Response](incident_response_observability.md),
> [Security Observability](security_observability_detection_engineering.md) và
> [Network Observability](network_observability_traffic_analysis.md).

---

## 1. Vì sao delivery observability khác pipeline monitoring?

Pipeline monitoring thường chỉ hỏi job xanh hay đỏ. Delivery observability hỏi rộng hơn:

- thay đổi nào đang đi qua hệ thống;
- thời gian bị tiêu tốn ở bước nào;
- artifact nào thực sự được triển khai;
- deployment có làm xấu SLO hay business outcome không;
- hệ thống có đủ evidence để tái hiện và audit không.

Một pipeline xanh chưa chứng minh production an toàn; một deployment đỏ cũng chưa chắc gây
customer impact nếu traffic chưa được chuyển sang phiên bản mới.

## 2. Quan sát value stream end-to-end

Dòng chảy tối thiểu:

```text
idea → commit → review → merge → build → test → artifact
     → deploy → release traffic → verify outcome → learn
```

Mỗi bước cần `started_at`, `finished_at`, outcome, owner và liên kết tới bước trước/sau.
Khoảng trống giữa các bước cũng là dữ liệu: chờ reviewer, chờ runner và chờ approval thường
lớn hơn thời gian máy thực thi.

## 3. Năm nhóm mục tiêu

Thiết kế telemetry theo năm câu hỏi:

1. **Flow:** thay đổi đi nhanh và ít tắc nghẽn không?
2. **Quality:** lỗi được phát hiện sớm và chính xác không?
3. **Reliability:** deployment có làm xấu dịch vụ không?
4. **Security:** artifact có nguồn gốc và chính sách hợp lệ không?
5. **Outcome:** thay đổi có tạo tác động mong muốn không?

Không tối ưu một nhóm bằng cách hy sinh âm thầm nhóm khác.

## 4. Identity contract xuyên suốt

Các hệ thống VCS, CI, registry, CD và runtime phải thống nhất ít nhất:

| Identity | Ý nghĩa |
|---|---|
| `change.id` | commit SHA hoặc change-set bất biến |
| `pipeline.name`, `pipeline.run.id` | định nghĩa pipeline và lần chạy |
| `artifact.name`, `artifact.digest` | artifact logic và nội dung bất biến |
| `deployment.id` | một lần triển khai |
| `service.name`, `service.version` | workload đang phục vụ |
| `environment.name` | dev, staging, production... |

Tên hiển thị có thể đổi; ID dùng để correlation phải ổn định.

## 5. Change unit là gì?

Đơn vị thay đổi có thể là commit, merge commit, pull request, release manifest hoặc một nhóm
artifact. Chọn một định nghĩa chính thức rồi lưu mapping khi nhiều commit được squash hoặc
batch cùng một deployment.

```text
deployment.id → release manifest → artifact digests → source commits
```

Nếu không truy ngược được chuỗi này, điều tra regression sẽ dựa vào phỏng đoán.

## 6. SLO cho delivery platform

Ví dụ SLI:

- tỷ lệ pipeline bắt đầu trong 2 phút sau merge;
- tỷ lệ build hợp lệ hoàn tất dưới 15 phút;
- tỷ lệ deployment có trạng thái cuối trong 30 phút;
- tỷ lệ artifact truy được provenance;
- tỷ lệ production rollout tự động xác minh thành công.

Định nghĩa denominator rõ ràng; loại trừ run bị người dùng hủy chỉ khi policy quy định trước,
không loại sau khi thấy số liệu xấu.

## 7. Telemetry từ source control

Ghi nhận push, branch/tag, pull request, merge, revert và actor bằng event chuẩn hóa. Không
dùng message commit làm identity và không đưa toàn bộ diff vào telemetry.

Các chỉ số hữu ích:

- PR age và review wait;
- batch size theo số file/dòng chỉ là proxy;
- tỷ lệ revert;
- thời gian từ first commit đến merge;
- tỷ lệ thay đổi có owner và issue liên kết.

## 8. Pull request và code review

Tách:

```text
PR lead time = author work + review wait + review work + merge wait
```

Số comment không đo chất lượng review. Theo dõi distribution theo repository/team, tránh
xếp hạng cá nhân. Review latency cao có thể do thiếu ownership, PR quá lớn hoặc reviewer
quá tải chứ không chỉ do “review chậm”.

## 9. Queue time và wait state

Mọi stage nên phân biệt:

- `queued_at`;
- `started_at`;
- `finished_at`;
- `blocked_reason`.

```text
queue_duration = started_at - queued_at
run_duration   = finished_at - started_at
```

Chỉ nhìn run duration sẽ bỏ lỡ runner starvation, approval wait và rate limit bên thứ ba.

## 10. Vòng đời pipeline run

State machine gợi ý:

```text
created → queued → running → {succeeded | failed | cancelled | timed_out}
```

Mỗi transition là event bất biến. `unknown` phải được hiển thị riêng, không quy thành failed.
Run được retry là run mới liên kết bằng `retry_of`; không ghi đè lịch sử lần cũ.

## 11. Stage, task và step

Phân cấp:

```text
pipeline run
└── stage
    └── task/job
        └── step
```

Instrument ở mức đủ để tìm bottleneck. Tạo span cho mọi shell command rất ngắn có thể tăng
chi phí mà không tăng khả năng chẩn đoán; aggregate các bước lặp nếu không cần từng instance.

## 12. Runner và worker

Theo dõi:

- available/busy/offline runners;
- queue depth và oldest queued age;
- CPU, memory, disk, inode và network;
- image pull, workspace checkout và cleanup time;
- autoscaling decision, provisioning time và failure;
- runner version, pool và execution class.

Phân biệt lỗi workload với lỗi hạ tầng runner để route đúng owner.

## 13. Dependency và build cache

Cache hit cao không đồng nghĩa đúng. Cần quan sát:

- hit/miss theo cache class;
- restore/save latency và bytes;
- eviction và corruption;
- key version;
- fallback về dependency registry;
- build reproducibility khi cache bị tắt.

Không đặt branch, commit SHA hoặc dependency list dài thành metric label.

## 14. Build observability

Một build record nên trả lời:

- source revision nào;
- toolchain/container digest nào;
- dependency lock nào;
- command/profile nào;
- output digest nào;
- mất bao lâu và dùng bao nhiêu tài nguyên;
- vì sao thất bại.

Chuẩn hóa failure category như compilation, dependency, timeout, infrastructure và policy.

## 15. Phân loại test

Tách unit, integration, contract, end-to-end, performance, security và smoke test. Với mỗi
suite, theo dõi duration, pass/fail/skip, retry, test count và môi trường.

Không cộng tất cả test vào một tỷ lệ pass: một unit test và một end-to-end test không có
chi phí, độ tin cậy hay phạm vi phát hiện giống nhau.

## 16. Flaky test

Flaky test cho kết quả khác nhau khi input và code không đổi. Một proxy thực dụng:

```text
failed first attempt + passed retry → suspected flaky
```

Proxy này có false positive; cần quarantine có owner, expiry và evidence. Retry vô hạn làm
pipeline “xanh giả”, tăng lead time và che regression.

## 17. Coverage không phải quality outcome

Line/branch coverage cho biết code nào được chạy, không cho biết assertion tốt hay kịch bản
quan trọng đã được kiểm tra. Kết hợp:

- coverage trend;
- changed-code coverage;
- mutation score khi phù hợp;
- escaped defects;
- test failure precision;
- thời gian phản hồi cho developer.

Không dùng một ngưỡng coverage duy nhất cho mọi repository.

## 18. Artifact identity bất biến

Tag như `latest` hoặc `v1` có thể bị trỏ lại; digest mới xác định nội dung. Deployment record
nên lưu digest image/package, manifest digest và dependency/bundle version.

```text
human tag ──resolves to──▶ immutable digest
```

Production verification phải so digest thực chạy với digest đã approve.

## 19. SBOM

Software Bill of Materials mô tả component và dependency trong artifact. Telemetry chỉ nên
lưu reference, digest, format, generation status và policy outcome; không biến toàn bộ SBOM
thành labels.

Quan sát:

- tỷ lệ artifact có SBOM;
- thời gian sinh/scan;
- scanner version và database freshness;
- lỗi parse hoặc component không xác định.

## 20. Provenance và SLSA

SLSA cung cấp mô hình tăng độ tin cậy cho source và build. Provenance liên kết artifact với
builder, input và quy trình tạo ra nó.

Điều cần đo:

- attestation có tồn tại và xác minh được không;
- builder identity có được tin cậy không;
- subject digest có khớp artifact không;
- policy level/track yêu cầu có đạt không;
- verifier dùng policy version nào.

## 21. Ký và xác minh artifact

Tách sự kiện signing khỏi verification. Một chữ ký hợp lệ về mật mã vẫn có thể vi phạm
policy nếu signer không được phép hoặc certificate đã hết scope.

Không log private key, token, raw certificate chain không cần thiết. Ghi `signer_identity`
đã chuẩn hóa, transparency-log reference, verification result và reason code.

## 22. Registry observability

Theo dõi push/pull latency, error, throttling, storage, replication lag, garbage collection
và availability theo region. Correlate registry request với pipeline/deployment nhưng không
dùng artifact digest làm label Prometheus nếu số lượng không giới hạn.

Probe cả authentication và manifest/blob retrieval; health endpoint xanh chưa chứng minh
runner có thể pull artifact thực tế.

## 23. Promotion giữa các environment

Promotion nên di chuyển cùng một digest đã xác minh, không rebuild khác nhau cho staging và
production. Event cần chứa source environment, target environment, artifact digest, policy
decision, approval và thời điểm.

Nếu phải transform cấu hình theo environment, ghi digest của cả artifact lẫn effective
configuration để phân biệt code change với config change.

## 24. Vòng đời deployment

State machine:

```text
requested → approved → started → progressing
          → {succeeded | failed | aborted | rolled_back}
```

`deployment succeeded` cần định nghĩa: controller hoàn tất, workload ready, smoke test đạt
hay business guardrail ổn? Nên lưu từng checkpoint thay vì gộp thành một boolean.

## 25. Deployment khác release

- **Deployment:** đưa code/config vào environment.
- **Release:** cho người dùng tiếp xúc với capability.

Feature flag hoặc traffic routing có thể tách hai thời điểm này. Vì vậy deployment frequency
không tự động bằng release frequency, và customer impact phải correlate với exposure thực tế.

## 26. Chọn chiến lược triển khai

| Strategy | Lợi ích | Rủi ro cần quan sát |
|---|---|---|
| Recreate | đơn giản | downtime |
| Rolling | ít tài nguyên phụ | mixed version |
| Blue-green | switch/rollback nhanh | gấp đôi capacity, state |
| Canary | giới hạn blast radius | sai cohort, tín hiệu nhiễu |

Telemetry phải biết strategy, phase, traffic weight và version composition.

## 27. Rolling update

Theo dõi available/updated/old replicas, unavailable duration, readiness, termination,
image pull và version skew. Một rollout có thể hoàn tất theo controller nhưng request vẫn
thất bại vì connection drain hoặc client giữ endpoint cũ.

Alert theo progress deadline và customer SLI, không chỉ theo trạng thái replica.

## 28. Blue-green

Quan sát riêng:

- health của blue và green;
- replication/state compatibility;
- smoke test trước switch;
- thời điểm và actor chuyển traffic;
- connection drain;
- thời gian giữ môi trường cũ;
- khả năng switch back.

So sánh hai môi trường bằng cùng workload và query window để tránh kết luận lệch.

## 29. Canary

Một canary record cần có baseline version, candidate version, cohort, traffic weight, phase,
guardrails và decision. Không so raw error count khi traffic hai nhóm khác nhau; dùng rate
và confidence phù hợp.

Canary nhỏ quá thiếu power; lớn quá mất mục tiêu giới hạn blast radius.

## 30. Progressive delivery analysis

Analysis có thể chạy nền hoặc chặn từng bước. Mỗi measurement phải lưu:

- query và datasource version;
- window, delay và interval;
- result;
- success/failure/inconclusive condition;
- decision và reason.

`inconclusive` không nên tự động được coi là success. Dry-run hữu ích để kiểm tra rule trước
khi cho phép abort production.

## 31. Feature flag trong delivery

Flag giúp tách deploy khỏi release nhưng tạo thêm state:

```text
artifact version + config version + flag state + evaluation context
```

Deployment dashboard nên đánh dấu flag change gần thời điểm rollout. Chi tiết contract,
privacy và lifecycle được trình bày ở
[Change, Configuration & Feature Flag Observability](change_configuration_feature_flag_observability.md).

## 32. Database migration

Migration cần identity, checksum, direction, compatibility phase, lock/wait time, rows/bytes,
duration và outcome. Ưu tiên expand-and-contract:

```text
expand schema → deploy compatible code → migrate data → remove old schema
```

Theo dõi replication lag, lock contention và error rate; rollback application không luôn
rollback được data migration.

## 33. Configuration và Infrastructure as Code

Gắn pipeline với plan/apply, resource count, policy decision, drift và config digest. Không
log secret value hoặc toàn bộ plan chưa redaction.

Tách:

- code artifact change;
- application configuration change;
- infrastructure change;
- runtime/manual change.

Chúng có blast radius và rollback semantics khác nhau.

## 34. GitOps reconciliation

Theo OpenGitOps, desired state được khai báo, version hóa/bất biến, tự động pull và liên tục
reconcile. Quan sát:

- desired revision và observed revision;
- sync/reconcile duration;
- drift;
- health;
- retry/backoff;
- suspended state;
- source fetch/authentication error.

“Git đã merge” không chứng minh cluster đã áp dụng.

## 35. Kubernetes rollout

Kết hợp Deployment status, ReplicaSet, Pod conditions, Events, container logs và request SLI.
Các nguyên nhân phổ biến:

- image pull;
- scheduling/capacity;
- readiness;
- crash loop;
- quota/policy;
- progress deadline;
- service selector hoặc routing.

Lưu workload UID/revision để tránh nhầm resource trùng tên sau khi tạo lại.

## 36. Rollback

Rollback event phải nêu target digest/config, trigger, actor, start/end và outcome. Kiểm tra:

- schema/data có backward compatible không;
- flag/config cũ còn dùng được không;
- traffic/session có drain không;
- dependency contract có đổi không;
- rollback có phục hồi SLO không.

Rollback thành công kỹ thuật nhưng SLO không hồi phục là evidence cần điều tra tiếp.

## 37. Roll-forward và hotfix

Rollback không phải lựa chọn duy nhất. Roll-forward phù hợp khi data/schema không thể đảo,
fix nhỏ và thời gian build/deploy dự đoán được.

Đánh dấu emergency path, approval exception, test bị bỏ qua và debt phải xử lý sau incident.
Không để hotfix ngoài source control hoặc không có provenance.

## 38. Correlate change với production

Ghi deployment marker vào dashboard và truyền `service.version` vào traces/logs. Phân tích:

```text
before window ↔ rollout window ↔ after window
baseline version ↔ candidate version
```

Tương quan thời gian chỉ là manh mối, không tự chứng minh nhân quả; kiểm tra traffic mix,
seasonality, dependency incident và config/flag change đồng thời.

## 39. CDEvents

CDEvents cung cấp vocabulary chung cho source control, CI, test, artifact, deployment và
operation, xây trên CloudEvents. Nó giúp các tool trao đổi event mà không phải mapping riêng
từng cặp.

Pin version/type, validate schema, giữ immutable event ID và hỗ trợ idempotency. Không giả
định mọi vendor đã triển khai đầy đủ cùng một phiên bản.

## 40. OpenTelemetry CI/CD semantic conventions

OpenTelemetry định nghĩa resource/span/metric cho CI/CD, nhưng trạng thái từng phần có thể
khác nhau. Trước khi áp dụng:

- pin semantic-convention version;
- ghi migration rule;
- kiểm tra attribute stability;
- giới hạn cardinality;
- đánh giá vendor mapping.

`cicd.pipeline.run.id` là duy nhất theo run nên metric resource mang thuộc tính này phải
**opt-in**, nếu không có thể tạo cardinality rất cao.

## 41. Thiết kế trace

Một trace có thể bắt đầu ở pipeline run và có span cho stage/task, artifact publication,
deployment request và analysis. Dùng span link khi công việc bất đồng bộ hoặc qua queue,
không cố duy trì một parent-child context vô hạn.

Không tail-sample chỉ error: cần giữ mẫu success để so sánh latency và path bình thường.

## 42. Thiết kế metric

Nhóm metric tối thiểu:

- run/task count theo outcome và loại;
- queue/run duration histogram;
- active/queued work gauge;
- deployment count và duration;
- rollback/rework count;
- artifact/provenance verification rate;
- runner saturation.

Label nên giới hạn ở repository/pipeline chuẩn hóa, stage class, environment và outcome;
run ID, commit SHA, digest thuộc log/trace/event.

## 43. Log và event

Log phục vụ chi tiết thực thi; event phục vụ state transition/audit. Contract gợi ý:

```json
{
  "event.name": "deployment.completed",
  "event.id": "immutable-id",
  "deployment.id": "dep-...",
  "artifact.digest": "sha256:...",
  "environment.name": "production",
  "outcome": "success",
  "reason.code": "verified"
}
```

Không log environment dump, command có token hoặc secret masking chưa kiểm thử.

## 44. Secret và privacy

Rủi ro phổ biến:

- token xuất hiện trong command line;
- credential nằm trong environment dump;
- URL có query secret;
- commit/PR chứa PII;
- artifact path tiết lộ tenant/customer;
- log test chứa production data.

Redact tại nguồn, rotate credential khi lộ, giới hạn retention và audit quyền đọc telemetry.

## 45. Cardinality budget

Cardinality cao thường đến từ commit SHA, run ID, job ID, branch động, test case, artifact
digest và error message. Đưa chúng vào trace/log/event, không làm label metric mặc định.

Ước lượng trước:

```text
series ≈ pipelines × stages × outcomes × environments × active label combinations
```

Đặt budget và alert theo series growth, ingestion bytes và query latency.

## 46. Quan sát control plane CI/CD

Pipeline của ứng dụng có thể thất bại vì control plane. Theo dõi scheduler, queue, database,
object storage, webhook, secret provider, artifact registry, API rate limit và notification.

Tạo synthetic pipeline định kỳ: checkout nhỏ → build → publish artifact thử → deploy sandbox
→ verify → cleanup. Nó kiểm tra hành trình thật tốt hơn health endpoint rời rạc.

## 47. Capacity và concurrency

Capacity planning cần arrival rate, service time, concurrency, runner provisioning time và
burst profile. Theo Little's Law ở steady state:

```text
work in system ≈ arrival rate × time in system
```

Đừng tăng concurrency mù quáng nếu bottleneck là registry, dependency server hoặc database
test dùng chung.

## 48. Starvation và head-of-line blocking

Một job dài có thể giữ runner hiếm và chặn hàng loạt job ngắn. Theo dõi queue age theo pool,
priority và workload class; dùng fairness/quota khi nhiều team dùng chung.

Alert theo oldest age và SLO breach, không chỉ queue depth: queue nhỏ vẫn nghiêm trọng nếu
job quan trọng bị treo lâu.

## 49. Chi phí software delivery

Phân rã:

- runner compute time;
- cache/object storage;
- artifact retention/egress;
- test environment;
- security scan;
- observability ingestion;
- thời gian developer chờ hoặc rerun.

Đo cost per successful change kèm quality guardrail; tối ưu chi phí bằng cách bỏ test giá
trị cao có thể làm tăng escaped defect và tổng chi phí.

## 50. DORA metrics hiện hành

Mô hình DORA hiện hành có năm metric:

**Throughput**

1. change lead time;
2. deployment frequency;
3. failed deployment recovery time.

**Instability**

4. change fail rate;
5. deployment rework rate.

Đo theo application/service có cùng context; không dùng để xếp hạng cá nhân hoặc so hai hệ
thống có rủi ro và quy trình hoàn toàn khác nhau.

## 51. Change lead time

Chọn mốc bắt đầu/kết thúc nhất quán, ví dụ commit được tạo đến khi chạy production:

```text
lead_time = production_time - change_commit_time
```

Dùng distribution và percentile, tách queue/run/wait để hành động được. Median thấp có thể
che long tail; batch commit hoặc cherry-pick cần mapping rõ.

## 52. Deployment frequency

Đếm deployment production thành công trong một khoảng thời gian theo service. Quy định cách
xử lý multi-region, retry, no-op và cùng release triển khai nhiều instance.

Frequency cao chỉ có ý nghĩa khi change fail/rework và outcome không xấu. Không chia nhỏ
deployment giả tạo chỉ để cải thiện metric.

## 53. Failed deployment recovery time

Đo thời gian từ failed deployment gây suy giảm đến khi dịch vụ được phục hồi bởi rollback,
roll-forward hoặc biện pháp khác. Cần incident/change marker và restoration criterion dựa
trên SLI, không chỉ pipeline xanh.

Tách detection time, decision time và remediation time để biết nên cải thiện phần nào.

## 54. Change fail rate

Ví dụ:

```text
change_fail_rate =
  production changes causing remediation / eligible production changes
```

Định nghĩa remediation gồm rollback, hotfix, incident hoặc patch khẩn cấp theo policy.
Denominator phải tương thích với numerator; quan sát theo rolling window đủ lớn.

## 55. Deployment rework rate

Metric này phản ánh tỷ lệ deployment production ngoài kế hoạch nhằm sửa sự cố do deployment
trước gây ra. Cần phân loại planned change và corrective rework bằng evidence, không dựa vào
message tự do.

Nó bổ sung góc nhìn instability: recovery nhanh vẫn có thể che một hệ thống thường xuyên
phải sửa lại.

## 56. Tránh gaming và aggregation sai

Anti-pattern:

- đổi định nghĩa khi số xấu;
- loại deployment thất bại khỏi denominator;
- dùng average thay percentile;
- so team không cùng context;
- gán mọi incident gần deployment cho deployment;
- tối ưu frequency bằng change cực nhỏ nhưng nhiều overhead;
- biến metric hệ thống thành KPI cá nhân.

Metric phải dẫn tới học hỏi, không tạo động cơ che giấu.

## 57. Dashboard phân tầng

Ba tầng:

1. **Executive/value stream:** throughput, instability, trend và outcome.
2. **Platform:** queue, capacity, reliability, cost và dependency.
3. **Run detail:** timeline, task, log, trace, artifact, policy và deployment.

Cho phép drill-down bằng link/exemplar, không đưa run ID thành dashboard variable truy vấn
metric cardinality cao.

## 58. Alerting

Alert có khả năng hành động:

- synthetic delivery path thất bại;
- oldest queue age vượt SLO;
- runner pool cạn kéo dài;
- deployment stuck/progress deadline;
- canary guardrail vi phạm;
- artifact verification/policy service unavailable;
- telemetry gap khiến không xác minh được rollout.

Thông báo phải chứa owner, environment, run/deployment link và runbook.

## 59. Incident workflow

Khi release gây regression:

1. đóng băng hoặc giảm tốc rollout;
2. xác định version/config/flag và exposure;
3. kiểm tra customer SLI;
4. quyết định rollback, roll-forward hoặc traffic shift;
5. theo dõi restoration;
6. lưu evidence và timeline;
7. khôi phục delivery path an toàn.

Không để pipeline retry tự động tiếp tục rollout khi guardrail chưa rõ.

## 60. Kiểm thử telemetry và failure injection

Thử có kiểm soát:

- runner biến mất giữa job;
- registry timeout;
- webhook duplicate/out-of-order;
- artifact verification fail;
- deployment controller chậm;
- metrics datasource mất dữ liệu;
- rollback fail;
- event schema mới không tương thích.

Xác minh alert, idempotency, degraded mode và evidence vẫn đủ để chẩn đoán.

## 61. Resilience và disaster recovery

Xác định RTO/RPO cho pipeline definitions, metadata database, artifact, cache, secret,
provenance và audit trail. Cache có thể tái tạo; source, signed artifact và evidence release
thường quan trọng hơn.

Diễn tập restore và một emergency delivery path tối thiểu, có approval, audit và expiry;
không biến đường khẩn cấp thành lối tắt thường xuyên.

## 62. Governance và policy

Policy-as-code nên version hóa:

- required review/test;
- artifact/signature/provenance;
- vulnerability threshold;
- environment approval;
- allowed deployment window;
- progressive-delivery guardrail;
- emergency exception.

Lưu policy version, input reference, decision và reason. `deny` không có reason sẽ làm chậm
khắc phục và khuyến khích bypass.

## 63. Supply-chain security

Kết hợp least privilege, isolated/ephemeral runner, pinned dependency/action, protected
branch, signed provenance, immutable artifact và verification tại deploy.

Quan sát cả hành vi bất thường:

- build từ source revision khác;
- artifact digest đổi sau approval;
- runner lạ;
- policy bị tắt;
- secret access tăng đột biến;
- deployment ngoài window.

Chuyển evidence quan trọng sang security monitoring có integrity protection.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: chọn một production deployment rồi dựng timeline từ commit tới customer SLI.

- [ ] Truy được commit → artifact digest → workload?
- [ ] Queue time tách khỏi run time?
- [ ] Test retry có lộ flaky test?
- [ ] Provenance/signature được verify khi deploy?
- [ ] Deployment và release được phân biệt?
- [ ] Guardrail có xử lý missing/inconclusive?
- [ ] DORA denominator được định nghĩa?
- [ ] Run ID/digest không nằm trong metric label?
- [ ] Rollback đã được diễn tập?

Câu hỏi:

1. Pipeline xanh còn có thể tạo incident bằng cách nào?
2. Vì sao promotion nên dùng cùng một artifact digest?
3. Deployment frequency khác release frequency thế nào?
4. DORA hiện hành có những metric nào?
5. Khi nào canary result là inconclusive?
6. Vì sao rollback controller thành công chưa đủ?
7. CDEvents và OpenTelemetry giải quyết hai lớp nào?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Delivery performance và interoperability

- [DORA metrics history và mô hình hiện hành](https://dora.dev/insights/dora-metrics-history/)
- [DORA guides](https://dora.dev/guides/)
- [CDEvents documentation](https://cdevents.dev/docs/)
- [CDEvents specification repository](https://github.com/cdevents/spec)

### Telemetry, provenance và rollout

- [OpenTelemetry CI/CD semantic conventions](https://opentelemetry.io/docs/specs/semconv/cicd/)
- [OpenTelemetry CI/CD spans](https://opentelemetry.io/docs/specs/semconv/cicd/cicd-spans/)
- [OpenTelemetry CI/CD metrics](https://opentelemetry.io/docs/specs/semconv/cicd/cicd-metrics/)
- [SLSA specification 1.2](https://slsa.dev/spec/v1.2/)
- [Argo Rollouts analysis](https://argo-rollouts.readthedocs.io/en/stable/features/analysis/)

Chủ đề tiếp theo:
[Change, Configuration & Feature Flag Observability](change_configuration_feature_flag_observability.md)
– desired/effective state, drift, reconciliation, rollout context, evaluation, audit và cleanup.

---

*Cập nhật lần cuối: 2026-07-30*
