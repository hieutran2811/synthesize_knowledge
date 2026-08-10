---
title: "Elasticsearch Query DSL – từ điều kiện đúng đến kết quả đúng"
topic: elasticsearch
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 13
---
# Elasticsearch Query DSL – từ điều kiện đúng đến kết quả đúng

> Thuật ngữ: [Glossary](../glossary.md).

> Query chạy không lỗi chưa có nghĩa kết quả đúng. Một search request còn phụ
> thuộc mapping, analyzer, query/filter context, shard statistics, sort order,
> refresh và dữ liệu thay đổi giữa các trang. Thiết kế query tốt phải trả lời được
> ba câu: document nào được phép xuất hiện, document nào xếp trên, và kết quả có
> ổn định/đầy đủ theo contract hay không.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Retriever, semantic
search, reranker và một số query option có thể phụ thuộc phiên bản, deployment
hoặc license.

---

## 1. Query DSL là một cây truy vấn

Query DSL là JSON abstract syntax tree, không phải chuỗi SQL:

```text
bool
├── must
│   └── multi_match("điện thoại pixel")
├── filter
│   ├── term(category="phone")
│   ├── term(in_stock=true)
│   └── range(price_minor)
└── should
    └── rank_feature(popularity)
```

Hai nhóm node:

- **Leaf query** tìm trên một field: `match`, `term`, `range`, `exists`...
- **Compound query** kết hợp hoặc thay đổi hành vi query con: `bool`, `dis_max`,
  `constant_score`, `function_score`...

Query DSL mô tả *cái cần tìm*. Search API còn mô tả:

- pagination và sort;
- field cần trả;
- highlight;
- aggregation;
- timeout, total-hit policy và partial-result policy;
- PIT/retriever/rescore.

---

## 2. Mapping và analyzer đi trước query

Giá trị `_source`:

```json
{ "name": "Điện thoại Pixel 10 Pro" }
```

không cho biết term thực sự trong index. Nếu `name` là `text` với analyzer
`standard`, term có thể là:

```text
[điện, thoại, pixel, 10, pro]
```

Nếu là `keyword`, term là:

```text
["Điện thoại Pixel 10 Pro"]
```

Vì vậy:

```text
mapping → analyzer → indexed terms → query rewrite → matches → score
```

Khi query không match, đừng thêm wildcard/fuzziness ngay. Kiểm tra:

```http
GET /products-read/_mapping/field/name*

POST /products-read/_analyze
{
  "field": "name",
  "text": "Điện thoại Pixel 10 Pro"
}
```

Đọc thêm [Indexing, Mapping & Analyzers](indexing_mapping.md).

Các ví dụ dưới đây giả định alias `products-read` trỏ tới index có mapping phù
hợp: `name`/`description` là `text`, `name.folded` là text đã fold dấu,
`product_id`/`category`/`brand`/`status` là `keyword`, `in_stock` là `boolean`,
`price_minor`/`sales_count`/`rating` là numeric và `popularity` là
`rank_feature`. Query không tự sửa một field mapping sai.

---

## 3. Query context và filter context

Context do **vị trí trong cây query** quyết định, không do tên query type.

### 3.1 Query context

Trả lời:

```text
Document match tốt đến đâu?
```

Nó tính `_score`. Top-level `query`, `bool.must` và `bool.should` thường chạy trong
query context.

### 3.2 Filter context

Trả lời:

```text
Document có thỏa điều kiện bắt buộc không?
```

Nó không tính score cho clause đó. `bool.filter`, `bool.must_not` và filter của
`constant_score` chạy trong filter context.

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "must": {
        "match": {
          "name": "điện thoại pixel"
        }
      },
      "filter": [
        {
          "term": {
            "category": "phone"
          }
        },
        {
          "term": {
            "in_stock": true
          }
        }
      ]
    }
  }
}
```

`match` quyết định relevance; category/stock chỉ quyết định eligibility.

> `term` không mặc nhiên là filter. Đặt `term` ở top-level `query` hoặc
> `bool.should` thì nó vẫn chạy trong query context và có thể đóng góp score.

### 3.3 Cache không phải lời hứa

Filter clause **được xem xét** cho node query cache. Elasticsearch dùng lịch sử
query và đặc điểm segment để quyết định cache; không phải mọi filter đều được cache.
Đừng biến timestamp range luôn thay đổi thành “filter để chắc chắn cache”.

---

## 4. Full-text và term-level là hai khái niệm khác context

| Nhóm | Input có được analyze? | Ví dụ | Dùng cho |
|---|---:|---|---|
| Full-text | Có | `match`, `multi_match`, `match_phrase` | `text`, relevance |
| Term-level | Không | `term`, `terms`, `range`, `prefix`, `wildcard` | term chính xác/structured data |

Term-level query match term đã lưu, không phải “so sánh nguyên `_source`”.

```text
text field indexed: "Quick Brown Fox" → [quick, brown, fox]

