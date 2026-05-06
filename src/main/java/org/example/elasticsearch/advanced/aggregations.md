# Elasticsearch Aggregations – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Aggregations là gì?

**Aggregations** là framework phân tích dữ liệu trong Elasticsearch: thống kê, group by, histogram, pipeline calculations – tương tự GROUP BY + analytic functions trong SQL nhưng real-time trên distributed data.

```
3 loại aggregation:
  Metric:   tính toán số liệu từ document values (avg, sum, min, max, percentiles)
  Bucket:   nhóm documents vào buckets (terms, date_histogram, range)
  Pipeline: tính toán từ output của các agg khác (moving_avg, derivative)

Aggs có thể nested và kết hợp:
  Root agg → Sub-agg (per bucket) → Sub-sub-agg...
  → Đây là "aggregation tree"
```

---

## How – Basic Structure

```bash
GET /orders/_search
{
  "size": 0,                    # không cần documents, chỉ cần agg results
  "query": {                    # filter scope before aggregating
    "range": { "@timestamp": { "gte": "now-30d" } }
  },
  "aggs": {                     # root aggregations
    "agg_name": {
      "agg_type": { ... },      # metric hoặc bucket
      "aggs": {                 # sub-aggregations (nested)
        "sub_agg_name": { ... }
      }
    }
  }
}
```

---

## Components – Metric Aggregations

```bash
GET /orders/_search
{
  "size": 0,
  "aggs": {
    # --- Single-value metrics ---
    "total_revenue": { "sum": { "field": "amount" } },
    "avg_order_value": { "avg": { "field": "amount" } },
    "min_order": { "min": { "field": "amount" } },
    "max_order": { "max": { "field": "amount" } },
    "order_count": { "value_count": { "field": "order_id" } },
    "unique_customers": { "cardinality": { "field": "customer_id", "precision_threshold": 40000 } },

    # --- Multi-value metrics ---
    "amount_stats": {
      "stats": { "field": "amount" }
      # → { count, min, max, avg, sum }
    },
    "amount_extended_stats": {
      "extended_stats": {
        "field": "amount",
        "sigma": 2            # std_deviation_bounds: mean ± 2σ
      }
      # → adds: sum_of_squares, variance, std_deviation, std_deviation_bounds
    },
    "amount_percentiles": {
      "percentiles": {
        "field": "amount",
        "percents": [25, 50, 75, 90, 95, 99],
        "keyed": true,
        "tdigest": { "compression": 100 }  # 100 = default; higher = more accurate, more memory
      }
    },
    "amount_percentile_ranks": {
      "percentile_ranks": {
        "field": "amount",
        "values": [10000, 50000, 100000]  # what % of orders are ≤ these values?
      }
    },
    
    # --- Geo metrics ---
    "centroid": { "geo_centroid": { "field": "location" } },
    "bounds": { "geo_bounds": { "field": "location", "wrap_longitude": true } },
    
    # --- Script metric (custom) ---
    "weighted_avg": {
      "weighted_avg": {
        "value":  { "field": "amount" },
        "weight": { "field": "weight_factor" }
      }
    },
    
    # --- Rate (per time unit in date_histogram sub-agg) ---
    # "orders_per_hour": { "rate": { "field": "amount", "unit": "hour" } }
    
    # --- Top hits (sample documents per bucket) ---
    "top_orders": {
      "top_hits": {
        "size": 3,
        "sort": [{ "amount": { "order": "desc" } }],
        "_source": ["order_id", "amount", "customer_id"]
      }
    }
  }
}
```

---

## Components – Bucket Aggregations

