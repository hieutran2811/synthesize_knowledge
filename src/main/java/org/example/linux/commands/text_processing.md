# Text Processing Advanced – Deep Dive

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Regular Expressions – Deep Dive

### What – Regex là gì?
**Regular Expression (Regex)** là pattern matching language dùng để tìm kiếm, trích xuất, thay thế text. Là nền tảng của grep, sed, awk, và hầu hết ngôn ngữ lập trình.

### How – Regex Syntax

```
Anchors
^        đầu dòng
$        cuối dòng
\b       word boundary
\B       non-word boundary

Character Classes
.        bất kỳ ký tự nào (trừ newline)
[abc]    a, b, hoặc c
[^abc]   không phải a, b, hoặc c
[a-z]    lowercase a đến z
[A-Z]    uppercase A đến Z
[0-9]    chữ số (= \d trong Perl regex)
\w       word char: [a-zA-Z0-9_]
\W       non-word char
\d       digit: [0-9]
\D       non-digit
\s       whitespace (space, tab, newline)
\S       non-whitespace

Quantifiers
*        0 hoặc nhiều lần
+        1 hoặc nhiều lần
?        0 hoặc 1 lần (optional)
{n}      đúng n lần
{n,}     ít nhất n lần
{n,m}    từ n đến m lần
*?       non-greedy (ít nhất có thể)
+?       non-greedy

Groups & Alternation
(abc)    capturing group
(?:abc)  non-capturing group
(a|b)    a hoặc b
\1 \2    backreference đến group 1, 2
```

### How – BRE vs ERE vs PCRE

```bash
# BRE (Basic RE) – grep mặc định, sed mặc định
# Cần escape: \( \) \{ \} \+ \?
grep "error\|warning" app.log       # alternation trong BRE
grep "\(error\)\{3\}" app.log       # repeat trong BRE

# ERE (Extended RE) – grep -E, sed -E
# Không cần escape: ( ) { } + ?
grep -E "error|warning" app.log
grep -E "error{2,3}" app.log
grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2}" app.log  # date pattern

# PCRE (Perl Compatible RE) – grep -P
# Thêm: \d \w \s lookahead/lookbehind named groups
grep -P "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" access.log  # IP
grep -P "(?<=User: )\w+" log.txt    # lookbehind
grep -P "error(?=:)" log.txt        # lookahead
```

### How – Practical Patterns

```bash
# IP Address
grep -E "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" file.txt

# Email
grep -E "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" file.txt

# URL
grep -E "https?://[a-zA-Z0-9./?=_%:-]+" file.txt

# Date (YYYY-MM-DD)
grep -E "[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])" file.txt

# IPv6
grep -P "([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}" file.txt

# Log timestamp (e.g., [2024-01-15 10:30:00])
grep -E "\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]" app.log

# JSON key-value (basic)
grep -P '"(\w+)":\s*"([^"]*)"' json.txt
```

---

## 2. grep – Advanced

### How – Advanced grep Options

```bash
# Recursive search với include/exclude
grep -r "TODO" --include="*.java" /src/
grep -r "password" --exclude="*.md" --exclude-dir=".git" /etc/
grep -r "secret" --include="*.{yml,yaml,conf}" /app/

# Multiple patterns
grep -e "error" -e "warning" -e "critical" app.log
grep -E "(error|warning|critical)" app.log

# Fixed string (không interpret regex)
grep -F "192.168.1.1" access.log    # literal match, faster
grep -F "$VAR_NAME" script.sh       # tìm literal dollar sign

# Context
grep -A 5 -B 2 "OutOfMemoryError" app.log  # 5 after, 2 before
grep -C 3 "Exception" app.log               # 3 around

# Color và counting
grep --color=always "ERROR" app.log | less -R  # color trong pager
grep -c "ERROR" *.log               # count per file
grep -H "ERROR" *.log               # print filename kèm

# Quiet mode (scripts)
if grep -q "error" app.log; then
    echo "Errors found!"
fi

# Invert + recursive tìm files không chứa pattern
grep -rL "Copyright" /src/java/     # files KHÔNG có Copyright

# Show only matches (không show cả dòng)
grep -o "[0-9]\+" numbers.txt       # chỉ in phần match
grep -oP "\d+\.\d+\.\d+\.\d+" access.log  # chỉ in IP addresses
```

