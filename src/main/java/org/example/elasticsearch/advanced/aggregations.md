# Elasticsearch Aggregations – phân tích phân tán có kiểm soát sai số

> Aggregation có thể trả một con số rất “đẹp” nhưng không phù hợp để ra quyết định:
> top terms có thể thiếu candidate từ shard, cardinality và percentiles là xấp xỉ,
> pipeline chạy sau khi toàn bộ bucket đã được tạo, còn shard timeout có thể làm
> response chỉ là một phần dữ liệu. Vì vậy phải hiểu cả phép tính lẫn execution
> model phân tán.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Một số aggregation,
downsampling, transform và cache behavior phụ thuộc deployment hoặc license.

---

## 1. Aggregation giải quyết bài toán gì?

Aggregation biến tập document match thành:

- metric: tổng, trung bình, min/max, percentile, distinct estimate;
- bucket: nhóm theo category, thời gian, khoảng giá, geo;
- pipeline: tính tiếp từ output của aggregation khác;
- sample/top document cho mỗi bucket.

```text
query/filter scope
       │
       ▼
matching documents
       │
       ├──► metric aggregation
       │
       └──► bucket aggregation
                 │
                 ├──► sub-aggregation
                 └──► pipeline aggregation
```

Nó giống `GROUP BY`/analytic function về ý tưởng, nhưng khác database báo cáo:

- dữ liệu near real-time, không transaction snapshot mặc định;
- mỗi shard tính cục bộ rồi coordinator reduce;
- một số phép tính có sai số chủ đích;
- bucket tree có thể dùng nhiều heap;
- search response có thể partial nếu policy cho phép.

Elasticsearch phù hợp dashboard/search analytics. Hóa đơn, sổ cái và báo cáo pháp
lý cần nguồn có consistency/decimal/audit contract riêng.

---

## 2. Cấu trúc request cơ bản

Giả sử `orders-read` có một document cho mỗi order:

| Field | Mapping |
|---|---|
| `order_id`, `customer_id` | `keyword` |
| `status`, `channel`, `payment_method`, `region`, `currency` | `keyword` |
| `amount_minor` | `long` |
| `@timestamp` | `date` |
| `items` | `nested` |
| `items.product_id`, `items.category` | `keyword` |
| `items.line_amount_minor` | `long` |

Request:

```http
GET /orders-read/_search?allow_partial_search_results=false
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        {
          "term": {
            "status": "completed"
          }
        },
        {
          "range": {
            "@timestamp": {
              "gte": "now-30d/d",
              "lt": "now/d",
              "time_zone": "Asia/Bangkok"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "revenue": {
      "sum": {
        "field": "amount_minor"
      }
    },
    "by_channel": {
      "terms": {
        "field": "channel",
        "size": 10
      },
      "aggs": {
        "channel_revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

- `size: 0`: không trả search hits.
- Top-level query giới hạn document cho **mọi** aggregation.
- `by_channel` tạo bucket.
- `channel_revenue` chạy riêng trong từng bucket.

---

## 3. Aggregation tree và tích số bucket

```text
by_region: 20 buckets
  └── by_channel: 10 buckets/region
        └── by_day: 30 buckets/channel

20 × 10 × 30 = 6,000 bucket
```

Nếu thêm 100 product:

```text
20 × 10 × 30 × 100 = 600,000 bucket
```

Mỗi bucket còn giữ metric/sub-aggregation state. `search.max_buckets` bảo vệ
cluster bằng cách từ chối response có quá nhiều bucket; tăng limit không làm phép
tính tự nhiên rẻ hơn.

Thiết kế từ câu hỏi business:

- Có thật sự cần mọi tổ hợp?
- Có thể filter scope trước?
- Có thể query từng dimension khi user drill-down?
- Có thể materialize bằng transform/downsampling?
- Có cần top-N hay cần enumerate tất cả?

---

## 4. Execution model: map trên shard, reduce ở coordinator

```text
Shard A ── local buckets/metrics ─┐
Shard B ── local buckets/metrics ─┼──► coordinating reduce ──► response
Shard C ── local buckets/metrics ─┘
```

Hệ quả:

1. Metric đơn giản có thể reduce chính xác về logic nhưng vẫn chịu floating-point
   precision và partial-shard risk.
2. Top-N cần shard gửi candidate; candidate bị bỏ ở shard không thể được coordinator
   “đoán lại”.
3. Cardinality/percentile dùng sketch/approximation để giảm memory.
4. Coordinator cần heap để merge bucket từ mọi shard.
5. Slowest shard ảnh hưởng tail latency.

Aggregation result chỉ có ý nghĩa nếu response complete:

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

---

## 5. Mapping quyết định aggregation có chạy được không

Aggregation thường đọc `doc_values`:

| Field | Aggregate trực tiếp? | Ghi chú |
|---|---:|---|
| `keyword` | Có | Terms, cardinality, sort |
| Numeric | Có | Sum, avg, stats, histogram |
| Date | Có | Date histogram, min/max |
| Boolean/IP/geo | Tùy aggregation | Có doc values/cấu trúc chuyên biệt |
| `text` | Không mặc định | Dùng keyword subfield |
| Runtime field | Có thể | Linh hoạt nhưng tốn query-time CPU |

Sai:

```json
{
  "terms": {
    "field": "product_name"
  }
}
```

nếu `product_name` là `text`.

Đúng khi mapping có multi-field:

```json
{
  "terms": {
    "field": "product_name.keyword"
  }
}
```

Không bật `fielddata` trên text chỉ để dashboard chạy; nó có thể dùng heap lớn và
semantics token không giống “tên sản phẩm”.

---

## 6. Metric aggregation cơ bản

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "revenue": {
      "sum": {
        "field": "amount_minor"
      }
    },
    "average_order": {
      "avg": {
        "field": "amount_minor"
      }
    },
    "smallest_order": {
      "min": {
        "field": "amount_minor"
      }
    },
    "largest_order": {
      "max": {
        "field": "amount_minor"
      }
    },
    "amount_stats": {
      "stats": {
        "field": "amount_minor"
      }
    },
    "amount_extended_stats": {
      "extended_stats": {
        "field": "amount_minor",
        "sigma": 2
      }
    }
  }
}
```

