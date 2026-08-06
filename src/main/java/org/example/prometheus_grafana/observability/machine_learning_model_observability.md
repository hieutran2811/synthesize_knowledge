# Machine Learning Model Observability – Từ Training đến Quyết định Production

> Bài này tập trung vào mô hình dự đoán/classification/regression/ranking/forecasting truyền
> thống. Với LLM, RAG và agent, xem
> [LLM & Generative AI Observability](llm_generative_ai_observability.md).
>
> Mục tiêu là nối model version, dữ liệu, feature, inference, ground truth và business outcome.
> Endpoint HTTP 200, latency thấp hoặc input drift bằng 0 đều không tự chứng minh mô hình đang
> tạo quyết định đúng, công bằng và có giá trị.
>
> Baseline tham chiếu: NIST AI RMF, MLflow 3.x và tài liệu model monitoring hiện hành của
> Azure Machine Learning, Google Vertex AI và Amazon SageMaker AI. Capability, preview status
> và vòng đời dịch vụ thay đổi; kiểm tra tài liệu provider trước khi thiết kế mới.
>
> Không ghi raw feature, prediction nhạy cảm, label, explanation hoặc user identity vào
> telemetry mặc định. Sampling không thay thế consent, minimization và access control.
>
> Nên đọc trước:
> [Data Pipeline & ETL Observability](data_pipeline_etl_observability.md),
> [API & HTTP Observability](api_http_observability.md),
> [Telemetry Governance & FinOps](telemetry_governance_finops.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao model observability khác?

Software thường thay đổi khi code/config thay đổi. Model có thể suy giảm dù artifact không
đổi vì thế giới, population, upstream data hoặc hành vi người dùng thay đổi.

```text
System health ≠ Data health ≠ Model quality ≠ Business value
```

Ví dụ:

- endpoint nhanh nhưng feature quan trọng luôn nhận default;
- input distribution ổn nhưng quan hệ giữa feature và label đã đổi;
- accuracy tổng thể ổn nhưng giảm mạnh ở một nhóm;
- prediction đúng theo label cũ nhưng KPI business không còn phù hợp.

Model observability phải quan sát cả hệ thống học từ dữ liệu và hậu quả quyết định.

## 2. Vòng đời end-to-end

```text
raw data
  → feature/label pipeline
  → train
  → evaluate
  → register/approve
  → deploy
  → infer
  → decision/action
  → delayed ground truth
  → monitor/retrain/retire
```

Mỗi inference cần truy vết về:

- model/version;
- feature set và schema version;
- serving code/config;
- experiment/training run;
- reference dataset;
- deployment/revision;
- policy/threshold;
- eventual outcome.

Không nhất thiết giữ raw payload trong trace; có thể lưu ID/tokenized join key ở kho bảo vệ.

## 3. Bốn mục tiêu

| Mục tiêu | Câu hỏi |
|---|---|
| Reliability | Serving/training có chạy ổn định không? |
| Quality | Prediction có còn chính xác và calibrated không? |
| Responsible behavior | Có bias, abuse, privacy hay safety risk không? |
| Value | Quyết định có cải thiện outcome business không? |

Một dashboard chỉ có CPU, latency và request count mới là serving observability, chưa phải
model observability đầy đủ.

## 4. Taxonomy sự cố

Phân loại sớm:

- infrastructure/serving;
- feature availability;
- schema/data quality;
- training-serving skew;
- data drift;
- concept drift;
- label/ground-truth issue;
- model/config regression;
- threshold/policy;
- fairness/safety/security;
- feedback-loop;
- business/process change.

Taxonomy giúp routing đúng owner: platform, data, ML, product, risk hoặc security.

## 5. SLI và SLO

Ví dụ:

```text
inference availability
inference latency p95/p99
feature availability ratio
prediction coverage
ground-truth coverage
quality metric by slice
calibration error
decision outcome rate
```

SLO nên tier theo model risk:

- model gợi ý nội dung có thể chấp nhận degraded fallback;
- fraud/credit/medical cần controls và review chặt hơn;
- batch forecast có deadline theo business;
- ranking cần quality và latency đồng thời.

Không page theo accuracy mỗi phút nếu label đến sau 30 ngày.

## 6. Inventory và risk tier

Registry tối thiểu:

```yaml
model: fraud_score
version: 42
owner: ml-risk
risk_tier: high
task: binary_classification
decision: manual_review_priority
features: fraud_features_v9
label_delay: P30D
fallback: rules_v12
review_due: 2026-10-01
```

Thêm intended use, excluded use, population, geography, constraints, approver và retirement
criteria. Model không có owner hoặc consumer không nên âm thầm tồn tại ở production.

## 7. Model identity

Identity cần immutable:

- model name và version/artifact digest;
- algorithm/framework version;
- code commit;
- hyperparameter fingerprint;
- training run ID;
- feature contract version;
- dataset snapshot;
- serving image digest;
- decision policy version.

Alias như `champion` hữu ích để routing nhưng không thay immutable version trong telemetry.
Alias có thể đổi giữa lúc điều tra.

## 8. Dataset và label version

“Train trên bảng X” chưa đủ. Cần:

- snapshot/time window;
- extraction query/code;
- filters và sampling;
- label definition/version;
- exclusion rule;
- schema/profile fingerprint;
- lineage;
- data quality result.

Nếu dataset mutable, ít nhất lưu snapshot ID hoặc manifest. Không thể tái lập model nếu chỉ
biết tên bảng hiện tại.

## 9. Feature pipeline

Feature observability nối:

```text
source → transform → offline feature → online feature → request
```

Theo dõi:

- freshness;
- null/default rate;
- range/category;
- lookup hit/miss;
- offline-online parity;
- feature computation latency;
- feature contract/version.

Feature store khỏe không chứng minh semantic feature đúng. Một đổi timezone hoặc unit vẫn
có thể tạo giá trị hợp lệ về type nhưng sai nghĩa.

## 10. Training observability

Quan sát:

- queue/start/duration;
- CPU/GPU/memory/I/O/network;
- data loading bottleneck;
- loss/metric curve;
- learning rate;
- checkpoint success/age;
- numerical instability;
- early stopping;
- distributed worker failure;
- cost/carbon nếu tổ chức theo dõi.

Không xuất mỗi step × layer × worker làm metric dài hạn. Chi tiết cao có thể nằm trong
experiment store với retention phù hợp.

## 11. Experiment tracking

Một run nên ghi:

```text
parameters + code version + environment
datasets + features + labels
metrics by split/slice
artifacts + signatures
start/end/status + owner
```

MLflow Tracking tổ chức theo experiment, run, logged model và artifacts. Tracking server cần
auth, backup và artifact-store policy; nó không nên trở thành kho tùy ý chứa dữ liệu nhạy cảm.

## 12. Reproducibility

Reproducibility có nhiều mức:

1. tái dựng code/environment;
2. đọc đúng dataset snapshot;
3. chạy lại pipeline;
4. thu được metric tương đương;
5. thu được artifact bitwise giống nhau.

GPU/non-deterministic algorithms có thể khiến mức 5 không thực tế. Ghi random seed,
library/driver, hardware và tolerance; đừng tuyên bố reproducible chỉ vì có notebook.

## 13. Offline evaluation

Offline evaluation cần:

- train/validation/test tách đúng;
- temporal split khi production có thời gian;
- leakage checks;
- representative slices;
- uncertainty/confidence interval;
- baseline/champion comparison;
- business cost matrix;
- threshold selection.

Test set bị dùng lặp lại để tuning sẽ mất tính độc lập. Version và governance evaluation set
như một data product.

## 14. Classification metrics

Từ confusion matrix:

```text
precision = TP / (TP + FP)
recall    = TP / (TP + FN)
FPR       = FP / (FP + TN)
F1        = 2 × precision × recall / (precision + recall)
```

Accuracy dễ gây hiểu sai khi class imbalance. Theo dõi PR-AUC/ROC-AUC phù hợp use case và
metric tại threshold vận hành thực tế.

Luôn nối metric với cost: false negative fraud khác false positive moderation.

## 15. Regression metrics

Các metric:

- MAE dễ diễn giải theo unit;
- MSE/RMSE phạt lỗi lớn mạnh hơn;
- MAPE nguy hiểm khi actual gần zero;
- quantile/pinball loss cho interval;
- residual distribution;
- coverage của prediction interval.

Đừng chỉ theo dõi aggregate. Residual theo range, region, season và product có thể lộ lỗi bị
trung bình che khuất.

## 16. Ranking và recommendation

Theo dõi:

- NDCG, MAP, MRR, Recall@K;
- coverage/diversity/novelty;
- position bias;
- click/conversion/dwell;
- latency từng stage retrieval/ranking;
- candidate starvation;
- exploration traffic.

Click không phải ground truth trung lập: UI position và policy cũ ảnh hưởng data thu được.

## 17. Forecasting

Ngoài MAE/RMSE:

- horizon-specific error;
- bias/mean error;
- interval coverage;
- seasonality segment;
- zero-demand behavior;
- reconciliation giữa hierarchy;
- forecast value added so với naive baseline.

Không so forecast tạo hôm nay với actual chưa finalized. Gắn forecast origin, horizon và
actual version.

## 18. Vision, NLP và unstructured input

Tabular profiler không đủ cho image/audio/text. Có thể theo dõi:

- format, resolution, duration, language;
- embedding distribution;
- corrupt/blank input;
- OCR/transcription quality;
- class/topic mix;
- human-labeled audit sample;
- content/safety policy.

Embedding distance là proxy, không tự chứng minh semantic drift hay quality loss.

## 19. Confidence và calibration

Model confidence không nhất thiết là probability đúng.

Calibration hỏi:

```text
Trong nhóm dự đoán 0.8, khoảng 80% có thật sự positive không?
```

Theo dõi:

- reliability diagram;
- Brier score;
- expected calibration error;
- abstention/uncertain rate;
- calibration theo slice.

Threshold thay đổi có thể đổi precision/recall mà model artifact không đổi; version policy.

## 20. Slice-based evaluation

Slice theo:

- region/device/channel;
- new vs existing user;
- traffic source;
- input range;
- protected/sensitive group khi hợp pháp;
- rare/high-value cases;
- time/season.

Chỉ dùng slice có mục đích và minimum sample size. Hàng nghìn slice tự phát gây multiple
testing, cardinality và privacy risk.

## 21. Fairness

Fairness metric phụ thuộc bối cảnh:

- selection/positive rate;
- TPR/FPR;
- precision;
- calibration;
- error/cost distribution;
- outcome sau quyết định.

Không có một metric fairness phù hợp mọi mục tiêu; một số tiêu chí có thể xung đột.
Threshold, population và legal context cần review bởi domain/risk/legal, không chỉ ML team.

## 22. Robustness

Đánh giá:

- missing/noisy feature;
- outlier;
- corrupt input;
- distribution shift;
- adversarial perturbation nếu phù hợp;
- dependency outage;
- reduced precision/hardware change;
- extreme but plausible scenario.

Theo dõi graceful degradation và fallback, không chỉ điểm trung bình trên clean test set.

## 23. Serving lifecycle

```text
request
→ validate
→ fetch/compute features
→ preprocess
→ infer
→ postprocess
→ policy/threshold
→ decision
→ side effect
```

Tạo span cho stage quan trọng. Model inference nhanh nhưng feature lookup hoặc policy engine
chậm vẫn làm user latency cao.

## 24. Online latency

Đo:

- end-to-end;
- feature fetch;
- queue/batching;
- preprocess;
- inference;
- postprocess;
- policy;
- cold/model load.

Histogram phải có bucket phù hợp SLO. P99 theo low-traffic model có thể không ổn định; xem
sample count và cửa sổ.

## 25. Throughput, concurrency và batching

Theo dõi:

- requests/predictions per second;
- concurrent requests;
- batch size;
- batch wait;
- queue depth/age;
- admission/rejection;
- saturation;
- autoscaling lag.

Dynamic batching tăng throughput nhưng có thể tăng tail latency. Dashboard cần thấy trade-off,
không tối ưu GPU utilization độc lập.

## 26. Resource observability

Metric:

- CPU/GPU utilization;
- GPU memory;
- model memory;
- accelerator errors;
- host/device transfer;
- cache hit;
- disk/network;
- container restart/OOM;
- power/cost nếu cần.

GPU utilization cao không đồng nghĩa hiệu quả nếu queueing và batch shape sai. Đo cost trên
successful prediction hoặc business outcome.

## 27. Error taxonomy

Phân biệt:

- invalid input/schema;
- feature unavailable;
- model load;
- inference/runtime;
- timeout/cancel;
- resource exhaustion;
- dependency;
- policy rejection;
- no-decision/abstain;
- side-effect failure.

HTTP status hoặc gRPC code chưa đủ. Request có thể trả fallback 200 nhưng model chính đã hỏng.
Metric cần `route=primary|fallback` và bounded `outcome`.

## 28. Feature availability

Theo dõi per feature set và critical feature:

```text
lookup availability
freshness
null/default rate
timeout
fallback source
```

Không nên label metric theo hàng nghìn feature. Tier feature, export top critical và lưu
profile chi tiết vào monitoring store.

Default value có thể giữ endpoint sống nhưng gây silent quality regression; đo default reason.

## 29. Training-serving skew

Skew xảy ra khi:

- code transform khác;
- timezone/unit khác;
- offline data point-in-time sai;
- online default khác;
- categorical mapping/version lệch;
- feature arrival timing khác.

So sánh cùng entity/time khi có thể:

```text
offline_feature(entity, event_time)
vs
online_feature_captured_at_decision
```

Distribution similarity không phát hiện mọi row-level skew.

## 30. Production data quality

Kiểm tra:

- schema/type;
- missing/default;
- range/domain;
- category unknown;
- freshness;
- duplicate;
- cross-feature invariant;
- preprocessing success.

Data-quality alert thường là tín hiệu sớm hơn model performance vì label đến muộn. Tuy nhiên
quality rule chỉ phản ánh contract biết trước, không bắt được mọi thay đổi thật.

## 31. Data drift

Data/covariate drift:

```text
P_prod(X) ≠ P_ref(X)
```

Có thể đo:

- PSI;
- Jensen-Shannon distance;
- Wasserstein distance;
- KS test cho numeric;
- chi-square cho categorical;
- embedding distance cho unstructured data.

Drift không tự đồng nghĩa performance giảm. Nó là tín hiệu cần điều tra theo feature importance,
slice, seasonality và ground truth.

## 32. Concept drift

Concept drift:

```text
P_prod(Y | X) ≠ P_ref(Y | X)
```

Input có thể không đổi nhưng quan hệ với label đổi, ví dụ fraudster thích nghi. Phát hiện
thường cần ground truth và metric performance theo thời gian.

Phân biệt sudden, gradual, recurring và seasonal drift để chọn response. Retrain ngay theo
mỗi drift alert có thể học nhiễu hoặc feedback bị ô nhiễm.

## 33. Prediction drift

Theo dõi distribution output:

- class share;
- score histogram;
- mean/quantile prediction;
- abstention;
- threshold crossing;
- top-k/category mix.

Prediction drift có thể do input, model, threshold hoặc traffic mix. Nó hữu ích khi chưa có
label, nhưng không phải quality metric.

## 34. Ground truth

Ground truth cần contract:

- nguồn;
- definition/version;
- availability delay;
- join key;
- finalization/correction;
- missingness;
- bias;
- owner.

Ví dụ chargeback sau 60 ngày không phải label hoàn hảo cho fraud nếu policy/refund process
thay đổi. Theo dõi label quality và lineage như feature data.

## 35. Delayed và censored labels

Nếu label đến muộn:

- dùng cohort đã đủ maturity;
- báo coverage;
- tách preliminary/final;
- backfill metric khi label đến;
- dùng proxy chỉ khi ghi rõ giới hạn.

```text
ground_truth_coverage =
  predictions_with_mature_label / eligible_predictions
```

Không tính accuracy trên nhóm có label sớm nếu nhóm đó không đại diện population.

## 36. Production performance

Join prediction với ground truth bằng immutable decision ID trong kho được bảo vệ.

Theo dõi:

- quality metric theo model version;
- threshold/policy version;
- slice;
- cohort/event time;
- label version;
- confidence interval;
- sample/coverage.

Tránh đưa user ID hoặc decision ID vào Prometheus label. Aggregate trước khi export.

## 37. Drift methods và limitations

Statistical test phụ thuộc sample size: traffic rất lớn khiến thay đổi nhỏ cũng “significant”.
Distance threshold tùy feature, scale và baseline.

Good practice:

- minimum sample;
- effect size;
- multiple-comparison control;
- feature importance;
- consecutive-window rule;
- stable binning;
- human-readable diagnostics;
- link đến quality/outcome.

Không dùng một PSI threshold cố định cho mọi feature mà không hiệu chỉnh.

## 38. Baseline và threshold

Baseline có thể là:

- training;
- validation;
- recent healthy production;
- same season last year;
- champion traffic;
- approved business regime.

Training baseline hữu ích cho skew; rolling production hữu ích cho thay đổi gần. Rolling
baseline có thể “đi theo” degradation chậm và che drift. Lưu cả fixed và rolling khi risk cao.

## 39. Seasonality và segmentation

Traffic thay đổi theo:

- giờ/ngày/tuần;
- holiday/campaign;
- geography;
- product lifecycle;
- weather/event;
- acquisition channel.

So sánh đúng cohort/season. Alert Monday với Sunday baseline thường tạo false positive.
Calendar và regime version phải là input của monitor.

## 40. Feature attribution drift

Attribution drift hỏi thứ tự/mức đóng góp feature có thay đổi không. Nó có thể gợi ý model
đang dựa vào tín hiệu khác, nhưng:

- explanation method có approximation;
- correlated features làm attribution không ổn định;
- output/scale khác ảnh hưởng;
- drift không tự là bias hay lỗi.

Gắn method/version/background dataset và không coi explanation như ground truth.

## 41. Explainability

Explainability phục vụ:

- debug;
- review quyết định;
- compliance;
- consumer trust;
- drift diagnosis.

Controls:

- explanation đúng model/version;
- local vs global rõ ràng;
- latency/cost;
- sensitive feature leakage;
- stability;
- retention và access.

Không log explanation chi tiết nếu có thể suy ngược feature nhạy cảm.

## 42. Out-of-distribution và novelty

OOD detection có thể dùng:

- density/distance;
- embedding neighborhood;
- ensemble uncertainty;
- conformal score;
- rule boundary;
- classifier phụ.

Đánh giá OOD detector riêng. Threshold quá nhạy làm abstain nhiều; quá lỏng làm model quyết
định ngoài vùng đã kiểm chứng. Theo dõi OOD rate và outcome của fallback.

## 43. Adversarial và abuse monitoring

Rủi ro:

- probing/model extraction;
- evasion;
- poisoning feedback/training;
- adversarial input;
- endpoint/resource abuse;
- stolen model/artifact;
- feature manipulation.

Kết hợp rate pattern, auth, input validity, prediction entropy và security telemetry. Không
block chỉ dựa trên một anomaly score chưa được kiểm chứng.

## 44. Privacy và security

Controls:

- data minimization;
- consent/purpose;
- tokenized join key;
- encryption;
- least privilege;
- artifact signing/hash;
- model registry RBAC;
- secure serialization;
- dependency/image scan;
- audit;
- retention/deletion.

Model artifact có thể chứa memorized data hoặc executable deserialization risk. Chỉ load
artifact từ nguồn tin cậy và kiểm tra digest/signature.

## 45. Feedback loop

Prediction có thể thay đổi chính data tương lai:

```text
model decision → user/system action → observed label → retraining data
```

Ví dụ chỉ điều tra giao dịch điểm cao thì label fraud quan sát được lệch về nhóm model đã chọn.
Theo dõi:

- exposure/selection policy;
- exploration sample;
- missing counterfactual;
- human override;
- intervention;
- label source.

## 46. Bias amplification

Historical label có thể phản ánh policy cũ. Retrain tự động trên outcome sau model có thể
khuếch đại bias.

Mitigation:

- causal review;
- exploration/audit sample;
- slice outcome;
- override analysis;
- label governance;
- approval gate;
- rollback;
- periodic independent evaluation.

Không gọi mọi chênh lệch là bias do model; phân rã data, policy, exposure và outcome.

## 47. Champion–challenger

Challenger nên được so với champion trên:

- cùng traffic/cohort;
- quality;
- calibration;
- fairness;
- latency/resource;
- business outcome;
- failure/fallback;
- uncertainty.

Offline winner không tự được promote. Gắn evaluation evidence, approver và decision record
vào registry.

## 48. Shadow, canary và A/B

| Kỹ thuật | Side effect | Mục đích |
|---|---|---|
| Shadow | Không | So prediction/performance an toàn |
| Canary | Có trên traffic nhỏ | Kiểm tra production risk |
| A/B | Có, phân nhóm | Đo causal business outcome |

Shadow có selection và temporal advantages nhưng không đo được feedback sau action. A/B cần
power, guardrail và ethics review phù hợp.

## 49. Rollout và rollback

Rollout gate:

```text
artifact verified
AND schema compatible
AND offline gates passed
AND shadow acceptable
AND canary operational + quality guardrails passed
AND fallback tested
```

Rollback phải gồm model, preprocessing, feature contract và threshold/policy. Chỉ rollback
model artifact có thể vẫn để lại incompatible serving code.

## 50. Retraining trigger

Trigger có thể là:

- schedule;
- đủ label mới;
- performance degradation;
- data/concept drift;
- business regime change;
- security/bug fix;
- policy requirement.

Retraining không đồng nghĩa promotion. Pipeline phải evaluate, compare, approve và deploy.
Tự động retrain từ data bị poisoning có thể làm sự cố nặng hơn.

## 51. Registry và promotion

Registry cần:

- immutable version;
- lineage tới run/dataset/code;
- signature/schema;
- evaluation artifacts;
- owner/risk;
- approval;
- aliases;
- deployment history;
- retirement state.

Trong MLflow, model aliases/tags phù hợp workflow mới; stage-based workflow cũ đã bị
deprecated. Luôn kiểm tra migration guide của phiên bản dùng thực tế.

## 52. Lineage và audit

Graph:

```text
source datasets
→ feature pipeline/version
→ training dataset/snapshot
→ experiment run
→ model artifact
→ deployment
→ predictions
→ decisions
→ labels/outcomes
```

Audit cần biết ai phê duyệt, khi nào, evidence nào và policy nào. Lineage thiếu decision/action
sẽ không trả lời được impact thực tế.

## 53. Metrics

Ví dụ:

```text
ml_inferences_total{model,version,outcome,route}
ml_inference_duration_seconds{model,version,stage}
ml_feature_fallback_total{model,feature_group,reason}
ml_prediction_score{model,version,slice}        # aggregate/histogram
ml_ground_truth_coverage_ratio{model,version}
ml_model_quality{model,version,metric,slice}
ml_drift_score{model,version,feature_group,method}
ml_abstentions_total{model,version,reason}
```

Không label theo prediction ID, entity/user, raw feature, experiment run hoặc error message.

## 54. Traces

Trace inference:

```text
decision request
├─ input validation
├─ feature fetch/compute
├─ preprocess
├─ model inference
├─ postprocess
├─ policy
└─ side effect
```

Attributes: immutable model version, feature contract, deployment revision, route và bounded
outcome. Prediction/feature content chỉ capture theo policy riêng, không mặc định.

Training trace có thể nối orchestration → data load → train → evaluate → register.

## 55. Logs và events

Event an toàn:

```json
{
  "event": "model_deployment_promoted",
  "model": "fraud_score",
  "version": "42",
  "artifact_digest": "sha256:...",
  "feature_contract": "fraud_features_v9",
  "policy_version": "review_threshold_v6",
  "approver": "risk-release-workflow",
  "evaluation_id": "eval-2026-07-30-04"
}
```

Identity con người trong audit cần access/retention riêng. Operational log không nên chứa
feature vector hoặc prediction gắn trực tiếp khách hàng.

## 56. Sampling

Ba sampling plane:

- operational telemetry sampling;
- inference capture sampling;
- labeled audit/evaluation sampling.

Random sample có thể bỏ rare/high-risk slice. Kết hợp:

- random representative;
- stratified;
- error/uncertainty;
- rare slice;
- security-triggered;
- fixed audit sample.

Ghi inclusion probability để tránh diễn giải sample như population.

## 57. Cardinality và storage

Ước lượng:

```text
models × versions × slices × metrics × environments × routes
```

Giới hạn:

- chỉ version active/recent trong Prometheus;
- slice registry và budget;
- distribution vào histogram/sketch;
- per-feature detail ở monitoring store;
- prediction-level record ở kho protected;
- TTL theo risk/use.

## 58. Dashboard

Dashboard theo tầng:

1. business/decision outcome;
2. production quality và ground-truth coverage;
3. fairness/calibration/slices;
4. drift/data quality;
5. serving RED và fallback;
6. feature health;
7. version/deployment/change;
8. cost/capacity.

Luôn hiển thị model + policy + feature version và sample count. Biểu đồ quality không ghi
label delay dễ dẫn đến kết luận sai.

## 59. Alerting

Page khi:

- decision path unavailable và không có fallback;
- feature contract critical hỏng;
- high-risk quality/guardrail vi phạm đã đủ evidence;
- wrong model/version hoặc artifact integrity;
- unsafe/bias incident theo policy.

Ticket/investigate khi:

- drift liên tục;
- ground-truth coverage giảm;
- calibration/slice degradation;
- fallback tăng;
- cost/latency regression chưa chạm SLO.

Alert cần owner và recommended action, không chỉ “PSI > 0.2”.

## 60. Incident workflow

```text
impact và decisions affected
→ model/policy/feature versions
→ serving/fallback health
→ feature/data quality
→ drift + ground truth
→ recent deploy/schema/business change
→ affected cohort
→ contain/rollback/review
```

Containment có thể:

- route fallback;
- raise abstention;
- disable automation, chuyển human review;
- rollback full bundle;
- quarantine cohort;
- pause retraining.

Giữ prediction/decision IDs trong kho audit nếu được phép để review và remediation.

## 61. Batch inference

Batch model cần:

- scheduled/actual start;
- source snapshot;
- model/version;
- rows planned/scored/rejected;
- partition coverage;
- duration/throughput;
- output quality;
- publish deadline;
- partial/atomic commit;
- replay idempotency.

Endpoint metric không áp dụng trực tiếp. SLO thường là “dataset prediction sẵn sàng trước giờ
business”, không phải requests per second.

## 62. Edge và on-device model

Thách thức:

- device/hardware/OS fragmentation;
- offline;
- delayed/aggregated telemetry;
- battery/memory;
- model download/integrity;
- version adoption;
- privacy;
- rollback chậm.

Theo dõi aggregate theo bounded device class và model version. Không fingerprint thiết bị.
Metric server chỉ thấy request đã tới, nên cần client-side health có consent và budget.

## 63. Governance và model card

Model card/registry record nên chứa:

- intended/excluded use;
- population và limitations;
- training/evaluation data;
- metric và slice;
- fairness/safety;
- privacy/security;
- owner/approver;
- monitoring plan;
- label delay;
- fallback/rollback;
- review/retirement.

NIST AI RMF tổ chức quản trị quanh Govern, Map, Measure và Manage. Observability cung cấp
evidence cho các hoạt động này, nhưng không tự động biến metric thành quyết định governance.

## 64. Workshop, checklist và câu hỏi

Workshop:

1. chọn một model production;
2. vẽ data → feature → model → decision → label;
3. ghi immutable identity;
4. thêm serving, data quality và label coverage;
5. chọn 3 slice;
6. mô phỏng feature default tăng;
7. thực hiện containment và rollback.

Checklist:

- [ ] Inventory, owner và risk tier?
- [ ] Model/data/feature/policy version immutable?
- [ ] Ground truth có definition và delay?
- [ ] Quality theo slice, sample count và confidence?
- [ ] Drift không bị diễn giải thành performance?
- [ ] Fallback/abstention được đo?
- [ ] Telemetry không lộ raw feature/prediction?
- [ ] Retraining tách khỏi promotion?
- [ ] Rollback cả bundle đã diễn tập?

Câu hỏi phỏng vấn:

1. Data drift khác concept drift thế nào?
2. Vì sao accuracy tổng thể có thể nguy hiểm?
3. Training-serving skew phát hiện ra sao?
4. Làm gì khi label đến sau 30 ngày?
5. Shadow khác A/B ở điểm nào?
6. Vì sao retrain tự động có thể khuếch đại bias?
7. Một model incident cần rollback những thành phần nào?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Risk và lifecycle

- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
- [MLflow Tracking](https://mlflow.org/docs/latest/ml/tracking/)
- [MLflow Model Registry workflows](https://mlflow.org/docs/latest/ml/model-registry/workflow/)
- [MLflow model evaluation](https://mlflow.org/docs/latest/ml/evaluation)

### Managed model monitoring

- [Azure Machine Learning model monitoring](https://learn.microsoft.com/azure/machine-learning/concept-model-monitoring)
- [Vertex AI Model Monitoring](https://cloud.google.com/vertex-ai/docs/model-monitoring/overview)
- [Amazon SageMaker Model Monitor](https://docs.aws.amazon.com/sagemaker/latest/dg/model-monitor.html)

> Lưu ý theo tài liệu AWS ngày 2026-07-30: SageMaker Model Monitor đóng quyền truy cập cho
> khách hàng mới từ ngày này; khách hàng hiện hữu vẫn có thể sử dụng nhưng AWS không dự kiến
> bổ sung tính năng mới. Không chọn dịch vụ mới chỉ từ một tutorial cũ; kiểm tra product
> lifecycle và phương án portable.

Chủ đề tiếp theo gợi ý:
[Security Observability & Detection Engineering](security_observability_detection_engineering.md)
– audit, identity, network, endpoint,
detection-as-code, SIEM, incident evidence và privacy.

---

*Cập nhật lần cuối: 2026-07-30*