---

## 3. sed – Advanced Stream Editor

### How – sed Addressing

```bash
# Địa chỉ theo dòng
sed '5s/foo/bar/' file.txt           # chỉ dòng 5
sed '5,10s/foo/bar/' file.txt        # dòng 5 đến 10
sed '5,+3s/foo/bar/' file.txt        # dòng 5 và 3 dòng tiếp theo
sed '5~2s/foo/bar/' file.txt         # dòng 5, 7, 9, 11... (step 2)
sed '${s/foo/bar/}' file.txt         # dòng cuối
sed '/pattern/s/foo/bar/' file.txt   # dòng chứa pattern

# Ranges
sed '/start/,/end/s/foo/bar/' file.txt  # từ dòng chứa "start" đến "end"
sed '/start/,/end/d' file.txt           # xóa block
```

### How – sed Multi-command

```bash
# -e: multiple commands
sed -e 's/foo/bar/' -e 's/baz/qux/' file.txt

# ; để tách commands
sed 's/foo/bar/;s/baz/qux/' file.txt

# Script file
cat > fix.sed << 'EOF'
s/http:/https:/g
s/www\.old-domain\.com/www.new-domain.com/g
/^#/d
/^$/d
EOF
sed -f fix.sed input.txt

# Multi-line patterns (N command)
sed ':a;N;$!ba;s/\n/ /g' file.txt    # join tất cả lines thành 1 dòng
sed 'N;s/\n/ /' file.txt             # join pairs of lines

# Hold space (buffer ẩn)
sed -n 'H;${x;s/\n/,/g;s/^,//;p}' file.txt  # join lines với comma
```

### How – sed Advanced Substitutions

```bash
# Backreferences trong replacement
sed 's/\(foo\) \(bar\)/\2 \1/' file.txt        # BRE: swap foo bar → bar foo
sed -E 's/(foo) (bar)/\2 \1/' file.txt          # ERE: same
sed -E 's/([0-9]+)/[\1]/g' file.txt             # wrap numbers in []

# & (entire match)
sed 's/[0-9]\+/(&)/g' file.txt       # wrap mỗi số trong ()
sed 's/.*/[&]/' file.txt             # wrap mỗi dòng trong []

# Case conversion (GNU sed)
sed 's/\b./\u&/g' file.txt          # capitalize first letter of each word
sed 's/.*/\L&/' file.txt            # convert to lowercase
sed 's/.*/\U&/' file.txt            # convert to uppercase

# Delete leading/trailing whitespace
sed 's/^[[:space:]]*//' file.txt    # leading whitespace
sed 's/[[:space:]]*$//' file.txt    # trailing whitespace
sed 's/^[[:space:]]*//;s/[[:space:]]*$//' file.txt  # both
```

### How – sed Production Patterns

```bash
# Uncomment a line
sed -i '/^#MaxConnections/s/^#//' /etc/ssh/sshd_config

# Thêm dòng sau pattern
sed -i '/^\[Service\]/a RestartSec=5' /etc/systemd/system/myapp.service

# Thêm dòng trước pattern
sed -i '/^ExecStart/i EnvironmentFile=/etc/myapp/env' /etc/systemd/system/myapp.service

# Replace nội dung giữa hai markers
sed -i '/# BEGIN CONFIG/,/# END CONFIG/c\
# BEGIN CONFIG\
NEW_SETTING=value\
# END CONFIG' config.file

# In-place với backup (cross-platform safe)
cp config.file config.file.bak && sed -i 's/old/new/g' config.file
```

---

## 4. awk – Advanced

### How – awk Program Structure

```bash
# Cú pháp đầy đủ:
# awk 'BEGIN{setup} /pattern/{action} END{teardown}' file

# BEGIN: chạy 1 lần trước khi đọc input
awk 'BEGIN {print "=== Report ==="; FS=":"} {print $1} END {print "Done"}' /etc/passwd

# Built-in variables
# FS   – Field Separator (mặc định: whitespace)
# OFS  – Output Field Separator
# RS   – Record Separator (mặc định: newline)
# ORS  – Output Record Separator
# NR   – Number of Records (line number, tổng)
# NF   – Number of Fields (columns trên dòng hiện tại)
# FNR  – File Number of Records (line number trong file hiện tại)
# FILENAME – tên file đang xử lý
# $0   – toàn bộ dòng
# $NF  – field cuối cùng
```

