# Security Risk Quantification, Scenario Analysis & Decision Uncertainty

> Mục tiêu: biến câu nói mơ hồ như “rủi ro cao” thành một mô hình đủ rõ để so sánh lựa chọn, đặt ngưỡng hành động
> và ra quyết định có trách nhiệm—không tạo ra độ chính xác giả từ dữ liệu yếu hoặc một công thức đẹp.

---

## 1. Quantification là decision support

Risk quantification có giá trị khi giúp trả lời một quyết định cụ thể:

- đầu tư control A hay B;
- xử lý ngay hay chờ thêm bằng chứng;
- chấp nhận, giảm thiểu, chuyển giao hay tránh risk;
- giới hạn rollout ở đâu;
- cần escalation tới authority nào;
- khi nào phải dừng hoặc đổi phương án.

Output không nhất thiết luôn là tiền. Nó có thể là tần suất, downtime, số người bị ảnh hưởng, xác suất vượt ngưỡng
hoặc distribution của loss. Mô hình tốt làm trade-off và uncertainty nhìn thấy được.

## 2. Quantification không phải cỗ máy tạo sự chắc chắn

Ba ngộ nhận phổ biến:

1. Có số thập phân nghĩa là chính xác.
2. Mô phỏng nhiều lần sẽ sửa được input yếu.
3. Một con số monetary có thể thay thế judgment về safety, legal, privacy hoặc ethics.

Mô hình chỉ có thể nhất quán với assumptions và evidence đã đưa vào. Nó không biến unknown thành fact.
Hãy dùng số để cấu trúc tranh luận, không dùng số để kết thúc tranh luận.

## 3. Bắt đầu từ quyết định, không bắt đầu từ công cụ

Decision framing tối thiểu:

```text
decision owner + decision deadline
options thật sự khả thi
criteria / constraints
risk scenarios có thể làm thay đổi lựa chọn
evidence hiện có + unknown quan trọng
ngưỡng khiến decision đổi
```

Nếu hai option vẫn được chọn giống nhau trên mọi range hợp lý, mô hình chi tiết hơn ít giá trị.
Nếu một input nhỏ có thể đảo quyết định, ưu tiên thu thập bằng chứng cho input đó.

## 4. Chọn đúng decision object và unit of analysis

Một mô hình chỉ nên định lượng một object rõ:

- một service trong một production boundary;
- một loại sự kiện đối với một population tài khoản;
- một nhà cung cấp và một business process;
- một portfolio scenarios trong một kỳ lập kế hoạch;
- một thay đổi architecture cụ thể.

Không trộn “rủi ro của cloud”, “rủi ro ransomware” và “rủi ro công ty” trong cùng một score.
Ghi rõ scope, exclusions, population, currency, time horizon và ngày hiệu lực của dữ liệu.

## 5. Scenario grammar

Một scenario hữu ích có cấu trúc:

```text
[threat source / initiating condition]
    thực hiện [event / pathway]
    qua [exposure / weakness / dependency]
    tác động [asset / service / population]
    dẫn tới [business consequence]
    trong [scope + time horizon]
```

Ví dụ: “Trong 12 tháng, attacker dùng credential bị đánh cắp để chiếm privileged support account,
truy cập tenant production và làm lộ dữ liệu khách hàng, gây response cost, downtime và notification obligations.”

## 6. Scenario quality gate

Không định lượng scenario nếu chưa trả lời được:

- event nào được tính là một occurrence;
- entry point và trust boundary nào liên quan;
- asset/population cụ thể là gì;
- consequence nào thuộc scope;
- control nào đã tồn tại;
- khi nào hai events được coi là cùng một incident;
- duplicate, near miss và blocked attempt được xử lý ra sao.

Scenario quá rộng tạo double counting; scenario quá hẹp bỏ mất common-cause và cascading loss.

## 7. Reference class và base rate

Ước lượng nên bắt đầu từ một nhóm sự kiện tương đồng thay vì ký ức nổi bật nhất.

Reference class có thể là:

