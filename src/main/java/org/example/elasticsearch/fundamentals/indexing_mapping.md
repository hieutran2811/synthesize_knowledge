# Elasticsearch Indexing, Mapping & Analyzers – thiết kế search contract

> Mapping không chỉ nói “field này là string hay number”. Nó quyết định dữ liệu
> được biến thành term nào, có thể filter/sort/aggregate ra sao, tốn bao nhiêu disk
> và một thay đổi có buộc reindex hay không. Mapping sai thường không lộ ngay lúc
> ingest; nó lộ khi query không match, aggregation thiếu dữ liệu hoặc cluster phình
> vì hàng chục nghìn field động.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Một số field type, vector
index option, synthetic `_source` và failure store phụ thuộc phiên bản, license hoặc
deployment; kiểm tra tài liệu của môi trường đang chạy trước khi áp dụng.

---

## 1. Mapping là search contract, không phải validator đầy đủ

Mapping định nghĩa cách một JSON field được xử lý:

- field type và cấu trúc object;
- có tạo inverted index hay không;
- có tạo `doc_values` để sort/aggregate hay không;
- analyzer/normalizer nào chạy lúc index;
- giá trị nào bị ignore hoặc coerce;
- runtime field nào được tính lúc query.

```text
JSON input
   │
   ├── mapping + analysis ──► inverted index / BKD / vector index
   ├── doc_values           ──► sort / aggregation / script
   └── _source              ──► lấy lại JSON, update, reindex
```

Mapping có kiểm tra type ở mức cần để index, nhưng không thay thế JSON Schema,
Bean Validation hoặc business validation:

- một số type có thể coerce giá trị;
- field không biết có thể bị bỏ qua nếu `dynamic: false`;
- `null` thường được coi là missing;
- mapping không kiểm tra các invariant như `end_at > start_at`;
- `ignore_malformed` có thể nhận document nhưng bỏ field lỗi khỏi index.

Luồng an toàn:

```text
API validation
   → domain validation
   → canonical event/document
   → ingest pipeline
   → Elasticsearch mapping
```

---

## 2. Một field có thể tồn tại trong nhiều cấu trúc

### 2.1 `_source`

`_source` chứa JSON document gốc đã gửi vào. Nó được lưu nhưng bản thân không được
index để search:

```json
{
  "name": "Điện thoại Pixel",
  "price_minor": 18990000
}
```

`_source` hỗ trợ:

- trả document trong GET/search;
- partial update;
- reindex sang mapping mới;
- debug dữ liệu ingest.

Tắt hoặc prune `_source` làm mất nhiều khả năng phục hồi. Nếu storage là vấn đề,
ưu tiên source filtering khi đọc, compression hoặc đánh giá synthetic `_source`
trước khi nghĩ đến tắt hoàn toàn.

### 2.2 Inverted index và các cấu trúc tìm kiếm

Với `text`/`keyword`, Elasticsearch tạo cấu trúc term → document:

```text
"điện"   → [doc 1, doc 9]
"thoại"  → [doc 1, doc 4, doc 9]
"pixel"  → [doc 1]
```

Numeric/date/geo/vector dùng cấu trúc phù hợp cho range, distance hoặc nearest
neighbor; không nên hình dung mọi field đều chỉ là chuỗi trong inverted index.

### 2.3 `doc_values`

`doc_values` là cấu trúc column-oriented trên đĩa, tối ưu hướng document → value:

```text
doc 1 → category=phone, price=18990000
doc 2 → category=laptop, price=25990000
```

Nó được dùng cho sort, aggregation và script, mặc định có trên phần lớn field type
trừ `text`/`annotated_text`.

### 2.4 Stored field

`store: true` lưu riêng một field để fetch mà không đọc toàn `_source`. Đây là lựa
chọn chuyên biệt, không phải mặc định cần bật cho mọi field.

---

## 3. Chọn field type từ hành vi query

| Dữ liệu | Field type thường dùng | Câu hỏi quyết định |
|---|---|---|
| Tên/mô tả cần full-text | `text` | Cần tokenization, phrase, relevance? |
| ID, mã, trạng thái, tag | `keyword` | Cần exact filter/sort/aggregation? |
| Số đo/range | `integer`, `long`, `double`, `scaled_float` | Có range/math không? |
| Tiền | thường `long` theo minor unit | Có cần tính chính xác và nhiều currency? |
| Thời gian | `date`, `date_nanos` | Precision và format nào? |
| IP | `ip` | Có CIDR/range query không? |
| Vị trí | `geo_point`, `geo_shape` | Point hay polygon/path? |
| Object cố định | `object` | Có cần giữ quan hệ từng phần tử mảng? |
| Mảng object độc lập | `nested` | Có query cùng một phần tử không? |
| Metadata key động | `flattened` | Có chấp nhận mọi leaf như keyword? |
| Embedding | `dense_vector` | Exact hay approximate kNN, recall/latency nào? |
| ID trông như số | thường `keyword` | Có thật sự cần range query không? |