### How – awk One-liners

```bash
# Print specific columns
awk '{print $1, $3}' file.txt
awk -F: '{print $1, $3}' /etc/passwd     # username và UID
awk '{print $(NF)}' file.txt             # cột cuối
awk '{print $(NF-1)}' file.txt           # cột áp cuối

# Filter + print
awk 'NR >= 5 && NR <= 10' file.txt       # dòng 5-10
awk 'NR % 2 == 0' file.txt              # dòng chẵn
awk '$3 > 100 {print $0}' data.txt      # rows where column 3 > 100
awk 'length($0) > 80' file.txt          # dòng dài hơn 80 chars

# Arithmetic
awk '{sum += $1} END {print sum}' numbers.txt        # tổng
awk '{sum += $1; count++} END {print sum/count}' numbers.txt  # average
awk 'BEGIN{max=0} $1>max {max=$1} END {print max}' numbers.txt  # max

# String operations
awk '{print toupper($0)}' file.txt       # uppercase
awk '{print tolower($1)}' file.txt       # lowercase first field
awk '{gsub(/foo/, "bar"); print}' file.txt  # global substitution
awk '{sub(/^[ \t]+/, ""); print}' file.txt  # trim leading whitespace

# Multiple file processing
awk 'FNR==1 {print "=== " FILENAME " ==="}' file1.txt file2.txt
awk 'NR==FNR {a[$0]=1; next} $0 in a {print}' list.txt source.txt  # intersection
```

### How – awk Arrays & Complex Logic

```bash
# Counting / Frequency
awk '{count[$1]++} END {for (k in count) print k, count[k]}' data.txt

# Sort by value (pipe to sort)
awk '{count[$1]++} END {for (k in count) print count[k], k}' data.txt | sort -rn

# Group and aggregate
awk -F, '{sum[$1] += $3} END {for (k in sum) print k, sum[k]}' sales.csv

# Print unique lines (alternative to sort | uniq)
awk '!seen[$0]++' file.txt

# Find duplicates
awk 'seen[$0]++ == 1' file.txt

# Join two files (như SQL JOIN)
# File1: id name
# File2: id score
awk 'NR==FNR {name[$1]=$2; next} {print $1, name[$1], $2}' file1.txt file2.txt

# Transpose columns/rows
awk '{for(i=1;i<=NF;i++) a[NR][i]=$i} END {for(j=1;j<=NF;j++) {for(i=1;i<=NR;i++) printf a[i][j]" "; print ""}}' matrix.txt
```

### How – awk for Log Analysis

```bash
# Nginx access log format:
# $remote_addr - $remote_user [$time_local] "$request" $status $bytes "$http_referer" "$http_user_agent"

# HTTP status code distribution
awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Top 10 IPs by requests
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# Top 10 URLs
awk '{print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# Average response size
awk '{sum += $10; count++} END {printf "Avg size: %.0f bytes\n", sum/count}' access.log

# Error rate per hour
awk '$9 >= 400 {
    split($4, t, "[:/]")
    hour = t[3] ":" t[4]
    errors[hour]++
    total[hour]++
}
$9 < 400 {
    split($4, t, "[:/]")
    hour = t[3] ":" t[4]
    total[hour]++
}
END {
    for (h in total) printf "%s errors=%d total=%d rate=%.1f%%\n",
        h, errors[h]+0, total[h], (errors[h]+0)/total[h]*100
}' access.log | sort

# Requests per minute (real-time traffic analysis)
awk '{print substr($4, 2, 17)}' access.log | sort | uniq -c
```

---

## 5. jq – JSON Processing

### What – jq là gì?
`jq` là command-line JSON processor. Là awk/sed cho JSON, cực kỳ hữu dụng trong DevOps khi làm việc với REST APIs, config files, logs.

### How – jq Basics

