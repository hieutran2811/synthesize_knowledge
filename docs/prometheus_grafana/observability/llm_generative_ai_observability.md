---
title: "LLM & Generative AI Observability – Từ Model Call đến Chất lượng và An toàn"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 8
---
# LLM & Generative AI Observability – Từ Model Call đến Chất lượng và An toàn

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát một ứng dụng GenAI qua prompt/template, model/provider,
> streaming, retrieval, agent/tool, guardrail và business outcome. Token, latency và HTTP 200
> không tự chứng minh câu trả lời đúng, an toàn hoặc hữu ích.
>
> Baseline tham chiếu: OpenTelemetry GenAI Semantic Conventions đang được phát triển trong
> repository chuyên biệt, NIST AI RMF/Generative AI Profile và OWASP Top 10 for LLM
> Applications 2025. Schema GenAI thay đổi nhanh; pin version và giữ migration plan.
>
> Không ghi prompt/output, retrieved documents, tool arguments/results, API key, system prompt
> hoặc user identity vào telemetry mặc định. Sampling không phải privacy control.
>
> Nên đọc trước:
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [API & HTTP Observability](api_http_observability.md),
> [Database Observability](database_observability_performance.md),
> [Telemetry Governance](telemetry_governance_finops.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao GenAI observability khác?

Hệ thống có:

- output xác suất;
- model/provider thay đổi;
- prompt/context động;
- token/cost biến thiên;
- streaming;
- retrieval/tool calls;
- safety filters;
- quality khó xác định online;
- cùng input có thể cho output khác.

Operational success và semantic success là hai trục riêng.

---

## 2. Vòng đời một workflow

```text
user task
→ policy/input validation
→ prompt assembly
→ retrieval/rerank
→ model request/stream
→ tool calls/agent loop
→ output validation/grounding
→ response/action
→ feedback/business outcome
```

Instrument từng stage, không tạo một span “LLM” bao trùm mơ hồ.

---

## 3. Ba mục tiêu

| Trục | Câu hỏi |
|---|---|
| reliability | request có hoàn tất đúng deadline không? |
| quality | output có đúng, phù hợp và hữu ích không? |
| safety/governance | dữ liệu, quyền và hành vi có nằm trong policy không? |

Dashboard phải thể hiện cả ba nhưng không trộn thành điểm số duy nhất thiếu giải thích.

---

## 4. SLO

Ví dụ:

- workflow availability/latency;
- time to first token;
- completion success;
- grounded-answer rate;
- tool-task success;
- policy violation/blocked rate;
- cost per successful outcome;
- human escalation;
- freshness của knowledge source.

Quality SLO cần dataset/evaluator đã version hóa.

---

## 5. Mô hình nhiều lớp

```text
product journey
→ orchestration/agent
→ prompt/policy
→ retrieval/vector/rerank
→ model gateway/provider/model
→ tool/API
→ output validation
→ user/business feedback
```

Model latency có thể chỉ là một phần của workflow.

---

## 6. Provider và model identity

Ghi low-cardinality:

- provider/system;
- requested model;
- response model/version khi có;
- endpoint/region;
- deployment name;
- operation;
- application release.

Không giả định marketing model name là immutable artifact.

---

## 7. Prompt/template identity

Thay vì raw prompt:

- template ID;
- template version;
- experiment/feature version;
- system-policy version;
- locale/use case;
- hash đã đánh giá privacy.

Hash prompt người dùng vẫn có thể là personal data và high-cardinality.

---

## 8. Request và response contract

Theo dõi:

- operation type;
- requested capabilities;
- structured-output/schema version;
- temperature/top-p class nếu cần;
- max output tokens;
- streaming;
- response format;
- outcome/error.

Không label theo mọi parameter số liên tục.

---

## 9. Latency decomposition

```text
admission/rate-limit
→ prompt/retrieval
→ provider queue
→ time to first token
→ token generation
→ tool loop
→ validation
→ client delivery
```

Total latency thấp có thể do output bị cắt ngắn.

---

## 10. Time to First Token

TTFT phản ánh lúc người dùng bắt đầu thấy response streaming. Nó gồm:

- network/gateway;
- provider queue;
- prompt prefill;
- model scheduling;
- first token transfer.

Đo client và server/provider view; không dùng TTFT cho non-streaming mà không ghi semantics.

---

## 11. Inter-token latency

Với streaming, theo dõi:

- first token;
- token/chunk rate;
- inter-token gaps;
- stalls;
- completion duration;
- disconnect/cancel.

Average throughput che pause dài giữa stream.

---

## 12. Token usage

Phân biệt:

- input/prompt;
- output/completion;
- cached;
- reasoning/internal nếu provider expose;
- tool/context;
- total.

Provider tokenizer/model khác nhau; không so raw token giữa model như cùng đơn vị semantic.

---

## 13. Cost

Cost có thể gồm:

- input/output/cached tokens;
- request;
- provisioned throughput;
- embeddings;
- vector database;
- reranker;
- tool/API;
- guardrail/evaluation;
- telemetry.

Gắn price-card version và currency/time; giá có thể thay đổi.

---

## 14. Error taxonomy

Tách:

- network/timeout;
- authentication/permission;
- quota/rate limit;
- provider/model unavailable;
- invalid request/context;
- content/policy block;
- structured-output parse;
- retrieval;
- tool;
- agent budget;
- quality failure.

HTTP error không bao phủ semantic failure.

---

## 15. Rate limits và quota

Quan sát:

- requests/tokens per interval;
- concurrent requests;
- remaining/reset nếu có;
- throttle;
- tenant fairness;
- model/region quota;
- queue/admission;
- reserved capacity.

Retry `429` không giới hạn tạo retry storm và cost.

---

## 16. Retry, fallback và model routing

Ghi:

- logical request ID nội bộ trong trace/log;
- attempt;
- reason;
- original/fallback model class;
- latency/cost added;
- quality impact;
- final outcome.

Fallback model “thành công” có thể không đáp ứng quality/safety contract ban đầu.

---

## 17. Streaming

Đo:

- stream started;
- first chunk/token;
- chunks/tokens;
- server/client cancellation;
- truncated stream;
- finish reason;
- validation strategy;
- bytes.

Nếu action được thực hiện trước khi output cuối được kiểm tra, risk tăng.

---

## 18. Finish/stop reason

Phân biệt:

- natural stop;
- length/context limit;
- content filter;
- tool call;
- client cancel;
- error.

Completion transport thành công nhưng `length` có thể tạo response không hoàn chỉnh.

---

## 19. Context window

Theo dõi:

- estimated/actual input tokens;
- configured/model limit;
- headroom;
- document/tool contribution;
- conversation growth;
- overflow error;
- compaction/summarization.

Không ghi context contents.

---

## 20. Truncation và compression

Khi context dài:

- drop oldest;
- summarize;
- select retrieval;
- compress tool output;
- reject.

Đo policy/version, tokens removed, latency và quality regression. Truncation im lặng là
correctness risk.

---

## 21. Prompt/model caching

Cache có thể giảm latency/cost nhưng cần:

- hit/miss;
- cache type;
- key policy/version;
- age;
- invalidation;
- tenant isolation;
- quality/correctness;
- cached-token accounting.

Không cache response nhạy cảm qua tenant.

---

## 22. RAG lifecycle

```text
query understanding
→ embedding
→ retrieval
→ filtering
→ reranking
→ context assembly
→ generation
→ citation/grounding check
```

Mỗi hop cần latency, error, version và quality metric.

---

## 23. Retrieval metrics

Theo dõi:

- query/retriever version;
- candidate count;
- top-k;
- empty result;
- latency;
- source freshness;
- permission filtering;
- recall/precision trên eval set;
- duplicate chunks.

Vector-search success không chứng minh tài liệu liên quan.

---

## 24. Chunking và ingestion

Quan sát offline pipeline:

- source documents;
- parse/chunk error;
- chunk size/overlap;
- embedding model/version;
- index lag;
- deletion/update;
- ACL propagation;
- duplicates;
- freshness.

Stale index tạo grounded-but-outdated answer.

---

## 25. Vector database

Cần:

- query/upsert latency/error;
- index/build;
- vector count/storage;
- memory/CPU;
- replication;
- filter selectivity;
- consistency;
- quota;
- tenant isolation.

Nối với [Database Observability](database_observability_performance.md), không coi vector DB là
hộp đen riêng.

---

## 26. Reranking

Reranker thêm:

- latency;
- tokens/cost;
- provider/model dependency;
- candidate reduction;
- score distribution;
- quality lift;
- error/fallback.

Đo lift bằng eval, không suy từ score tuyệt đối giữa model.

---

## 27. Grounding và citations

Kiểm tra:

- claim có nguồn;
- citation trỏ đúng đoạn;
- nguồn được phép;
- nguồn đủ mới;
- citation coverage;
- unsupported claim;
- link/access.

Citation tồn tại không chứng minh claim được nguồn hỗ trợ.

---

## 28. Hallucination và factuality

Không có một metric universal. Kết hợp:

- domain-specific checks;
- retrieval grounding;
- deterministic validator;
- human review;
- curated eval;
- incident/user report;
- abstention.

Luôn ghi evaluator/version và confidence limitations.

---

## 29. Offline evaluation

Dataset cần:

- use-case coverage;
- normal/edge/adversarial;
- expected outcome/rubric;
- privacy/license;
- version;
- leakage prevention;
- reviewer agreement;
- reproducible config.

Không tối ưu chỉ theo một benchmark tổng.

---

## 30. Online evaluation

Có thể dùng:

- explicit feedback;
- task completion;
- correction/retry;
- escalation;
- policy violation;
- sample human review;
- delayed business outcome.

Feedback có selection bias; user im lặng không đồng nghĩa hài lòng.

---

## 31. LLM-as-a-judge

Judge nhanh và scale được nhưng có:

- model bias;
- self-preference;
- prompt sensitivity;
- non-determinism;
- shared failure với candidate;
- cost;
- version drift.

Calibrate với human labels và giữ judge prompt/model/version.

---

## 32. Golden datasets

Quản trị như code/data product:

- immutable versions;
- provenance;
- owners;
- train/eval separation;
- scenario tags;
- expected rubric;
- privacy;
- review history.

Không sửa expected answer âm thầm để release mới “pass”.

---

## 33. Human feedback

Đo:

- rating/accept/edit/reject;
- reason taxonomy;
- reviewer expertise;
- time-to-review;
- inter-rater agreement;
- appeal;
- affected population.

Không dùng raw feedback text làm metric label.

---

## 34. Agent lifecycle

```text
goal
→ plan
→ model decision
→ tool call
→ observation
→ repeat
→ final result
```

SLI gồm task success, steps, wall time, cost, tool errors, loop/budget stop và human handoff.

---

## 35. Tool calls

Theo dõi:

- tool name/version;
- authorization scope;
- arguments schema validation;
- latency/error;
- result size;
- retry;
- side-effect/idempotency;
- approval;
- outcome.

Không ghi raw arguments/results mặc định.

---

## 36. Loop và budgets

Guardrails:

- max steps;
- max tokens/cost;
- wall-clock deadline;
- repeated-action detection;
- recursion depth;
- tool-call rate;
- human approval.

Alert loop/cost runaway trước khi quota cạn.

---

## 37. Planning

Đánh giá:

- plan validity;
- step completion;
- replan count;
- unsupported action;
- policy conflict;
- final task success.

Không cần lưu chain-of-thought/private reasoning; lưu structured plan/action summary an toàn.

---

## 38. Memory và conversation state

Phân biệt:

- current context;
- short-term session;
- long-term profile;
- retrieved history;
- summary.

Quan sát read/write/error/age/version và deletion. Memory sai tenant hoặc stale là security/
correctness incident.

---

## 39. MCP và external tools

Với Model Context Protocol hoặc tool protocol khác, quan sát:

- client/server identity;
- method/tool/resource template;
- transport latency/error;
- capability/version;
- permission/approval;
- payload-size bucket;
- retries;
- trust boundary.

Không log resource content/secret.

---

## 40. OpenTelemetry GenAI conventions

GenAI conventions đã chuyển sang repository chuyên biệt và tiếp tục tiến hóa. Do đó:

- pin commit/release/schema;
- theo dõi changelog;
- test generated attributes;
- giữ compatibility layer;
- không hard-code raw prompt/output collection;
- canary instrumentation.

---

## 41. Trace design

Một trace có thể gồm:

```text
user request
→ retrieval/embedding
→ model generation
→ tool calls
→ validation
→ response
```

Dùng span links cho async/fan-out khi cần. Span name low-cardinality theo operation/model class.

---

## 42. Metrics

Bộ cơ bản:

- operation requests/errors/duration;
- TTFT/generation duration;
- input/output tokens;
- cost estimate;
- active/concurrent;
- tool/retrieval outcome;
- quality/safety rates;
- evaluator coverage.

Model, provider, operation, prompt version là dimensions được quản trị.

---

## 43. Events và logs

Structured event có thể chứa:

- lifecycle/finish reason;
- stable error;
- prompt/template version;
- model/provider;
- token/cost;
- guardrail decision;
- evaluation score;
- trace ID.

Prompt/output content là opt-in riêng, không mặc định.

---

## 44. Prompt/output privacy

Nội dung có thể chứa PII, secret, health/payment data, source code hoặc copyrighted material.
Áp dụng:

- classification;
- no-content mode;
- on-device/source redaction;
- encryption;
- tenant isolation;
- retention/deletion;
- access audit.

---

## 45. Redaction

Redaction regex đơn giản không bắt mọi secret/PII và có false positive. Thiết kế:

- allowlist trước;
- structured-field policy;
- secret scanner;
- domain detector;
- human test;
- failure mode fail-closed/open rõ;
- metrics về redaction, không raw match.

---

## 46. Prompt injection

Quan sát:

- untrusted input/source;
- injection detector/guardrail decision;
- instruction/data boundary;
- tool request bất thường;
- privilege escalation;
- blocked/allowed;
- downstream effect.

RAG hoặc fine-tuning không tự loại bỏ prompt injection.

---

## 47. Insecure output handling

Model output là untrusted input cho:

- HTML/SQL/shell/code;
- tool arguments;
- URLs;
- database writes;
- messages.

Đo validation/sanitization failure, blocked action và approval. Không thực thi trực tiếp chỉ vì
model trả JSON hợp lệ.

---

## 48. Data exfiltration

Guardrails:

- egress/tool allowlist;
- tenant/document ACL;
- secret detection;
- output policy;
- DLP;
- least privilege;
- rate/budget;
- incident audit.

Telemetry chính nó không được trở thành đường exfiltration.

---

## 49. Access control

Authorization phải ở tool/data/backend, không giao cho prompt. Quan sát:

- principal/service;
- resource/action template;
- allow/deny reason;
- approval;
- policy version;
- unusual pattern.

Không để model tự khai identity.

---

## 50. Model và supply chain

Inventory:

- model/provider/version;
- fine-tune/adapters;
- prompt;
- embedding/reranker;
- datasets;
- libraries;
- deployment endpoint;
- license/terms;
- evaluation evidence.

Provider model update có thể là change event dù application không deploy.

---

## 51. Safety và moderation

Theo dõi policy categories hữu hạn:

- input flagged/blocked;
- output flagged/blocked;
- severity/confidence;
- appeal/override;
- false positive/negative sample;
- latency;
- policy/model version.

Không đưa sensitive content vào alert notification.

---

## 52. Bias và fairness

Đánh giá theo use case, affected groups và legal/privacy constraints:

- performance disparities;
- harmful stereotypes;
- refusal disparity;
- language/locale;
- accessibility;
- human review.

Không thu protected attributes nếu không có cơ sở, governance và security phù hợp.

---

## 53. Guardrail observability

Guardrail có failure modes:

- unavailable/timeout;
- fail-open/fail-closed;
- version drift;
- bypass;
- excessive blocking;
- cost/latency;
- inconsistent stages.

Dashboard phải biết request nào chưa được guardrail đánh giá.

---

## 54. Sampling

Không sample-away safety incident hiếm, nhưng lưu mọi content là rủi ro. Tách:

- aggregate metrics 100%;
- metadata traces có budget;
- content capture opt-in/quarantine;
- safety events ưu tiên không chứa content;
- evaluation sample có consent;
- weights/coverage.

---

## 55. Cardinality và cost

Tránh metric labels:

- prompt text/hash;
- conversation/user/request ID;
- document ID;
- tool arguments;
- error message;
- model response.

Giữ versions và taxonomy hữu hạn; chi tiết ở protected trace/log với retention ngắn.

---

## 56. Dashboard

```text
Business task/quality/safety
→ workflow/version
→ model/provider latency/tokens/cost
→ RAG/retrieval
→ agent/tools
→ guardrails
→ infrastructure/quota
→ changes/evaluations
```

Hiển thị evaluation coverage và sample size cạnh quality score.

---

## 57. Alerting

Page/halt rollout khi:

- user/business SLO burn;
- safety/data exposure incident;
- widespread provider/quota failure;
- runaway agent/cost;
- retrieval/guardrail unavailable theo policy;
- severe quality regression có evidence.

Không page từng low-confidence judge score.

---

## 58. Incident workflow

```text
1. Xác nhận use case, release, prompt/model/provider
2. Tách operational, quality và safety
3. Kiểm tra routing/retry/fallback/quota
4. Kiểm tra RAG/tool/guardrail
5. Giữ evidence trong access boundary
6. Disable feature/model/tool hoặc rollback
7. Đánh giá affected outputs/users
8. Re-evaluate, communicate và learn
```

---

## 59. Evaluation regression

Pipeline release:

```text
unit/schema/security tests
→ offline golden eval
→ adversarial/red-team
→ shadow/canary
→ online outcome/human review
```

So cùng dataset, evaluator, seeds/config khi có và confidence interval.

---

## 60. Canary và A/B

Randomize/segment phù hợp, theo dõi:

- task quality;
- latency/TTFT;
- tokens/cost;
- refusal/safety;
- tool success;
- user outcome;
- sample size.

Không gửi high-risk task vào experiment chưa được review.

---

## 61. Capacity

Model API capacity gồm:

- requests/tokens per minute;
- concurrent streams;
- context/output sizes;
- provider regions;
- embedding/retrieval;
- tool dependencies;
- fallback quota;
- evaluation traffic.

Load test bằng synthetic/redacted prompts, không production data.

---

## 62. Resilience

Thiết kế degraded modes:

- smaller/fallback model;
- non-AI deterministic path;
- retrieval-only result;
- cached safe response;
- human handoff;
- queue;
- reject/load shed.

Mỗi mode có quality/safety contract riêng.

---

## 63. Governance

Mỗi use case cần:

- owner và intended use;
- risk tier;
- model/prompt/data inventory;
- SLO/evaluation;
- safety/access/privacy;
- human oversight;
- cost budget;
- incident/disclosure;
- deprecation.

Áp dụng vòng đời govern–map–measure–manage, không chỉ dashboard.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một GenAI journey.
2. Vẽ prompt → RAG → model → tool → outcome.
3. Instrument TTFT, tokens, cost và error không ghi content.
4. Version prompt/model/evaluator.
5. Chạy golden + adversarial eval.
6. Mô phỏng rate limit, prompt injection và tool failure.

### Checklist

- [ ] Reliability, quality và safety được tách.
- [ ] Model/provider/prompt/evaluator có version.
- [ ] TTFT, generation, tokens và cost có semantics.
- [ ] RAG freshness/ACL/grounding có signal.
- [ ] Agent có step/time/token/cost budgets.
- [ ] Tool arguments/results không bị log mặc định.
- [ ] Prompt/output capture là opt-in được bảo vệ.
- [ ] Guardrail fail-open/closed được ghi rõ.
- [ ] Evaluation coverage/sample size hiển thị.
- [ ] OTel GenAI schema được pin/migration test.

### Câu hỏi

1. HTTP 200 có chứng minh output đúng không?
2. TTFT khác total generation latency thế nào?
3. Token giữa model có so trực tiếp được không?
4. Citation tồn tại có chứng minh grounding không?
5. LLM-as-a-judge có bias gì?
6. Agent loop cần những budget nào?
7. Vì sao không lưu chain-of-thought?
8. Prompt injection khác insecure output handling thế nào?
9. Sampling có phải privacy control không?
10. Guardrail unavailable nên fail-open hay fail-closed?
11. Fallback model ảnh hưởng contract ra sao?
12. Cost per outcome khác cost per model call thế nào?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### OpenTelemetry

- [OpenTelemetry GenAI Semantic Conventions repository](https://github.com/open-telemetry/semantic-conventions-genai)
- [OpenTelemetry notice về việc chuyển GenAI conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [OpenTelemetry tracing](https://opentelemetry.io/docs/concepts/signals/traces/)

### Risk, safety và security

- [NIST AI Risk Management Framework](https://www.nist.gov/itl/ai-risk-management-framework)
- [NIST Generative AI Profile](https://doi.org/10.6028/NIST.AI.600-1)
- [NIST AI Resource Center](https://airc.nist.gov/)
- [OWASP Top 10 for LLM Applications 2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/)

Chủ đề tiếp theo gợi ý:
[Data Pipeline & ETL Observability](data_pipeline_etl_observability.md) – freshness,
completeness, schema, lineage, backfill,
data quality, orchestration, warehouse cost và data incidents.

---

*Cập nhật lần cuối: 2026-07-30*