Chọn type theo cách truy vấn, không theo vẻ ngoài JSON. Mã bưu chính `"00123"` và
product ID `123456` thường là `keyword`, không phải number.

---

## 4. `text` và `keyword`

Giá trị:

```text
"Điện thoại Pixel 10 Pro"
```

Mapping `text` với analyzer phù hợp có thể sinh:

```text
[điện, thoại, pixel, 10, pro]
```

Mapping `keyword` giữ một term:

```text
["Điện thoại Pixel 10 Pro"]
```

| Nhu cầu | `text` | `keyword` |
|---|---:|---:|
| Full-text match | Tốt | Không phù hợp |
| Exact filter | Không phải mục tiêu | Tốt |
| Sort | Không mặc định | Tốt |
| Terms aggregation | Không mặc định | Tốt |
| Analyzer | Có | Không; dùng normalizer nếu cần |
| Phrase/relevance | Có | Không |

Không cần “mọi string đều có cả hai”. Multi-field làm tăng disk và indexing work.
Chỉ thêm biến thể khi query contract cần:

```http
PUT /products-v1
{
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "fields": {
          "sort": {
            "type": "keyword",
            "ignore_above": 256
          }
        }
      }
    }
  }
}
```

`name` dùng full-text; `name.sort` dùng sort/aggregation.

### 4.1 Chuỗi `keyword` quá dài

Lucene có giới hạn term 32766 byte. `keyword` quá dài có thể làm cả document bị
reject nếu không có guardrail. `ignore_above` tính theo ký tự, trong khi giới hạn
Lucene tính theo UTF-8 byte:

```json
"raw_path": {
  "type": "keyword",
  "ignore_above": 8191
}
```

Giá trị vượt giới hạn vẫn có trong `_source`, nhưng không xuất hiện trong exact
query, sort hoặc aggregation. Đây là dữ liệu “ingest thành công nhưng aggregate
thiếu” cần được quan sát bằng `_ignored` và validation upstream.

---

## 5. Number, ID và money

### 5.1 Chọn numeric type nhỏ nhất có ý nghĩa

Không cần ép mọi số nguyên thành `integer`. Cần xét:

- miền giá trị hiện tại và tương lai;
- range/aggregation;
- precision;
- producer có gửi dạng chuỗi hay floating point không.

### 5.2 ID dạng số

Nếu chỉ exact lookup:

```json
"customer_id": { "type": "keyword" }
```

Numeric type tối ưu range query; `keyword` thường phù hợp ID và giữ được leading
zero.

### 5.3 Money

Tránh dùng binary floating point cho giá trị cần đối soát:

```json
"price_minor": { "type": "long" },
"currency":    { "type": "keyword" }
```

```json
{
  "price_minor": 18990000,
  "currency": "VND"
}
```

`scaled_float` có thể phù hợp số đo có precision biết trước, nhưng với tiền, minor
unit integer thường dễ giải thích và reconcile hơn. Elasticsearch vẫn không thay
thế billing ledger hoặc decimal arithmetic ở domain layer.

---

## 6. Date, null, array và coercion

### 6.1 Date format phải là contract

```json
"created_at": {
  "type": "date",
  "format": "strict_date_optional_time||epoch_millis"
}
```

Không gửi epoch “không rõ giây hay millisecond”. Chuẩn hóa timezone, precision và
format ở producer.

### 6.2 `null` khác missing

Mặc định:

```json
{ "discount_code": null }
```

không tạo indexed value. Nếu cần một sentinel searchable, `null_value` có thể thay
explicit `null`, nhưng không thay field hoàn toàn vắng mặt và có nguy cơ trộn dữ
liệu thật với sentinel.

### 6.3 Array không có field type riêng

```json
"tags": ["android", "5g", "camera"]
```

Mapping vẫn là:

```json
"tags": { "type": "keyword" }
```

Các phần tử phải tương thích cùng field type. Thứ tự/multiplicity trong
`doc_values` không nhất thiết giống `_source`; không dựa vào aggregation hoặc
script để tái tạo nguyên xi array đầu vào.

### 6.4 Coercion không phải chiến lược dữ liệu

Elasticsearch có thể nhận một số chuỗi số tùy mapping setting. Production nên gửi
canonical JSON type và theo dõi document bị reject thay vì dựa vào coercion ngầm.

---

## 7. `object`, `nested` và `flattened`

### 7.1 `object`: field được flatten

Document:

```json
{
  "variants": [
    { "color": "red",  "size": "S" },
    { "color": "blue", "size": "L" }
  ]
}
```

Với `object`, Lucene nhìn gần như:

```text
variants.color = [red, blue]
variants.size  = [S, L]
```

Quan hệ theo từng phần tử bị mất. Điều kiện `color=red AND size=L` có thể match dù
không có variant đỏ size L.

### 7.2 `nested`: giữ độc lập từng object

```json
"variants": {
  "type": "nested",
  "properties": {
    "sku":   { "type": "keyword" },
    "color": { "type": "keyword" },
    "size":  { "type": "keyword" }
  }
}
```

Mỗi nested object được index thành hidden Lucene document. Query đúng hơn nhưng:

- document count thực tế tăng;
- query/update phức tạp và tốn hơn;
- update một nested item vẫn reindex root document cùng nested children;
- nested object có giới hạn để bảo vệ cluster.

Nếu có thể denormalize thành một document cho mỗi variant, mô hình đó thường đơn
giản hơn cho query và scaling.

### 7.3 `flattened`: key động nhưng query đơn giản

```json
"attributes": { "type": "flattened" }
```

Phù hợp:

```json
{
  "attributes": {
    "brand": "Google",
    "release": "2026",
    "camera.main": "50MP"
  }
}
```

Toàn object chỉ tạo một field mapping. Trade-off:

- leaf được xử lý như keyword;
- numeric range theo semantic số không được hỗ trợ như numeric field;
- không có full-text/highlight đầy đủ;
- phù hợp metadata tùy ý, không phù hợp mọi nội dung.

---

## 8. Explicit mapping cho product search

```http
PUT /products-v1
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "index.mapping.ignore_above": 8191,
    "analysis": {
      "normalizer": {
        "lowercase_keyword": {
          "type": "custom",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "product_id": {
        "type": "keyword"
      },
      "name": {
        "type": "text",
        "analyzer": "standard",
        "fields": {
          "sort": {
            "type": "keyword",
            "normalizer": "lowercase_keyword",
            "ignore_above": 256
          }
        }
      },
      "description": {
        "type": "text"
      },
      "category": {
        "type": "keyword",
        "normalizer": "lowercase_keyword"
      },
      "tags": {
        "type": "keyword",
        "normalizer": "lowercase_keyword"
      },
      "price_minor": {
        "type": "long"
      },
      "currency": {
        "type": "keyword"
      },
      "created_at": {
        "type": "date",
        "format": "strict_date_optional_time||epoch_millis"
      },
      "attributes": {
        "type": "flattened"
      },
      "variants": {
        "type": "nested",
        "properties": {
          "sku":      { "type": "keyword" },
          "color":    { "type": "keyword" },
          "size":     { "type": "keyword" },
          "in_stock": { "type": "boolean" }
        }
      }
    }
  }
}
```

Shard count trong ví dụ chỉ minh họa. Production phải benchmark như đã trình bày
trong [Architecture](architecture.md).

---

## 9. Dynamic mapping modes

| `dynamic` | Field lạ | `_source` | Search field lạ | Khi dùng |
|---|---|---:|---:|---|
| `true` | Tạo mapping tự động | Có | Có | Prototype hoặc input được kiểm soát |
| `false` | Không tạo mapping | Có | Không | Giữ payload phụ nhưng không index |
| `strict` | Reject document | Không ingest | Không | Contract chặt |
| `runtime` | Tạo runtime field động | Có | Tính lúc query | Schema linh hoạt, chấp nhận query cost |

`dynamic: strict` giúp phát hiện producer drift sớm, nhưng nếu không có DLQ/retry
policy sẽ biến một field mới thành mất dữ liệu ingest.

Có thể đặt dynamic khác nhau theo object:

```json
{
  "dynamic": "strict",
  "properties": {
    "metadata": {
      "type": "object",
      "dynamic": false
    }
  }
}
```

Top-level được kiểm soát chặt; `metadata` vẫn giữ trong `_source` nhưng field con
không được index.

---

## 10. Dynamic templates và mapping explosion

Dynamic template áp rule cho field mới:

```http
PUT /events-v1
{
  "mappings": {
    "dynamic_templates": [
      {
        "ids_as_keyword": {
          "match": "*_id",
          "match_mapping_type": "string",
          "mapping": {
            "type": "keyword",
            "ignore_above": 256
          }
        }
      },
      {
        "messages_as_text": {
          "match": "*_message",
          "match_mapping_type": "string",
          "mapping": {
            "type": "text"
          }
        }
      }
    ]
  }
}
```

Thứ tự template quan trọng: template đầu tiên match sẽ được dùng.

### 10.1 Mapping explosion

Payload nguy hiểm:

```json
{
  "labels": {
    "request_8f91": "slow",
    "request_4a22": "retry",
    "request_b771": "ok"
  }
}
```

Mỗi request ID thành một field mới. Hệ quả:

- cluster state và heap tăng;
- mapping update/publish chậm;
- simple query cũng tốn hơn;
- Kibana/data view khó tải;
- vượt `index.mapping.total_fields.limit` làm reject document.

Giải pháp:

- sửa producer để key động trở thành value;
- dùng `flattened` nếu chỉ cần exact/simple query;
- `dynamic: false` hoặc `strict`;
- giữ total field limit như guardrail, không tăng vô hạn;
- version template và kiểm tra field count.

`nested` không chữa mapping explosion nếu bên trong vẫn tạo field name động.

---

## 11. Analysis pipeline

Text analysis gồm:

```text
character filters → tokenizer → token filters
```

Ví dụ khái niệm:

```text
Input:          "<b>Pixel 10 Pro</b>"
html_strip:     "Pixel 10 Pro"
standard:       [Pixel, 10, Pro]
lowercase:      [pixel, 10, pro]
```

