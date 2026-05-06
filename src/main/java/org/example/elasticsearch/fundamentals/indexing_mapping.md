# Elasticsearch Indexing, Mapping & Analyzers – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Mapping là gì?

**Mapping** định nghĩa cấu trúc document trong index: field names, data types, và cách Elasticsearch index/store mỗi field.

```
Giống schema trong relational DB:
  SQL:           CREATE TABLE orders (id INT, name VARCHAR(255), amount DECIMAL)
  Elasticsearch: PUT /orders { "mappings": { "properties": { ... } } }

Khác biệt:
  - Dynamic mapping: ES tự suy ra type từ JSON (có thể disabled)
  - Schema-on-read: không enforce strict constraints
  - Multi-fields: 1 field có thể indexed nhiều cách (text + keyword)
```

---

## Components – Field Types

```
Core types:
  text:        full-text indexed (analyzed), không sort/aggregate
  keyword:     exact value, sort/aggregate/filter (max 32KB default)
  long, int, short, byte, double, float, half_float, scaled_float
  boolean:     true/false
  date:        ISO 8601, epoch_millis
  binary:      base64-encoded bytes (not indexed by default)
  range:       integer_range, float_range, long_range, date_range, ip_range

Complex types:
  object:      nested JSON object (flattened in Lucene)
  nested:      array of objects (each object queryable independently)
  flattened:   dynamic key-value object (1 field mapped as flat keyword)
  join:        parent-child relationships within index (avoid if possible)

Specialty types:
  ip:          IPv4/IPv6 addresses
  geo_point:   latitude/longitude
  geo_shape:   polygons, linestrings
  point:       cartesian coordinates
  shape:       cartesian geometry
  completion:  fast autocomplete (FST-based)
  search_as_you_type: n-gram based suggest field type
  dense_vector: k-NN search (vector embeddings)
  rank_feature: boost score based on numeric value
  percolator:  stores queries, search by document
```

---

## How – Mapping Definition

```bash
# Tạo index với explicit mapping
PUT /products
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1,
    "default_pipeline": "products_pipeline"
  },
  "mappings": {
    "dynamic": "strict",          # strict | true | false | runtime
    "properties": {
      "id": {
        "type": "keyword"
      },
      "name": {
        "type": "text",
        "analyzer": "vi_analyzer",   # custom analyzer
        "fields": {
          "keyword": {
            "type": "keyword",
            "ignore_above": 256      # truncate for indexing
          },
          "suggest": {
            "type": "search_as_you_type"
          }
        }
      },
      "description": {
        "type": "text",
        "analyzer": "standard",
        "index_options": "offsets"   # for highlighting
      },
      "price": {
        "type": "scaled_float",
        "scaling_factor": 100       # store as integer * 100
      },
      "category": {
        "type": "keyword"
      },
      "tags": {
        "type": "keyword"            # array of keywords (ES handles arrays natively)
      },
      "created_at": {
        "type": "date",
        "format": "strict_date_optional_time||epoch_millis"
      },
      "location": {
        "type": "geo_point"
      },
      "attributes": {
        "type": "nested",            # queryable nested objects
        "properties": {
          "key":   { "type": "keyword" },
          "value": { "type": "keyword" }
        }
      },
      "embedding": {
        "type": "dense_vector",
        "dims": 768,
        "index": true,
        "similarity": "cosine"       # cosine | dot_product | l2_norm
      }
    }
  }
}

# Add field to existing index (cannot change existing field type!)
PUT /products/_mapping
{
  "properties": {
    "brand": { "type": "keyword" }
  }
}

# View mapping
GET /products/_mapping
GET /products/_mapping/field/name
```

### Dynamic Mapping

```bash
# Dynamic templates: control auto-mapping rules
PUT /logs
{
  "mappings": {
    "dynamic_templates": [
      {
        "strings_as_keyword": {
          "match_mapping_type": "string",
          "unmatch": "*_text",
          "mapping": { "type": "keyword" }
        }
      },
      {
        "string_fields_as_text": {
          "match_mapping_type": "string",
          "match": "*_text",
          "mapping": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword" } }
          }
        }
      },
      {
        "longs_as_integer": {
          "match_mapping_type": "long",
          "mapping": { "type": "integer" }
        }
      }
    ]
  }
}
```