term("Quick Brown Fox") → tìm đúng term "Quick Brown Fox" → không có
match("Quick Brown Fox") → analyze [quick, brown, fox]    → có thể match
```

---

## 5. `match`: full-text query mặc định

```http
GET /products-read/_search
{
  "query": {
    "match": {
      "name": {
        "query": "điện thoại pixel",
        "operator": "and"
      }
    }
  }
}
```

`match` analyze query string bằng search analyzer của field rồi dựng query từ các
term.

Các option cần hiểu:

| Option | Ý nghĩa | Rủi ro |
|---|---|---|
| `operator` | `or` hoặc `and` giữa term | `and` giảm recall với query dài |
| `minimum_should_match` | Số/tỷ lệ term bắt buộc | Cần test theo query length |
| `fuzziness` | Cho phép edit distance | Tăng term expansion/false positive |
| `prefix_length` | Prefix không fuzzy | Cân bằng precision/cost |
| `zero_terms_query` | Khi analyzer loại hết term | `all` có thể trả toàn index ngoài ý muốn |
| `lenient` | Bỏ qua một số type error | Có thể che bug contract |

Ví dụ mềm hơn `AND`:

```http
GET /products-read/_search
{
  "query": {
    "match": {
      "name": {
        "query": "điện thoại pixel pro chính hãng",
        "minimum_should_match": "70%"
      }
    }
  }
}
```

Không chọn `operator`/minimum bằng cảm giác; đo recall/precision trên query set.

---

## 6. Phrase và proximity

### 6.1 `match_phrase`

```http
GET /products-read/_search
{
  "query": {
    "match_phrase": {
      "name": {
        "query": "pixel pro",
        "slop": 1
      }
    }
  }
}
```

Phrase query dùng token position:

- `slop: 0`: đúng thứ tự/liền kề theo positions;
- slop lớn hơn cho phép dịch chuyển;
- transposition thường tốn slop lớn hơn một bước.

Phrase không có nghĩa exact `_source`; analyzer vẫn lowercase, stem, synonym...

### 6.2 Rescore phrase thay vì phrase trên toàn corpus

Có thể lấy candidate bằng `match`, sau đó phrase-rescore top window. Cách này giữ
recall ban đầu và chỉ trả chi phí phrase cho tập nhỏ hơn; xem §18.

---

## 7. Search nhiều field

### 7.1 `multi_match`

```http
GET /products-read/_search
{
  "query": {
    "multi_match": {
      "query": "điện thoại pixel",
      "fields": [
        "name^4",
        "name.folded^1.5",
        "description"
      ],
      "type": "best_fields",
      "tie_breaker": 0.2
    }
  }
}
```

| Type | Mental model | Khi phù hợp |
|---|---|---|
| `best_fields` | Lấy field tốt nhất, có thể cộng phần từ field khác | Cùng concept ở nhiều field |
| `most_fields` | Cộng score từ nhiều field | Nhiều biến thể analyzer của cùng text |
| `cross_fields` | Term-centric qua các field | Tên/họ hoặc field cùng analyzer |
| `phrase` | `match_phrase` trên từng field | Phrase quan trọng |
| `phrase_prefix` | Phrase với term cuối là prefix | Autocomplete có kiểm soát |

Boost `^4` là trọng số tương đối, không đảm bảo field đó “quan trọng đúng bốn lần”
trong business outcome.

### 7.2 `dis_max`

`best_fields` thường dùng hành vi giống `dis_max`:

```http
GET /products-read/_search
{
  "query": {
    "dis_max": {
      "queries": [
        {
          "match": {
            "name": "pixel"
          }
        },
        {
          "match": {
            "description": "pixel"
          }
        }
      ],
      "tie_breaker": 0.2
    }
  }
}
```

Score tốt nhất thắng; `tie_breaker` cộng một phần score từ các query còn lại.

---

## 8. Prefix/autocomplete query

### 8.1 `match_bool_prefix`

Input:

```text
"pixel 10 pr"
```

Các term trước match bình thường, term cuối là prefix. Phù hợp search-as-you-type
đơn giản:

```http
GET /products-read/_search
{
  "query": {
    "match_bool_prefix": {
      "name": "pixel 10 pr"
    }
  }
}
```

### 8.2 `match_phrase_prefix`

Giữ thứ tự phrase, term cuối mở rộng prefix:

```http
GET /products-read/_search
{
  "query": {
    "match_phrase_prefix": {
      "name": {
        "query": "pixel 10 pr",
        "max_expansions": 50
      }
    }
  }
}
```

Term expansion phụ thuộc từ điển term và có thể không ổn định về quality/cost.
Với autocomplete quan trọng, cân nhắc `search_as_you_type`, edge n-gram hoặc
completion mapping được thiết kế từ trước.

---

## 9. `term`, `terms` và `ids`

### 9.1 `term`

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "term": {
          "category": "phone"
        }
      }
    }
  }
}
```

Dùng cho `keyword`, boolean, numeric/date term chính xác. Giá trị phải khớp term
sau normalizer; nó không chạy analyzer.

### 9.2 `terms`

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "terms": {
          "category": [
            "phone",
            "tablet"
          ]
        }
      }
    }
  }
}
```

`terms` là membership trong tập, không phải nhiều full-text token. Danh sách cực
lớn làm request/query nặng và bị giới hạn; nếu ACL có hàng trăm nghìn ID, xem lại
data model, routing hoặc document-level security thay vì đẩy danh sách tùy ý.

### 9.3 `ids`

```http
GET /products-read/_search
{
  "query": {
    "ids": {
      "values": [
        "p-101",
        "p-102"
      ]
    }
  }
}
```

Nếu chỉ lấy một document biết ID/index, GET API đơn giản và có real-time visibility
khác `_search`.

---

## 10. `range` và date math

Numeric range:

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "range": {
          "price_minor": {
            "gte": 10000000,
            "lt": 20000000
          }
        }
      }
    }
  }
}
```