- Character filter thay đổi chuỗi trước tokenization.
- Tokenizer chia chuỗi thành token và vị trí.
- Token filter lowercase, stem, fold accent, thêm synonym/ngram...

Inverted index lưu output cuối, không lưu lại “ý định” của analyzer. Đổi index
analyzer không tự biến đổi term đã nằm trong segment cũ.

### 11.1 Kiểm thử bằng `_analyze`

```http
POST /_analyze
{
  "analyzer": "standard",
  "text": "Điện thoại Pixel 10 Pro"
}
```

Với field thực:

```http
POST /products-v1/_analyze
{
  "field": "name",
  "text": "Điện thoại Pixel 10 Pro"
}
```

Test token, position và offset trên corpus thật, gồm typo, dấu câu, emoji, mã sản
phẩm và chuỗi đa ngôn ngữ.

---

## 12. Built-in analyzer: hiểu đúng mặc định

| Analyzer | Hành vi chính |
|---|---|
| `standard` | Unicode word boundary, bỏ phần lớn punctuation, lowercase |
| `simple` | Tách khi gặp non-letter, lowercase |
| `whitespace` | Chỉ tách whitespace, không lowercase |
| `keyword` | Giữ toàn chuỗi thành một token |
| `stop` | Giống `simple` và hỗ trợ loại stop word |
| Language analyzer | Có stemming/stop word theo ngôn ngữ được hỗ trợ |
| `fingerprint` | Normalize, sort và deduplicate token cho matching/dedup |

`standard` **không tự bỏ stop word mặc định**; nó chỉ hỗ trợ cấu hình stop word.
Không chọn analyzer theo tên nghe hợp lý—hãy xem token thật.

---

## 13. Index analyzer và search analyzer

Text được analyze hai lần:

```text
Index time:  document text → terms lưu trong index
Search time: query text    → terms đem đi match
```

Thông thường dùng cùng analyzer để term tương thích. Khác analyzer chỉ khi có chủ
đích, ví dụ autocomplete:

```json
"name_prefix": {
  "type": "text",
  "analyzer": "autocomplete_index",
  "search_analyzer": "standard"
}
```

Index `"pixel"` thành `[p, pi, pix, pixe, pixel]`, còn query `"pix"` giữ token hợp
lý để match prefix. Nếu dùng edge-ngram cả search time, query dài có thể sinh quá
nhiều token và relevance khó kiểm soát.

Analyzer của field đã index không thể tùy tiện đổi bằng update mapping. Thay đổi
index analysis thường cần index version mới và reindex.

---

## 14. Tiếng Việt và dấu

Tiếng Việt có khoảng trắng giữa âm tiết, dấu thanh và từ ghép nhiều âm tiết. Không
có một analyzer mặc định giải quyết đúng mọi domain.

Hai nhu cầu khác nhau:

```text
Precision: "ma" không nên luôn đồng nghĩa "má", "mà", "mã", "mạ"
Recall:    người dùng gõ "dien thoai" vẫn muốn thấy "điện thoại"
```

Cách an toàn là giữ nhiều field có mục tiêu rõ:

```http
PUT /products-vi-v1
{
  "settings": {
    "analysis": {
      "filter": {
        "vi_fold_preserve": {
          "type": "asciifolding",
          "preserve_original": true
        }
      },
      "analyzer": {
        "vi_folded": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "vi_fold_preserve"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "standard",
        "fields": {
          "folded": {
            "type": "text",
            "analyzer": "vi_folded"
          }
        }
      }
    }
  }
}
```

`asciifolding` tăng recall nhưng có thể tạo false positive. Đánh giá bằng bộ query
gắn relevance judgment; không mặc định boost field folded bằng field giữ dấu.

Nếu cần Unicode normalization/tokenization nâng cao, đánh giá ICU analysis plugin
và tokenizer chuyên biệt, nhưng vẫn phải test từ ghép/domain vocabulary thực tế.

---

## 15. Normalizer cho `keyword`

Normalizer giống analyzer một-token: không được tách thành nhiều token.

```http
PUT /customers-v1
{
  "settings": {
    "analysis": {
      "normalizer": {
        "email_normalizer": {
          "type": "custom",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "email": {
        "type": "keyword",
        "normalizer": "email_normalizer"
      }
    }
  }
}
```

Lưu ý: lowercase toàn email có thể phù hợp lookup của hệ thống cụ thể, nhưng việc
canonicalize identifier phải thống nhất với source of truth. Normalizer không sửa
giá trị gốc trong `_source`.

---

## 16. Autocomplete: chọn đúng chiến lược

| Nhu cầu | Lựa chọn ban đầu |
|---|---|
| Search-as-you-type trên text | `search_as_you_type` hoặc edge n-gram |
| Suggest danh sách cụm đã chuẩn bị | `completion` suggester |
| Prefix trên exact identifier nhỏ | prefix query trên `keyword`, benchmark |
| Typo tolerance | fuzzy/matching strategy ở query time, có guardrail |