```bash
GET /orders/_search
{
  "size": 0,
  "aggs": {
    # --- Terms: group by field value (like GROUP BY) ---
    "by_category": {
      "terms": {
        "field": "category",
        "size": 10,                    # top N buckets
        "min_doc_count": 1,
        "order": { "_count": "desc" }, # or {"_key":"asc"} or {"revenue":"desc"} (sub-agg)
        "shard_size": 100,             # size * 1.5 + 10 default; increase for accuracy
        "show_term_doc_count_error": true,
        "missing": "Unknown"           # bucket for docs without this field
      },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } }  # sub-agg per category
      }
    },

    # --- Significant terms: unusual terms compared to background ---
    "significant_categories": {
      "significant_terms": {
        "field": "category",
        "background_filter": { "term": { "region": "APAC" } }
      }
    },

    # --- Date histogram: time-series grouping ---
    "orders_over_time": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "1d",   # 1m, 1h, 1d, 1w, 1M, 1q, 1y
        # "fixed_interval": "6h",    # fixed: 1ms, 1s, 1m, 1h, 1d
        "format": "yyyy-MM-dd",
        "time_zone": "+07:00",
        "min_doc_count": 0,          # include empty buckets
        "extended_bounds": {         # fill in bounds even if no data
          "min": "2024-01-01",
          "max": "2024-12-31"
        },
        "missing": "2024-01-01"      # default date for missing field
      },
      "aggs": {
        "daily_revenue": { "sum": { "field": "amount" } },
        "unique_customers": { "cardinality": { "field": "customer_id" } }
      }
    },

    # --- Histogram: numeric grouping ---
    "price_distribution": {
      "histogram": {
        "field": "amount",
        "interval": 1000000,        # bucket every 1M VND
        "min_doc_count": 0,
        "extended_bounds": { "min": 0, "max": 100000000 },
        "offset": 500000            # shift buckets: 500k, 1.5M, 2.5M...
      }
    },

    # --- Variable width histogram ---
    "amount_var_width": {
      "variable_width_histogram": {
        "field": "amount",
        "buckets": 10              # target 10 buckets (auto-sized)
      }
    },

    # --- Range: explicit range buckets ---
    "price_ranges": {
      "range": {
        "field": "amount",
        "ranges": [
          { "key": "Budget",    "to": 5000000 },
          { "key": "Mid-range", "from": 5000000, "to": 20000000 },
          { "key": "Premium",   "from": 20000000 }
        ]
      }
    },

    # --- Date range ---
    "recent_orders": {
      "date_range": {
        "field": "order_date",
        "format": "yyyy-MM-dd",
        "ranges": [
          { "key": "last_7d",  "from": "now-7d/d", "to": "now/d" },
          { "key": "last_30d", "from": "now-30d/d", "to": "now-7d/d" }
        ]
      }
    },

    # --- Filter: single filter bucket ---
    "vip_orders": {
      "filter": { "term": { "customer_tier": "VIP" } },
      "aggs": { "vip_revenue": { "sum": { "field": "amount" } } }
    },

    # --- Filters: multiple named filter buckets ---
    "order_types": {
      "filters": {
        "filters": {
          "online":   { "term": { "channel": "online" } },
          "offline":  { "term": { "channel": "offline" } },
          "mobile":   { "term": { "channel": "mobile" } }
        },
        "other_bucket_key": "other"  # catch-all bucket
      },
      "aggs": { "revenue": { "sum": { "field": "amount" } } }
    },

    # --- Nested: aggregate on nested objects ---
    "attribute_values": {
      "nested": { "path": "attributes" },
      "aggs": {
        "colors": {
          "filter": { "term": { "attributes.key": "color" } },
          "aggs": {
            "color_values": { "terms": { "field": "attributes.value", "size": 20 } }
          }
        }
      }
    },

    # --- Geo distance ---
    "nearby_stores": {
      "geo_distance": {
        "field": "location",
        "origin": { "lat": 10.762622, "lon": 106.660172 },  # Ho Chi Minh City
        "unit": "km",
        "ranges": [
          { "key": "0-5km",   "to": 5 },
          { "key": "5-20km",  "from": 5, "to": 20 },
          { "key": "20km+",   "from": 20 }
        ]
      }
    },

    # --- Composite: paginated multi-level bucketing ---
    "category_brand_combo": {
      "composite": {
        "size": 100,
        "sources": [
          { "category": { "terms": { "field": "category" } } },
          { "brand":    { "terms": { "field": "brand" } } },
          { "date":     { "date_histogram": { "field": "order_date", "calendar_interval": "1d" } } }
        ],
        "after": { "category": "smartphones", "brand": "apple", "date": 1704067200000 }  # pagination
      },
      "aggs": { "revenue": { "sum": { "field": "amount" } } }
    }
  }
}
```

