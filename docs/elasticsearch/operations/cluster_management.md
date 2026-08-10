---
title: "Elasticsearch Cluster Management – vận hành theo failure semantics"
topic: elasticsearch
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# Elasticsearch Cluster Management – vận hành theo failure semantics

> Thuật ngữ: [Glossary](../glossary.md).

> Vận hành Elasticsearch không phải giữ dashboard luôn màu xanh. Mục tiêu là biết
> dữ liệu nào đang phục vụ được, copy nào còn hợp lệ, hệ thống tự phục hồi đến đâu,
> khi nào cần can thiệp và thao tác nào có thể làm mất dữ liệu. Mọi runbook phải
> bảo vệ correctness trước khi tối ưu tốc độ recovery.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Elastic Cloud Hosted,
ECE, ECK và Serverless tự quản lý một phần hạ tầng khác nhau; lệnh dành cho
self-managed không được áp dụng máy móc lên deployment do orchestrator quản lý.

---

## 1. Ba lớp vận hành phải tách biệt

```text
Control plane
  master election → cluster state → allocation decision

Data plane
  primary/replica → indexing/search → refresh/merge

Protection plane
  snapshot/restore + nguồn rebuild + CCR
```

| Cơ chế | Bảo vệ chính | Không bảo vệ |
|---|---|---|
| Replica | node/shard-copy failure, tăng read capacity | xóa nhầm, lỗi ứng dụng, cluster-wide corruption |
| Multi-zone placement | mất một failure domain | mất nhiều zone vượt thiết kế |
| Snapshot | point-in-time recovery, xóa nhầm, DR | RPO sau snapshot gần nhất, failover tức thời |
| CCR | RPO thấp, read locality, tách cluster | xóa/lỗi logic có thể replicate; không thay snapshot |
| Source có thể replay | rebuild search projection | cấu hình hệ thống nếu không backup riêng |

`green` chỉ nói mọi shard copy theo cấu hình đang assigned. Nó không chứng minh
backup dùng được, dữ liệu đúng hoặc cluster chịu được zone failure.

---

## 2. Xác định trách nhiệm theo deployment

| Deployment | Elastic/orchestrator thường quản lý | Người dùng vẫn phải quản lý |
|---|---|---|
| Serverless | node, shard placement, upgrade hạ tầng | data model, query, client, quota và export/rebuild |
| Cloud Hosted/ECE | orchestration, plan change, platform snapshot | SLO, topology/zone, restore drill, application |
| ECK | rolling pod orchestration, resource lifecycle | manifest, PDB, storage, version plan, data correctness |
| Self-managed | không có lớp tự động mặc định | OS, JVM, discovery, certificate, node, upgrade, backup |

Trước runbook phải ghi:

- deployment type và version;
- owner của compute/storage/network;
- repository snapshot nào do platform quản lý;
- quyền API hiện có;
- cách rollback được platform hỗ trợ;
- nơi lưu cấu hình ngoài cluster.

---

## 3. Master, cluster state và voting configuration

Master được bầu quản lý metadata/control plane:

- index, mapping, template và policy metadata;
- node membership;
- shard allocation;
- cluster settings;
- publish cluster-state update.

Master không phải “router trung tâm” cho mọi search. Client không nên gửi bulk hay
search nặng vào dedicated master.

### 3.1 Quorum hiện đại

Elasticsearch tự quản lý voting configuration và chỉ commit quyết định khi có
đa số của cấu hình đó. Không còn cấu hình `discovery.zen.minimum_master_nodes`.

HA cần ít nhất ba master-eligible node, trong đó ít nhất hai node không phải
voting-only. Không dừng đồng thời một nửa hoặc hơn số node trong voting
configuration.

```http
GET /_cluster/state?filter_path=master_node,metadata.cluster_coordination.last_committed_config
```

Số master-eligible lẻ thường dễ hiểu, nhưng Elasticsearch có thể loại một node
khỏi voting configuration khi số node chẵn. Đừng tự suy quorum chỉ từ `_cat/nodes`;
đọc voting configuration thực tế.

### 3.2 `cluster.initial_master_nodes` chỉ dùng một lần

Setting này chỉ bootstrap **cluster hoàn toàn mới**:

```yaml
cluster.name: search-prod
node.name: master-a
cluster.initial_master_nodes:
  - master-a
  - master-b
  - master-c
```

Sau khi cluster hình thành:

- bỏ setting khỏi cấu hình;
- không dùng khi thêm node;
- không dùng khi restart;
- không dùng trong rolling upgrade;
- không dùng để “cứu” cluster mất quorum.

Dùng lại sai có thể bootstrap một cluster khác với lịch sử cluster state khác.

---

## 4. Health status nói gì và không nói gì?

```http
GET /_cluster/health?filter_path=cluster_name,status,*_shards,number_of_nodes,number_of_data_nodes
```

| Status | Ý nghĩa shard | Tác động |
|---|---|---|
| Green | primary và replica theo cấu hình đều assigned | không chứng minh app/SLO/backup đúng |
| Yellow | primary assigned, ít nhất một replica unassigned | dữ liệu thường đọc/ghi được nhưng giảm redundancy |
| Red | ít nhất một primary unassigned | một phần index/search/write có thể thất bại |