Time range:

```http
GET /events-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "range": {
          "@timestamp": {
            "gte": "now-7d/d",
            "lt": "now/d",
            "time_zone": "Asia/Bangkok"
          }
        }
      }
    }
  }
}
```

`now` vẫn là current system time UTC. `time_zone` ảnh hưởng cách hiểu date literal
và rounding như `now/d`, không biến `now` thành clock khác.

Tránh range query trên `text`/`keyword` để mô phỏng numeric/date; nó có thể bị coi
là expensive và có lexical semantics sai.

---

## 11. `exists` không có nghĩa `_source` có key

`exists` kiểm tra indexed value:

```http
GET /products-read/_search
{
  "query": {
    "exists": {
      "field": "discount_price_minor"
    }
  }
}
```

Có thể **không exists** khi:

- JSON là `null` hoặc `[]`;
- cả `index` và `doc_values` bị tắt;
- giá trị vượt `ignore_above`;
- malformed value bị `ignore_malformed`.

Vẫn **exists** với:

- empty string `""`;
- array `[null, "value"]`;
- mapping có `null_value`.

Tìm missing:

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "must_not": {
        "exists": {
          "field": "discount_price_minor"
        }
      }
    }
  }
}
```

Nếu business cần phân biệt missing/null/blank/ignored, model explicit status thay
vì suy luận toàn bộ từ `exists`.

---

## 12. Wildcard, regexp, prefix và fuzzy

Các query này match/expand term trong term dictionary, không phải đơn giản “quét
`_source`”, nhưng vẫn có thể rất tốn tài nguyên.

```http
GET /products-read/_search
{
  "query": {
    "prefix": {
      "sku": {
        "value": "PX-10-"
      }
    }
  }
}
```

```http
GET /products-read/_search
{
  "query": {
    "wildcard": {
      "sku": {
        "value": "PX-*-PRO",
        "case_insensitive": true
      }
    }
  }
}
```

Guardrail:

- tránh pattern bắt đầu `*`/`?`;
- giới hạn input length và wildcard count;
- filter trước bằng tenant/category/time nếu có thể;
- dùng `wildcard` field, n-gram hoặc explicit prefix field theo workload;
- benchmark term cardinality thật;
- cân nhắc `search.allow_expensive_queries=false`.

`fuzziness` dựa trên edit distance và thường tối đa hai edit. Nó không hiểu âm
nghĩa hay keyboard layout; fuzzy trên token ngắn dễ gây false positive. Synonym
multi-token cũng không được fuzzy giống term thường.

---

## 13. `bool`: logic và scoring

| Clause | Bắt buộc? | Score? | Context |
|---|---:|---:|---|
| `must` | Có | Có | Query |
| `filter` | Có | Không | Filter |
| `must_not` | Phải không match | Không | Filter |
| `should` | Tùy `minimum_should_match` | Có | Query |

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "điện thoại pixel",
            "fields": [
              "name^4",
              "name.folded^1.5",
              "description"
            ]
          }
        }
      ],
      "filter": [
        {
          "term": {
            "category": "phone"
          }
        },
        {
          "term": {
            "in_stock": true
          }
        }
      ],
      "must_not": [
        {
          "term": {
            "status": "discontinued"
          }
        }
      ],
      "should": [
        {
          "term": {
            "brand": {
              "value": "google",
              "boost": 1.5
            }
          }
        }
      ]
    }
  }
}
```

### 13.1 Default `minimum_should_match`

- Có `should` nhưng không có `must`/`filter`: mặc định `1`.
- Có `must` hoặc `filter`: mặc định `0`, nên `should` chỉ boost.

Nếu business bắt buộc ít nhất một điều kiện ưu tiên, khai báo rõ:

```json
{
  "minimum_should_match": 1
}
```

Đừng dựa vào default khi query builder có thể thêm/bớt clause động.

### 13.2 Logic ngoặc

Yêu cầu:

```text
(brand=google AND name~pixel)
OR
(brand=samsung AND name~galaxy)
```

cần nested bool đúng ngoặc. Flatten tất cả `must`/`should` có thể đổi semantic.
Unit test query builder bằng truth table.

---

## 14. `constant_score`

Khi tất cả điều kiện chỉ là eligibility nhưng API vẫn cần score hằng:

```http
GET /products-read/_search
{
  "query": {
    "constant_score": {
      "filter": {
        "bool": {
          "filter": [
            {
              "term": {
                "category": "phone"
              }
            },
            {
              "term": {
                "in_stock": true
              }
            }
          ]
        }
      },
      "boost": 1.0
    }
  }
}
```

Mọi matching document nhận cùng score. Nếu sort theo field, có thể không cần score
và dùng bool filter trực tiếp.

---

## 15. Nested query và join

Mapping `variants` là `nested`:

```http
GET /products-read/_search
{
  "query": {
    "nested": {
      "path": "variants",
      "query": {
        "bool": {
          "filter": [
            {
              "term": {
                "variants.color": "red"
              }
            },
            {
              "term": {
                "variants.size": "L"
              }
            },
            {
              "term": {
                "variants.in_stock": true
              }
            }
          ]
        }
      },
      "score_mode": "none",
      "inner_hits": {
        "name": "matching_variants",
        "size": 3
      }
    }
  }
}
```

`inner_hits` trả nested object nào match, nhưng tăng fetch/query cost.

