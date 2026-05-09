# Bash Scripting Deep Dive – Basics

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Variable Types & Scoping

### What – Variables trong Bash
Bash là **dynamically typed** (không khai báo type), nhưng có thể dùng `declare` để set attributes.

### How – Variable Types

```bash
# String (default)
NAME="Alice"
GREETING="Hello, $NAME"
echo "${NAME^^}"                     # ALICE (uppercase)
echo "${NAME,,}"                     # alice (lowercase)
echo "${#NAME}"                      # 5 (length)

# Integer với declare
declare -i COUNT=0
COUNT=COUNT+1                        # arithmetic tự động
declare -i RESULT=10/3               # 3 (integer division)

# Read-only
declare -r PI=3.14159
readonly MAX_SIZE=100
# PI=3 → bash: PI: readonly variable (error)

# Export (environment variable)
declare -x API_URL="https://api.example.com"
export DB_HOST="localhost"           # same effect

# Lowercase/uppercase naming convention
# Uppercase: environment vars, constants (PATH, HOME, API_KEY)
# Lowercase: local script vars (count, name, result)

# Nameref (reference to another variable) – Bash 4.3+
declare -n ref=NAME
ref="Bob"                            # thay đổi NAME qua ref
echo "$NAME"                         # Bob
```

### How – String Operations

```bash
NAME="Hello, World!"

# Length
echo "${#NAME}"                      # 13

# Substring: ${var:offset:length}
echo "${NAME:7}"                     # World!
echo "${NAME:7:5}"                   # World
echo "${NAME: -6}"                   # orld! (từ cuối)
echo "${NAME: -6:5}"                 # orld

# Pattern removal
FILE="/var/log/nginx/access.log"
echo "${FILE#*/}"                    # var/log/nginx/access.log (remove shortest prefix)
echo "${FILE##*/}"                   # access.log (remove longest prefix = basename)
echo "${FILE%/*}"                    # /var/log/nginx (remove shortest suffix = dirname)
echo "${FILE%%.*}"                   # /var/log/nginx/access (remove longest suffix)

# Replacement
TEXT="foo bar foo baz"
echo "${TEXT/foo/qux}"               # qux bar foo baz (first)
echo "${TEXT//foo/qux}"              # qux bar qux baz (all)
echo "${TEXT/#foo/qux}"              # qux bar foo baz (only if starts with)
echo "${TEXT/%baz/END}"              # foo bar foo END (only if ends with)

# Default values
echo "${UNDEFINED:-default}"         # default (nếu unset hoặc empty)
echo "${UNDEFINED-default}"          # default (chỉ nếu unset)
echo "${VAR:=value}"                 # assign nếu unset/empty, then use
echo "${REQUIRED:?Error: required}"  # error nếu unset

# Case conversion (Bash 4+)
STR="hello world"
echo "${STR^}"                       # Hello world (capitalize first)
echo "${STR^^}"                      # HELLO WORLD (all uppercase)
echo "${STR,,}"                      # hello world (all lowercase)

# Check if set
[[ -v MY_VAR ]] && echo "set" || echo "unset"
[[ -z "${MY_VAR}" ]] && echo "empty"
[[ -n "${MY_VAR}" ]] && echo "non-empty"
```

---

## 2. Arrays

### How – Indexed Arrays

```bash
# Khai báo
declare -a FRUITS=("apple" "banana" "cherry")
SERVERS=("web1" "web2" "web3")         # implicit declare
FILES=()                                # empty array

# Thêm phần tử
FRUITS+=("date")                        # append
FRUITS[4]="elderberry"                  # set by index

# Truy cập
echo "${FRUITS[0]}"                     # apple
echo "${FRUITS[-1]}"                    # elderberry (last)
echo "${FRUITS[@]}"                     # tất cả phần tử
echo "${FRUITS[*]}"                     # tất cả phần tử (khác biệt khi trong "")
echo "${#FRUITS[@]}"                    # số phần tử (5)
echo "${!FRUITS[@]}"                    # indices (0 1 2 3 4)

# Slice
echo "${FRUITS[@]:1:3}"                 # banana cherry date (từ index 1, lấy 3)

# Delete
unset "FRUITS[2]"                       # xóa index 2 (cherry)
unset FRUITS                            # xóa toàn bộ array

# Iterate
for fruit in "${FRUITS[@]}"; do
    echo "Fruit: $fruit"
done

# Iterate với index
for i in "${!FRUITS[@]}"; do
    echo "$i: ${FRUITS[$i]}"
done

# Readarray / mapfile (read file into array)
readarray -t LINES < input.txt          # mỗi dòng thành 1 element
mapfile -t LINES < input.txt            # same
readarray -t LINES < <(find . -name "*.log")  # from command output
```

### How – Associative Arrays (Hash Maps)