Cluster status là mức nghiêm trọng cao nhất toàn cluster. Khi red, đừng kết luận
toàn bộ dữ liệu mất; xác định index và primary nào bị ảnh hưởng:

```http
GET /_cat/indices?v=true&health=red&h=health,status,index,pri,rep,docs.count,store.size
```

```http
GET /_cat/shards?v=true&h=index,shard,prirep,state,node,unassigned.reason&s=state,index
```

Yellow một node thường do replica không được đặt cùng node với primary. Hạ replica
về 0 chỉ biến status thành green bằng cách giảm fault tolerance.

---

## 5. Bộ bằng chứng tối thiểu trước khi thay đổi

```http
GET /_cluster/health
```

```http
GET /_cat/nodes?v=true&h=name,ip,role,master,version,heap.percent,cpu,disk.used_percent
```

```http
GET /_cat/shards?v=true&h=index,shard,prirep,state,docs,store,node,unassigned.reason
```

```http
GET /_cat/allocation?v=true
```

```http
GET /_cluster/settings?flat_settings=true&include_defaults=true
```

```http
GET /_cluster/pending_tasks
```

```http
GET /_tasks?detailed=true
```

Luôn lưu:

- UTC timestamp và incident/change ID;
- response gốc, không chỉ screenshot;
- topology theo zone/tier;
- recent deploy, node restart, policy/setting change;
- disk/heap/CPU/network và client error;
- snapshot gần nhất đã hoàn tất.

Các counter thường tích lũy từ lúc node start; so sánh delta theo cửa sổ.

---

## 6. Allocation là tập hợp các decider

Master không đặt shard chỉ theo dung lượng. Nhiều decider cùng đánh giá:

- node role/data tier;
- primary và replica không cùng node;
- include/exclude/require filter;
- awareness/forced awareness;
- disk watermark;
- version compatibility;
- delayed allocation;
- recovery concurrency;
- shard-per-node constraint.

Không sửa setting dựa trên phỏng đoán. Hỏi allocation explain:

```http
GET /_cluster/allocation/explain?include_yes_decisions=true&include_disk_info=true

{
  "index": "orders-000042",
  "shard": 3,
  "primary": false
}
```

Đọc:

- `current_state`;
- `unassigned_info.reason`;
- `can_allocate`;
- quyết định của từng node;
- decider trả `NO` và lý do cụ thể.

Không truyền body sẽ giải thích một shard unassigned bất kỳ, hữu ích cho triage
nhưng không đảm bảo đó là shard quan trọng nhất.

---

## 7. Các nguyên nhân unassigned phổ biến

| Decider/lý do | Câu hỏi |
|---|---|
| `same_shard` | Có đủ node trong tier để giữ primary + replica? |
| `disk_threshold` | Node nào dưới low watermark? Shard có chỗ để move không? |
| `filter` | Index/cluster allocation filter còn sót? |
| `awareness` | Zone/rack label đủ và đúng giá trị? |
| `data_tier` | Tier policy trỏ tới role đang tồn tại? |
| `shards_limit` | Index/node shard limit bị chạm? |
| `max_retry` | Allocation đã fail nhiều lần; nguyên nhân gốc đã sửa chưa? |
| `node_left` | Node đang restart, mất thật hay bị network/GC pause? |
| `no_valid_shard_copy` | Còn in-sync copy, snapshot hay nguồn rebuild không? |

Sau khi sửa nguyên nhân của `max_retry`, yêu cầu thử lại:

```http
POST /_cluster/reroute?retry_failed=true
```

Không dùng reroute thủ công nếu automatic allocator có thể xử lý sau khi sửa
constraint.

---

## 8. Awareness và forced awareness

Gắn node theo failure domain:

```yaml
node.attr.zone: apse1-a
cluster.routing.allocation.awareness.attributes: zone
```

Awareness cố phân tán shard copy giữa các zone. Forced awareness định nghĩa toàn
bộ giá trị mong đợi:

```yaml
cluster.routing.allocation.awareness.force.zone.values:
  - apse1-a
  - apse1-b
  - apse1-c
```

Khi mất một zone, forced awareness có thể để replica unassigned thay vì dồn cả
primary và replica vào các zone còn lại. Trade-off:

- bảo vệ capacity và tránh đặt hai copy cùng tập failure domain còn lại;
- cluster có thể yellow cho tới khi zone phục hồi;
- mỗi zone còn lại phải đủ capacity để phục vụ traffic thiết kế;
- số replica phải phù hợp số zone.

Kiểm thử mất zone, không chỉ kiểm tra config tồn tại.

---

## 9. Disk watermark và flood-stage

Disk allocator dùng ba mốc:

```text
low         → không nhận thêm phần lớn shard allocation
high        → cố move shard ra khỏi node
flood-stage → block write index có shard trên node đó
```

Mặc định phổ biến là 85%/90%/95%, nhưng dung lượng disk lớn cần hiểu
`max_headroom`. Với watermark theo phần trăm, headroom giới hạn lượng free space
bắt buộc trên disk rất lớn.