Edge n-gram làm số term tăng mạnh:

```text
"pixel" → p, pi, pix, pixe, pixel
```

Đừng đặt `min_gram=1`, `max_gram` rất lớn trên mọi field mà không đo index size và
latency. Product name, SKU và free-form description thường cần chiến lược khác nhau.

---

## 17. Synonym: ưu tiên search time

Ví dụ domain:

```text
điện thoại, smartphone
tv => television
```

Index-time synonym làm term được mở rộng khi ingest; thay rule phải reindex.
Search-time synonym linh hoạt hơn và phù hợp thay đổi vocabulary.

Workflow với Synonyms API:

```http
PUT /_synonyms/product-search
{
  "synonyms_set": [
    {
      "id": "phone",
      "synonyms": "điện thoại, smartphone"
    },
    {
      "id": "tv",
      "synonyms": "tv => television"
    }
  ]
}
```

Sau đó dùng `synonym_graph` trong search analyzer, đặc biệt khi có synonym nhiều
token:

```json
"filter": {
  "product_synonyms": {
    "type": "synonym_graph",
    "synonyms_set": "product-search",
    "updateable": true
  }
}
```

Guardrail:

- synonym set phải tồn tại trước khi index tham chiếu nó;
- `updateable: true` chỉ dùng trong search analyzer;
- invalid rule có thể làm analyzer reload thất bại hoặc index không mở được;
- thứ tự token filter ảnh hưởng cách parse synonym rule;
- test `_analyze` trước/sau thay đổi và kiểm tra relevance regression;
- synonym không phải nơi nhét mọi typo hoặc business boost.

---

## 18. Multi-fields và `copy_to`

### 18.1 Multi-field

Một source value được index nhiều cách:

```json
"title": {
  "type": "text",
  "fields": {
    "exact": { "type": "keyword" },
    "folded": {
      "type": "text",
      "analyzer": "vi_folded"
    }
  }
}
```

### 18.2 `copy_to`

Nhiều field đổ term vào field search tổng:

```json
"all_text": {
  "type": "text"
},
"name": {
  "type": "text",
  "copy_to": "all_text"
},
"description": {
  "type": "text",
  "copy_to": "all_text"
}
```

`copy_to` copy **value**, không copy term đã analyze, và không thay đổi `_source`.
Nó có thể giảm số field query phải chạm, nhưng làm mất khả năng boost/giải thích
theo field nếu chỉ query field tổng.

---

## 19. Vector field là một contract riêng

```json
"embedding": {
  "type": "dense_vector",
  "dims": 384,
  "similarity": "cosine"
}
```

Cần version ít nhất:

- embedding model;
- model revision;
- dimension;
- normalization;
- similarity;
- chunking strategy;
- index/quantization option;
- query embedding pipeline.

`dense_vector` chỉ nhận một vector cho mỗi field. Nếu một document có nhiều chunk,
thiết kế thường là document-per-chunk hoặc nested/chunk index có trade-off rõ.

Default quantization/index strategy có thể đổi theo phiên bản, dimension và license.
Không mặc định dựa vào default khi capacity/recall quan trọng; khai báo có chủ đích,
benchmark recall@k, p95/p99, ingest time, RAM và disk.

Raw vector vẫn có thể được giữ để reindex/rerank ngay cả khi index dùng quantization,
vì vậy “nén 32 lần” không đồng nghĩa tổng disk giảm đúng 32 lần.

---

## 20. Cập nhật mapping: cái gì thay in-place được?

Thường có thể:

- thêm field mới;
- thêm runtime field;
- cập nhật một số parameter được tài liệu cho phép như `ignore_above`;
- thêm multi-field cho future documents.

Thường cần index mới + reindex:

- đổi field type;
- đổi index analyzer của field đã có dữ liệu;
- đổi object thành nested;
- thay shard strategy;
- thay semantic khiến dữ liệu cũ cần được index lại.

Thêm multi-field không backfill document cũ. Chỉ document được index/update sau đó
có term ở subfield mới, trừ khi chạy update/reindex.

Quy tắc:

```text
Nếu thay đổi làm term/cấu trúc Lucene của dữ liệu cũ phải khác
→ tạo index version mới và reindex.
```

---

## 21. Component template và index template

Component template là khối tái sử dụng:

```http
PUT /_component_template/product-mappings-v2
{
  "version": 2,
  "_meta": {
    "owner": "search-platform"
  },
  "template": {
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "product_id": { "type": "keyword" },
        "created_at": { "type": "date" }
      }
    }
  }
}
```

Index template chọn index pattern và compose component:

```http
PUT /_index_template/products-template-v2
{
  "index_patterns": ["products-v2-*"],
  "priority": 500,
  "version": 2,
  "composed_of": ["product-mappings-v2"],
  "template": {
    "settings": {
      "number_of_replicas": 1
    }
  }
}
```

Precedence quan trọng:

```text
create-index request
  > index template body
  > component templates phía sau
  > component templates phía trước
```

Nếu nhiều index template match, template có priority cao nhất được dùng. Tránh
pattern va chạm built-in template.