```bash
# Cài đặt
apt install jq

# Input: JSON string hoặc file
echo '{"name":"Alice","age":30}' | jq '.'    # pretty print
jq '.' data.json                              # pretty print file

# Truy cập fields
echo '{"name":"Alice","age":30}' | jq '.name'           # "Alice"
echo '{"user":{"name":"Alice"}}' | jq '.user.name'      # "Alice"
echo '{"items":[1,2,3]}' | jq '.items[0]'               # 1
echo '{"items":[1,2,3]}' | jq '.items[-1]'              # 3 (last)
echo '{"items":[1,2,3]}' | jq '.items[1:3]'             # [2,3] (slice)

# Raw string output (không có quotes)
echo '{"name":"Alice"}' | jq -r '.name'     # Alice (no quotes)

# Null handling
echo '{"a":1}' | jq '.b // "default"'       # "default" (null-coalescing)
echo '{"a":null}' | jq '.a // "fallback"'   # "fallback"
```

### How – jq Arrays & Objects

```bash
# Array operations
echo '[1,2,3,4,5]' | jq '.[]'               # iterate all elements
echo '[1,2,3]' | jq 'length'                # 3
echo '[1,2,3]' | jq 'first, last'           # 1, 3
echo '[3,1,2]' | jq 'sort'                  # [1,2,3]
echo '[1,2,2,3]' | jq 'unique'              # [1,2,3]
echo '[[1,2],[3,4]]' | jq 'flatten'         # [1,2,3,4]
echo '[1,2,3]' | jq 'reverse'               # [3,2,1]
echo '[1,2,3]' | jq 'map(. * 2)'            # [2,4,6]
echo '[1,2,3,4]' | jq '[.[] | select(. > 2)]'  # [3,4]
echo '[1,2,3]' | jq 'add'                   # 6 (sum)

# Object operations
echo '{"a":1,"b":2}' | jq 'keys'            # ["a","b"]
echo '{"a":1,"b":2}' | jq 'values'          # [1,2]
echo '{"a":1,"b":2}' | jq 'to_entries'      # [{key,value} objects]
echo '{"a":1}' | jq '. + {"b":2}'           # merge objects
echo '{"a":1,"b":2}' | jq 'del(.b)'         # delete key

# Construct new objects
echo '{"name":"Alice","age":30,"city":"NY"}' | jq '{name, city}'  # pick fields
echo '[{"name":"Alice","age":30}]' | jq '.[] | {name: .name, doubled_age: (.age * 2)}'
```

### How – jq Advanced Queries

```bash
# Filter array of objects
echo '[{"name":"Alice","active":true},{"name":"Bob","active":false}]' | \
    jq '[.[] | select(.active == true)]'

# Map over array
echo '[{"name":"Alice"},{"name":"Bob"}]' | jq '[.[] | .name]'
# Shorthand:
echo '[{"name":"Alice"},{"name":"Bob"}]' | jq '[.[].name]'
# Even shorter:
echo '[{"name":"Alice"},{"name":"Bob"}]' | jq '.[].name'

# group_by
echo '[{"type":"a","val":1},{"type":"b","val":2},{"type":"a","val":3}]' | \
    jq 'group_by(.type) | map({type: .[0].type, total: (map(.val) | add)})'

# String interpolation
echo '{"name":"Alice","score":95}' | jq '"User \(.name) scored \(.score)"'

# Conditional
echo '{"score":75}' | jq 'if .score >= 90 then "A" elif .score >= 80 then "B" else "C" end'

# Recursive descent
echo '{"a":{"b":{"c":42}}}' | jq '.. | numbers'  # find all numbers recursively
```

### How – jq Real-world DevOps

```bash
# Parse kubectl output
kubectl get pods -o json | jq '.items[] | {name: .metadata.name, status: .status.phase}'
kubectl get pods -o json | jq '[.items[] | select(.status.phase != "Running")]'

# Parse AWS CLI output
aws ec2 describe-instances | jq '.Reservations[].Instances[] | {id: .InstanceId, ip: .PrivateIpAddress, state: .State.Name}'

# Process docker inspect
docker inspect mycontainer | jq '.[0].NetworkSettings.IPAddress'
docker ps -q | xargs docker inspect | jq '.[] | {name: .Name, ip: .NetworkSettings.IPAddress}'

# GitHub API
curl -s "https://api.github.com/repos/org/repo/pulls" | \
    jq '.[] | {number: .number, title: .title, author: .user.login}'

# Extract from nested arrays
jq '.results[] | .items[] | select(.status == "error") | .message' response.json

# Build JSON from shell variables
jq -n --arg name "$NAME" --arg env "$ENV" '{"name": $name, "env": $env}'
jq -n --argjson port "$PORT" '{"port": $port}'  # number type
```