```http
GET /_cluster/settings?flat_settings=true&include_defaults=true&filter_path=*.cluster.routing.allocation.disk.watermark*
```

Lưu ý:

- percentage/ratio diễn tả **disk đã dùng**;
- byte value diễn tả **free space còn lại**;
- không trộn percentage và byte giữa low/high/flood-stage;
- nếu tự override percentage, default max-headroom tương ứng có thể không còn áp
  dụng; kiểm tra effective setting;
- allocator hoạt động độc lập trong từng data tier.

Không cố làm disk usage mọi node bằng nhau. Desired-balance allocator cân cả shard
count, index spread, disk estimate và write load.

---

## 10. Runbook disk watermark

### 10.1 Xác định node/index bị ảnh hưởng

```http
GET /_cat/allocation?v=true&s=disk.percent:desc
```

```http
GET /_cat/indices?v=true&s=store.size:desc&h=health,status,index,pri,rep,docs.count,store.size
```

```http
GET /*/_settings?flat_settings=true&filter_path=*.settings.index.blocks.read_only_allow_delete
```

### 10.2 Giảm áp lực an toàn

Theo bằng chứng:

1. dừng hoặc rate-limit ingest không thiết yếu;
2. xóa **index đã hết retention** sau xác minh, thay vì delete-by-query;
3. tăng disk/node trong đúng tier;
4. sửa lifecycle/rollover;
5. giải phóng snapshot/recovery/merge contention;
6. tạm tăng watermark chỉ khi có headroom và kế hoạch hoàn nguyên.

Đừng xóa file trong `path.data`. Đừng force merge khi disk đang cạn vì merge cần
dung lượng tạm.

Khi disk xuống dưới high watermark, Elasticsearch hiện đại tự gỡ
`read_only_allow_delete`. Nếu block còn lại, xác nhận disk và nguyên nhân trước
khi reset:

```http
PUT /orders-*/_settings

{
  "index.blocks.read_only_allow_delete": null
}
```

---

## 11. Recovery không chỉ là copy byte

| Loại | Ví dụ | Nguồn |
|---|---|---|
| Local primary recovery | node restart | local store + translog |
| Peer recovery | tạo/move replica | primary shard copy |
| Snapshot recovery | restore/searchable snapshot | repository |
| CCR recovery | bootstrap follower | leader/remote |

Quan sát:

```http
GET /_cat/recovery?v=true&active_only=true&h=index,shard,time,type,stage,source_node,target_node,files_percent,bytes_percent,translog_ops_percent
```

```http
GET /_recovery?active_only=true&detailed=true
```

Recovery cạnh tranh disk, network, CPU và page cache với traffic. Recovery xong
về byte chưa có nghĩa cache đã ấm hoặc p99 đã về baseline.

### 11.1 Đừng tune throttle theo cảm giác

`indices.recovery.max_bytes_per_sec`, concurrent recovery và rebalance setting
đều có trade-off:

- tăng có thể rút ngắn recovery nhưng làm search/indexing chậm;
- giảm bảo vệ workload nhưng kéo dài thời gian thiếu redundancy;
- storage/network thực tế có thể là giới hạn;
- cloud/orchestrator có thể quản lý setting.

Chọn theo recovery RTO và benchmark failure drill. Reset override khi xong.

---

## 12. Thêm và loại data node

Thêm node không bảo đảm cân bằng ngay; allocator cần tính desired balance và move
shard trong constraint.

Khi loại data node self-managed, exclude trước:

```http
PUT /_cluster/settings

{
  "persistent": {
    "cluster.routing.allocation.exclude._name": "data-hot-07"
  }
}
```

Theo dõi đến khi không còn shard:

```http
GET /_cat/shards?v=true&h=index,shard,prirep,state,node&s=node
```

Sau khi node đã rời và cluster ổn định, xóa exclusion:

```http
PUT /_cluster/settings

{
  "persistent": {
    "cluster.routing.allocation.exclude._name": null
  }
}
```

Với ECK/ECE/Cloud, dùng workflow resize/decommission của orchestrator để nó phối
hợp allocation và lifecycle.

### 12.1 Loại master-eligible node

Đảm bảo vẫn còn đa số voting configuration. Khi loại đồng thời nhiều
master-eligible node, dùng voting exclusions theo tài liệu và chờ cấu hình commit
trước khi tắt:

```http
POST /_cluster/voting_config_exclusions?node_names=master-c
```

Sau khi node đã rời và voting configuration cập nhật:

```http
DELETE /_cluster/voting_config_exclusions
```

Không loại nửa hoặc hơn voting configuration trong một bước.

---

## 13. ILM và data tier

Với data stream/time-series:

```text
hot → warm → cold → frozen → delete
```

Data tier dùng `_tier_preference`; ILM `migrate` action chuyển index theo phase.
Tránh custom attribute `data=warm` kiểu cũ nếu built-in tier role giải quyết được.

Policy mẫu:

```http
PUT /_ilm/policy/logs-retention

{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "40gb",
            "max_age": "1d"
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 5
          }
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

Các số trên chỉ là ví dụ. `min_age` sau rollover được tính theo rollover time;
policy phải khớp retention pháp lý và capacity.

### 13.1 Data stream template

```http
PUT /_index_template/logs-template

{
  "index_patterns": [
    "logs-app-*"
  ],
  "data_stream": {},
  "priority": 500,
  "template": {
    "settings": {
      "index.lifecycle.name": "logs-retention",
      "index.number_of_replicas": 1
    },
    "mappings": {
      "properties": {
        "@timestamp": {
          "type": "date"
        },
        "service.name": {
          "type": "keyword"
        }
      }
    }
  }
}
```

Data stream tránh bootstrap rollover alias thủ công và bảo vệ write index khỏi
thao tác sai phổ biến.

---

## 14. Debug ILM bị kẹt

```http
GET /logs-app-prod/_ilm/explain?only_errors=true
```

```http
GET /_ilm/status
```

Kiểm tra:

- index có policy đúng không;
- rollover condition đã đạt chưa;
- alias/data stream write index đúng chưa;
- warm/cold tier có node không;
- shard có green nếu action yêu cầu không;
- shrink prerequisite, disk và allocation;
- snapshot repository/license cho searchable snapshot;
- error step và retry count.

Sau khi sửa nguyên nhân:

```http
POST /logs-app-prod/_ilm/retry
```

Không dùng move-to-step để bỏ qua lỗi trừ khi đã hiểu state machine; nhảy step có
thể để index ở trạng thái không đáp ứng prerequisite.

---

## 15. Snapshot là backup ở mức segment

Snapshot:

- incremental giữa các snapshot trong cùng repository;
- deduplicate segment bất biến;
- lấy shard data từ primary khả dụng;
- có thể chạy khi cluster đang hoạt động;
- không phải một instant atomic toàn cluster: mỗi shard được copy trong khoảng
  start/end của snapshot;
- phụ thuộc version/index compatibility khi restore.

Không backup bằng cách copy `path.data` hoặc filesystem snapshot riêng lẻ khi node
đang chạy. Các file giữa node/segment/cluster state không tạo backup nhất quán.

Snapshot đang chạy giữ shard không bị relocate sau khi copy bắt đầu; allocation
và snapshot có tương tác nên cần tính cửa sổ maintenance.

---

## 16. Repository là dữ liệu bất khả xâm phạm

Đăng ký S3 repository minh họa:

```http
PUT /_snapshot/prod-dr

{
  "type": "s3",
  "settings": {
    "bucket": "company-search-backup",
    "base_path": "prod/search-v1"
  }
}
```

Credential phải nằm trong secure keystore/IAM role, không ghi secret trong request
hay source control.

Xác minh repository:

```http
POST /_snapshot/prod-dr/_verify
```

`_verify` chỉ kiểm tra node truy cập repository; nó không chứng minh snapshot đầy
đủ hoặc restore đạt RTO.

Quy tắc:

- chỉ một cluster được quyền ghi cùng repository;
- cluster khác đăng ký read-only;
- không sửa/xóa object trực tiếp ngoài Elasticsearch;
- xóa snapshot qua API để giữ metadata/dedup đúng;
- repository storage có versioning/immutability/access control phù hợp;
- backup cấu hình repository và node config ở nơi khác vì snapshot không chứa
  repository registration hoặc `elasticsearch.yml`.

---

## 17. SLM: RPO phải được kiểm chứng

```http
PUT /_slm/policy/prod-daily

{
  "schedule": "0 30 1 * * ?",
  "name": "<prod-{now/d}>",
  "repository": "prod-dr",
  "config": {
    "indices": [
      "*"
    ],
    "include_global_state": true,
    "partial": false
  },
  "retention": {
    "expire_after": "30d",
    "min_count": 7,
    "max_count": 60
  }
}
```

Theo dõi:

```http
GET /_slm/status
```

```http
GET /_slm/policy/prod-daily
```

```http
GET /_snapshot/prod-dr/_all?index_names=false&sort=start_time&order=desc&size=5
```

RPO thực tế tính từ snapshot **SUCCESS gần nhất có coverage cần thiết**, không từ
lịch cron. Alert:

- policy không chạy;
- snapshot `FAILED`/`PARTIAL`;
- duration tăng bất thường;
- repository access/throttle;
- snapshot thành công nhưng thiếu index/feature state;
- retention cleanup thất bại.

`partial: false` phù hợp backup DR nghiêm ngặt: primary unavailable làm snapshot
fail thay vì tạo backup thiếu mà không được chú ý.

---

## 18. Snapshot chứa gì?

Mặc định full snapshot có thể chứa:

- regular index và data stream;
- persistent cluster settings;
- index template;
- ingest pipeline;
- ILM policy;
- stored script;
- feature states.

Không chứa:

- transient cluster settings;
- repository registration;
- node configuration file;
- security configuration file trên filesystem;
- dữ liệu phát sinh sau thời điểm shard được snapshot.

Từ Elasticsearch 8+, system indices/system data streams được backup và restore qua
**feature state**.

```http
GET /_features
```

```http
GET /_snapshot/prod-dr/prod-2026.07.31?index_names=false
```

Nếu đặt `include_global_state: false`, feature state mặc định cũng không được
restore. Có thể chọn `feature_states` cụ thể, nhưng phải hiểu dependency giữa
Kibana, security, Fleet và các feature khác.

---

## 19. Restore drill

DR drill nên restore vào cluster cô lập, không ghi đè production.

### 19.1 Restore index dưới tên mới

```http
POST /_snapshot/prod-dr/prod-2026.07.31/_restore

