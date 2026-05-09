# Bash Advanced – Deep Dive

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Subshells vs Subprocess vs Forking

### What – Subshell là gì?
**Subshell** là copy của shell hiện tại, chạy trong child process. Thay đổi variables, cd, set trong subshell **không ảnh hưởng** parent shell.

### How – Subshell Creation

```bash
# Explicit subshell với ()
(cd /tmp && ls)                        # ls trong /tmp, pwd không đổi sau
echo "$?"                              # exit code của subshell

# Subshell preserves environment
X=10
(X=20; echo "Inside: $X")             # Inside: 20
echo "Outside: $X"                    # Outside: 10

# Pipeline tạo subshell (QUAN TRỌNG!)
echo "hello" | read -r LINE
echo "$LINE"                           # EMPTY! read chạy trong subshell của pipe

# Fix: dùng process substitution hoặc lastpipe
shopt -s lastpipe                      # Bash 4.2+: last pipe cmd chạy trong current shell
echo "hello" | read -r LINE
echo "$LINE"                           # hello

# Fix: dùng $()
LINE=$(echo "hello")
echo "$LINE"                           # hello

# Subshell with timeout
timeout 5 bash -c 'sleep 10; echo done'  # kill nếu > 5 giây

# BASH_SUBSHELL variable
echo "Level: $BASH_SUBSHELL"           # 0 (parent)
(echo "Level: $BASH_SUBSHELL")         # 1
((echo "Level: $BASH_SUBSHELL"))       # 2
```

### How – Command Substitution

```bash
# $() vs `` (backtick)
DATE=$(date +%Y-%m-%d)                 # preferred
DATE=`date +%Y-%m-%d`                  # legacy, harder to nest

# Nesting (chỉ $() có thể nest dễ dàng)
RESULT=$(echo $(cat file.txt | wc -l))

# Capture exit code
OUTPUT=$(command)
EXIT_CODE=$?

# Trailing newlines bị stripped
OUTPUT=$(printf "line1\nline2\n")
echo "$OUTPUT"                         # line1↵line2 (trailing newline stripped)

# Giữ trailing newlines
OUTPUT=$(printf "line1\nline2\n"; echo x)
OUTPUT="${OUTPUT%x}"                   # remove the trailing 'x'
```

---

## 2. Process Substitution

### What – Process Substitution là gì?
**Process substitution** `<()` và `>()` cho phép dùng output của command như một file. Tạo named pipe (FIFO) hoặc `/dev/fd/` để truyền data.

### How – Sử dụng

```bash
# <() – command output as file (for reading)
diff <(sort file1.txt) <(sort file2.txt)   # diff sorted versions
comm <(sort list1) <(sort list2)            # set operations
wc -l <(find . -name "*.java")              # count files
grep "pattern" <(cat /var/log/*.log)        # grep multiple logs as one

# Multiple process substitutions
diff <(ssh server1 "ls /opt/app") <(ssh server2 "ls /opt/app")

# >() – command as file (for writing)
tee >(wc -l > line_count.txt) >(grep ERROR > errors.txt) > /dev/null

# Logging tất cả trong khi vẫn in ra screen
./deploy.sh > >(tee deploy.log) 2> >(tee errors.log >&2)

# Phân tích: bước trung gian
sort < <(cat /etc/passwd | cut -d: -f1)    # redirect from process sub

# Không thể pipe trực tiếp vào process sub:
# command | <(other_command)  ← WRONG
# Nhưng có thể:
command | tee >(process1) >(process2) > /dev/null
```

---

## 3. Coprocesses

### What – Coprocess là gì?
**Coprocess** (Bash 4+) chạy command trong background và tạo 2 pipes (stdin, stdout) để communicate bi-directionally, khác với subshell/subprocess.

### How – Sử dụng