Luôn simulate:

```http
POST /_index_template/_simulate_index/products-v2-000001
```

Review output cuối thay vì chỉ review từng component riêng.

---

## 22. Data stream cho dữ liệu append-only theo thời gian

Data stream phù hợp logs/events/time-series có `@timestamp`, liên tục append và
cần rollover/lifecycle:

```http
PUT /_index_template/app-events-template
{
  "index_patterns": ["app-events-*"],
  "data_stream": {},
  "priority": 500,
  "template": {
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "@timestamp": { "type": "date" },
        "event_id":   { "type": "keyword" },
        "event_type": { "type": "keyword" },
        "message":    { "type": "text" }
      }
    }
  }
}
```

```http
PUT /_data_stream/app-events-prod

POST /app-events-prod/_doc
{
  "@timestamp": "2026-07-31T10:15:30Z",
  "event_id": "evt-101",
  "event_type": "order_created",
  "message": "Order o-101 created"
}
```

Content catalog cập nhật theo ID thường phù hợp versioned index + aliases hơn.
Đừng dùng data stream chỉ vì tên dữ liệu có chữ “log”.

---

## 23. Ingest pipeline

Ingest pipeline biến đổi document trước mapping/indexing:

```http
PUT /_ingest/pipeline/product-normalize-v1
{
  "description": "Normalize product document before indexing",
  "processors": [
    {
      "trim": {
        "field": "name"
      }
    },
    {
      "lowercase": {
        "field": "category"
      }
    },
    {
      "set": {
        "field": "indexed_at",
        "value": "{{{_ingest.timestamp}}}"
      }
    }
  ],
  "on_failure": [
    {
      "set": {
        "field": "ingest_error.message",
        "value": "{{{_ingest.on_failure_message}}}"
      }
    }
  ]
}
```

Test từng processor:

```http
POST /_ingest/pipeline/product-normalize-v1/_simulate?verbose=true
{
  "docs": [
    {
      "_index": "products-v2-000001",
      "_id": "p-101",
      "_source": {
        "name": "  Pixel 10 Pro  ",
        "category": "PHONE"
      }
    }
  ]
}
```

Pipeline có thể được chọn qua:

- request parameter `pipeline`;
- `index.default_pipeline`;
- `index.final_pipeline`.

Guardrail:

- gắn `tag`/description cho processor để debug;
- test missing/null/wrong type và payload lớn;
- không `ignore_failure` rộng rồi âm thầm làm mất field;
- heavy script, enrich hoặc regex có thể thành ingest bottleneck;
- `on_failure` phải dẫn tới retry/failure store/DLQ có người sở hữu;
- pipeline thành công không đảm bảo document qua mapping.

---

## 24. Indexing API và document identity

### 24.1 `index` có thể overwrite cùng ID

```http
PUT /products-write/_doc/p-101
{
  "product_id": "p-101",
  "name": "Pixel 10 Pro"
}
```

ID ổn định giúp retry idempotent ở mức document identity.

### 24.2 `create` từ chối ID đã tồn tại

```http
PUT /events-write/_create/evt-101
{
  "event_id": "evt-101",
  "event_type": "order_created"
}
```

Phù hợp immutable event khi duplicate phải được phát hiện.

### 24.3 Update vẫn là reindex document

Lucene segment bất biến; partial update đọc/merge `_source` rồi index phiên bản
document mới. Nhiều update nhỏ không miễn phí.

Để chống lost update:

```http
PUT /products-write/_doc/p-101?if_seq_no=17&if_primary_term=3
{
  "product_id": "p-101",
  "name": "Pixel 10 Pro"
}
```

Conflict phải được application retry/reconcile dựa trên domain semantics.

---

## 25. Bulk API: HTTP 200 vẫn có thể mất item

Bulk dùng NDJSON, mỗi action và source nằm trên dòng riêng:

```http
POST /_bulk
{"create":{"_index":"events-write","_id":"evt-101"}}
{"event_id":"evt-101","event_type":"order_created"}
{"index":{"_index":"products-write","_id":"p-101"}}
{"product_id":"p-101","name":"Pixel 10 Pro"}
```

Payload cần newline cuối. Quan trọng hơn: response HTTP có thể `200` nhưng
`errors: true` và một số item thất bại.

Client production phải:

1. đọc từng item response;
2. phân loại retryable và permanent error;
3. retry riêng item retryable với exponential backoff + jitter;
4. không retry mapping/validation error vô hạn;
5. đưa permanent error vào DLQ/failure workflow;
6. giữ stable `_id` hoặc idempotency key;
7. giới hạn concurrency để tôn trọng backpressure.

Không có bulk size “5–15 MB” đúng cho mọi workload. Benchmark một shard/node với
document thật, tăng dần batch đến khi throughput chững, sau đó giữ headroom cho
heap, network và concurrent clients. Tránh request khổng lồ.

Theo dõi ít nhất:

- item success/failure theo error type;
- retry count và DLQ depth;
- ingest latency;
- indexing rejection/429;
- refresh/merge pressure;
- source-to-index lag.