`stats` trả `count`, `min`, `max`, `avg`, `sum`. `extended_stats` thêm variance,
standard deviation và bounds; thống kê này không tự kiểm tra distribution có phù
hợp giả định hay không.

### 6.1 Multi-valued field

Với:

```json
{
  "scores": [
    2,
    5,
    8
  ]
}
```

`sum(scores)` cộng cả ba value, `value_count(scores)` trả 3. Nó không mặc nhiên
chọn một giá trị cho mỗi document.

### 6.2 Missing

Metric thường bỏ document thiếu field. `missing` có thể thay bằng giá trị giả:

```json
{
  "avg": {
    "field": "amount_minor",
    "missing": 0
  }
}
```

Việc coi missing là zero là business decision, không phải tối ưu kỹ thuật.

---

## 7. `value_count` không phải luôn là số document

```json
{
  "value_count": {
    "field": "order_id"
  }
}
```

Nó đếm số **value** được trích từ field và không deduplicate.

- Một document có một `order_id`: thường bằng document count.
- Field multi-valued: có thể lớn hơn document count.
- Document thiếu field: không được đếm.
- Duplicate order documents: vẫn đếm duplicate.

Nếu một document đúng bằng một order và query scope đã đúng, bucket `doc_count`
hoặc `hits.total` diễn đạt số order rõ hơn. Nếu index chứa event, muốn distinct
order phải dùng cardinality xấp xỉ hoặc materialize một document/order.

---

## 8. Cardinality là ước lượng distinct

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "unique_customers": {
      "cardinality": {
        "field": "customer_id",
        "precision_threshold": 10000
      }
    }
  }
}
```

Cardinality dùng HyperLogLog++:

- memory gần như cố định theo precision threshold;
- threshold tối đa có ý nghĩa là 40,000;
- dưới threshold thường gần chính xác, **không được hứa exact**;
- trên threshold vẫn trả estimate với sai số.

Tăng threshold:

```text
accuracy thường tăng
memory mỗi cardinality state tăng
× số bucket cha
× số shard/concurrent request
```

Một cardinality trong 20,000 tenant bucket nguy hiểm hơn cardinality top-level.

Muốn exact distinct cho billing/audit:

- materialize unique entity;
- dùng database/warehouse có contract exact;
- hoặc enumerate key bằng composite rồi đếm ở workflow kiểm soát, nếu scale cho phép.

---

## 9. Percentiles cũng là xấp xỉ

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "amount_percentiles": {
      "percentiles": {
        "field": "amount_minor",
        "percents": [
          50,
          90,
          95,
          99
        ],
        "tdigest": {
          "compression": 200
        }
      }
    },
    "amount_percentile_ranks": {
      "percentile_ranks": {
        "field": "amount_minor",
        "values": [
          10000000,
          20000000
        ]
      }
    }
  }
}
```

- Percentile: “p95 có value khoảng bao nhiêu?”
- Percentile rank: “bao nhiêu phần trăm value ≤ ngưỡng này?”

T-Digest/HDR trade memory với accuracy; tail percentile và ít sample dễ dao động.
Đừng so p99 giữa hai dashboard nếu algorithm/config/window khác nhau.

---

## 10. `top_hits` và `top_metrics`

### 10.1 `top_hits`

Lấy document đại diện trong mỗi bucket:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "by_customer": {
      "terms": {
        "field": "customer_id",
        "size": 100
      },
      "aggs": {
        "latest_order": {
          "top_hits": {
            "size": 1,
            "sort": [
              {
                "@timestamp": "desc"
              }
            ],
            "_source": [
              "order_id",
              "@timestamp",
              "amount_minor"
            ]
          }
        }
      }
    }
  }
}
```

`top_hits` chạy fetch/highlight/source features và rất đắt khi nhân với nhiều
bucket. Không dùng top-level `top_hits`; search hits thường đã giải quyết việc đó.

### 10.2 `top_metrics`

Nếu chỉ cần vài metric/doc-value của document đầu theo sort, `top_metrics` nhẹ hơn:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "by_customer": {
      "terms": {
        "field": "customer_id",
        "size": 100
      },
      "aggs": {
        "latest_amount": {
          "top_metrics": {
            "metrics": {
              "field": "amount_minor"
            },
            "sort": {
              "@timestamp": "desc"
            }
          }
        }
      }
    }
  }
}
```