---

## Components – Analysis Pipeline

```
Text analysis: convert text → tokens (terms) stored in inverted index

Analysis pipeline:
  Character Filters → Tokenizer → Token Filters

  Input:  "The Quick-brown FOX jumped over LAZY Dog!"
  After char filter (html_strip nếu có HTML)
  After tokenizer (standard): [The, Quick, brown, FOX, jumped, over, LAZY, Dog]
  After lowercase filter:     [the, quick, brown, fox, jumped, over, lazy, dog]
  After stop filter:          [quick, brown, fox, jumped, lazy, dog]
  After stemmer (english):    [quick, brown, fox, jump, lazi, dog]

Inverted index: term → list of document IDs
  "fox"  → [doc1, doc3, doc7]
  "jump" → [doc1, doc5]
  "lazi" → [doc1]
```

### Built-in Analyzers

```bash
# Test analyzer
POST /_analyze
{
  "analyzer": "standard",
  "text": "The Quick-Brown Fox! Is jumping over 2 lazy dogs."
}

# Built-in analyzers:
#   standard:   whitespace + lowercase + stop words (most common)
#   simple:     split on non-letters + lowercase
#   whitespace: split on whitespace only (no lowercase)
#   keyword:    no analysis (treat as single token, same as keyword type)
#   english:    standard + stemming + english stop words
#   fingerprint: lowercase + sort + deduplicate (for deduplication)
#   pattern:    regex-based tokenizer
#   language analyzers: arabic, cjk, czech, danish, dutch, english,
#                       finnish, french, german, greek, hindi, hungarian,
#                       indonesian, irish, italian, latvian, lithuanian,
#                       norwegian, persian, portuguese, romanian, russian,
#                       sorani, spanish, swedish, turkish, thai

# Per-field analyzer test
POST /products/_analyze
{
  "field": "name",
  "text": "Điện thoại iPhone 15 Pro Max"
}
```

### Custom Analyzer

```bash
PUT /products
{
  "settings": {
    "analysis": {
      "char_filter": {
        "html_strip_filter": {
          "type": "html_strip"
        },
        "ampersand_filter": {
          "type": "mapping",
          "mappings": ["& => and"]
        }
      },
      "tokenizer": {
        "edge_ngram_tokenizer": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 20,
          "token_chars": ["letter", "digit"]
        }
      },
      "filter": {
        "vietnamese_stop": {
          "type": "stop",
          "stopwords": ["và", "của", "là", "được", "có", "cho", "trong", "với"]
        },
        "edge_ngram_filter": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 20
        },
        "synonym_filter": {
          "type": "synonym_graph",
          "synonyms_path": "analysis/synonyms.txt",
          "updateable": true        # runtime reloadable (ES 7.3+)
        }
      },
      "analyzer": {
        "vi_analyzer": {
          "type": "custom",
          "char_filter": ["html_strip_filter"],
          "tokenizer": "standard",
          "filter": ["lowercase", "vietnamese_stop", "asciifolding"]
        },
        "autocomplete_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase", "edge_ngram_filter"]
        },
        "autocomplete_search_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase"]   # search: no ngram (match prefix only)
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "vi_analyzer",
        "fields": {
          "autocomplete": {
            "type": "text",
            "analyzer": "autocomplete_analyzer",
            "search_analyzer": "autocomplete_search_analyzer"
          }
        }
      }
    }
  }
}
```

---

## How – Indexing Documents