- cùng loại service và exposure;
- cùng population identity;
- incident nội bộ trong vài năm;
- peer/sector data có định nghĩa đủ gần;
- cùng attack path trước và sau control change.

Ghi rõ lý do nhóm này tương đồng và điểm khác biệt cần điều chỉnh. Base rate là điểm xuất phát, không phải câu trả lời cuối.

## 8. Time horizon và đơn vị đo

Frequency cần đơn vị như `events/year`; impact cần đơn vị như `VND/event`, `hours/event` hoặc `people/event`.

Không so sánh trực tiếp:

- probability trong 30 ngày với probability trong 12 tháng;
- loss theo incident với loss cả năm;
- service downtime với business-process downtime;
- gross loss với net loss sau recovery/insurance.

Nếu dùng annualized view, ghi assumptions về seasonality, growth, exposure time và control rollout.

## 9. Inherent, current, residual và target risk

| View | Câu hỏi |
|---|---|
| Inherent | Scenario thế nào nếu không tính các controls đang đánh giá? |
| Current | Với implementation thực tế hôm nay, exposure là gì? |
| Residual | Sau treatment đã chọn, pathway/consequence nào còn lại? |
| Target | Mức exposure tổ chức muốn đạt theo thời hạn nào? |

Không tính residual bằng `inherent score - control score`. Control có thể giảm frequency, giảm magnitude, chuyển pathway,
tạo dependency mới hoặc thất bại cùng lúc; cần mô hình hóa effect lên factor tương ứng.

## 10. Chọn mức định lượng phù hợp

| Mức | Khi phù hợp | Output điển hình |
|---|---|---|
| Qualitative | triage nhanh, data rất ít | narrative + ordered category |
| Semi-quantitative | cần consistency và threshold | band có định nghĩa, range neo rõ |
| Quantitative | decision material, cần trade-off | distributions, percentiles, exceedance |

Không phải mọi risk đều cần Monte Carlo. Mức nỗ lực nên tỷ lệ với materiality, reversibility, uncertainty và chi phí trì hoãn.

## 11. Data inventory và lineage

Mỗi input nên có record:

```text
name / definition / unit
source + extraction time
population + coverage period
transformations / exclusions
owner / steward
quality limitations
model versions consuming it
```

Nếu không tái tạo được input từ source tới output, con số không đủ điều kiện cho decision quan trọng.

## 12. Dữ liệu sự kiện nội bộ

Nguồn thường dùng:

- incident/case records;
- identity và access events;
- fraud/abuse losses;
- outage và recovery records;
- service desk, legal, privacy và claims data;
- control tests, exercises và near misses.

Đếm incident không đủ. Cần thống nhất taxonomy, deduplication, detection coverage, closure criteria và loss attribution.
“Không thấy incident” có thể nghĩa là frequency thấp, hoặc visibility thấp.

## 13. Dữ liệu bên ngoài

External data giúp mở rộng reference class nhưng phải kiểm tra:

- định nghĩa event/loss có tương thích không;
- sample có selection/reporting bias không;
- sector, geography và company size có tương đồng không;
- gross hay net loss;
- năm dữ liệu và inflation/currency;
- event rất lớn có bị cắt ngọn hay không.

Không copy một industry average vào mô hình nội bộ mà không có adjustment rationale.

## 14. Missing data và bias

Các bias thường gặp:

- chỉ incident lớn được báo cáo;
- blocked attempts bị đếm như successful events;
- loss gián tiếp bị bỏ quên;
- dữ liệu tốt hơn ở system được giám sát kỹ;
- control mới chưa đủ thời gian quan sát;
- survivorship bias từ vendor hoặc business unit còn hoạt động.

Mô hình nên biểu diễn missingness thành uncertainty hoặc scenario riêng, không silently điền một point estimate.

## 15. Expert elicitation có kỷ luật

Khi thiếu data, expert judgment là evidence hợp lệ nếu quy trình minh bạch:

1. Định nghĩa quantity và resolution rule.
2. Cho chuyên gia ước lượng độc lập trước thảo luận.
3. Yêu cầu low/high trước, rồi median.
4. Ghi facts, assumptions và rationale riêng.
5. Challenge reference class và disconfirming evidence.
6. Aggregate nhưng giữ disagreement material.
7. Đặt ngày cập nhật khi có evidence mới.

Không để người có chức danh cao đưa con số đầu tiên và neo cả nhóm.

## 16. Calibration training

Calibration đo sự phù hợp giữa confidence và kết quả thực tế. Nếu một người đưa nhiều khoảng tin cậy 80%,
khoảng 80% đáp án đúng nên rơi vào các khoảng đó trong dài hạn.

Một bài tập thực tế:

- dùng câu hỏi có đáp án kiểm chứng được;
- ước lượng khoảng 80% hoặc probability;
- resolve và chấm kết quả;
- xem lại overconfidence/underconfidence;
- lặp lại trước các workshop quan trọng.

Calibration không biến chuyên gia thành oracle; nó giảm thói quen đưa range quá hẹp.

## 17. Decomposition và Fermi estimation

Một quantity khó có thể tách thành factors dễ ước lượng hơn:

```text
annual successful events
≈ exposure opportunities/year
× probability threat acts per opportunity
× probability pathway succeeds given action
```

Loss có thể tách thành records affected, response hours, outage duration, notification population và unit cost.
Chỉ tách khi factors có nghĩa, tránh tạo chuỗi nhân dài với correlation bị bỏ qua.

## 18. Estimates là ranges

Thay vì “frequency = 2”, dùng một range có semantics, ví dụ:

```text
P05 = 0.2 events/year
P50 = 1.0 events/year
P95 = 4.0 events/year
```

`P05/P50/P95` mô tả quantiles của belief/model, không phải minimum/average/maximum chắc chắn.
Nếu dùng `low / most likely / high`, phải định nghĩa low/high là percentile nào.

## 19. Distribution selection

Một số distribution thường gặp:

- Bernoulli: event có/không trong một trial;
- Poisson: count events độc lập với rate tương đối ổn định;
- triangular/PERT: limited elicitation, có bounds/mode;
- lognormal: positive loss với right tail;
- Pareto/heavy-tail: extreme loss có vai trò lớn;
- empirical/bootstrap: tái sử dụng observed sample.

Tên distribution không tạo validity. Ghi lý do chọn, fit, truncation, parameter source và limitations.

## 20. Frequency estimation

Tách ba khái niệm:

- opportunity/contact frequency;
- threat-event frequency;
- successful loss-event frequency.

Blocked scans không bằng compromise; phishing email không bằng session takeover.
Frequency model phải thể hiện control nào ngăn event, control nào chỉ phát hiện và control nào giảm consequence sau event.

## 21. Rate và probability không phải một thứ

`λ = 2 events/year` là rate, không phải “200% probability”. Nếu giả định Poisson phù hợp, probability có ít nhất một event trong kỳ `t` là:

```text
P(N ≥ 1) = 1 - e^(-λt)
```

Đây là hệ quả của một model assumption: events độc lập và rate ổn định. Không dùng công thức khi có seasonality mạnh,
campaign clustering, contagion hoặc attacker thích nghi với control.

## 22. Conditional probability và attack path

Một attack path thường có các bước phụ thuộc:

```text
credential obtained
    → MFA/session bypass
        → privileged access
            → sensitive action
                → detection before harm?
```

Không nhân probability của từng bước nếu chúng không conditional đúng hoặc chia sẻ common cause.
Giữ rõ `P(B|A)` và nguồn ước lượng; dùng alternative paths để tránh giả định chỉ có một con đường.

## 23. Ước lượng control effect

Control effect nên gắn vào factor cụ thể:

| Control | Factor có thể thay đổi |
|---|---|
| phishing-resistant MFA | probability takeover thành công |
| rate limit | opportunity/success rate |
| segmentation | population và blast radius |
| immutable recovery | outage duration/recovery loss |
| detection | dwell time và probability containment sớm |