`has_child`/`has_parent` yêu cầu join field, cùng index/routing constraints và tốn
hơn denormalized document. Chỉ dùng khi cardinality/update pattern khiến
denormalization không hợp lý và đã benchmark.

---

## 16. Relevance và BM25

BM25 mặc định kết hợp:

- term frequency có saturation;
- inverse document frequency: term hiếm thường quan trọng hơn;
- field length normalization;
- boost và các compound score.

Mental model:

```text
"pixel" hiếm hơn "điện thoại"
→ thường đóng góp score lớn hơn

term lặp 20 lần
→ không mặc định mạnh gấp 20 lần vì saturation

field ngắn match cùng term
→ có thể được ưu tiên hơn field rất dài
```

Score là số floating point dùng để xếp hạng trong cùng query/index state. Không coi
`_score=8` là “relevance 80%” và không dùng threshold cố định qua mọi corpus.

### 16.1 Distributed scoring

Search mặc định chạy query trên từng shard rồi coordinator merge. Term statistics
theo shard có thể làm score hơi khác, đặc biệt dataset nhỏ hoặc shard skew.
`dfs_query_then_fetch` thu thập global term statistics trước nhưng thêm round trip;
phù hợp chẩn đoán/trường hợp đặc biệt, không phải cách chữa shard design.

---

## 17. Boost và business signals

Boost đơn giản:

```json
{
  "fields": [
    "name^4",
    "description"
  ]
}
```

Nhưng business relevance thường gồm:

```text
lexical relevance
+ popularity đã saturation
+ freshness decay
+ availability/business rules
- quality penalty
```

Không nhân raw `sales_count` trực tiếp: head product sẽ thống trị mãi. Dùng
`log1p`, saturation hoặc `rank_feature`.

### 17.1 `function_score`

```http
GET /products-read/_search
{
  "query": {
    "function_score": {
      "query": {
        "match": {
          "name": "pixel"
        }
      },
      "functions": [
        {
          "filter": {
            "term": {
              "in_stock": true
            }
          },
          "weight": 1.2
        },
        {
          "field_value_factor": {
            "field": "sales_count",
            "modifier": "log1p",
            "factor": 0.1,
            "missing": 0
          }
        },
        {
          "gauss": {
            "created_at": {
              "origin": "now",
              "scale": "30d",
              "offset": "7d",
              "decay": 0.5
            }
          }
        }
      ],
      "score_mode": "sum",
      "boost_mode": "sum"
    }
  }
}
```

### 17.2 `rank_feature`

Nếu feature dương, single-valued và dùng riêng để ranking, mapping `rank_feature`
cùng `rank_feature` query có thể hiệu quả hơn generic scoring function:

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "must": {
        "match": {
          "name": "pixel"
        }
      },
      "should": {
        "rank_feature": {
          "field": "popularity",
          "saturation": {
            "pivot": 100
          }
        }
      }
    }
  }
}
```

### 17.3 `script_score`

Linh hoạt nhưng chạy per matching document và có thể expensive. Filter candidate
set trước, dùng params để tái sử dụng compiled script, xử lý missing field và
benchmark p99. Score phải không âm.

`min_score` buộc score từng candidate rồi mới loại, vì vậy không thay thế filter.

---

## 18. Rescore: retrieval rẻ, ranking đắt

Hai tầng:

```text
Stage 1: BM25/filter lấy candidate có recall cao
Stage 2: phrase/script/LTR rerank top window
```

```http
GET /products-read/_search
{
  "query": {
    "match": {
      "name": "pixel pro"
    }
  },
  "rescore": {
    "window_size": 100,
    "query": {
      "rescore_query": {
        "match_phrase": {
          "name": {
            "query": "pixel pro",
            "slop": 1
          }
        }
      },
      "query_weight": 1.0,
      "rescore_query_weight": 2.0,
      "score_mode": "total"
    }
  }
}
```

Rescore chạy trên top window **mỗi shard** trước khi coordinator merge. Window quá
nhỏ bỏ lỡ candidate; quá lớn làm mất lợi ích. Giữ `window_size` nhất quán giữa
các trang, nếu không thứ tự có thể dịch chuyển.

Explicit field sort khác `_score desc` không tương thích query rescore.

---

## 19. Lexical, semantic và hybrid retrieval

Lexical search mạnh với:

- tên, mã, thuật ngữ chính xác;
- filter;
- khả năng explain;
- latency/cost dự đoán được.

Semantic search mạnh khi query và document cùng ý nhưng khác từ. Elasticsearch 9.x
cho phép `match` trên `semantic_text`; behavior semantic được field xử lý:

```http
GET /articles/_search
{
  "query": {
    "match": {
      "content_semantic": "cách giảm đau cơ sau khi chạy bộ"
    }
  }
}
```

Hybrid bằng RRF retriever kết hợp thứ hạng lexical và semantic:

```http
GET /articles/_search
{
  "retriever": {
    "rrf": {
      "retrievers": [
        {
          "standard": {
            "query": {
              "multi_match": {
                "query": "cách giảm đau cơ sau khi chạy bộ",
                "fields": [
                  "title^3",
                  "content"
                ]
              }
            }
          }
        },
        {
          "standard": {
            "query": {
              "match": {
                "content_semantic": "cách giảm đau cơ sau khi chạy bộ"
              }
            }
          }
        }
      ]
    }
  }
}
```

RRF kết hợp **rank**, không coi BM25 score và vector similarity là cùng thang đo.
Hybrid không tự động tốt hơn: cần query set, judgment, recall@k/NDCG và cost/latency
test. Filter tenant/ACL phải được áp đúng vào mọi retrieval branch.

---

## 20. Sort là một phần của correctness

Mặc định search có scoring sort theo `_score desc`. Field sort:

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "term": {
          "category": "phone"
        }
      }
    }
  },
  "sort": [
    {
      "price_minor": {
        "order": "asc",
        "missing": "_last"
      }
    },
    {
      "product_id": {
        "order": "asc"
      }
    }
  ]
}
```

