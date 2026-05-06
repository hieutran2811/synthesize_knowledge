# Elasticsearch Query DSL – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Query DSL là gì?

**Query DSL** là JSON-based language để search, filter, và score documents trong Elasticsearch.

```
2 loại queries:
  Leaf queries:   match trên 1 field (match, term, range, exists...)
  Compound queries: kết hợp nhiều queries (bool, dis_max, constant_score...)

2 context:
  Query context:  tính relevance score (_score) → How well does this match?
  Filter context: yes/no match (không tính score) → Does this match? (cached)
```

---

## Components – Query Types

### Full-text Queries (analyzed, query context)

```bash
# match: standard full-text search (analyzed)
GET /products/_search
{
  "query": {
    "match": {
      "name": {
        "query": "iphone pro max",
        "operator": "and",           # default: or (any term matches)
        "minimum_should_match": "75%", # at least 75% of terms must match
        "fuzziness": "AUTO",         # typo tolerance: AUTO|0|1|2
        "prefix_length": 1,          # no fuzz on first N chars
        "zero_terms_query": "all"    # if all terms are stop words → return all
      }
    }
  }
}

# match_phrase: exact phrase (word order + proximity)
GET /products/_search
{
  "query": {
    "match_phrase": {
      "description": {
        "query": "machine learning",
        "slop": 2            # allow up to 2 words between terms
      }
    }
  }
}

# match_phrase_prefix: autocomplete (last term as prefix)
GET /products/_search
{
  "query": {
    "match_phrase_prefix": {
      "name": { "query": "iphone 15 p", "max_expansions": 50 }
    }
  }
}

# multi_match: search across multiple fields
GET /products/_search
{
  "query": {
    "multi_match": {
      "query": "iphone camera",
      "fields": ["name^3", "description^1", "tags^2"],  # ^N = boost
      "type": "best_fields",  # best_fields | most_fields | cross_fields | phrase | phrase_prefix
      "tie_breaker": 0.3      # for best_fields: add score from other fields * tie_breaker
    }
  }
}
```

### Term-level Queries (not analyzed, filter context)

```bash
# term: exact value match (use for keyword, numbers, dates)
GET /products/_search
{
  "query": {
    "term": {
      "category": { "value": "smartphones", "boost": 2.0 }
    }
  }
}

# terms: multiple exact values (IN operator)
GET /products/_search
{
  "query": {
    "terms": {
      "category": ["smartphones", "tablets"],
      "boost": 1.0
    }
  }
}

# range: range query for numbers, dates
GET /products/_search
{
  "query": {
    "range": {
      "price": { "gte": 10000000, "lte": 30000000 }
    }
  }
}

GET /logs/_search
{
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-1h/h",    # round to hour
        "lt":  "now/h",
        "format": "strict_date_optional_time",
        "time_zone": "+07:00"
      }
    }
  }
}

# exists: field has a non-null value
GET /products/_search
{ "query": { "exists": { "field": "discount_price" } } }

# wildcard: glob-style pattern (slow, use sparingly)
GET /products/_search
{ "query": { "wildcard": { "sku": { "value": "IP-15-*", "case_insensitive": true } } } }

# regexp: regex pattern (expensive)
GET /products/_search
{ "query": { "regexp": { "sku": { "value": "IP-1[5-9]-.*" } } } }

# prefix: prefix search on keyword/text
GET /products/_search
{ "query": { "prefix": { "name.keyword": { "value": "iPhone" } } } }

# fuzzy: typo-tolerant term search
GET /products/_search
{ "query": { "fuzzy": { "name": { "value": "iphonne", "fuzziness": 2 } } } }

# ids: fetch by document IDs
GET /products/_search
{ "query": { "ids": { "values": ["1", "2", "3"] } } }
```

---

## How – Bool Query (Compound)

```
bool: combines queries with boolean logic
  must:    AND (score contribution) → query context
  filter:  AND (no score, cached) → filter context
  should:  OR (score contribution, minimum_should_match)
  must_not: NOT (no score, cached)
```

```bash
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "name": "iphone" } }    # affects score
      ],
      "filter": [
        { "term": { "category": "smartphones" } },  # no score, cached
        { "range": { "price": { "gte": 10000000, "lte": 50000000 } } },
        { "term": { "in_stock": true } }
      ],
      "should": [
        { "term": { "brand": "apple" } },    # bonus score if matches
        { "match": { "tags": "5g" } }
      ],
      "minimum_should_match": 0,             # 0 = should is optional; 1 = at least 1 should match
      "must_not": [
        { "term": { "status": "discontinued" } }
      ],
      "boost": 1.5
    }
  }
}

# Nested bool (complex logic)
GET /products/_search
{
  "query": {
    "bool": {
      "should": [
        {
          "bool": {
            "must": [
              { "match": { "name": "iphone" } },
              { "term": { "brand": "apple" } }
            ]
          }
        },
        {
          "bool": {
            "must": [
              { "match": { "name": "galaxy" } },
              { "term": { "brand": "samsung" } }
            ]
          }
        }
      ],
      "minimum_should_match": 1
    }
  }
}
```