Phân biệt design effectiveness, implementation coverage, operating reliability và adversary adaptation.
Không dùng vendor claim như observed effect nếu chưa có evidence nội bộ.

## 24. Impact taxonomy

Impact có thể gồm:

- response, forensics và restoration;
- interruption/productivity;
- replacement/reconstruction;
- fraud/theft;
- notification, legal và contractual response;
- customer remediation/churn;
- safety, privacy, civil liberties hoặc societal harm;
- strategic opportunity loss.

Taxonomy giúp tránh double counting. Mỗi component cần unit, owner, time window và attribution rule.

## 25. Direct và indirect loss

Direct loss xuất hiện gần event: contractor response, overtime, restored infrastructure, refund.
Indirect loss có thể đến sau: delayed launch, churn, higher financing/insurance cost hoặc management distraction.

Không dùng một “reputation multiplier” cố định cho mọi scenario. Mô hình causal pathway:

```text
event severity → disclosure/experience → stakeholder response → economic consequence
```

Nếu evidence yếu, giữ indirect loss như range rộng hoặc một decision-relevant non-monetary outcome.

## 26. Harm không nên hoặc không thể quy thành tiền

Monetization không được ghi đè:

- legal prohibition;
- safety threshold;
- fundamental rights;
- ethical commitments;
- irreversible environmental/social harm;
- contractual minimum bắt buộc.

Dùng constraints/guardrails trước, sau đó tối ưu các option còn hợp lệ. Có thể báo cáo song song monetary loss,
people affected, recovery time và severity class thay vì ép mọi harm vào một đơn vị.

## 27. Annual loss distribution

Một mô hình phổ biến kết hợp:

```text
annual frequency distribution
× per-event magnitude distribution
→ annual loss distribution
```

Output nên gồm median, tail percentiles và probability vượt thresholds. Không chỉ đưa mean.
Nếu một năm có nhiều events, mô phỏng count và severity cho từng event; tránh nhân hai averages rồi gọi đó là full distribution.

## 28. Expected loss và giới hạn của nó

Expected annual loss hữu ích để so sánh exposure lặp lại, nhưng có thể che khuất tail:

- Option A: loss nhỏ thường xuyên.
- Option B: hầu như không loss nhưng có khả năng cực lớn.

Hai option có thể cùng mean nhưng không cùng khả năng sống sót. Báo cáo thêm P90/P95/P99, maximum plausible loss,
probability vượt tolerance và thời gian recovery. Không dùng expected loss như budget ceiling tự động.

## 29. Correlation và common-mode failure

Không cộng các scenario như độc lập nếu chúng cùng phụ thuộc:

- identity provider;
- cloud region/control plane;
- shared library/build pipeline;
- managed service provider;
- workforce/process;
- geopolitical/campaign driver.

Model correlation, shared event hoặc stress scenario. Nếu chưa đủ data để ước lượng correlation, chạy ít nhất independent/base/common-cause cases.

## 30. Portfolio aggregation và concentration

Aggregation không chỉ là cộng expected values. Cần giữ:

- scenario identity và owner;
- dependency/common cause;
- business-unit/geography/provider concentration;
- timing và response-capacity contention;
- diversification assumptions;
- tail contribution.

Portfolio view phải cho phép drill-down. Một total lớn mà không biết scenario nào tạo tail không giúp quyết định treatment.

## 31. Tail risk và stress scenario

Rare event thường thiếu data nhưng vẫn material. Stress test nên hỏi:

- nếu primary control thất bại cùng lúc thì sao;
- nếu incident kéo dài hơn lịch sử;
- nếu recovery site/provider cũng unavailable;
- nếu nhiều business units bị ảnh hưởng;
- nếu notification/recovery resources bị nghẽn;
- nếu event xảy ra đúng peak period.

Stress scenario không phải prediction; nó kiểm tra survivability và quyết định trước các điều kiện khắc nghiệt hợp lý.

## 32. Monte Carlo simulation

Monte Carlo lấy mẫu nhiều lần từ input distributions để tạo output distribution:

```text
for each simulated year:
    sample event count
    for each event: sample magnitude and dependencies
    sum annual outcomes
summarize percentiles / exceedance
```

Số lượt chạy lớn chỉ giảm simulation noise. Nó không sửa bias, scenario sai, distribution sai hoặc correlation bị bỏ qua.

## 33. Aleatory và epistemic uncertainty

| Loại | Ý nghĩa | Cách xử lý |
|---|---|---|
| Aleatory | biến động vốn có của event/outcome | distribution, resilience, buffer |
| Epistemic | thiếu hiểu biết/data/model | nghiên cứu, test, pilot, range/model alternatives |

Hai loại có thể cùng tồn tại. Thu thập thêm data có thể giảm epistemic uncertainty nhưng không loại bỏ randomness.
Ghi loại uncertainty giúp chọn đúng hành động.

## 34. Confidence khác probability và precision

- `10% probability of event` nói về event.
- `low confidence` nói về chất lượng belief/model.
- `10.0%` chỉ thể hiện formatting precision, không chứng minh confidence.

Một output nên đi kèm confidence rationale: data coverage, recency, agreement, calibration, model fit và unknowns.
Không thu hẹp range để slide trông “quyết đoán” hơn.

## 35. Sensitivity analysis

Sensitivity trả lời: input nào làm output hoặc decision thay đổi nhiều nhất?

Thực hiện ít nhất:

1. thay đổi từng input trong range hợp lý;
2. kiểm tra ranking/options có đảo không;
3. thử structural assumptions khác;
4. thử correlation/tail cases;
5. xác định evidence nào đáng mua thêm.

Tornado chart chỉ là visualization; giá trị nằm ở action sau khi biết decision driver.

## 36. Scenario và option comparison

Mỗi option cần cùng baseline và horizon:

| Option | Frequency effect | Magnitude effect | Cost/time | New risk | Reversible? |
|---|---|---|---|---|
| Giữ nguyên | baseline | baseline | thấp | exposure kéo dài | có |
| Control A | giảm success | ít đổi | vừa/nhanh | dependency mới | khá |
| Control B | ít đổi | giảm blast radius | cao/chậm | migration risk | thấp |

Không cho treatment chỉ lợi ích mà không có implementation/transition/operational risk.

## 37. Appetite, tolerance và decision threshold

Appetite là định hướng mức/type risk tổ chức sẵn sàng theo đuổi hoặc giữ; tolerance cụ thể hóa boundaries.

Threshold có thể là:

- probability annual loss vượt một mức;
- maximum outage/plausible records affected;
- minimum safety/privacy/legal condition;
- concentration vào một provider;
- deadline control gap phải đóng;
- confidence tối thiểu để rollout rộng.

Threshold phải gắn authority và action. “Đỏ” mà không trigger gì chỉ là màu.

## 38. Value of information

Thông tin mới có giá trị khi nó có thể thay đổi quyết định hoặc cách triển khai.

```text
VOI ≈ expected decision improvement from new evidence
      - cost of obtaining it
      - cost/risk of delay
```

Hỏi ba câu: input nào đang drive decision, evidence nào có thể thu hẹp/di chuyển range, và kết quả nào sẽ đảo option?
Không trì hoãn vô hạn để tìm certainty không thể đạt.

## 39. Value of control và treatment

So sánh control bằng thay đổi toàn bộ outcome distribution, không chỉ “risk score giảm 2 điểm”:

- exposure giảm bao nhiêu;
- tail giảm hay chỉ mean giảm;
- time-to-benefit;
- coverage và reliability;
- implementation/operating cost;
- dependencies và failure modes mới;
- option value cho tương lai.

Treatment có thể là tránh, giảm, chuyển giao/chia sẻ hoặc chấp nhận; mỗi loại cần residual scenario rõ.

## 40. Cost-benefit và discounting

Với chương trình nhiều năm, có thể so sánh present value của cost và risk reduction. Nhưng cần công khai:

- horizon và discount rate;
- ramp-up/adoption;
- maintenance/replacement cost;
- exposure growth;
- benefits ngoài monetary loss;
- terminal assumptions.