---

## Components – Pipeline Aggregations

```bash
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "daily_orders": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "1d"
      },
      "aggs": {
        "daily_revenue": { "sum": { "field": "amount" } },
        "daily_count":   { "value_count": { "field": "order_id" } },
        
        # Parent pipeline: operates on each bucket
        "avg_order_value": {
          "bucket_script": {
            "buckets_path": {
              "revenue": "daily_revenue",
              "count":   "daily_count"
            },
            "script": "params.count > 0 ? params.revenue / params.count : 0"
          }
        }
      }
    },

    # Sibling pipeline: operates on all buckets of a sibling agg
    "total_avg_daily_revenue": {
      "avg_bucket": {
        "buckets_path": "daily_orders>daily_revenue"
      }
    },
    "total_sum_daily_revenue": {
      "sum_bucket": {
        "buckets_path": "daily_orders>daily_revenue"
      }
    },
    "max_daily_revenue": {
      "max_bucket": { "buckets_path": "daily_orders>daily_revenue" }
    },
    "min_daily_revenue": {
      "min_bucket": { "buckets_path": "daily_orders>daily_revenue" }
    },
    "stats_daily_revenue": {
      "stats_bucket": { "buckets_path": "daily_orders>daily_revenue" }
    },
    "top_3_days": {
      "bucket_sort": {
        "sort": [{ "daily_revenue": { "order": "desc" } }],
        "size": 3
      }
    }
  }
}

# More pipeline aggregations within date_histogram
GET /orders/_search
{
  "size": 0,
  "aggs": {
    "daily": {
      "date_histogram": { "field": "order_date", "calendar_interval": "1d" },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } },
        
        # Moving average
        "revenue_moving_avg": {
          "moving_avg": {
            "buckets_path": "revenue",
            "window": 7,
            "model": "ewma",       # simple | linear | ewma | holt | holt_winters
            "settings": { "alpha": 0.3 }
          }
        },
        
        # Derivative (rate of change)
        "revenue_derivative": {
          "derivative": {
            "buckets_path": "revenue",
            "unit": "day"
          }
        },
        
        # Cumulative sum
        "cumulative_revenue": {
          "cumulative_sum": { "buckets_path": "revenue" }
        },
        
        # Cumulative cardinality
        # "cumulative_users": {
        #   "cumulative_cardinality": { "buckets_path": "unique_users" }
        # },
        
        # Bucket filter (filter buckets after computation)
        "high_revenue_only": {
          "bucket_selector": {
            "buckets_path": { "dailyRevenue": "revenue" },
            "script": "params.dailyRevenue > 1000000"  # keep only days with revenue > 1M
          }
        }
      }
    }
  }
}
```

---

## Why – Aggregation Architecture

```
Why aggregations are fast:
  doc_values: column-store format (default for keyword/numeric/date)
    → Sequential disk read (cache-friendly) vs row-store (random access)
    → Single-pass scan over field values across all documents
  
  Global ordinals (terms agg):
    → Pre-computed dictionary: term → integer (ordinal)
    → Aggregate on integers, map back to terms at the end
    → Loaded lazily and cached per shard
  
  Shard-level pre-aggregation:
    → Each shard aggregates independently
    → Coordinating node merges shard results
    → Not perfectly accurate for cardinality + top-N (approximation trade-off)
```

---

## Trade-offs