```bash
# Khai báo (PHẢI dùng declare -A)
declare -A CONFIG
declare -A COLORS=([red]="#FF0000" [green]="#00FF00" [blue]="#0000FF")

# Set
CONFIG[host]="localhost"
CONFIG[port]="5432"
CONFIG[db]="myapp"

# Truy cập
echo "${CONFIG[host]}"                  # localhost
echo "${CONFIG[@]}"                     # tất cả values
echo "${!CONFIG[@]}"                    # tất cả keys
echo "${#CONFIG[@]}"                    # số entries

# Check key exists
if [[ -v CONFIG[host] ]]; then
    echo "host is set"
fi

# Delete
unset "CONFIG[host]"

# Iterate
for key in "${!CONFIG[@]}"; do
    echo "$key = ${CONFIG[$key]}"
done

# Build từ output
declare -A USER_HOME
while IFS=: read -r user _ _ _ _ home _; do
    USER_HOME[$user]=$home
done < /etc/passwd
echo "${USER_HOME[root]}"               # /root
```

---

## 3. Arithmetic

### How – Arithmetic Expansion

```bash
# $(( )) – arithmetic expansion (integer only)
echo $((2 + 3))                        # 5
echo $((10 / 3))                       # 3 (integer division)
echo $((10 % 3))                       # 1 (modulo)
echo $((2 ** 10))                      # 1024 (power)
echo $((16#FF))                        # 255 (hex to decimal)
echo $((8#77))                         # 63 (octal to decimal)
echo $((2#1010))                       # 10 (binary to decimal)

# Variables
x=5; y=3
echo $((x * y))                        # 15
((x++))                                # increment
((y--))                                # decrement
((x += 10))                            # compound assignment
((result = x > y ? x : y))            # ternary

# Bitwise
echo $((5 & 3))                        # 1 (AND)
echo $((5 | 3))                        # 7 (OR)
echo $((5 ^ 3))                        # 6 (XOR)
echo $((~5))                           # -6 (NOT)
echo $((5 << 1))                       # 10 (left shift)
echo $((20 >> 2))                      # 5 (right shift)

# (( )) – arithmetic command (return 0 if true, 1 if false)
if ((x > y)); then
    echo "x is greater"
fi
((count++))                            # safe increment (no $)

# Floating point với bc
echo "scale=2; 10/3" | bc             # 3.33
echo "scale=4; sqrt(2)" | bc          # 1.4142
RESULT=$(echo "scale=2; $price * $qty" | bc)

# Python cho float (alternative)
python3 -c "print(10/3)"              # 3.3333333333333335
python3 -c "print(f'{10/3:.2f}')"    # 3.33
```

---

## 4. Here-docs & Here-strings

### How – Here-documents

```bash
# Basic heredoc
cat << EOF
Hello $USER
Today is $(date)
EOF

# Quoted (no expansion)
cat << 'EOF'
$LITERAL_TEXT
No expansion here: $(date)
EOF

# Indented heredoc (Bash 4+, dùng <<-)
if true; then
    cat <<- EOF
        Indented text (leading tabs stripped)
        Tab-indented
        EOF
fi

# Heredoc to file
cat > /etc/nginx/conf.d/myapp.conf << 'EOF'
server {
    listen 80;
    server_name myapp.com;
    location / {
        proxy_pass http://127.0.0.1:3000;
    }
}
EOF

# Heredoc to command
ssh user@host << 'ENDSSH'
    sudo systemctl restart nginx
    sudo systemctl status nginx
ENDSSH

# Heredoc in variable
QUERY=$(cat << 'EOF'
SELECT id, name
FROM users
WHERE active = true
ORDER BY created_at DESC
LIMIT 100;
EOF
)

psql mydb <<< "$QUERY"                 # here-string
```

### How – Here-strings

```bash
# <<< : single string as stdin
wc -w <<< "hello world"               # 2
read -r line <<< "first second third"
echo "$line"                           # first second third

# Check command output
if grep -q "error" <<< "$LOG_OUTPUT"; then
    echo "Error found"
fi

# Base64 decode
base64 -d <<< "SGVsbG8gV29ybGQ="      # Hello World
```

---

## 5. Input/Output & Redirection Deep Dive

### How – File Descriptors

```bash
# File Descriptors (FD)
# 0 = stdin
# 1 = stdout
# 2 = stderr
# 3+ = custom FDs

# Open custom FD
exec 3> output.txt                    # FD 3 → file for writing
echo "message" >&3                    # write to FD 3
exec 3>&-                             # close FD 3

exec 4< input.txt                     # FD 4 ← file for reading
read -u 4 line                        # read from FD 4
exec 4<&-                             # close FD 4

# Dupicate FDs
exec 5>&1                             # save stdout to FD 5
exec 1> output.log                    # redirect stdout to file
echo "goes to log"
exec 1>&5                             # restore stdout
exec 5>&-                             # close FD 5

# Redirect stderr to stdout
command 2>&1                          # stderr → stdout
command &> file.txt                   # both stdout + stderr to file (bash shorthand)
command 2>/dev/null                   # discard stderr

# Process substitution
diff <(sort file1.txt) <(sort file2.txt)   # virtual stdin
tee >(gzip > out.gz) >(wc -l) > /dev/null # multiple outputs
```