---

## How – Nested Queries

```bash
# Nested query: query on nested objects
GET /products/_search
{
  "query": {
    "nested": {
      "path": "attributes",
      "query": {
        "bool": {
          "must": [
            { "term": { "attributes.key": "color" } },
            { "term": { "attributes.value": "black" } }
          ]
        }
      },
      "score_mode": "avg",   # avg | sum | min | max | none
      "inner_hits": {        # return matching nested objects
        "size": 3,
        "highlight": { "fields": { "attributes.value": {} } }
      }
    }
  }
}

# Has child / has parent queries (join field type)
GET /orders/_search
{
  "query": {
    "has_child": {
      "type": "order_item",
      "query": { "term": { "product_id": "iphone-15" } },
      "min_children": 1,
      "score_mode": "sum",
      "inner_hits": {}
    }
  }
}
```

---

## How – Relevance Scoring

```
BM25 (Best Match 25) – default scoring algorithm (ES 5+):
  score = IDF * TF-saturation
  
  TF (Term Frequency):  how often term appears in document
    → More occurrences → higher score, but diminishing returns (saturation)
  IDF (Inverse Document Frequency): how rare the term is across all docs
    → Rare term → higher score
  
  Parameters:
    k1 (default 1.2): TF saturation (higher = less saturation)
    b  (default 0.75): length normalization (1 = full norm, 0 = none)

  Per-field boost via mappings or query
```

```bash
# Explain scoring
GET /products/_explain/1
{
  "query": { "match": { "name": "iphone" } }
}

# Boost specific fields
GET /products/_search
{
  "query": {
    "multi_match": {
      "query": "iphone",
      "fields": ["name^5", "description^1"]  # name 5x more important
    }
  }
}
```

### Function Score

```bash
# function_score: modify relevance score with functions
GET /products/_search
{
  "query": {
    "function_score": {
      "query": { "match": { "name": "iphone" } },
      "functions": [
        {
          "filter": { "term": { "is_featured": true } },
          "weight": 2.0    # multiply score by 2 for featured products
        },
        {
          "field_value_factor": {
            "field": "sales_count",
            "factor": 0.1,
            "modifier": "log1p",  # log1p | sqrt | square | reciprocal | none
            "missing": 1
          }
        },
        {
          "gauss": {
            "price": {
              "origin": "15000000",  # peak score at this price
              "scale": "5000000",    # half-score at origin ± scale
              "offset": "1000000",   # no decay within offset
              "decay": 0.5
            }
          }
        },
        {
          "random_score": {
            "seed": 42,
            "field": "_seq_no"   # consistent random (same query → same order)
          }
        }
      ],
      "score_mode": "multiply",  # multiply | sum | avg | max | min | first
      "boost_mode": "multiply",  # how to combine with base query score
      "min_score": 0.5           # filter out low-score results
    }
  }
}

# script_score: fully custom scoring
GET /products/_search
{
  "query": {
    "script_score": {
      "query": { "match": { "name": "iphone" } },
      "script": {
        "source": """
          double score = _score;
          if (doc['is_featured'].value) score *= 2.0;
          if (doc['price'].value < 20000000) score *= 1.5;
          return score;
        """
      }
    }
  }
}
```

---

## How – Search Options

```bash
# Pagination
GET /products/_search
{
  "from": 0,                 # offset (avoid deep pagination: from > 10000 → error)
  "size": 20,
  "query": { "match_all": {} },
  "sort": [
    { "price": { "order": "asc" } },
    { "_score": { "order": "desc" } }
  ],
  "_source": ["name", "price", "category"],  # field filtering
  "stored_fields": ["name"],                  # retrieve stored fields only
  "docvalue_fields": [{ "field": "created_at", "format": "yyyy-MM-dd" }]
}

# Search after (deep pagination without performance penalty)
GET /products/_search
{
  "size": 20,
  "sort": [{ "price": "asc" }, { "_id": "asc" }],
  "search_after": [15990000, "product-123"]  # values from last hit's sort fields
}

# Point-in-time (stable pagination for changing data)
POST /products/_pit?keep_alive=1m
# → returns pit.id

GET /products/_search
{
  "size": 20,
  "pit": { "id": "<pit_id>", "keep_alive": "1m" },
  "sort": [{ "_shard_doc": "asc" }],
  "search_after": [1234]
}

# Scroll API (bulk data export, not for user pagination)
POST /products/_search?scroll=5m
{
  "size": 1000,
  "query": { "match_all": {} }
}
# Use scroll_id from response to fetch next batch
POST /_search/scroll
{
  "scroll": "5m",
  "scroll_id": "<scroll_id>"
}
DELETE /_search/scroll { "scroll_id": "<scroll_id>" }
```

### Highlighting