Chọn theo output cần thiết, không theo tên “top”.

---

## 11. `terms`: top-N chứ không phải enumerate tất cả

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "top_channels": {
      "terms": {
        "field": "channel",
        "size": 10,
        "shard_size": 50,
        "order": {
          "_count": "desc"
        },
        "show_term_doc_count_error": true
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

Mỗi shard gửi candidate buckets cho coordinator. Mặc định `shard_size` được tính
xấp xỉ từ `size` (`size * 1.5 + 10`). Tăng `shard_size` thường rẻ hơn tăng `size`
vì response cuối vẫn chỉ giữ top `size`, nhưng shard/coordinator vẫn dùng thêm
network và memory.

Response quan trọng:

```json
{
  "doc_count_error_upper_bound": 17,
  "sum_other_doc_count": 8421
}
```

- `sum_other_doc_count > 0`: có document thuộc bucket không được trả.
- `doc_count_error_upper_bound`: upper bound sai số count trong trường hợp hỗ trợ.
- Per-bucket error chỉ xuất hiện khi yêu cầu và không phải lúc nào cũng tính được.

---

## 12. Tại sao top terms có thể sai?

Tìm top 2 toàn cluster:

```text
Shard A local top 2: apple=100, samsung=90
Shard B local top 2: xiaomi=100, oppo=90

google=80 ở cả A và B
→ global google=160 đáng ra top 1
→ nhưng không shard nào gửi google nếu shard_size chỉ 2
→ coordinator không biết google tồn tại
```

Tăng `shard_size` làm giảm nguy cơ, không biến mọi order thành exact.

### 12.1 Thứ tự an toàn và nguy hiểm

| Order | Tính chất |
|---|---|
| `_count desc` | Mặc định, có thể có bounded count error |
| `_key asc/desc` | Count của bucket trả về có thể xác định chính xác hơn |
| `_count asc` | Rất dễ sai; dùng `rare_terms` |
| Sub-aggregation `max desc` | Một trong số ít trường hợp có lập luận an toàn |
| Sub-aggregation `min asc` | Một trong số ít trường hợp có lập luận an toàn |
| `sum/avg desc`, `min desc`, `max asc` | Top-N có thể sai không có bound hữu ích |

Ví dụ “top category theo revenue” bằng:

```json
{
  "order": {
    "revenue": "desc"
  }
}
```

có thể chọn sai category toàn cục. Tăng `shard_size` giúp thực nghiệm nhưng không
tạo guarantee. Với báo cáo quan trọng, enumerate bằng composite/transform/warehouse
rồi sort trên tập đầy đủ.

Sai số `doc_count` còn truyền xuống sub-aggregation: nếu bucket thiếu document,
`sum`, `avg`, top hits bên trong cũng tính trên tập thiếu.

---

## 13. `rare_terms` và `significant_terms`

### 13.1 Rare terms

Không dùng `terms` với `_count asc` để tìm giá trị hiếm:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "rare_payment_methods": {
      "rare_terms": {
        "field": "payment_method",
        "max_doc_count": 10
      }
    }
  }
}
```

### 13.2 Significant terms

Tìm term xuất hiện bất thường trong foreground so với background:

```http
GET /orders-read/_search
{
  "size": 0,
  "query": {
    "term": {
      "region": "apac"
    }
  },
  "aggs": {
    "unusual_payment_methods": {
      "significant_terms": {
        "field": "payment_method"
      }
    }
  }
}
```

“Significant” không đồng nghĩa phổ biến nhất. Kết quả phụ thuộc foreground,
background và heuristic; cần sample size đủ và giải thích business.

---

## 14. Date histogram: calendar khác fixed interval

Calendar interval:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "day",
        "time_zone": "Asia/Bangkok",
        "min_doc_count": 0,
        "extended_bounds": {
          "min": "now-30d/d",
          "max": "now/d"
        }
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

Fixed interval:

```json
{
  "date_histogram": {
    "field": "@timestamp",
    "fixed_interval": "24h"
  }
}
```

Khác nhau:

| Calendar | Fixed |
|---|---|
| Theo calendar/time zone | Theo duration cố định |
| Day có thể 23/25 giờ vì DST | `24h` luôn duration 24 giờ |
| Month dài khác nhau | Không có “fixed month” tự nhiên |
| Hợp báo cáo ngày/tháng địa phương | Hợp window kỹ thuật cố định |

`time_zone` ảnh hưởng bucket boundary. Cùng event có thể nằm ở ngày khác nếu
dashboard đổi zone.

### 14.1 `extended_bounds` không filter dữ liệu

Nó yêu cầu tạo thêm empty buckets đến bounds, không loại document bên ngoài. Muốn
giới hạn scope, dùng top-level range query. `hard_bounds` có thể chặn bucket ngoài
biên nhưng cũng không thay business filter một cách ngầm định.

---

## 15. Histogram, range và auto date histogram

Numeric histogram:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "amount_distribution": {
      "histogram": {
        "field": "amount_minor",
        "interval": 5000000,
        "min_doc_count": 0,
        "extended_bounds": {
          "min": 0,
          "max": 50000000
        }
      }
    }
  }
}
```