NPV đẹp không hợp thức hóa option vi phạm constraint. Không giả định risk reduction tồn tại mãi sau khi ngừng vận hành control.

## 41. Decision dưới deep uncertainty

Khi model alternatives cho kết quả rất khác, tìm option robust thay vì “ước lượng đúng nhất”:

- hiệu quả chấp nhận được ở nhiều futures;
- giới hạn downside/tail;
- có trigger để đổi hướng;
- giữ năng lực recovery;
- tránh lock-in sớm;
- giảm regret nếu assumption sai.

Deep uncertainty cần adaptive plan, không cần point estimate giả chính xác.

## 42. Reversibility, pilot và real options

Phân loại quyết định:

- reversible, low-cost: thử nhanh với guardrails;
- reversible nhưng recovery chậm: stage rollout;
- hard-to-reverse/material: tăng evidence và independent challenge;
- irreversible/safety critical: áp dụng constraints nghiêm ngặt.

Pilot có giá trị khi tạo evidence đại diện và có resolution rule. Canary không hữu ích nếu population quá khác production hoặc success criteria mơ hồ.

## 43. Trình bày uncertainty cho người quyết định

Một decision view tốt gồm:

```text
decision + deadline + owner
scenario và business consequence
options + constraints
P50 / P90 / P95 hoặc exceedance probabilities
top assumptions + confidence
sensitivity / tail / common-cause case
recommended action + trigger + next evidence
```

Dùng range/fan chart khi cần, nhưng luôn có narrative và đơn vị. Không giấu unknown dưới màu trung bình.

## 44. Decision record và model card

Model card tối thiểu:

- purpose và prohibited uses;
- scenario/scope/time horizon;
- owner, reviewers, version;
- inputs, lineage, transformations;
- distributions và dependencies;
- assumptions/limitations;
- calibration/validation status;
- outputs và decision consumers;
- change/expiry/review triggers.

Decision record tham chiếu model version, options, rationale, dissent, conditions và evidence cần theo dõi.

## 45. Governance và independent challenge

Vai trò nên tách khi material:

- scenario/business owner xác nhận consequence;
- risk analyst xây model;
- data owner xác nhận lineage/quality;
- control owner xác nhận implementation;
- independent reviewer challenge assumptions;
- decision authority chọn option/accept residual risk.

Reviewer không chỉ kiểm tra spreadsheet formula; họ challenge framing, omitted scenarios, bias, dependencies và fitness for decision.

## 46. Model risk và change control

Model có lifecycle:

```text
draft → reviewed → approved for stated use → monitored
      → recalibrated / superseded / retired
```

Trigger review khi scenario/boundary thay đổi, data source drift, control rollout, incident lớn, prediction miss,
appetite/tolerance đổi hoặc model được dùng cho decision ngoài purpose ban đầu. Giữ version, changelog và ability tái tạo output cũ.

## 47. Validation, backtesting và scoring

Validation có nhiều lớp:

- conceptual: causal structure có hợp lý;
- data: coverage/definition/lineage;
- computational: formulas/simulation/reproducibility;
- outcome: forecast so với resolved events;
- decision: model có cải thiện lựa chọn và trigger không.

Với probability forecasts, có thể theo dõi calibration và Brier score. Với rare events, kết hợp proxy tests, exercises,
stress tests và evidence về từng factor; không chờ hàng thập kỷ mới validate.

## 48. Ví dụ: privileged credential compromise

Decision: chọn giữa mở rộng phishing-resistant MFA hoặc tăng session detection cho support admins trong 12 tháng.

```text
Scenario: stolen support credential → bypass/session abuse
          → privileged tenant access → customer-data exposure

Frequency inputs:
  credential exposure opportunities
  probability usable credential/session
  probability privilege path succeeds
  probability containment before harmful action

Magnitude inputs:
  tenants/records affected
  investigation + restoration hours
  downtime/refund/notification ranges
  tail case: shared admin plane compromise
```