```bash
# Tạo coprocess
coproc MY_COPROC { bc; }
# MY_COPROC[0] = FD đọc output của coprocess
# MY_COPROC[1] = FD write vào input của coprocess
# MY_COPROC_PID = PID

# Giao tiếp
echo "2^10" >&"${MY_COPROC[1]}"       # send expression
read result <&"${MY_COPROC[0]}"       # read result
echo "$result"                         # 1024

# Ứng dụng: persistent connection
coproc DB { psql -U user mydb 2>/dev/null; }
echo "SELECT count(*) FROM users;" >&"${DB[1]}"
read count <&"${DB[0]}"

# Đóng
exec "${DB[1]}">&-                     # close stdin của coprocess → EOF
wait "${DB_PID}"
```

---

## 4. getopts – Argument Parsing

### What – getopts là gì?
`getopts` là bash builtin để parse **POSIX-style** short options (`-f`, `-v`). Khác với `getopt` (external command, hỗ trợ long options).

### How – getopts Deep Dive

```bash
#!/usr/bin/env bash
set -euo pipefail

# getopts syntax: getopts "optstring" OPTVAR
# optstring: letters; : after letter = expects argument
# OPTARG: value cho option có argument
# OPTIND: index của next argument to be processed

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <environment>

Options:
  -h          Show this help
  -v          Verbose mode
  -e <env>    Environment (dev|staging|prod)
  -t <tag>    Docker image tag (default: latest)
  -f          Force deployment (skip confirmation)
  -n <count>  Number of replicas (default: 2)

Arguments:
  environment  Target environment

Examples:
  $(basename "$0") -e prod -t v1.2.3 production
  $(basename "$0") -vf -e staging staging
EOF
}

# Defaults
VERBOSE=false
FORCE=false
ENV=""
TAG="latest"
REPLICAS=2

# Parse options
while getopts ":hve:t:fn:" opt; do
    case "$opt" in
        h)  usage; exit 0 ;;
        v)  VERBOSE=true ;;
        e)  ENV="$OPTARG" ;;
        t)  TAG="$OPTARG" ;;
        f)  FORCE=true ;;
        n)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: -n requires a positive integer" >&2
                exit 1
            fi
            REPLICAS="$OPTARG"
            ;;
        :)  echo "Error: -$OPTARG requires an argument" >&2; usage; exit 1 ;;
        \?) echo "Error: Unknown option -$OPTARG" >&2; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))                  # shift processed options

# Validate positional args
[[ $# -ge 1 ]] || { echo "Error: environment argument required" >&2; usage; exit 1; }
DEPLOY_TARGET="$1"

$VERBOSE && set -x
echo "Deploying: env=$ENV, tag=$TAG, replicas=$REPLICAS, force=$FORCE, target=$DEPLOY_TARGET"
```

### How – Long Options với getopt (external)

```bash
#!/usr/bin/env bash
# getopt (không phải getopts) hỗ trợ long options

# Parse long options
OPTS=$(getopt \
    --options hve:t:fn: \
    --longoptions help,verbose,env:,tag:,force,replicas: \
    --name "$(basename "$0")" -- "$@")

[[ $? -ne 0 ]] && { echo "Failed to parse options" >&2; exit 1; }

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        -v|--verbose)  VERBOSE=true; shift ;;
        -e|--env)      ENV="$2"; shift 2 ;;
        -t|--tag)      TAG="$2"; shift 2 ;;
        -f|--force)    FORCE=true; shift ;;
        -n|--replicas) REPLICAS="$2"; shift 2 ;;
        --)            shift; break ;;
        *)             echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
```

---

## 5. Signal Handling & Traps

### What – Signals trong Bash Scripts
Scripts có thể **catch signals** và thực hiện cleanup trước khi exit.

### How – trap