{
  "indices": "orders-*",
  "include_global_state": false,
  "include_aliases": false,
  "rename_pattern": "(.+)",
  "rename_replacement": "dr-$1",
  "index_settings": {
    "index.number_of_replicas": 0
  }
}
```

Chỉ giảm replica trong cluster drill cô lập có mục tiêu rõ; production restore phải
trả replica về topology HA trước cutover.

Theo dõi:

```http
GET /_cluster/health?wait_for_status=yellow&timeout=30s
```

```http
GET /_cat/recovery?v=true&active_only=true
```

### 19.2 Kiểm tra sau restore

- index/data stream/alias đúng;
- document count và business reconciliation;
- sample query, aggregation và analyzer;
- mapping/template/pipeline;
- application read-only smoke test;
- RTO từ bắt đầu tới khi phục vụ được;
- replica/zone placement;
- quyền và feature state nếu khôi phục hệ thống.

`security` feature state có thể ghi đè authentication data và làm operator mất
quyền. Chuẩn bị file-realm break-glass hoặc console access trước khi restore.

---

## 20. Restore compatibility và migration

Không giả định snapshot là đường downgrade:

- snapshot chỉ restore vào version tương thích;
- index tạo bởi version cũ có compatibility matrix riêng;
- feature state phụ thuộc version;
- downgrade in-place không được hỗ trợ;
- đôi khi phải restore sang intermediate version rồi reindex.

Trước upgrade:

1. đọc version/index compatibility;
2. chạy Upgrade Assistant/deprecation checks;
3. restore snapshot thật vào target-version staging;
4. test application/client/plugin;
5. đo performance và disk;
6. xác định rollback là dựng cluster cũ + restore/replay, không phải hạ binary.

---

## 21. Rolling upgrade: sự thật quan trọng

Đối với self-managed:

- mixed version chỉ hợp lệ trong lúc upgrade;
- upgraded node có thể join cluster do master version cũ điều phối, nhưng node cũ
  không phải lúc nào cũng join được master version mới;
- vì vậy master-eligible node nâng **cuối cùng**;
- sau khi node target version tham gia, không có rollback in-place đáng tin cậy;
- chỉ bắt đầu khi có thể hoàn tất toàn cluster.

Cloud/ECE/ECK nên dùng plan/operator workflow của nền tảng.

### 21.1 Thứ tự chính thức

```text
1. data_frozen
2. data_cold
3. data_warm
4. data_hot
5. data_content / data khác
6. ingest, ml, transform, coordinator, remote-cluster-client
7. master và voting-only master-eligible
8. Kibana và ingest client/component theo compatibility plan
```

Node có nhiều role thuộc nhóm xuất hiện sớm nhất.

---

## 22. Upgrade preflight

- [ ] Upgrade path được version matrix hỗ trợ?
- [ ] Không dùng release candidate cho production?
- [ ] Deprecation log/Upgrade Assistant đã xử lý?
- [ ] Plugin trên mọi node có target-version build?
- [ ] Client, Kibana, Agent/Beats/Logstash compatibility rõ?
- [ ] Snapshot SUCCESS gần nhất và restore drill đạt RTO?
- [ ] Cluster green, không unassigned shard/pending task bất thường?
- [ ] Disk/heap/CPU có headroom cho relocation/merge?
- [ ] Có canary/staging với dataset và workload thật?
- [ ] `cluster.initial_master_nodes` không còn trong config?
- [ ] Config/data/log path không bị package upgrade ghi đè?
- [ ] On-call, change window, stop condition và communication sẵn sàng?

Ghi baseline:

```http
GET /
```

```http
GET /_cat/nodes?v=true&h=name,role,master,version
```

```http
GET /_cluster/health
```

```http
GET /_migration/deprecations
```

---

## 23. Quy trình mỗi data node khi rolling upgrade

### 23.1 Tạm chỉ cho allocation primary

Trước khi dừng data node:

```http
PUT /_cluster/settings

{
  "persistent": {
    "cluster.routing.allocation.enable": "primaries"
  }
}
```

Setting này ngăn replica relocation không cần thiết khi node sớm quay lại, nhưng
vẫn cho local primary recovery. Không đặt `none` theo thói quen.

### 23.2 Giảm write và flush nếu phù hợp

```http
POST /_flush
```

Flush là optional; dừng indexing không bắt buộc nhưng làm recovery nhanh hơn.
Không dùng synced-flush API cũ.

### 23.3 Dừng, nâng và khởi động một node

- dừng service đúng cách;
- nâng binary/package và plugin;
- merge config có review;
- giữ nguyên `path.data`, cluster name và certificate identity;
- start node;
- kiểm tra log và node join đúng cluster/version.

```http
GET /_cat/nodes?v=true&h=name,role,master,version
```

### 23.4 Bật lại allocation bằng cách xóa override

```http
PUT /_cluster/settings