---

## 26. `_source`, fetch và disk trade-off

Best default là giữ `_source`:

```json
"_source": { "enabled": true }
```

Khi search chỉ cần vài field, dùng source filtering hoặc `fields` API thay vì trả
payload lớn:

```http
GET /products-read/_search
{
  "_source": ["product_id", "name", "price_minor"],
  "query": {
    "match_all": {}
  }
}
```

Tắt `doc_values` chỉ khi chắc chắn không sort, aggregate hoặc script field đó.
`text` vốn không có doc values; bật `fielddata` trên text có thể dùng nhiều heap,
thường nên thêm `keyword` subfield thay thế.

`index: false` không đồng nghĩa field hoàn toàn không dùng được: một số type còn
có thể query chậm qua doc values. Nhưng nếu field chỉ để trả lại, giữ trong
`_source` và tránh tạo cấu trúc không cần thiết.

---

## 27. Reindex và zero-downtime migration

Mapping version:

```text
products-v1
products-v2

products-read  → current read index
products-write → current write index
```

Quy trình an toàn:

```text
1. Tạo template/mapping/pipeline v2
2. Simulate template và pipeline
3. Tạo products-v2
4. Ghi checkpoint nguồn
5. Backfill v1/source of truth → v2
6. Replay thay đổi sau checkpoint hoặc dual-write có reconcile
7. So sánh count + checksum/sample + business queries
8. Atomic alias switch
9. Theo dõi và giữ rollback window
10. Xóa v1 chỉ sau retention/approval
```

Reindex cơ bản:

```http
POST /_reindex?wait_for_completion=false
{
  "source": {
    "index": "products-v1"
  },
  "dest": {
    "index": "products-v2",
    "pipeline": "product-normalize-v2"
  }
}
```

Alias switch:

```http
POST /_aliases
{
  "actions": [
    {
      "remove": {
        "index": "products-v1",
        "alias": "products-read"
      }
    },
    {
      "add": {
        "index": "products-v2",
        "alias": "products-read"
      }
    }
  ]
}
```

Alias switch atomic chỉ đảm bảo tên trỏ sang index mới atomically. Nó không tự
copy những write phát sinh trong lúc backfill. Phải giải quyết delta bằng freeze
ngắn, outbox/CDC, event replay hoặc dual-write có reconciliation.

Count bằng nhau cũng chưa đủ: analyzer mới có thể làm query behavior đổi dù số
document đúng.

---

## 28. Mapping/analyzer contract testing

### 28.1 Mapping tests

- field lạ bị reject hay giữ trong `_source` đúng policy;
- null/missing/empty array khác nhau ra sao;
- date/numeric sai type đi vào DLQ;
- object/nested cho kết quả đúng;
- field count không tăng ngoài dự kiến.

### 28.2 Analyzer golden tests

```text
Input                     Expected essential terms
"Điện thoại Pixel"        điện, thoại, pixel
"dien thoai pixel"        dien, thoai, pixel
"SKU-PX10-PRO"            theo contract của SKU field
"C++ for beginners"       theo contract của title field
```

Không nhất thiết snapshot toàn token response nếu quá brittle. Kiểm tra term bắt
buộc/cấm, position quan trọng và search relevance trên corpus versioned.

### 28.3 Template/pipeline tests

```http
POST /_index_template/_simulate_index/products-v2-000001
POST /_ingest/pipeline/product-normalize-v2/_simulate?verbose=true
```

Chạy trong CI hoặc môi trường integration cùng version Elasticsearch mục tiêu.

### 28.4 Relevance regression

Giữ query set có expected relevant documents/grades:

```text
query → relevant product IDs → grade
```

So sánh recall@k, precision@k, MRR/NDCG và business metrics trước khi chuyển alias.

---

## 29. Failure modes thường gặp

### 29.1 Field đầu tiên quyết định dynamic type sai

Ngày đầu producer gửi `"latency": "unknown"`, field thành text/keyword; ngày sau
gửi `125` và bị conflict. Dùng explicit mapping cùng validation/DLQ.

### 29.2 `text` dùng terms aggregation

Aggregation lỗi hoặc đội ngũ bật `fielddata` làm heap tăng. Thêm `keyword`
subfield nếu thật sự cần exact aggregation.

### 29.3 `keyword` dài làm reject document

Stack trace/path/raw payload vượt Lucene term limit. Dùng `text`, `wildcard`,
`ignore_above` hoặc không index tùy query; theo dõi `_ignored`.

### 29.4 `object` array trả false positive

Query match color của phần tử này với size của phần tử khác. Dùng nested hoặc đổi
document model.

### 29.5 Dynamic labels làm mapping explosion

Request ID/customer-generated key trở thành field name. Chuyển key thành value,
`flattened`, hoặc chặn dynamic.

### 29.6 Synonym update làm analyzer lỗi

Rule invalid hoặc synonym set chưa tồn tại khiến reload/open index thất bại. Tạo
resource trước, validate `_analyze`, rollout và có rollback.