```
Terms aggregation accuracy:
  Problem: shard-level pre-aggregation → may miss terms in top-N
  Example: get top 10 categories
    Shard 1: returns its top 10 (may not include global top 10)
    Shard 2: same
    Merge: some true top terms may be missed
  
  Solution: increase shard_size (default: size * 1.5 + 10)
    shard_size: 1000 → more accurate, more memory/CPU
    doc_count_error_upper_bound: reported per term (how wrong it might be)
  
  Trade-off: shard_size ↑ → accuracy ↑, performance ↓

Cardinality accuracy:
  HyperLogLog++ algorithm: approximate count distinct
  precision_threshold (default 3000): max threshold for exact count
    → Higher = more accurate, more memory (per bucket)
    → Error rate: ~1-6% for high cardinality
    → 40000 = max meaningful value (~40KB per field per node)

Nested aggregations performance:
  nested → reverse_nested: extra nested lookup per document
  → Avoid deeply nested agg trees on large indices
  → Pre-compute aggregations with rollups for dashboards

Composite vs Terms:
  Terms:     fast, approximate, limited size
  Composite: paginated, exact, supports multiple keys, slower
  → Use composite for ETL/export; terms for dashboards
```

---

## Real-world

```bash
# E-commerce dashboard aggregation
GET /orders/_search
{
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        { "range": { "order_date": { "gte": "now-30d", "lte": "now" } } },
        { "term": { "status": "completed" } }
      ]
    }
  },
  "aggs": {
    "total_revenue": { "sum": { "field": "amount" } },
    "total_orders": { "value_count": { "field": "order_id" } },
    "unique_customers": { "cardinality": { "field": "customer_id", "precision_threshold": 10000 } },
    
    "revenue_by_day": {
      "date_histogram": {
        "field": "order_date",
        "calendar_interval": "1d",
        "time_zone": "+07:00",
        "min_doc_count": 0
      },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } },
        "orders":  { "value_count": { "field": "order_id" } },
        "7day_ma": {
          "moving_avg": { "buckets_path": "revenue", "window": 7, "model": "simple" }
        }
      }
    },
    
    "top_categories": {
      "terms": {
        "field": "category",
        "size": 10,
        "order": { "category_revenue": "desc" }
      },
      "aggs": {
        "category_revenue": { "sum": { "field": "amount" } },
        "avg_order_size":   { "avg":  { "field": "amount" } },
        "top_products": {
          "top_hits": {
            "size": 3,
            "sort": [{ "amount": "desc" }],
            "_source": ["product_name", "amount"]
          }
        }
      }
    },
    
    "revenue_by_hour_of_day": {
      "terms": {
        "field": "hour_of_day",   # computed field or script
        "size": 24,
        "order": { "_key": "asc" }
      },
      "aggs": {
        "hourly_revenue": { "sum": { "field": "amount" } }
      }
    },

    "payment_method_breakdown": {
      "terms": { "field": "payment_method", "size": 10 },
      "aggs": {
        "revenue": { "sum": { "field": "amount" } },
        "percentage": {
          "bucket_script": {
            "buckets_path": { "revenue": "revenue", "total": "_count" },
            "script": "params.revenue"
          }
        }
      }
    }
  }
}
```

```
Performance tips for aggregations:
  1. Use filter in query context to reduce doc set before aggregating
  2. Set size: 0 when only aggregation results are needed
  3. Use doc_values fields (keyword, numeric, date) – avoid scripted metrics
  4. Cache with request_cache: true (default for size:0 queries)
  5. Use composite + after for pagination over agg results (not from+size)
  6. For dashboards: consider Elasticsearch Rollup Jobs hoặc TSDS (Time Series Data Stream)
  7. eager_global_ordinals: true for hot keyword fields in terms aggs
```

---

## Ghi chú – Chủ đề tiếp theo
> `optimization.md`: Shard sizing, bulk indexing optimization, query performance tuning, caching strategies (filter cache, shard request cache, field data cache), mapping optimizations, monitoring performance

---

*Cập nhật lần cuối: 2026-05-06*