{
  "persistent": {
    "cluster.routing.allocation.enable": null
  }
}
```

```http
GET /_cluster/health?wait_for_status=green&timeout=30m
```

```http
GET /_cat/recovery?v=true&active_only=true
```

Đợi green và workload ổn định trước node tiếp theo. Nếu timeout, dừng quy trình và
điều tra; không tiếp tục chỉ vì node đã xuất hiện trong `_cat/nodes`.

Với non-data/master group, chỉ áp dụng bước allocation khi role và platform yêu
cầu; vẫn nâng từng node và giữ quorum/capacity.

---

## 24. Stop condition trong upgrade

Dừng đưa thêm node ra khỏi service khi:

- node mới không join;
- cluster red hoặc allocation không tiến triển;
- master election/cluster-state publish bất ổn;
- error/429/p99 vượt guardrail;
- disk/heap/recovery vượt capacity;
- plugin/config/certificate lỗi;
- data/mapping/query regression;
- không còn đủ voting majority hoặc zone capacity.

“Dừng” nghĩa là giữ các node còn lại, phục hồi service/capacity và thu thập bằng
chứng. Không downgrade node đã nâng để thử vận may. Nếu không thể hoàn tất, recovery
plan là cluster tương thích khác + snapshot/replay đã chuẩn bị.

---

## 25. Persistent và transient cluster settings

Ưu tiên:

1. orchestrator/config management;
2. `elasticsearch.yml` cho static self-managed setting;
3. persistent cluster setting cho dynamic override có kiểm soát;
4. request/index setting đúng scope.

Transient setting có thể biến mất khi cluster bất ổn và không còn được khuyến
nghị cho vận hành lâu dài.

```http
GET /_cluster/settings?flat_settings=true&include_defaults=true
```

Reset về default bằng `null`, không copy default hiện tại thành hard-coded value:

```http
PUT /_cluster/settings

{
  "persistent": {
    "cluster.routing.allocation.enable": null,
    "indices.recovery.max_bytes_per_sec": null
  }
}
```

Mỗi override cần owner, lý do, expiry và rollback. Tránh tune các heuristic
`cluster.routing.allocation.balance.*`; Elastic khuyến nghị giữ default cho cluster
hợp lý.

---

## 26. Pending cluster task và cluster-state pressure

```http
GET /_cluster/pending_tasks
```

```http
GET /_cat/pending_tasks?v=true
```

Pending task lâu có thể do:

- master CPU/heap/disk/network;
- cluster-state publication chậm;
- mapping/index/shard explosion;
- node chậm hoặc network partition;
- allocation/rebalance churn;
- hàng loạt template/index/alias update.

Không chỉ scale master. Giảm nguồn tạo metadata, gom mapping update, sửa
oversharding và kiểm tra follower/applier node. Dedicated master cần ổn định nhưng
không phải nơi chứa query traffic.

---

## 27. Runbook cluster yellow

1. Xác định replica unassigned:

```http
GET /_cat/shards?v=true&h=index,shard,prirep,state,node,unassigned.reason&s=state
```

2. Gọi allocation explain cho shard cụ thể.
3. Kiểm tra:
   - node/tier/zone có đủ không;
   - disk watermark;
   - allocation bị disable;
   - filter/awareness;
   - replica count;
   - node đang restart và delayed allocation.
4. Sửa nguyên nhân nhỏ nhất.
5. Theo dõi recovery tới green.
6. Xác nhận fault tolerance thực tế bằng failure-domain test.

Không hạ replica chỉ để dashboard xanh trừ single-node dev hoặc business đã chấp
nhận giảm durability bằng thay đổi có phê duyệt.

---

## 28. Runbook cluster red

### 28.1 Triage

```http
GET /_cluster/health?level=indices
```

```http
GET /_cat/shards?v=true&h=index,shard,prirep,state,node,unassigned.reason&s=state,index
```

```http
GET /_cluster/allocation/explain?include_yes_decisions=true&include_disk_info=true

{
  "index": "orders-000042",
  "shard": 3,
  "primary": true
}
```

### 28.2 Quyết định theo copy

```text
Có node chỉ tạm restart?
  └─ Có → sửa node/network/GC; chờ local recovery

Có in-sync replica/copy hợp lệ?
  └─ Có → sửa allocation constraint để promote/recover tự động

Có snapshot đã drill?
  └─ Có → restore index dưới tên mới, validate, rồi cutover

Có source-of-truth/replay?
  └─ Có → rebuild versioned index và reconcile

Không còn valid copy/snapshot/source?
  └─ incident mất dữ liệu; chỉ lúc này cân nhắc stale/empty primary
```

Đóng băng destructive automation, giữ log/disk/node có thể chứa copy và ghi rõ
phạm vi dữ liệu unavailable.

---

## 29. `allocate_stale_primary` và `allocate_empty_primary`

Đây là **data-loss operation**, không phải lệnh chữa red thông thường.

Stale primary:

```http
POST /_cluster/reroute