---

## 6. Other Advanced Text Tools

### How – sort advanced

```bash
# Sort by multiple keys
sort -k2,2 -k1,1n data.txt          # primary: col2 alpha; secondary: col1 numeric
sort -t: -k3,3n /etc/passwd         # sort by UID (field 3, numeric)
sort -k5,5hr file.txt               # col5, human-readable, reverse

# Sort stability
sort -s -k1,1 data.txt              # stable sort (preserve order for equal keys)

# Check if sorted
sort -c data.txt                    # exit code 1 nếu không sorted
sort -C data.txt                    # quiet version
```

### How – awk vs Python cho complex processing

```bash
# Khi awk không đủ: dùng Python one-liner
python3 -c "
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    if d.get('level') == 'ERROR':
        print(d['message'])
" < structured.log

# CSV processing với Python
python3 -c "
import sys, csv
reader = csv.DictReader(sys.stdin)
total = sum(float(row['amount']) for row in reader if row['status'] == 'paid')
print(f'Total paid: {total:.2f}')
"
```

### How – parallel text processing

```bash
# GNU parallel (cài: apt install parallel)
# Xử lý nhiều files song song
ls *.log | parallel gzip {}

# parallel grep (nhanh hơn cho nhiều files lớn)
find . -name "*.log" | parallel -j4 grep -l "ERROR" {}

# xargs với -P (parallel)
find . -name "*.txt" | xargs -P 4 -I {} wc -l {}
```

---

## 7. Compare & Trade-offs

### Compare – grep vs awk vs sed vs jq

| | grep | sed | awk | jq |
|--|------|-----|-----|----|
| Dữ liệu | Bất kỳ text | Bất kỳ text | Structured text | JSON only |
| Mục đích | Filter dòng | Transform text | Compute, parse | Parse JSON |
| Fields | Không | Không | Có (whitespace/delimiter) | Có (key names) |
| Arithmetic | Không | Không | Có | Có |
| Learning curve | Thấp | Trung bình | Trung bình | Trung bình |
| Performance | Rất nhanh | Nhanh | Nhanh | Nhanh |

### Trade-offs
- **awk**: rất mạnh cho text, nhưng khi logic phức tạp → chuyển sang Python
- **sed**: tốt cho substitution, nhưng multi-line phức tạp → awk hoặc Python
- **jq**: perfect cho JSON, nhưng không xử lý YAML/TOML → `yq` cho YAML
- **Regex**: BRE (portable) vs ERE (readable) vs PCRE (powerful) – chọn theo tool

### Real-world Pipeline Examples

```bash
# Parse structured JSON logs (e.g., from Node.js/Java)
tail -f app.log | jq -r 'select(.level == "ERROR") | "\(.timestamp) \(.message)"'

# Nginx log → error report
awk '$9 >= 400' /var/log/nginx/access.log | \
    awk '{print $9, $7}' | \
    sort | uniq -c | sort -rn | \
    awk '{printf "%5d  HTTP %-3s  %s\n", $1, $2, $3}' | \
    head -20

# Config file processing pipeline
grep -v "^#" /etc/nginx/nginx.conf | \
    sed '/^$/d' | \
    awk '/server {/{found=1} found{print} /}/{found=0}'

# Extract and transform data
cat users.csv | \
    awk -F, 'NR>1 {print $1, $2, $4}' | \      # skip header, select fields
    sed 's/ /_/g' | \                             # spaces to underscore
    sort -k3,3rn | \                              # sort by score desc
    head -10                                       # top 10
```

---

### Ghi chú – Chủ đề tiếp theo
> **11.3 Process & Resource Management Advanced**: cgroups v2, namespaces, ulimit, strace, ltrace, perf