Guardrail:

- sort field cần `doc_values`; không sort `text`;
- luôn có tie-breaker duy nhất cho pagination;
- multi-valued field cần `mode` phù hợp;
- query nhiều index có mapping khác nhau cần `unmapped_type`/format nhất quán;
- field sort thường không tính score trừ khi `track_scores: true`;
- `track_scores` làm thêm việc, chỉ bật khi client dùng `_score`.

Không dùng `_id` trực tiếp làm tie-breaker sort. Tạo/copy ID vào field `keyword`
có `doc_values`, ví dụ `product_id`.

---

## 21. `from` + `size`: chỉ cho trang nông

```http
GET /products-read/_search
{
  "from": 40,
  "size": 20,
  "query": {
    "match": {
      "name": "pixel"
    }
  }
}
```

Mỗi shard phải giữ candidate của cả các trang trước:

```text
from=9,980, size=20
→ mỗi shard có thể phải giữ top 10,000
→ coordinator merge rồi bỏ 9,980 hit
```

Mặc định `index.max_result_window` giới hạn `from + size` ở 10,000. Tăng limit chỉ
dời guardrail và tăng memory/CPU risk.

---

## 22. `search_after`: cursor theo sort value

Mapping có `product_id` unique keyword. Trang đầu:

```http
GET /products-read/_search
{
  "size": 20,
  "query": {
    "match": {
      "name": "pixel"
    }
  },
  "sort": [
    {
      "_score": "desc"
    },
    {
      "product_id": "asc"
    }
  ]
}
```

Lấy mảng `sort` của hit cuối:

```json
{
  "sort": [
    7.2134,
    "p-101"
  ]
}
```

Trang tiếp:

```http
GET /products-read/_search
{
  "size": 20,
  "query": {
    "match": {
      "name": "pixel"
    }
  },
  "sort": [
    {
      "_score": "desc"
    },
    {
      "product_id": "asc"
    }
  ],
  "search_after": [
    7.2134,
    "p-101"
  ]
}
```

Query, sort, analyzer/index target phải giữ nguyên. `search_after` hiệu quả hơn
deep offset nhưng không tự tạo snapshot; refresh giữa hai request vẫn có thể gây
duplicate/missing/order change. Dùng PIT nếu cần view ổn định.

---

## 23. Point in time (PIT) + `search_after`

Mở PIT:

```http
POST /products-read/_pit?keep_alive=2m
```

Trang đầu: khi có PIT, **không đặt index/alias trong search path**.

```http
GET /_search
{
  "size": 20,
  "pit": {
    "id": "<pit-id>",
    "keep_alive": "2m"
  },
  "query": {
    "match": {
      "name": "pixel"
    }
  },
  "sort": [
    {
      "_score": "desc"
    }
  ]
}
```

PIT thêm implicit `_shard_doc` tie-breaker. Response hit chứa sort values gồm cả
tie-breaker. Trang tiếp gửi lại toàn bộ:

```http
GET /_search
{
  "size": 20,
  "pit": {
    "id": "<latest-pit-id>",
    "keep_alive": "2m"
  },
  "query": {
    "match": {
      "name": "pixel"
    }
  },
  "sort": [
    {
      "_score": "desc"
    }
  ],
  "search_after": [
    7.2134,
    4294967298
  ]
}
```

Luôn dùng PIT ID mới nhất từ response nếu API trả ID cập nhật. Đóng khi xong:

```http
DELETE /_pit
{
  "id": "<latest-pit-id>"
}
```

PIT giữ old segments/file handles sống trong keep-alive. Không đặt keep-alive hàng
giờ cho mọi user; gia hạn vừa đủ từng request và đóng chủ động.

Scroll không còn được khuyến nghị cho deep user pagination. Với duyệt lượng lớn,
ưu tiên PIT + `search_after`; dùng Reindex API/helper khi mục tiêu là migration.

---

## 24. Total hits là một trade-off

Mặc định Elasticsearch đếm chính xác đến ngưỡng 10,000:

```json
{
  "total": {
    "value": 10000,
    "relation": "gte"
  }
}
```

Nghĩa là “ít nhất 10,000”, không phải đúng 10,000.

Exact count:

```json
{
  "track_total_hits": true
}
```

có thể tốn đáng kể và vô hiệu một số tối ưu bỏ qua non-competitive hit.

Các lựa chọn:

```json
{
  "track_total_hits": false
}
```

hoặc:

```json
{
  "track_total_hits": 5000
}
```

Product UI thường chỉ cần “hơn 1.000 kết quả”; reporting/audit mới cần exact. Đừng
trả exact count ở mọi keystroke autocomplete.

---

## 25. Trả đúng field, không trả cả document

### 25.1 Source filtering

```http
GET /products-read/_search
{
  "_source": [
    "product_id",
    "name",
    "price_minor",
    "currency"
  ],
  "query": {
    "match_all": {}
  }
}
```