### How – tee & Advanced Redirection

```bash
# tee – write to file AND stdout
command | tee output.txt               # stdout + file
command | tee -a output.txt            # append
command | tee file1.txt file2.txt      # multiple files
command | tee >(process1) >(process2)  # process substitution

# Real-world: logging with tee
./deploy.sh 2>&1 | tee /var/log/deploy_$(date +%Y%m%d).log

# Named pipes (FIFO)
mkfifo /tmp/mypipe
command1 > /tmp/mypipe &
command2 < /tmp/mypipe
```

---

## 6. String Manipulation Patterns

### How – Common Patterns

```bash
# Trim whitespace
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"  # leading
    var="${var%"${var##*[![:space:]]}"}"  # trailing
    echo "$var"
}

# URL encode
urlencode() {
    python3 -c "import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# Join array with delimiter
join_by() {
    local IFS="$1"
    shift
    echo "$*"
}
join_by , "${ARRAY[@]}"                # "a,b,c"

# Split string into array
IFS=',' read -ra PARTS <<< "a,b,c,d"
for part in "${PARTS[@]}"; do echo "$part"; done

# String contains
if [[ "$str" == *"substring"* ]]; then
    echo "found"
fi

# String starts/ends with
[[ "$str" == prefix* ]] && echo "starts with prefix"
[[ "$str" == *suffix ]] && echo "ends with suffix"

# Regex match
if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "valid email"
fi
# Capture groups via BASH_REMATCH
if [[ "2024-01-15" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    year="${BASH_REMATCH[1]}"
    month="${BASH_REMATCH[2]}"
    day="${BASH_REMATCH[3]}"
fi

# Number padding
printf "%05d" 42                       # 00042
printf "%-10s|%10s" "left" "right"    # left padding
```

---

## 7. Control Flow Deep Dive

### How – case Statement

```bash
# case với patterns
case "$ENV" in
    production|prod)
        echo "Production mode"
        CONFIG_FILE="/etc/app/prod.conf"
        ;;
    staging|stage)
        echo "Staging mode"
        CONFIG_FILE="/etc/app/staging.conf"
        ;;
    development|dev|"")
        echo "Development mode"
        CONFIG_FILE="./config/dev.conf"
        ;;
    *)
        echo "Unknown environment: $ENV" >&2
        exit 1
        ;;
esac

# case với regex (Bash 4+, extglob)
shopt -s extglob
case "$INPUT" in
    +([0-9]))         echo "Positive integer" ;;
    -+([0-9]))        echo "Negative integer" ;;
    +([0-9]).+([0-9])) echo "Decimal" ;;
    *)                echo "Other" ;;
esac
```

### How – select – Interactive Menu

```bash
PS3="Choose an option: "
select OPTION in "Deploy" "Rollback" "Status" "Exit"; do
    case $OPTION in
        Deploy)   ./deploy.sh; break ;;
        Rollback) ./rollback.sh; break ;;
        Status)   ./status.sh ;;
        Exit)     exit 0 ;;
        *)        echo "Invalid option $REPLY" ;;
    esac
done
```

---

## 8. Real-world Patterns

### How – Config File Parsing

```bash
# Parse INI-style config
parse_config() {
    local file="$1"
    local section=""
    while IFS='= ' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue   # skip comments
        [[ "$key" =~ ^\[(.+)\]$ ]] && section="${BASH_REMATCH[1]}" && continue
        [[ -z "$key" ]] && continue
        declare -g "CONFIG_${section}_${key}=${value}"
    done < "$file"
}

parse_config app.ini
echo "$CONFIG_database_host"
```

### How – Parallel Execution

```bash
# Background jobs với wait
PIDS=()
for server in "${SERVERS[@]}"; do
    ssh "$server" "sudo systemctl restart nginx" &
    PIDS+=($!)
done

# Wait và check all
FAILED=0
for pid in "${PIDS[@]}"; do
    wait "$pid" || ((FAILED++))
done
[[ $FAILED -eq 0 ]] || { echo "Failed on $FAILED servers"; exit 1; }

# Limit parallelism (xargs)
printf '%s\n' "${SERVERS[@]}" | xargs -P 5 -I {} ssh {} "sudo systemctl restart nginx"
```

### Compare – Bash vs Python vs Ruby for scripting

| | Bash | Python | Ruby |
|--|------|--------|------|
| System integration | Native | via subprocess | via shell |
| Text processing | Powerful pipes | Libraries | Libraries |
| Learning curve | Steep (quirks) | Easy | Easy |
| Portability | Nearly universal | Need Python | Need Ruby |
| Complex logic | Difficult | Easy | Easy |
| Khi dùng | System tasks, DevOps | Complex logic, data | Flexible scripting |

**Rule of thumb**: Nếu cần >50 dòng logic phức tạp → Python thay vì Bash.

---

### Ghi chú – Chủ đề tiếp theo
> **12.2 Bash Advanced**: process substitution, subshell vs subprocess, coprocess, regex matching, getopts deep dive, signal handling