Explicit ranges:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "amount_ranges": {
      "range": {
        "field": "amount_minor",
        "keyed": true,
        "ranges": [
          {
            "key": "budget",
            "to": 10000000
          },
          {
            "key": "mid",
            "from": 10000000,
            "to": 30000000
          },
          {
            "key": "premium",
            "from": 30000000
          }
        ]
      }
    }
  }
}
```

Auto date histogram chọn interval để gần target bucket count:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "timeline": {
      "auto_date_histogram": {
        "field": "@timestamp",
        "buckets": 30,
        "time_zone": "Asia/Bangkok"
      }
    }
  }
}
```

Phù hợp UI zoom linh hoạt; không phù hợp API contract cần interval ổn định giữa
các request.

---

## 16. Filter scope, filter aggregation, `post_filter` và global

### 16.1 Top-level query

Giới hạn tất cả aggregation và thường hiệu quả nhất:

```json
{
  "query": {
    "term": {
      "status": "completed"
    }
  }
}
```

### 16.2 Filter aggregation

So sánh subset trong cùng request:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "all_revenue": {
      "sum": {
        "field": "amount_minor"
      }
    },
    "mobile": {
      "filter": {
        "term": {
          "channel": "mobile"
        }
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

Nhiều filter song song dùng `filters` aggregation thay vì nhiều filter aggregation
rời nếu phù hợp.

### 16.3 `post_filter`

Lọc hits sau khi aggregation tính. Nó không thay aggregation scope; xem
[Query DSL §27](../fundamentals/query_dsl.md).

### 16.4 Global aggregation

`global` bỏ qua top-level query để tính trên toàn search execution context. Nó hữu
ích so subset với toàn bộ nhưng dễ lộ/đếm dữ liệu ngoài tenant filter nếu dùng sai.
Security/tenant enforcement không được dựa vào một query clause mà global có thể
bỏ qua; enforcement phải ở tầng không bypass.

---

## 17. Nested và reverse nested

Aggregate item category trong order documents:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "items_scope": {
      "nested": {
        "path": "items"
      },
      "aggs": {
        "by_category": {
          "terms": {
            "field": "items.category",
            "size": 20
          },
          "aggs": {
            "item_revenue": {
              "sum": {
                "field": "items.line_amount_minor"
              }
            },
            "back_to_orders": {
              "reverse_nested": {},
              "aggs": {
                "unique_customers": {
                  "cardinality": {
                    "field": "customer_id"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Trong nested scope:

- `doc_count` là số nested item, không phải số root order;
- root field không aggregate trực tiếp nếu chưa `reverse_nested`;
- một order có nhiều item cùng category có thể xuất hiện nhiều nested docs;
- nested × cardinality × nhiều bucket có thể rất tốn memory.

Nếu dashboard chủ yếu theo line item, index riêng một document/line item đôi khi
đơn giản hơn nested tree.

---

## 18. Nhiều key: `multi_terms` hay `composite`?

### `multi_terms`

Trả top-N tổ hợp theo behavior gần `terms`:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "top_region_channel": {
      "multi_terms": {
        "terms": [
          {
            "field": "region"
          },
          {
            "field": "channel"
          }
        ],
        "size": 20
      }
    }
  }
}
```

### `composite`

Page qua tất cả unique key combinations theo key order:

```text
terms/multi_terms → top-N dashboard
composite         → enumerate/export/transform workflow
```

Nếu thường xuyên aggregate cùng một compound key, có thể index một combined
keyword field để giảm overhead, sau benchmark.

---

## 19. Composite aggregation và `after_key`

Trang đầu:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "groups": {
      "composite": {
        "size": 500,
        "sources": [
          {
            "region": {
              "terms": {
                "field": "region",
                "order": "asc"
              }
            }
          },
          {
            "channel": {
              "terms": {
                "field": "channel",
                "order": "asc"
              }
            }
          },
          {
            "day": {
              "date_histogram": {
                "field": "@timestamp",
                "calendar_interval": "day",
                "order": "asc"
              }
            }
          }
        ]
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

Response:

```json
{
  "after_key": {
    "region": "emea",
    "channel": "web",
    "day": 1785456000000
  },
  "buckets": []
}
```

Trang tiếp phải dùng **đúng `after_key` từ response**, không tự lấy key bucket
cuối:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "groups": {
      "composite": {
        "size": 500,
        "after": {
          "region": "emea",
          "channel": "web",
          "day": 1785456000000
        },
        "sources": [
          {
            "region": {
              "terms": {
                "field": "region",
                "order": "asc"
              }
            }
          },
          {
            "channel": {
              "terms": {
                "field": "channel",
                "order": "asc"
              }
            }
          },
          {
            "day": {
              "date_histogram": {
                "field": "@timestamp",
                "calendar_interval": "day",
                "order": "asc"
              }
            }
          }
        ]
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

Composite:

- enumerate bucket theo source key, không sort toàn bộ theo sub-aggregation metric;
- có thể đắt, cần page size và load test;
- page qua index đang refresh có thể thay đổi kết quả; cân nhắc PIT/stable source
  cho export có consistency requirement;
- metric con như cardinality/percentile vẫn giữ tính xấp xỉ của chính nó;
- index sort cùng prefix/order của composite sources có thể hỗ trợ early termination.

---

## 20. Pipeline aggregation chạy trên output, không đọc document

Hai nhóm:

```text
Parent pipeline
  chạy trong từng bucket của parent
  moving_fn, derivative, cumulative_sum, bucket_script,
  bucket_selector, bucket_sort

Sibling pipeline
  chạy cạnh multi-bucket aggregation
  avg_bucket, sum_bucket, min_bucket, max_bucket, stats_bucket
```

`buckets_path` trỏ tới metric:

```text
daily>revenue
```

Pipeline không tạo lại document scope. Nếu metric đầu vào sai/approximate/partial,
pipeline chỉ tính tiếp trên dữ liệu đó.

---

## 21. Bucket script và sibling pipeline

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "day",
        "time_zone": "Asia/Bangkok",
        "min_doc_count": 0
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        },
        "orders": {
          "value_count": {
            "field": "order_id"
          }
        },
        "average_order": {
          "bucket_script": {
            "buckets_path": {
              "revenue": "revenue",
              "orders": "orders"
            },
            "script": "params.orders > 0 ? params.revenue / params.orders : null"
          }
        }
      }
    },
    "average_daily_revenue": {
      "avg_bucket": {
        "buckets_path": "daily>revenue"
      }
    },
    "largest_day": {
      "max_bucket": {
        "buckets_path": "daily>revenue"
      }
    }
  }
}
```

Nếu một order có đúng một `order_id`, `value_count` phù hợp ví dụ. Nếu không, mẫu
số phải được model lại.

---

## 22. Moving function, derivative và cumulative sum

`moving_avg` cũ đã bị loại bỏ; dùng `moving_fn`:

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "day",
        "time_zone": "Asia/Bangkok",
        "min_doc_count": 0
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        },
        "revenue_7d_average": {
          "moving_fn": {
            "buckets_path": "revenue",
            "window": 7,
            "script": "MovingFunctions.unweightedAvg(values)"
          }
        },
        "daily_change": {
          "derivative": {
            "buckets_path": "revenue",
            "unit": "day"
          }
        },
        "cumulative_revenue": {
          "cumulative_sum": {
            "buckets_path": "revenue"
          }
        }
      }
    }
  }
}
```

Sequential pipeline cần ordered histogram và thường cần `min_doc_count: 0`.
Business phải quyết định empty day là zero hay missing; kết quả moving/derivative
khác nhau.

---

## 23. `bucket_sort` và `bucket_selector` không tiết kiệm upstream work

```http
GET /orders-read/_search
{
  "size": 0,
  "aggs": {
    "channels": {
      "terms": {
        "field": "channel",
        "size": 100
      },
      "aggs": {
        "revenue": {
          "sum": {
            "field": "amount_minor"
          }
        },
        "keep_large": {
          "bucket_selector": {
            "buckets_path": {
              "revenue": "revenue"
            },
            "script": "params.revenue >= 100000000"
          }
        },
        "sort_result": {
          "bucket_sort": {
            "sort": [
              {
                "revenue": {
                  "order": "desc"
                }
              }
            ],
            "size": 10
          }
        }
      }
    }
  }
}
```

Execution:

```text
terms tạo tối đa 100 bucket candidate/result
→ revenue tính cho bucket
→ selector loại
→ bucket_sort sắp phần còn lại và giữ 10
```

Nó **không** tìm top 10 revenue trong mọi possible channel nếu parent terms đã
loại candidate theo doc count. Nó cũng không giảm memory/CPU đã dùng để tạo 100
bucket.

Muốn giảm work phải filter document sớm, giảm parent bucket cardinality, đổi data
model hoặc materialize.

---

## 24. Gap policy và empty bucket semantics

Pipeline gặp missing metric/bucket cần `gap_policy` phù hợp:

```json
{
  "derivative": {
    "buckets_path": "revenue",
    "gap_policy": "insert_zeros"
  }
}
```

Nhưng zero và missing khác business:

- cửa hàng đóng cửa: zero revenue có thể đúng;
- pipeline ingest chậm: zero là sai;
- metric không áp dụng: missing/null hợp lý.

Đừng dùng `insert_zeros` chỉ để chart liền. Theo dõi data completeness riêng.

---

## 25. Runtime field và script aggregation

Runtime mapping:

```http
GET /orders-read/_search
{
  "size": 0,
  "runtime_mappings": {
    "amount_band": {
      "type": "keyword",
      "script": {
        "source": "long v = doc['amount_minor'].value; emit(v < 10000000 ? 'budget' : v < 30000000 ? 'mid' : 'premium')"
      }
    }
  },
  "aggs": {
    "by_band": {
      "terms": {
        "field": "amount_band"
      }
    }
  }
}
```

Hữu ích thử nghiệm hoặc migration, nhưng script chạy query time trên nhiều document.
Nếu dashboard gọi liên tục, materialize `amount_band` khi ingest thường nhanh và
dễ kiểm soát hơn.

Script phải xử lý missing/multi-value và dùng params/stored script khi phù hợp.
Scripted metric linh hoạt nhất nhưng khó tối ưu, khó audit và có thể bị chặn bởi
security/search settings.

---

## 26. Tiền và độ chính xác số

Mapping money bằng `long` minor units tốt hơn floating input, nhưng aggregation
response vẫn chịu representation/reduction floating point của metric. Số nguyên
rất lớn có thể mất precision khi chuyển sang double.

```text
Elasticsearch revenue dashboard:
  gần real-time, search/filter linh hoạt

Billing/accounting ledger:
  decimal/integer exact, transaction, correction, audit trail
```

Không dùng `sum(amount_minor)` trên search index làm nguồn duy nhất để phát hành
hóa đơn. Reconcile với ledger/source of truth; ghi rõ currency, refund, tax, status
và event cutoff.

Không cộng nhiều currency trong cùng metric:

```text
100 USD + 100 EUR ≠ 200 "revenue"
```

Bucket theo currency hoặc quy đổi bằng rate/version ở domain pipeline có audit.

---

## 27. Bucket memory và circuit breaker

Risk tăng theo:

```text
number of shards
× parent buckets
× child buckets
× metric state per bucket
× concurrent requests
```

Cardinality/percentile/top_hits/script state làm mỗi bucket nặng hơn.

Guardrail:

- top-level filter giảm document scope;
- `size: 0` nếu không cần hits;
- giới hạn terms/composite page size;
- tránh bucket tree do user tự chọn vô hạn;
- giới hạn date range/interval;
- dùng `search.max_buckets` như safety rail;
- rate limit/concurrency limit dashboard;
- theo dõi breaker/rejection/GC/coordinator heap.

Circuit breaker dựa trên estimate; không phải guarantee không OOM. Đừng tăng breaker
limit trước khi biết aggregation tree nào tạo pressure.

---

## 28. Global ordinals

Terms aggregation trên keyword có thể dùng global ordinals:

```text
term string → per-segment ordinal → global ordinal
```

Mặc định ordinals thường được dựng lazy khi cần sau refresh. `eager_global_ordinals`
có thể chuyển chi phí sang refresh:

```json
{
  "type": "keyword",
  "eager_global_ordinals": true
}
```

Phù hợp field thường xuyên terms aggregate và refresh/query latency yêu cầu ổn
định. Trade-off:

- refresh chậm hơn;
- thêm memory;
- mapping high-cardinality/ít query không đáng.

Đo refresh time và first-query latency trước/sau.

---

## 29. Request cache

Shard request cache thường hữu ích cho dashboard `size: 0` lặp lại khi shard không
đổi. Cache key phụ thuộc request và shard state:

- refresh làm entry liên quan cũ đi;
- request có `now`/script không deterministic khó tái sử dụng;
- đổi JSON/query/parameter làm key khác;
- time-series shard cũ read-only có cache hit tốt hơn hot shard.

Không bật `request_cache: true` như cách chữa query chậm mà không đo:

```http
GET /orders-read/_search?request_cache=true
{
  "size": 0,
  "query": {
    "range": {
      "@timestamp": {
        "gte": "2026-07-01T00:00:00Z",
        "lt": "2026-08-01T00:00:00Z"
      }
    }
  },
  "aggs": {
    "revenue": {
      "sum": {
        "field": "amount_minor"
      }
    }
  }
}
```

Absolute range tạo request ổn định hơn `now-30d` đổi liên tục.

---

## 30. Độ chính xác theo aggregation

| Kết quả | Tính chất mặc định | Cần kiểm tra |
|---|---|---|
| `sum`/`avg`/`min`/`max` | Reduce trên matched values | Floating precision, partial shards, missing |
| `value_count` | Đếm values | Multi-value, missing, duplicate documents |
| `terms` top `_count desc` | Candidate-based, có thể sai count/order | Error bound, `sum_other_doc_count`, shard size |
| `terms` ordered by arbitrary metric | Có thể chọn sai top-N | Không có bound hữu ích |
| `rare_terms` | Thiết kế tìm term hiếm | Threshold/sample/distribution |
| `cardinality` | Xấp xỉ HLL++ | Precision threshold, memory |
| `percentiles` | Xấp xỉ | Algorithm/config/sample/tail |
| `date_histogram` | Bucket theo boundary | Time zone, DST, missing/empty |
| `composite` key pages | Enumerate theo key | Stable view, after key, partial shards |
| Pipeline | Tính từ output đã có | Inherits approximation/gaps |

Không ghi “exact” chỉ vì response không có trường `error`.

---

## 31. Dashboard doanh thu có contract rõ

```http
GET /orders-read/_search?allow_partial_search_results=false
{
  "size": 0,
  "track_total_hits": false,
  "query": {
    "bool": {
      "filter": [
        {
          "term": {
            "status": "completed"
          }
        },
        {
          "term": {
            "currency": "VND"
          }
        },
        {
          "range": {
            "@timestamp": {
              "gte": "2026-07-01T00:00:00+07:00",
              "lt": "2026-08-01T00:00:00+07:00"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "revenue_minor": {
      "sum": {
        "field": "amount_minor"
      }
    },
    "orders": {
      "value_count": {
        "field": "order_id"
      }
    },
    "customers_estimate": {
      "cardinality": {
        "field": "customer_id",
        "precision_threshold": 10000
      }
    },
    "daily": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "day",
        "time_zone": "Asia/Bangkok",
        "min_doc_count": 0,
        "extended_bounds": {
          "min": "2026-07-01T00:00:00+07:00",
          "max": "2026-07-31T00:00:00+07:00"
        }
      },
      "aggs": {
        "revenue_minor": {
          "sum": {
            "field": "amount_minor"
          }
        },
        "orders": {
          "value_count": {
            "field": "order_id"
          }
        },
        "average_order_minor": {
          "bucket_script": {
            "buckets_path": {
              "revenue": "revenue_minor",
              "orders": "orders"
            },
            "script": "params.orders > 0 ? params.revenue / params.orders : null"
          }
        },
        "revenue_7d_average": {
          "moving_fn": {
            "buckets_path": "revenue_minor",
            "window": 7,
            "script": "MovingFunctions.unweightedAvg(values)"
          }
        }
      }
    },
    "channels": {
      "terms": {
        "field": "channel",
        "size": 20,
        "order": {
          "_count": "desc"
        },
        "show_term_doc_count_error": true
      },
      "aggs": {
        "revenue_minor": {
          "sum": {
            "field": "amount_minor"
          }
        }
      }
    }
  }
}
```

API response/metadata nên nói rõ:

- `customers_estimate` là xấp xỉ;
- currency và timezone;
- time window half-open `[from, to)`;
- source/index lag;
- `timed_out` và shard failure policy;
- revenue dùng cho dashboard, không thay ledger.

---

## 32. Materialize thay vì tính lại mọi lần

Khi cùng aggregation đắt chạy liên tục:

### Transform

Tạo entity-centric/materialized index:

```text
raw orders → continuous transform → daily_revenue_by_channel
```

Ưu:

- dashboard query ít bucket;
- định nghĩa metric được version;
- giảm compute lặp.

Trade-off:

- có checkpoint/lag;
- correction/backfill cần runbook;
- mapping đích và retention riêng.

### Downsampling/TSDS

Phù hợp time-series metrics với dimension/metric semantics đúng. Không mặc nhiên
phù hợp order/business event tùy ý.

### Warehouse/database

Phù hợp join phức tạp, exact reporting, long-running batch và governance BI.

Chọn nơi tính theo correctness/SLA/cost, không vì “dữ liệu đã ở Elasticsearch”.

---

## 33. Failure modes thường gặp

### 33.1 Top category theo revenue sai

`terms` ordered by `sum desc` bỏ category không lọt local candidate. Dùng composite/
transform/warehouse hoặc chấp nhận approximate có validation.

### 33.2 Dùng `_count asc` tìm term hiếm

Shard trả local rare terms không bảo đảm global rare. Dùng `rare_terms`.

### 33.3 Cardinality được hiển thị như exact

Dashboard ghi “12,345 khách hàng” nhưng HLL++ là estimate. Label approximate hoặc
dùng exact source cho use case yêu cầu.

### 33.4 Percentile thay đổi dù traffic giống nhau

Approximation, sample distribution, shard/layout hoặc config đổi. So sánh cùng
algorithm/window và giữ confidence/sample context.

### 33.5 `bucket_sort` đặt sau terms nhưng tưởng tìm top toàn bộ

Nó chỉ sort bucket parent đã trả. Parent candidate selection đã xảy ra trước.

### 33.6 `bucket_selector` không giảm memory

Toàn bộ upstream bucket/metric vẫn được tính rồi mới loại. Filter document sớm hoặc
materialize.

### 33.7 Calendar day bị 23/25 giờ

Đây là behavior đúng qua DST. Nếu cần duration tuyệt đối, dùng fixed interval; nếu
cần ngày địa phương, giữ calendar interval và giải thích.

### 33.8 `extended_bounds` làm xuất hiện dữ liệu ngoài khoảng

Nó không filter document. Dùng top-level range query; bounds chỉ điều khiển bucket.

### 33.9 Nested `doc_count` bị hiểu là order count

Trong nested scope, count là nested item. Reverse nested hoặc đổi data model.

### 33.10 `moving_avg` không còn tồn tại

Dùng `moving_fn` và test script/window/gap policy.

### 33.11 Circuit breaker/too many buckets

User chọn 2 năm × interval phút × nhiều dimensions. Giới hạn range/interval/
dimensions ở API, không chỉ tăng `search.max_buckets`.

### 33.12 HTTP 200 nhưng số thấp bất thường

Shard timeout/failure hoặc index lag. Kiểm tra response metadata và ingestion
freshness trước khi kết luận business giảm.

### 33.13 Trộn currency

Sum số tiền khác đơn vị tạo số vô nghĩa. Bucket/filter theo currency hoặc dùng
conversion ledger có rate version.

---

## 34. Debug và đo performance

### Validate scope

```http
GET /orders-read/_count
{
  "query": {
    "bool": {
      "filter": [
        {
          "term": {
            "status": "completed"
          }
        }
      ]
    }
  }
}
```

### Profile aggregation

```http
GET /orders-read/_search
{
  "size": 0,
  "profile": true,
  "aggs": {
    "channels": {
      "terms": {
        "field": "channel"
      }
    }
  }
}
```

Profile thêm overhead và không đo đầy đủ network/queue/coordinator reduce; dùng
để tìm component tương đối đắt, không làm benchmark latency.

### Thử accuracy

- So `terms` với `shard_size` khác nhau.
- So result với composite/full source trên sample.
- Reconcile cardinality/percentile với exact job định kỳ.
- Test single shard và multi-shard để lộ distributed candidate issue.
- Mô phỏng partial shard/timeout theo runbook.

Theo dõi:

- search p50/p95/p99;
- coordinator/data-node heap và GC;
- breaker/rejected requests;
- bucket count;
- cache hit;
- transform/index freshness;
- result error metadata.

---

## 35. Checklist thiết kế

### Semantics

- [ ] Một document đại diện entity/event nào?
- [ ] `doc_count`/`value_count`/cardinality đang đếm đúng thứ cần đếm?
- [ ] Missing là bỏ qua, zero hay bucket riêng?
- [ ] Currency, timezone và interval được khai báo?
- [ ] Window dùng half-open boundaries để tránh double count?

### Accuracy

- [ ] Metric nào exact theo logic, metric nào approximate?
- [ ] `terms` order có distributed correctness guarantee phù hợp?
- [ ] Có xem `sum_other_doc_count` và error metadata?
- [ ] Cardinality/percentile được label estimate?
- [ ] Response partial/timeout bị từ chối hoặc hiển thị rõ?

### Resource

- [ ] Ước lượng tích số bucket?
- [ ] Terms/composite/page/date range có giới hạn?
- [ ] Cardinality/percentile/top_hits có nằm dưới high-cardinality parent?
- [ ] Pipeline không bị nhầm là giảm upstream work?
- [ ] Có concurrency/rate-limit và breaker alert?

### Data model

- [ ] Field aggregate dùng doc values đúng type?
- [ ] Nested count semantics đã được xử lý?
- [ ] Runtime/script có nên materialize lúc ingest?
- [ ] Dashboard lặp lại có nên dùng transform/downsampling?
- [ ] Exact finance/reporting có nguồn khác Elasticsearch?

### Vận hành

- [ ] Query version/metric definition có owner?
- [ ] Có benchmark trên dữ liệu nhiều shard thật?
- [ ] Có reconciliation với source of truth?
- [ ] Có freshness/checkpoint lag trong response/dashboard?
- [ ] Có runbook cho breaker, partial shards và result drift?

---

## 36. Câu hỏi phỏng vấn

### Cơ bản

1. Metric, bucket và pipeline aggregation khác nhau thế nào?
2. Vì sao aggregation thường dùng `doc_values`?
3. `value_count` và `doc_count` khác nhau ra sao?
4. Calendar interval khác fixed interval thế nào?

### Trung cấp

1. Tại sao `terms` top-N có thể sai trên nhiều shard?
2. `size` và `shard_size` khác nhau thế nào?
3. Cardinality/percentiles đánh đổi memory và accuracy ra sao?
4. `extended_bounds` có filter document không?
5. Nested aggregation count gì?
6. `bucket_sort` chạy ở giai đoạn nào?

### Nâng cao

1. Vì sao order `terms` theo `sum desc` có thể chọn sai bucket?
2. Thiết kế exact top revenue theo category thế nào?
3. Composite pagination qua index đang update có failure mode gì?
4. Làm sao ước lượng memory của nested bucket tree?
5. Khi nào eager global ordinals có lợi?
6. Thiết kế dashboard vừa near-real-time vừa reconcile được với ledger ra sao?

---

## 37. Nguồn và chủ đề tiếp theo

Tài liệu chính thức:

- [Aggregations](https://www.elastic.co/docs/reference/aggregations)
- [Terms aggregation](https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-terms-aggregation)
- [Cardinality aggregation](https://www.elastic.co/docs/reference/aggregations/search-aggregations-metrics-cardinality-aggregation)
- [Percentiles aggregation](https://www.elastic.co/docs/reference/aggregations/search-aggregations-metrics-percentile-aggregation)
- [Date histogram](https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-datehistogram-aggregation)
- [Composite aggregation](https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-composite-aggregation)
- [Moving function](https://www.elastic.co/docs/reference/aggregations/search-aggregations-pipeline-movfn-aggregation)
- [Bucket sort](https://www.elastic.co/docs/reference/aggregations/search-aggregations-pipeline-bucket-sort-aggregation)
- [Nested aggregation](https://www.elastic.co/docs/reference/aggregations/search-aggregations-bucket-nested-aggregation)
- [Search settings](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/search-settings)
- [Transforms](https://www.elastic.co/docs/explore-analyze/transforms)

Học tiếp:

1. [Performance & Optimization](../performance/optimization.md) – benchmark,
   cache, shard, indexing/search backpressure.
2. [Query DSL](../fundamentals/query_dsl.md) – filter scope, PIT và partial result.
3. [Indexing & Mapping](../fundamentals/indexing_mapping.md) – doc values, runtime
   fields và data contract.
4. [Cluster Management](../operations/cluster_management.md) – breaker, task,
   recovery và capacity.

---

*Cập nhật lần cuối: 2026-07-31.*