Giảm network/serialization nhưng `_source` vẫn phải được đọc/decompress tùy trường
hợp.

### 25.2 `fields`/doc values

```http
GET /events-read/_search
{
  "_source": false,
  "fields": [
    "event_id",
    {
      "field": "@timestamp",
      "format": "strict_date_time"
    }
  ],
  "query": {
    "match_all": {}
  }
}
```

`fields` ưu tiên mapping/doc values và trả array semantics. `stored_fields` chỉ
trả field đã mapping `store: true`; nó không phải alias cho `_source`.

---

## 26. Highlight và suggestion

Highlight:

```http
GET /products-read/_search
{
  "query": {
    "match": {
      "description": "camera ban đêm"
    }
  },
  "highlight": {
    "pre_tags": [
      "<mark>"
    ],
    "post_tags": [
      "</mark>"
    ],
    "fields": {
      "description": {
        "fragment_size": 150,
        "number_of_fragments": 2
      }
    }
  }
}
```

Highlighter có thể re-analyze/load text và tăng fetch cost. Client phải render an
toàn, không coi highlight HTML từ dữ liệu người dùng là trusted.

Suggestion/autocomplete cần mapping riêng (`completion`, `search_as_you_type`,
ngram). Spell correction là gợi ý, không nên tự động thay query mà không đo
precision và cho người dùng biết.

---

## 27. Query, aggregation và `post_filter`

Top-level query giới hạn cả hits và aggregation:

```http
GET /products-read/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": {
        "term": {
          "category": "phone"
        }
      }
    }
  },
  "aggs": {
    "brands": {
      "terms": {
        "field": "brand"
      }
    }
  }
}
```