```bash
# Index single document
PUT /products/_doc/1
{
  "name": "iPhone 15 Pro",
  "price": 29990000,
  "category": "smartphones",
  "tags": ["apple", "ios", "5g"],
  "created_at": "2024-09-22T00:00:00Z"
}

# Index with auto-generated ID
POST /products/_doc
{ "name": "Samsung Galaxy S24", "price": 25990000 }

# Upsert (update or insert)
POST /products/_update/1
{
  "doc": { "price": 28990000 },
  "doc_as_upsert": true
}

# Update by script
POST /products/_update/1
{
  "script": {
    "source": "ctx._source.price *= params.discount",
    "params": { "discount": 0.9 }
  }
}

# Bulk API (production standard for mass indexing)
POST /_bulk
{ "index": { "_index": "products", "_id": "1" } }
{ "name": "iPhone 15", "price": 24990000 }
{ "index": { "_index": "products", "_id": "2" } }
{ "name": "iPad Pro", "price": 35990000 }
{ "update": { "_index": "products", "_id": "1" } }
{ "doc": { "price": 23990000 } }
{ "delete": { "_index": "products", "_id": "99" } }

# Optimal bulk size: 5-15MB per request, 1000-5000 docs
# curl -s -H "Content-Type: application/x-ndjson" \
#   --data-binary @products.ndjson localhost:9200/_bulk
```

---

## How – Ingest Pipeline

```
Ingest pipeline: pre-process documents before indexing
  - Transform, enrich, filter at ingest time
  - Runs on ingest nodes (or any node with ingest role)
  - Alternative to Logstash for simple transformations
```

```bash
# Define pipeline
PUT _ingest/pipeline/products_pipeline
{
  "description": "Process product documents",
  "processors": [
    {
      "set": {
        "field": "indexed_at",
        "value": "{{_ingest.timestamp}}"
      }
    },
    {
      "lowercase": {
        "field": "category"
      }
    },
    {
      "trim": {
        "field": "name"
      }
    },
    {
      "split": {
        "field": "tags_string",
        "separator": ",",
        "target_field": "tags",
        "ignore_missing": true
      }
    },
    {
      "remove": {
        "field": ["tags_string", "internal_field"],
        "ignore_missing": true
      }
    },
    {
      "grok": {
        "field": "log_message",
        "patterns": ["%{IP:client_ip} %{HTTPDATE:timestamp} %{WORD:method} %{URIPATHPARAM:path} %{NUMBER:status_code:int}"],
        "ignore_missing": true
      }
    },
    {
      "geoip": {
        "field": "client_ip",
        "target_field": "geo",
        "ignore_missing": true
      }
    },
    {
      "convert": {
        "field": "price",
        "type": "float",
        "ignore_missing": true
      }
    },
    {
      "script": {
        "source": "ctx.price_tier = ctx.price > 20000000 ? 'premium' : 'standard'"
      }
    },
    {
      "enrich": {
        "policy_name": "category_enrich_policy",  # lookup from enrich index
        "field": "category",
        "target_field": "category_info"
      }
    }
  ],
  "on_failure": [
    {
      "set": {
        "field": "_index",
        "value": "failed_{{ _index }}"
      }
    }
  ]
}

# Test pipeline
POST _ingest/pipeline/products_pipeline/_simulate
{
  "docs": [
    {
      "_index": "products",
      "_id": "1",
      "_source": {
        "name": "  iPhone 15  ",
        "category": "SMARTPHONES",
        "price": 29990000,
        "tags_string": "apple,ios,5g"
      }
    }
  ]
}

# Apply pipeline at index level
PUT /products/_settings
{ "default_pipeline": "products_pipeline" }

# Or per-request
PUT /products/_doc/1?pipeline=products_pipeline
{ ... }
```

---

## How – Index Templates

```bash
# Index template (for auto-applied settings/mappings)
PUT _index_template/logs_template
{
  "index_patterns": ["logs-*", "app-logs-*"],
  "priority": 100,
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 1,
      "refresh_interval": "5s",
      "index.lifecycle.name": "logs_policy",
      "index.lifecycle.rollover_alias": "logs"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp":  { "type": "date" },
        "level":       { "type": "keyword" },
        "service":     { "type": "keyword" },
        "message":     { "type": "text" },
        "trace_id":    { "type": "keyword" },
        "duration_ms": { "type": "long" }
      }
    },
    "aliases": {
      "logs": { "is_write_index": true }
    }
  },
  "composed_of": ["component_template_base"]  # reuse component templates
}

# Component template (reusable building block)
PUT _component_template/component_template_base
{
  "template": {
    "settings": {
      "index.mapping.total_fields.limit": 2000
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "host":       { "type": "keyword" }
      }
    }
  }
}
```