```bash
# trap 'command' SIGNAL [SIGNAL...]

# Cleanup on exit (luôn chạy)
TMPFILE=$(mktemp)
LOCKFILE="/var/run/myscript.pid"

cleanup() {
    echo "Cleaning up..."
    rm -f "$TMPFILE" "$LOCKFILE"
}
trap cleanup EXIT                      # chạy khi script exit (bất kể lý do)

# Handle interrupt
handle_interrupt() {
    echo ""
    echo "Script interrupted by user"
    exit 130                           # convention: 128 + signal number
}
trap handle_interrupt INT TERM

# Log signals
trap 'echo "Received SIGUSR1"' USR1
trap 'echo "Received SIGUSR2"' USR2
trap 'echo "Received SIGHUP – reloading config"' HUP

# Reset trap
trap - INT                             # reset INT to default
trap "" INT                            # ignore INT (không thể Ctrl+C)

# PID file pattern
PID_FILE="/var/run/myservice.pid"
trap 'rm -f "$PID_FILE"; exit' INT TERM EXIT
echo $$ > "$PID_FILE"

# Graceful shutdown với timeout
cleanup_with_timeout() {
    echo "Stopping workers..."
    kill "${WORKER_PIDS[@]}" 2>/dev/null
    local waited=0
    while kill -0 "${WORKER_PIDS[@]}" 2>/dev/null && [[ $waited -lt 30 ]]; do
        sleep 1
        ((waited++))
    done
    kill -9 "${WORKER_PIDS[@]}" 2>/dev/null
    echo "Cleanup done"
}
trap cleanup_with_timeout EXIT
```

### How – Debugging với trap DEBUG

```bash
# Trace execution
set -x                                 # print each command before executing
set +x                                 # turn off

# DEBUG trap: runs before each command
trap 'echo "DEBUG: $BASH_COMMAND"' DEBUG

# ERR trap: runs when command fails (complement to set -e)
trap 'echo "ERROR: line $LINENO: $BASH_COMMAND"' ERR

# RETURN trap: runs when function returns
func() {
    trap 'echo "Returning from func"' RETURN
    echo "In func"
}

# Detailed error function
error_handler() {
    local exit_code=$?
    local line_number=$1
    echo "Error $exit_code on line $line_number: $BASH_COMMAND" >&2
    echo "Stack trace:"
    local i
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        echo "  ${FUNCNAME[$i]} (${BASH_SOURCE[$i]}:${BASH_LINENO[$((i-1))]})"
    done
    exit $exit_code
}
trap 'error_handler $LINENO' ERR
```

---

## 6. Advanced I/O Patterns

### How – Reading User Input

```bash
# read – đọc từ stdin
read -r NAME                           # đọc 1 dòng
read -r -p "Enter name: " NAME        # với prompt
read -r -s -p "Password: " PASS       # silent (ẩn input)
read -r -t 10 INPUT                    # timeout 10 giây
read -r -n 1 CHOICE                   # chỉ đọc 1 ký tự
read -r -d '' MULTILINE               # đọc đến null byte (heredoc content)
read -r -a ARRAY <<< "a b c d"        # đọc vào array

# Check timeout
if ! read -r -t 5 -p "Continue? [y/N] " ANSWER; then
    echo "Timeout – assuming No"
    ANSWER="n"
fi

# Read with validation loop
while true; do
    read -r -p "Enter port (1024-65535): " PORT
    if [[ "$PORT" =~ ^[0-9]+$ ]] && ((PORT >= 1024 && PORT <= 65535)); then
        break
    fi
    echo "Invalid port. Try again."
done

# Dialog/whiptail – TUI
dialog --inputbox "Enter hostname:" 8 40 2>/tmp/answer
HOSTNAME=$(cat /tmp/answer)
```

### How – Output Formatting