{
  "commands": [
    {
      "allocate_stale_primary": {
        "index": "orders-000042",
        "shard": 3,
        "node": "data-hot-02",
        "accept_data_loss": true
      }
    }
  ]
}
```

Empty primary bỏ toàn bộ dữ liệu shard:

```http
POST /_cluster/reroute

{
  "commands": [
    {
      "allocate_empty_primary": {
        "index": "orders-000042",
        "shard": 3,
        "node": "data-hot-02",
        "accept_data_loss": true
      }
    }
  ]
}
```

Sau thao tác, copy tốt hơn xuất hiện muộn có thể bị ghi đè bởi primary mới. Trước
khi chạy cần:

- incident commander và business/data owner phê duyệt;
- inventory mọi shard copy/node/snapshot;
- ước lượng chính xác dữ liệu mất;
- bảo toàn disk/log để forensic;
- kế hoạch reconcile/replay;
- thử `dry_run`/`explain` cho reroute phù hợp;
- ghi request/response và thời điểm.

---

## 30. Network partition và master instability

Dấu hiệu:

- master thay đổi liên tục;
- `master not discovered`;
- node join/leave lặp lại;
- cluster-state publication timeout;
- transport TLS/handshake error;
- search vẫn chạy cục bộ nhưng metadata/write thất bại.

Kiểm tra:

- voting configuration và số node khả dụng;
- transport network 9300, DNS và certificate;
- GC pause/CPU starvation trên master;
- clock/log timeline;
- zone/network policy/firewall;
- master heap và cluster-state size.

Không bootstrap lại bằng `cluster.initial_master_nodes`. Không tạo “master riêng”
ở mỗi phía partition. Elasticsearch quorum ngăn split-brain inconsistency; phía
không có majority phải ngừng control-plane progress.

---

## 31. CCR trong DR

CCR sao chép operation từ leader sang follower:

```text
leader cluster ──► follower cluster
         async replication lag