---

## Why – Analysis & Mapping Design Choices

```
Why text vs keyword?
  text:    "The Quick Brown Fox" → [quick, brown, fox] → full-text search
  keyword: "The Quick Brown Fox" → exact → filter/sort/aggregate

Why multi-fields?
  name.keyword for aggregations + sort
  name for full-text search
  name.suggest for autocomplete
  → 1 value, 3 indexes, different use cases

Why nested vs object?
  object (default): fields flattened → cross-document corruption
    { "attrs": [{"k":"color","v":"red"},{"k":"size","v":"M"}] }
    → attrs.k: [color, size], attrs.v: [red, M]
    → query k=color AND v=M → matches (incorrect: M isn't color M!)
  nested: each object indexed separately → correct queries
    → Slower queries, more storage, but correct results

Why disable dynamic mapping in production?
  Unexpected field → auto-created with wrong type (string → text when should be keyword)
  → Too many fields → mapping explosion (memory, performance)
  → Set dynamic: false hoặc strict
```

---

## Trade-offs

```
text vs keyword:
  text:    searchable (analyzed), not sortable/aggregatable
  keyword: sortable/aggregatable, exact match only, 32KB limit
  → Almost always: use both via multi-fields

Dynamic mapping:
  true:    convenient for development, risky in production
  false:   unknown fields stored but not indexed (still in _source)
  strict:  unknown fields → exception
  → Production: strict (explicit control) hoặc false (safe default)

nested vs flattened:
  nested:    correct queries for arrays of objects, slower, more memory
  flattened: fast, single field mapping for dynamic keys (logs, metadata)
  → Use nested when query accuracy matters, flattened for tags/attributes

index_options:
  docs:    track document IDs (smallest, no TF/IDF scoring)
  freqs:   term frequency (BM25 scoring)
  positions: phrase queries (default for text)
  offsets: fast highlighting (more storage)
  → Logs/keyword fields: docs; search fields: positions; highlight fields: offsets
```

---

## Real-world

```bash
# Reindex: apply new mapping (mapping changes require reindex)
POST _reindex
{
  "source": {
    "index": "products",
    "query": { "range": { "created_at": { "gte": "2024-01-01" } } }
  },
  "dest": {
    "index": "products_v2",
    "pipeline": "products_pipeline"
  }
}

# Blue-green reindex with alias swap (zero downtime)
# 1. Create products_v2 with new mapping
# 2. Reindex products → products_v2
# 3. Swap alias atomically
POST _aliases
{
  "actions": [
    { "remove": { "index": "products",    "alias": "products_alias" } },
    { "add":    { "index": "products_v2", "alias": "products_alias" } }
  ]
}

# Mapping best practices
# 1. Disable _source for pure search (saves storage, but loses update/reindex)
# 2. Enable doc_values=false for text-only fields (saves disk, loses sort/agg)
# 3. Use store=true only for fields not in _source
# 4. index=false for fields only needed in _source (not searchable)

PUT /metrics_optimized
{
  "mappings": {
    "_source": { "enabled": true },     # keep for reindex
    "properties": {
      "timestamp": { "type": "date" },
      "value": {
        "type": "double",
        "doc_values": true,              # needed for aggregations
        "index": true
      },
      "raw_json": {
        "type": "object",
        "enabled": false                 # stored in _source, not indexed
      }
    }
  }
}
```

---

## Ghi chú – Chủ đề tiếp theo
> `query_dsl.md`: Query DSL – match, bool, term, range, nested, span queries; relevance scoring (BM25, function_score, script_score); highlighting; suggestions (term, phrase, completion)

---

*Cập nhật lần cuối: 2026-05-06*