```bash
GET /products/_search
{
  "query": { "match": { "description": "machine learning" } },
  "highlight": {
    "pre_tags": ["<em>"],
    "post_tags": ["</em>"],
    "fields": {
      "description": {
        "fragment_size": 150,         # chars per fragment
        "number_of_fragments": 3,
        "fragmenter": "span",         # sentence | simple | span
        "type": "unified"             # unified (default) | plain | fvh (fast vector highlighter)
      }
    }
  }
}
```

### Suggestions

```bash
# Term suggester (spell check)
GET /products/_search
{
  "suggest": {
    "name-suggest": {
      "text": "iphon 15 proe",
      "term": {
        "field": "name",
        "suggest_mode": "missing",   # missing | popular | always
        "sort": "score",
        "max_edits": 2
      }
    }
  }
}

# Phrase suggester (phrase correction)
GET /products/_search
{
  "suggest": {
    "name-phrase": {
      "text": "machine lerning",
      "phrase": {
        "field": "name",
        "size": 5,
        "gram_size": 3,
        "confidence": 1.0,
        "highlight": { "pre_tag": "<em>", "post_tag": "</em>" }
      }
    }
  }
}

# Completion suggester (fast autocomplete)
GET /products/_search
{
  "suggest": {
    "product-suggest": {
      "prefix": "iph",
      "completion": {
        "field": "name.suggest",    # must be completion type
        "size": 10,
        "skip_duplicates": true,
        "fuzzy": { "fuzziness": 1 },
        "contexts": {
          "category": ["smartphones"]  # context filter
        }
      }
    }
  }
}
```

---

## Why – Query Context vs Filter Context

```
Filter context (must use for):
  - Exact values: term, terms, range on numbers/dates
  - Boolean: exists, must_not
  - No relevance needed
  Benefits:
    ✅ Faster (no scoring computation)
    ✅ Cached (filter cache → reuse across queries)
    → Rule: always use filter for non-scoring conditions

Query context (use for):
  - Full-text search (match, multi_match)
  - Relevance needed (_score matters)
  - Scoring functions
  → Rule: only use query context when score matters

Best practice:
  bool.filter + bool.must
  → must:   relevance queries (affect score)
  → filter: exact/range conditions (don't affect score, cached)
```

---

## Trade-offs

```
match vs term:
  match:  analyzed → "Apple iPhone" → [apple, iphone] → finds partial
  term:   not analyzed → "Apple iPhone" → exact string → misses lowercase
  → Always use term on keyword fields, match on text fields

fuzziness in match:
  ✅ Typo tolerance
  ❌ Slower (Levenshtein automaton), more false positives
  → Use AUTO (0 edit for 1-2 chars, 1 for 3-5, 2 for 6+)

Wildcard/regexp:
  ✅ Flexible pattern matching
  ❌ Very slow (full scan), can kill cluster
  → Avoid leading wildcards (*foo) → use n-gram indexing instead

Deep pagination (from+size):
  from=10000: loads 10020 docs, throws away first 10000 → slow
  → Use search_after for deep pagination
  → Use scroll/PIT for data export

nested queries:
  ✅ Correct results for arrays of objects
  ❌ 2-3x slower than regular queries
  → Don't over-nest; consider flattened for simple cases
```

---

## Real-world

```bash
# E-commerce search pattern
GET /products/_search
{
  "query": {
    "bool": {
      "must": [
        {
          "multi_match": {
            "query": "điện thoại iphone",
            "fields": ["name^4", "name.keyword^5", "description^1", "tags^2"],
            "type": "best_fields",
            "operator": "or",
            "minimum_should_match": "60%"
          }
        }
      ],
      "filter": [
        { "term": { "in_stock": true } },
        { "range": { "price": { "gte": 5000000, "lte": 50000000 } } },
        { "terms": { "category": ["smartphones"] } }
      ],
      "should": [
        { "term": { "is_featured": { "value": true, "boost": 2.0 } } },
        { "range": { "rating": { "gte": 4.5, "boost": 1.5 } } }
      ]
    }
  },
  "sort": [
    { "_score": { "order": "desc" } },
    { "sales_rank": { "order": "asc" } }
  ],
  "from": 0,
  "size": 20,
  "highlight": {
    "fields": {
      "name": { "number_of_fragments": 0 },
      "description": { "fragment_size": 200, "number_of_fragments": 2 }
    }
  },
  "aggs": {
    "categories": { "terms": { "field": "category", "size": 10 } },
    "price_range": {
      "range": {
        "field": "price",
        "ranges": [
          { "key": "Under 10M", "to": 10000000 },
          { "key": "10M-20M", "from": 10000000, "to": 20000000 },
          { "key": "Over 20M", "from": 20000000 }
        ]
      }
    }
  }
}
```

---

## Ghi chú – Chủ đề tiếp theo
> `aggregations.md`: Metric aggregations (avg, stats, percentiles, cardinality), Bucket aggregations (terms, date_histogram, range, nested aggs), Pipeline aggregations (moving_avg, derivative, bucket_sort)

---

*Cập nhật lần cuối: 2026-05-06*