```bash
# printf (more reliable than echo)
printf "%-20s %5d %8.2f\n" "Product" 42 19.99
printf "%s\n" "${ARRAY[@]}"           # array, one per line
printf "%b" "Line1\nLine2\n"          # interpret backslash escapes

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'                           # No Color

echo -e "${GREEN}Success${NC}"
echo -e "${RED}Error: something failed${NC}"
printf "${YELLOW}Warning: %s${NC}\n" "disk almost full"

# Progress bar
progress_bar() {
    local current=$1 total=$2 width=${3:-50}
    local percent=$(( current * 100 / total ))
    local filled=$(( width * current / total ))
    local empty=$(( width - filled ))
    printf "\r[%s%s] %3d%%" "$(printf '#%.0s' $(seq 1 $filled))" \
           "$(printf '.%.0s' $(seq 1 $empty))" "$percent"
    [[ $current -eq $total ]] && echo
}

# Spinner
spinner() {
    local pid=$1 chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    while kill -0 "$pid" 2>/dev/null; do
        for ((i=0; i<${#chars}; i++)); do
            printf "\r${chars:$i:1} Processing..."
            sleep 0.1
        done
    done
    printf "\r✓ Done!              \n"
}
```

---

## 7. Bash Options & Modes

### How – set Options

```bash
set -e                    # exit on error (ERR)
set -u                    # error on undefined variable
set -o pipefail           # pipe fails if any component fails
set -x                    # trace mode (debug)
set -n                    # dry run (parse but don't execute)
set -v                    # verbose (print lines as read)
set -C                    # prevent > from overwriting files
set -f                    # disable globbing

# Best practice header cho production scripts
set -euo pipefail

# shopt – shell options
shopt -s extglob          # extended globbing (+(pattern), ?(pattern), etc.)
shopt -s globstar         # **/ matches any number of dirs
shopt -s nullglob         # glob patterns → empty array (not literal) if no match
shopt -s dotglob          # include hidden files in glob
shopt -s nocaseglob       # case-insensitive globbing
shopt -s lastpipe         # last pipe cmd in current shell
shopt -s histappend       # append history (not overwrite)

# Extended globbing patterns (requires extglob)
ls +(foo|bar)*.txt        # one or more "foo" or "bar"
ls ?(optional)file.txt    # zero or one
ls !(exclude).txt         # NOT matching
ls *(any).log             # zero or more
ls @(exactly_one).conf    # exactly one
```

---

## 8. Real-world Advanced Patterns

### How – Script Locking (prevent concurrent runs)

```bash
# flock – file locking
LOCKFILE="/var/run/myscript.lock"

(
    flock -n 9 || { echo "Script already running"; exit 1; }
    # ... critical section ...
) 9>"$LOCKFILE"

# Hoặc với timeout
flock --timeout 30 "$LOCKFILE" ./script.sh

# PID-based lock
PIDFILE="/var/run/myscript.pid"
if [[ -f "$PIDFILE" ]]; then
    OLD_PID=$(cat "$PIDFILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Script already running (PID $OLD_PID)" >&2
        exit 1
    fi
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
```

### How – Retry Logic

```bash
retry() {
    local attempts=${RETRY_ATTEMPTS:-3}
    local delay=${RETRY_DELAY:-5}
    local count=0

    until "$@"; do
        ((count++))
        [[ $count -ge $attempts ]] && {
            echo "Failed after $attempts attempts: $*" >&2
            return 1
        }
        echo "Attempt $count failed. Retrying in ${delay}s..." >&2
        sleep "$delay"
        delay=$((delay * 2))           # exponential backoff
    done
}

retry curl -f https://api.example.com/health
retry psql -c "SELECT 1" || exit 1
```

### How – Script Testing với BATS

```bash
# BATS (Bash Automated Testing System)
# apt install bats

# test_deploy.bats
@test "deploy fails without environment" {
    run ./deploy.sh
    [ "$status" -ne 0 ]
    [[ "$output" =~ "environment required" ]]
}

@test "deploy succeeds with valid args" {
    run ./deploy.sh -e dev development
    [ "$status" -eq 0 ]
}

@test "config file is created" {
    run ./setup.sh
    [ -f "/etc/myapp/config.conf" ]
}

# Run tests
bats test_deploy.bats
```

---

### Ghi chú – Chủ đề tiếp theo
> **12.3 Script Patterns**: idempotent scripts, locking mechanisms, logging frameworks, CI/CD integration, testing patterns