`post_filter` chỉ lọc hits sau khi aggregation đã tính. Nó hữu ích cho faceted
navigation khi muốn hiển thị bucket rộng hơn lựa chọn hiện tại:

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "filter": {
        "term": {
          "category": "phone"
        }
      }
    }
  },
  "aggs": {
    "all_brands": {
      "terms": {
        "field": "brand"
      }
    }
  },
  "post_filter": {
    "term": {
      "brand": "google"
    }
  }
}
```

Hits chỉ còn Google; `all_brands` vẫn thấy brand khác trong category phone.

`post_filter` không phải “filter nhanh hơn”; nếu aggregation cũng phải theo filter,
đặt điều kiện trong top-level query.

---

## 28. Collapse không phải group-by hoàn chỉnh

Lấy top hit mỗi `seller_id`:

```http
GET /offers-read/_search
{
  "query": {
    "match": {
      "title": "pixel"
    }
  },
  "collapse": {
    "field": "seller_id",
    "inner_hits": {
      "name": "other_offers",
      "size": 2,
      "sort": [
        {
          "price_minor": "asc"
        }
      ]
    }
  }
}
```

Collapse field phải single-valued keyword/numeric có doc values. Total hits vẫn là
số matching documents trước collapse; số group distinct không được trả chính xác
từ collapse. Nhiều `inner_hits` tạo thêm query và có thể rất chậm.

---

## 29. Named query để giải thích rule nào match

```http
GET /products-read/_search
{
  "query": {
    "bool": {
      "should": [
        {
          "term": {
            "brand": {
              "value": "google",
              "_name": "preferred_brand"
            }
          }
        },
        {
          "range": {
            "rating": {
              "gte": 4.5,
              "_name": "high_rating"
            }
          }
        }
      ],
      "minimum_should_match": 1
    }
  }
}
```

Mỗi hit có thể trả `matched_queries`. Tên phải unique; named query trong filter
vẫn có thể được báo match dù score của nó không đóng góp.

Hữu ích cho debug, A/B ranking và explain business rule, nhưng không thay relevance
evaluation.

---

## 30. Validate, explain và profile

### 30.1 Validate/rewrite

```http
GET /products-read/_validate/query?rewrite=true&all_shards=true
{
  "query": {
    "match": {
      "name": {
        "query": "pixle",
        "fuzziness": "AUTO"
      }
    }
  }
}
```

Cho biết syntax/mapping hợp lệ và query được rewrite ra sao.

### 30.2 Explain một document

```http
GET /products-read/_explain/p-101
{
  "query": {
    "match": {
      "name": "pixel"
    }
  }
}
```

Trả lời vì sao document này match/không match và score hình thành thế nào.

### 30.3 Profile execution

```http
GET /products-read/_search
{
  "profile": true,
  "query": {
    "match": {
      "name": "pixel"
    }
  }
}
```

Profile thêm overhead đáng kể, không dùng làm latency benchmark. Nó không đo đầy
đủ network, queue và coordinator merge; dùng để so cost tương đối của query tree
trên môi trường kiểm soát.

---

## 31. Cache mental model

### Node query cache

- chỉ query trong filter context mới eligible;
- Elasticsearch theo dõi tần suất để quyết định cache;
- cache theo segment và có thể mất khi merge;
- range với `now` thay đổi liên tục thường ít tái sử dụng.

### Shard request cache

Thường hữu ích cho request aggregation lặp lại, đặc biệt `size: 0`, khi index
không đổi. Request body khác hoặc refresh có thể làm miss/invalidate.

### Filesystem cache

Lucene dựa mạnh vào OS page cache; đây không phải Elasticsearch query-result cache
nhưng ảnh hưởng latency rất lớn.

Đừng tối ưu bằng cách “làm mọi thứ cacheable”. Đo cache hit, heap và workload.

---

## 32. Guardrail cho query do người dùng nhập

Không đưa raw search-box input vào `query_string` nếu người dùng không thực sự học
query syntax. `query_string` strict, ký tự đặc biệt có thể làm request lỗi và
wildcard/regexp có thể rất đắt.

Lựa chọn:

- `match`/`multi_match` cho search box thông thường;
- `simple_query_string` nếu cần cú pháp đơn giản nhưng bỏ qua syntax lỗi;
- `query_string` chỉ cho power user, với field/feature/length guardrail;
- explicit Query DSL builder từ filter đã validate.

Không mặc định search `*` field:

```json
{
  "fields": [
    "name^4",
    "description"
  ]
}
```

Giới hạn:

- query text length;
- clause count ở application;
- `terms` list size;
- wildcard/regexp/fuzzy use;
- result `size`, aggregation bucket và highlight field;
- timeout/concurrency/rate limit.

Elasticsearch có `search.allow_expensive_queries=false` để chặn một số fuzzy,
regexp, prefix, wildcard, join, script query... nhưng application vẫn cần guardrail.

---

## 33. Search consistency và partial results

### 33.1 Near real-time

Search chỉ thấy document sau refresh. GET theo ID có thể thấy sớm hơn. Nếu workflow
write rồi search ngay, dùng `refresh=wait_for`, GET hoặc application state; không
ép refresh cho mọi write.

### 33.2 Pagination khi dữ liệu thay đổi

Không PIT:

```text
page 1 → refresh/update/delete → page 2
```

có thể duplicate/missing vì score/sort thay đổi. PIT giữ index view ổn định nhưng
không làm query business immutable và không nên giữ vô hạn.

### 33.3 Shard failure và timeout

Response phải được kiểm tra:

```json
{
  "timed_out": false,
  "_shards": {
    "total": 12,
    "successful": 12,
    "skipped": 0,
    "failed": 0
  }
}
```

Một HTTP response có hits không mặc nhiên là complete. Với endpoint correctness
nhạy cảm, dùng:

```http
GET /products-read/_search?allow_partial_search_results=false
```

và vẫn kiểm tra `timed_out`, `_shards.failed`/failures. Timeout có thể cho partial
hoặc empty result tùy cách request kết thúc; client phải định nghĩa rõ retry/fallback
thay vì hiển thị “không có sản phẩm”.

### 33.4 Alias/version drift

Nếu alias switch giữa các trang mà không PIT, mapping/analyzer/corpus có thể đổi.
Cursor token nên gắn query version, sort và PIT/state phù hợp; không nhận cursor
cũ với query builder mới.

---

## 34. E-commerce search hoàn chỉnh

```http
GET /products-read/_search?allow_partial_search_results=false
{
  "size": 20,
  "track_total_hits": 5000,
  "_source": [
    "product_id",
    "name",
    "price_minor",
    "currency",
    "brand"
  ],
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "điện thoại pixel pro",
            "fields": [
              "name^4",
              "name.folded^1.5",
              "description"
            ],
            "type": "best_fields",
            "minimum_should_match": "70%"
          }
        }
      ],
      "filter": [
        {
          "term": {
            "category": "phone"
          }
        },
        {
          "term": {
            "in_stock": true
          }
        },
        {
          "range": {
            "price_minor": {
              "gte": 10000000,
              "lt": 30000000
            }
          }
        }
      ],
      "must_not": [
        {
          "term": {
            "status": "discontinued"
          }
        }
      ],
      "should": [
        {
          "term": {
            "brand": {
              "value": "google",
              "boost": 1.3,
              "_name": "preferred_brand"
            }
          }
        }
      ]
    }
  },
  "sort": [
    {
      "_score": "desc"
    },
    {
      "product_id": "asc"
    }
  ],
  "highlight": {
    "fields": {
      "name": {
        "number_of_fragments": 0
      }
    }
  },
  "aggs": {
    "brands": {
      "terms": {
        "field": "brand",
        "size": 20
      }
    }
  }
}
```

Search contract cần ghi rõ:

- query version và field boosts;
- filter semantics;
- total-hit accuracy;
- sort/tie-breaker;
- partial-result behavior;
- SLA latency;
- fallback khi search timeout/unavailable.

---

## 35. Failure modes thường gặp

### 35.1 `term` trên `text` không trả kết quả

`term` không analyze input trong khi text đã được lowercase/tokenize/stem. Dùng
`match` hoặc query `keyword` subfield đúng semantics.

### 35.2 `should` bỗng trở thành optional

Query builder thêm `filter`, default `minimum_should_match` đổi từ 1 thành 0. Khai
báo explicit và test truth table.

### 35.3 Filter chính xác nhưng relevance tệ

Analyzer/field boost/query intent sai; đừng sửa bằng popularity boost ngày càng
lớn. Dùng explain + relevance judgments.

### 35.4 Fuzzy/wildcard làm p99 tăng

Term expansion quá lớn, đặc biệt leading wildcard và từ điển high-cardinality.
Giới hạn input, mapping chuyên biệt và expensive-query guardrail.

### 35.5 Trang có duplicate hoặc thiếu hit

Sort không unique hoặc refresh xảy ra giữa request. Dùng unique tie-breaker; PIT
+ `search_after` khi cần stable view.

### 35.6 Sort bằng `_id`

`_id` không có doc values cho sort/aggregation. Copy business/document ID vào
`keyword` field.

### 35.7 Exact total làm query chậm

`track_total_hits: true` buộc đếm toàn bộ và mất early-termination optimization.
Chỉ bật cho use case cần exact.

### 35.8 HTTP 200 nhưng kết quả thiếu

Một số shard failure hoặc timeout trả partial result. Kiểm tra response metadata
và đặt `allow_partial_search_results=false` khi phù hợp.

### 35.9 `post_filter` làm facet “không khớp”

Đây có thể là chủ đích: post filter không ảnh hưởng aggregation. Nếu muốn cùng
scope, đưa filter vào top-level query.

### 35.10 Script score thống trị cluster

Script chạy trên quá nhiều candidate. Filter/retrieve trước, rescore top window,
dùng rank_feature/native function và benchmark.

### 35.11 Hybrid trả tài liệu sai tenant

ACL filter chỉ áp lexical branch nhưng quên semantic branch. Security filter phải
được áp trong mọi retriever hoặc tầng enforcement không thể bypass.

---

## 36. Checklist thiết kế

### Correctness

- [ ] Mapping/analyzer của mọi field đã được xác nhận?
- [ ] Full-text dùng `match`; exact term dùng field phù hợp?
- [ ] Eligibility nằm trong filter, relevance nằm trong scoring clause?
- [ ] `minimum_should_match` được khai báo khi business phụ thuộc?
- [ ] Nested bool phản ánh đúng ngoặc logic?
- [ ] Missing/null/blank semantics không suy luận sai từ `exists`?

### Ranking

- [ ] Có query set và relevance judgments?
- [ ] Boost được đo, không chỉnh theo một ví dụ?
- [ ] Popularity/freshness có saturation/decay?
- [ ] Expensive ranking chỉ chạy trên candidate window?
- [ ] Hybrid filter/ACL áp cho mọi branch?

### Pagination

- [ ] Trang nông dùng `from/size`; trang sâu dùng `search_after`?
- [ ] Sort có tie-breaker unique có doc values?
- [ ] Stable view dùng PIT và đóng PIT?
- [ ] Cursor gắn query/sort/version?
- [ ] Total-hit accuracy được chọn có chủ đích?

### Safety

- [ ] Không nhận raw `query_string` không kiểm soát?
- [ ] Có giới hạn wildcard/fuzzy/regexp/terms/size/highlight?
- [ ] Client kiểm tra `timed_out` và shard failures?
- [ ] Correctness endpoint có partial-result policy?
- [ ] Query cancellation/timeout/rate limit/concurrency rõ ràng?

### Debugging

- [ ] Có named clauses cho rule quan trọng?
- [ ] Biết dùng `_analyze`, validate, explain và profile?
- [ ] Profile không bị dùng như latency benchmark?
- [ ] Search log lưu query template/version, không lộ dữ liệu nhạy cảm?

---

## 37. Câu hỏi phỏng vấn

### Cơ bản

1. Query context và filter context khác nhau thế nào?
2. `match` và `term` khác nhau ra sao?
3. `must`, `filter`, `should`, `must_not` làm gì?
4. Vì sao `exists` không đồng nghĩa `_source` có key?

### Trung cấp

1. Default `minimum_should_match` thay đổi khi nào?
2. `from/size`, `search_after` và PIT khác nhau thế nào?
3. Vì sao không dùng `_id` làm sort tie-breaker?
4. `post_filter` ảnh hưởng hits và aggregation ra sao?
5. Explain và Profile API giải quyết hai câu hỏi khác nhau nào?

### Nâng cao

1. Thiết kế hai-stage retrieval/rescore như thế nào?
2. Làm sao kết hợp lexical và semantic score không cùng thang đo?
3. Tại sao score có thể khác giữa shard/replica hoặc sau refresh?
4. Làm sao bảo đảm tenant/ACL filter không bị bypass trong hybrid search?
5. Thiết kế cursor contract sống qua alias migration ra sao?
6. Khi nào exact total hits đáng chi phí?

---

## 38. Nguồn và chủ đề tiếp theo

Tài liệu chính thức:

- [Query DSL](https://www.elastic.co/docs/reference/query-languages/querydsl)
- [Query and filter context](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-filter-context)
- [Boolean query](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-bool-query)
- [Match query](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-match-query)
- [Term query](https://www.elastic.co/docs/reference/query-languages/query-dsl/query-dsl-term-query)
- [Paginate search results](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/paginate-search-results)
- [Track total hits](https://www.elastic.co/docs/solutions/search/the-search-api)
- [Filter search results](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/filter-search-results)
- [Rescore](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/rescore-search-results)
- [Retrievers](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/retrievers)
- [Hybrid search](https://www.elastic.co/docs/solutions/search/hybrid-search)
- [Troubleshoot searches](https://www.elastic.co/docs/troubleshoot/elasticsearch/troubleshooting-searches)
- [Node query cache](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/node-query-cache-settings)

Học tiếp:

1. [Aggregations](../advanced/aggregations.md) – bucket, metric, pipeline và
   distributed accuracy.
2. [Indexing & Mapping](indexing_mapping.md) – term/analyzer/doc values tạo nền
   cho query.
3. [Performance](../performance/optimization.md) – benchmark và profile theo
   workload thật.
4. [Cluster Management](../operations/cluster_management.md) – partial failure,
   recovery và production operations.

---

*Cập nhật lần cuối: 2026-07-31.*