```

Phù hợp:

- RPO thấp hơn snapshot interval;
- read locality;
- tách search/reporting;
- regional DR.

Không bảo vệ độc lập khỏi:

- xóa/cập nhật sai được replicate;
- schema/application bug;
- credential/control-plane lỗi chung;
- failover chưa diễn tập;
- dependency ngoài Elasticsearch.

Theo dõi follower:

```http
GET /_ccr/stats
```

```http
GET /orders-follower/_ccr/info
```

DR plan cần quyết định DNS/client routing, write fencing, dữ liệu chưa replicate,
promotion/unfollow, failback và reconciliation. Luôn giữ snapshot độc lập với CCR.

---

## 32. Maintenance và capacity headroom

Cluster “đủ cho bình thường” chưa chắc đủ khi:

- mất một node/zone;
- recovery và traffic chạy cùng lúc;
- rolling upgrade giảm capacity từng node;
- snapshot/merge/reindex cạnh tranh disk;
- cache lạnh sau restart;
- hot tier nhận burst.

Capacity test phải chạy N-1 hoặc mất zone theo thiết kế. Guardrail gồm:

- search/index p99 và 429;
- recovery ETA;
- disk free/headroom;
- JVM pressure/GC;
- thread-pool queue;
- unassigned shard;
- snapshot duration;
- master pending task.

Maintenance window phải xét traffic theo timezone và lifecycle job, không chỉ giờ
thấp điểm của một team.

---

## 33. Nhịp vận hành

### Hàng ngày

- cluster health và unassigned shard;
- disk watermark/headroom;
- node/zone/tier skew;
- snapshot/SLM success và RPO;
- 429, breaker, GC và pending task;
- certificate/license/retention deadline sắp tới.

### Hàng tuần

- shard size/count và rollover;
- ILM error;
- recovery/snapshot duration trend;
- persistent cluster override còn cần không;
- hot node/tenant;
- deprecation log.

### Hàng tháng/quý

- restore drill và đo RTO;
- node/zone failure game day;
- capacity forecast;
- upgrade rehearsal;
- break-glass credential test;
- audit repository access/immutability;
- review runbook bằng incident gần nhất.

---

## 34. Anti-pattern

### 34.1 Dashboard red → restart cả cluster

Làm mất evidence, tạo recovery storm và có thể mất quorum. Xác định shard/node/
decider trước.

### 34.2 Tăng watermark khi disk đầy

Chỉ trì hoãn flood-stage và giảm safety margin. Giải phóng/tăng capacity và sửa
retention.

### 34.3 Sửa file trong snapshot repository

Có thể làm repository corrupt hoặc mất dữ liệu im lặng. Chỉ thao tác qua API.

### 34.4 Snapshot SUCCESS = backup đã kiểm thử

Sai. Cần restore drill, business validation và đo RTO.

### 34.5 Ba master nên đặt `minimum_master_nodes=2`

Setting Zen Discovery cũ không còn tồn tại. Voting configuration được tự quản lý.

### 34.6 Nâng master trước

Sai thứ tự rolling upgrade: data tier trước, master/voting-only cuối.

### 34.7 `allocate_stale_primary` để cluster xanh nhanh

Có thể ghi đè copy tốt hơn và mất acknowledged data. Chỉ là last resort có phê
duyệt data loss.

### 34.8 Giữ allocation disabled sau maintenance

Replica/new shard không được allocate. Reset override về `null` và kiểm tra green.

### 34.9 Replica hoặc CCR thay snapshot

Xóa nhầm/corruption có thể lan sang copy. Cần backup point-in-time độc lập.

### 34.10 Tune balance heuristic để disk bằng nhau

Disk bằng nhau không phải mục tiêu allocator. Defaults cân nhiều yếu tố; sửa
heuristic có thể gây relocation churn.

---

## 35. Checklist production

### Control plane

- [ ] Có ít nhất ba master-eligible node cho HA, hai node không voting-only?
- [ ] Master phân bố failure domain và không nhận application traffic?
- [ ] `cluster.initial_master_nodes` đã bỏ sau bootstrap?
- [ ] Biết voting configuration thực tế và quy trình loại master?
- [ ] Cluster-state/mapping/shard count nằm trong capacity?

### Allocation và recovery

- [ ] Awareness/forced awareness đã test mất zone?
- [ ] Có capacity N-1/mất zone trong từng tier?
- [ ] Allocation explain nằm trong runbook?
- [ ] Watermark/headroom dựa trên disk thật?
- [ ] Recovery RTO đã benchmark cùng production traffic?
- [ ] Mọi allocation/recovery override có expiry và rollback?

### Snapshot/DR

- [ ] SLM SUCCESS gần nhất đáp ứng RPO?
- [ ] Snapshot có cluster state và feature state cần thiết?
- [ ] Repository chỉ có một writer, immutable và không bị sửa ngoài ES?
- [ ] Node config, keystore/certificate và repository config backup riêng?
- [ ] Restore drill cô lập đạt RTO và business validation?
- [ ] CCR có fencing/failover/failback/reconciliation và snapshot độc lập?

### Upgrade

- [ ] Compatibility, deprecation, plugin/client đã kiểm tra?
- [ ] Target-version staging restore và load test đạt?
- [ ] Biết không thể downgrade in-place?
- [ ] Thứ tự frozen → cold → warm → hot → other → master-last?
- [ ] Nâng từng node, đợi green và SLO ổn định?
- [ ] Có stop condition, on-call và recovery cluster plan?

---

## 36. Câu hỏi phỏng vấn

1. Green/yellow/red nói gì và không nói gì?
2. Vì sao replica không phải backup?
3. Allocation explain giúp phân biệt các nguyên nhân unassigned thế nào?
4. Awareness và forced awareness khác nhau ra sao khi mất zone?
5. Low/high/flood-stage watermark làm gì?
6. Snapshot incremental nhưng tại sao vẫn cần retention qua API?
7. Feature state là gì và vì sao quan trọng khi DR?
8. `_verify` repository khác restore drill thế nào?
9. Tại sao rolling upgrade phải nâng master cuối?
10. Vì sao không thể xem downgrade binary là rollback?
11. Khi nào được dùng `allocate_stale_primary`?
12. Voting configuration hiện đại ngăn split brain thế nào?
13. CCR và snapshot giải quyết hai RPO/failure mode khác nhau ra sao?
14. Vì sao cluster cần capacity headroom khi trạng thái bình thường?

---

## 37. Nguồn và chủ đề tiếp theo

Nguồn chính thức:

- [Cluster health: red hoặc yellow](https://www.elastic.co/docs/troubleshoot/elasticsearch/red-yellow-cluster-status)
- [Shard allocation settings](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/cluster-level-shard-allocation-routing-settings)
- [Voting configurations](https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-voting)
- [Bootstrapping a cluster](https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-bootstrap-cluster)
- [Add and remove nodes](https://www.elastic.co/docs/deploy-manage/maintenance/add-and-remove-elasticsearch-nodes)
- [Index lifecycle management](https://www.elastic.co/docs/manage-data/lifecycle/index-lifecycle-management)
- [Snapshot and restore](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore)
- [Create and monitor snapshots](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore/create-snapshots)
- [Restore a snapshot](https://www.elastic.co/docs/deploy-manage/tools/snapshot-and-restore/restore-snapshot)
- [Upgrade Elasticsearch](https://www.elastic.co/docs/deploy-manage/upgrade/deployment-or-cluster/elasticsearch)
- [Plan an upgrade](https://www.elastic.co/docs/deploy-manage/upgrade/plan-upgrade)

Học tiếp:

1. [Security](security.md) – TLS, realm, role/privilege, API key, audit và
   multi-tenant authorization.
2. [Architecture](../fundamentals/architecture.md) – cluster state, read/write
   path và failure semantics.
3. [Performance](../performance/optimization.md) – capacity, backpressure và
   bottleneck runbook.
4. [Indexing & Mapping](../fundamentals/indexing_mapping.md) – template, data
   stream và reindex migration.

---

*Cập nhật lần cuối: 2026-07-31.*