### 29.7 Bulk caller chỉ nhìn HTTP status

Request HTTP 200 nhưng hàng trăm item lỗi mapping/429. Parse từng item và reconcile
source-to-index count/lag.

### 29.8 Alias switched nhưng document mới bị mất

Backfill đọc snapshot cũ trong khi application vẫn ghi v1. Cần delta replay hoặc
dual-write/freeze có chủ đích.

### 29.9 Autocomplete index phình bất ngờ

N-gram quá rộng trên field dài. Giới hạn field, gram range và benchmark vocabulary
thật; cân nhắc `search_as_you_type`/completion.

### 29.10 Tắt `_source` để tiết kiệm disk

Sau đó không thể update/reindex/debug theo cách bình thường. Đánh giá compression,
source filtering hoặc synthetic source trước.

---

## 30. Checklist thiết kế

### Contract

- [ ] Có owner và version cho mapping/analyzer/template?
- [ ] Field type được chọn từ query behavior?
- [ ] Business validation chạy trước Elasticsearch?
- [ ] Null, missing, array, date/timezone và money có quy ước?
- [ ] Unknown field dùng `strict`, `false`, `true` hay `runtime` có chủ đích?

### Text search

- [ ] Analyzer được test bằng corpus thật?
- [ ] Index/search analyzer tạo term tương thích?
- [ ] Accent folding tiếng Việt đã đo precision/recall?
- [ ] Synonym được version, validate và rollback?
- [ ] Autocomplete có budget disk/latency?

### Schema growth

- [ ] Dynamic key không biến thành field name?
- [ ] Có field-count guardrail và cảnh báo mapping drift?
- [ ] `object`, `nested`, `flattened` được chọn đúng semantics?
- [ ] Keyword dài có `ignore_above`/model phù hợp?

### Ingest

- [ ] Template và pipeline được simulate?
- [ ] Bulk client parse từng item?
- [ ] Retry có backoff, idempotency và DLQ?
- [ ] Có metric source-to-index lag và permanent failure?
- [ ] `_id` strategy hỗ trợ retry/reconcile?

### Migration

- [ ] Thay đổi nào cần reindex đã được nhận diện?
- [ ] Có checkpoint/delta replay trong lúc backfill?
- [ ] Validation gồm business query, không chỉ count?
- [ ] Alias switch và rollback window rõ ràng?
- [ ] Index cũ chỉ xóa sau retention/approval?

---

## 31. Câu hỏi phỏng vấn

### Cơ bản

1. `_source`, inverted index và `doc_values` khác nhau thế nào?
2. Khi nào dùng `text`, khi nào dùng `keyword`?
3. Analyzer gồm những bước nào?
4. Vì sao write JSON array không cần array field type?

### Trung cấp

1. `object`, `nested` và `flattened` khác nhau ra sao?
2. `dynamic: false`, `strict` và `runtime` xử lý field lạ thế nào?
3. Tại sao thêm multi-field không làm document cũ có dữ liệu ở subfield?
4. Vì sao search-time synonym thường linh hoạt hơn index-time synonym?
5. Bulk API HTTP 200 vẫn có thể mất dữ liệu như thế nào?

### Nâng cao

1. Thiết kế mapping đa ngôn ngữ và không dấu tiếng Việt ra sao?
2. Làm sao ngăn mapping explosion từ customer-defined metadata?
3. Migration analyzer không downtime cần xử lý concurrent write thế nào?
4. Chọn vector index/quantization bằng metric nào?
5. Làm sao version và test mapping/analyzer như một public contract?

---

## 32. Nguồn và chủ đề tiếp theo

Tài liệu chính thức:

- [Mapping](https://www.elastic.co/docs/manage-data/data-store/mapping)
- [Field data types](https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/field-data-types)
- [`_source`](https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/mapping-source-field)
- [`doc_values`](https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/doc-values)
- [Text analysis](https://www.elastic.co/docs/manage-data/data-store/text-analysis)
- [Index and search analysis](https://www.elastic.co/docs/manage-data/data-store/text-analysis/index-search-analysis)
- [Synonyms](https://www.elastic.co/docs/solutions/search/full-text/search-with-synonyms)
- [Mapping explosion](https://www.elastic.co/docs/troubleshoot/elasticsearch/mapping-explosion)
- [Templates](https://www.elastic.co/docs/manage-data/data-store/templates)
- [Ingest pipelines](https://www.elastic.co/docs/manage-data/ingest/transform-enrich/ingest-pipelines)
- [Dense vector](https://www.elastic.co/docs/reference/elasticsearch/mapping-reference/dense-vector)
- [Indexing performance](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance)

Học tiếp:

1. [Query DSL](query_dsl.md) – query/filter context, scoring, pagination và search
   correctness.
2. [Architecture](architecture.md) – shard, segment, refresh và write/read path.
3. [Aggregations](../advanced/aggregations.md) – doc values, bucket và reduce.
4. [Performance](../performance/optimization.md) – benchmark indexing/search theo
   workload thật.

---

*Cập nhật lần cuối: 2026-07-31.*