MFA có thể giảm success probability; detection giảm dwell time/magnitude. Sensitivity có thể cho thấy admin-plane segmentation
giảm tail mạnh hơn cả hai. Decision record nên giữ assumptions về coverage, adoption và bypass pathways.

## 49. Lộ trình 90 ngày

### Ngày 1–30: chuẩn hóa

- chọn 3–5 material decisions, không chọn toàn bộ register;
- định nghĩa scenario grammar, unit, horizon và data dictionary;
- kiểm kê internal/external evidence;
- calibration workshop và independent elicitation;
- tạo model-card/decision-record template.

### Ngày 31–60: pilot

- xây range-based models đơn giản;
- chạy sensitivity, tail và common-cause cases;
- đối chiếu appetite/tolerance và actual options;
- review bởi business, data, control và independent challenger.

### Ngày 61–90: vận hành

- đưa output vào một decision forum thật;
- ghi quyết định, triggers và evidence follow-up;
- backtest resolved inputs;
- version/change-control models;
- mở rộng chỉ khi pilot thực sự cải thiện decision.

## 50. Checklist production, anti-pattern và nguồn

### Checklist

- [ ] Decision, owner, deadline, options và constraints đã rõ.
- [ ] Scenario có threat/event/pathway/asset/consequence/scope/horizon.
- [ ] Frequency và magnitude dùng đúng units; range có percentile semantics.
- [ ] Data lineage, missingness, bias và expert assumptions được ghi.
- [ ] Control effect gắn vào factor, coverage và reliability thực tế.
- [ ] Tail, correlation, concentration và common-cause đã được thử.
- [ ] Monetary outcome không ghi đè legal/safety/privacy/ethical guardrails.
- [ ] Sensitivity xác định input có thể đổi decision.
- [ ] Output có confidence, limitations và exceedance thresholds.
- [ ] Model/decision có version, reviewer, trigger và expiry.

### Anti-pattern cần tránh

- Nhân hai ordinal scores `likelihood × impact` rồi coi khoảng cách là toán học.
- Cộng số lượng risk đỏ/vàng/xanh để đo enterprise exposure.
- Dùng point estimate không có range hoặc rationale.
- Gọi blocked attempts là loss events.
- Monte Carlo trên inputs tùy ý và correlation bằng 0.
- Chỉ báo cáo mean, bỏ tail và survivability.
- Dùng annualized loss expectancy làm ngân sách tối đa tự động.
- Thu hẹp range để đạt approval.
- Model owner cũng là reviewer/decision authority cho material case.
- Giữ model sau khi purpose, scope hoặc evidence đã đổi.

### Nguồn chính thức

- [NIST IR 8286A Rev.1](https://csrc.nist.gov/pubs/ir/8286/a/r1/final) — risk guidance, scenario identification,
  likelihood/impact estimation, appetite/tolerance và cybersecurity risk register.
- [NIST IR 8286B](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final) — ưu tiên risk theo enterprise objectives,
  lựa chọn response và lưu response information trong risk register.
- [NIST IR 8286 Rev.1](https://csrc.nist.gov/pubs/ir/8286/r1/final) — tích hợp cybersecurity risk với enterprise risk management.
- [NIST IR 8286D](https://csrc.nist.gov/pubs/ir/8286/d/upd1/final) — dùng business impact analysis để ưu tiên và xử lý risk.
- [NIST SP 800-30 Rev.1](https://csrc.nist.gov/pubs/sp/800/30/r1/final) — chuẩn bị, thực hiện, truyền đạt và duy trì risk assessment.

### Học tiếp

1. [Cybersecurity Mergers, Acquisitions & Divestitures Engineering](cybersecurity_mergers_acquisitions_divestitures_engineering.md) — due diligence, transition risk,
   identity/data/control integration, TSA, separation và inherited liability.
2. [Security Risk Transfer, Cyber Insurance & Contractual Allocation](security_risk_transfer_cyber_insurance_contractual_allocation.md) — insurability, exclusions,
   retention, limits, claims evidence và residual accountability.

---

*Cập nhật lần cuối: 2026-08-03.*
