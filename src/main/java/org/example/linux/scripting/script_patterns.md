# Script Patterns – Production Best Practices

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Production Script Template

### What – Script Template là gì?
Template chuẩn hóa cấu trúc script production: error handling, logging, locking, cleanup, usage.

### How – Complete Template

```bash
#!/usr/bin/env bash
# =============================================================================
# Script: deploy.sh
# Description: Deployment automation script
# Usage: deploy.sh [OPTIONS] <environment>
# =============================================================================

# Fail fast
set -euo pipefail
IFS=$'\n\t'                            # safer IFS (avoid word splitting on space)

# =============================================================================
# Constants
# =============================================================================
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="/var/log/myapp"
readonly LOG_FILE="${LOG_DIR}/deploy_$(date +%Y%m%d).log"
readonly LOCK_FILE="/var/run/${SCRIPT_NAME%.sh}.lock"
readonly VERSION="1.0.0"

# =============================================================================
# Defaults
# =============================================================================
VERBOSE=${VERBOSE:-0}
DRY_RUN=0
ENV=""
TAG="latest"

# =============================================================================
# Logging
# =============================================================================
mkdir -p "$LOG_DIR"

log()     { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
warn()    { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "$LOG_FILE" >&2; }
error()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }
debug()   { [[ "$VERBOSE" -eq 1 ]] && echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "$LOG_FILE"; }
success() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*" | tee -a "$LOG_FILE"; }

# =============================================================================
# Error handling
# =============================================================================
error_handler() {
    local exit_code=$?
    local line_number="${1:-unknown}"
    error "Script failed at line $line_number (exit code: $exit_code)"
    error "Command: $BASH_COMMAND"
    cleanup
    exit $exit_code
}
trap 'error_handler $LINENO' ERR

# =============================================================================
# Cleanup
# =============================================================================
TEMP_FILES=()

cleanup() {
    log "Cleaning up..."
    for f in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
        rm -f "$f"
    done
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# =============================================================================
# Lock (prevent concurrent runs)
# =============================================================================
acquire_lock() {
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        local pid
        pid=$(cat "$LOCK_FILE/pid" 2>/dev/null || echo "unknown")
        error "Another instance is running (PID: $pid). Lock: $LOCK_FILE"
        exit 1
    fi
    echo $$ > "$LOCK_FILE/pid"
    debug "Lock acquired: $LOCK_FILE"
}

# =============================================================================
# Validation
# =============================================================================
check_dependencies() {
    local missing=()
    for cmd in docker kubectl helm curl jq; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    [[ ${#missing[@]} -eq 0 ]] || {
        error "Missing dependencies: ${missing[*]}"
        exit 1
    }
}

check_env() {
    local required_vars=(API_KEY REGISTRY_URL DB_HOST)
    local missing=()
    for var in "${required_vars[@]}"; do
        [[ -v $var && -n "${!var}" ]] || missing+=("$var")
    done
    [[ ${#missing[@]} -eq 0 ]] || {
        error "Missing required environment variables: ${missing[*]}"
        exit 1
    }
}

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat << EOF
$SCRIPT_NAME v$VERSION – Deployment automation

Usage: $SCRIPT_NAME [OPTIONS] <environment>

Arguments:
  environment   Target environment (dev|staging|prod)

Options:
  -h, --help      Show this help
  -v, --verbose   Verbose output
  -e, --env ENV   Environment configuration
  -t, --tag TAG   Docker image tag (default: latest)
  -n, --dry-run   Dry run mode (no actual changes)

Environment Variables:
  API_KEY        Required: API authentication key
  REGISTRY_URL   Required: Docker registry URL
  VERBOSE        Set to 1 for verbose output

Examples:
  $SCRIPT_NAME -e prod -t v1.2.3 production
  $SCRIPT_NAME --dry-run staging
EOF
}

# =============================================================================
# Main Logic
# =============================================================================
deploy() {
    local env="$1" tag="$2"

    log "Starting deployment: env=$env, tag=$tag"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY RUN] Would deploy $tag to $env"
        return 0
    fi

    # Actual deployment steps
    local tmpdir
    tmpdir=$(mktemp -d)
    TEMP_FILES+=("$tmpdir")

    # ... deployment logic ...
    success "Deployment completed: env=$env, tag=$tag"
}

# =============================================================================
# Argument Parsing
# =============================================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -v|--verbose) VERBOSE=1; set -x ;;
            -e|--env)     ENV="${2:?'--env requires an argument'}"; shift ;;
            -t|--tag)     TAG="${2:?'--tag requires an argument'}"; shift ;;
            -n|--dry-run) DRY_RUN=1 ;;
            --)           shift; break ;;
            -*)           error "Unknown option: $1"; usage; exit 1 ;;
            *)            break ;;
        esac
        shift
    done

    [[ $# -ge 1 ]] || { error "Environment argument required"; usage; exit 1; }
    DEPLOY_TARGET="$1"
}

# =============================================================================
# Entry Point
# =============================================================================
main() {
    parse_args "$@"
    check_dependencies
    check_env
    acquire_lock
    deploy "$DEPLOY_TARGET" "$TAG"
}

main "$@"
```

---

## 2. Idempotent Scripts

### What – Idempotency là gì?
Script **idempotent** = chạy nhiều lần cho kết quả giống lần đầu. Không tạo duplicate, không fail nếu resource đã tồn tại.

### How – Idempotent Patterns

```bash
# Check before create
create_user() {
    local username="$1"
    if id "$username" &>/dev/null; then
        log "User $username already exists, skipping"
        return 0
    fi
    useradd -m -s /bin/bash "$username"
    success "Created user: $username"
}

# Directory creation (idempotent by nature với -p)
mkdir -p /opt/app/{bin,conf,logs,data}

# File content (write only if different)
write_config() {
    local file="$1"
    local content="$2"
    local current_content=""
    [[ -f "$file" ]] && current_content=$(cat "$file")
    if [[ "$current_content" != "$content" ]]; then
        echo "$content" > "$file"
        log "Updated: $file"
    else
        debug "No change needed: $file"
    fi
}

# Package installation (idempotent)
install_package() {
    local package="$1"
    if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
        debug "Package already installed: $package"
        return 0
    fi
    apt-get install -y "$package"
}

# Symlink (idempotent)
make_symlink() {
    local src="$1" dst="$2"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        debug "Symlink already correct: $dst → $src"
        return 0
    fi
    ln -sfn "$src" "$dst"
    log "Created symlink: $dst → $src"
}

# Service enable/start (idempotent)
ensure_service() {
    local service="$1"
    systemctl is-enabled "$service" &>/dev/null || systemctl enable "$service"
    systemctl is-active "$service" &>/dev/null || systemctl start "$service"
}

# Database migration (idempotent via version tracking)
run_migration() {
    local version="$1"
    local sql_file="$2"
    if psql -c "SELECT 1 FROM schema_migrations WHERE version='$version'" | grep -q "1 row"; then
        debug "Migration $version already applied"
        return 0
    fi
    psql < "$sql_file"
    psql -c "INSERT INTO schema_migrations(version) VALUES('$version')"
    log "Applied migration: $version"
}
```

---

## 3. Logging Framework

### How – Structured Logging

```bash
# Structured log với JSON
log_json() {
    local level="$1" message="$2"
    shift 2
    local extra=""
    while [[ $# -gt 0 ]]; do
        extra+=", \"$1\": \"$2\""
        shift 2
    done
    printf '{"timestamp":"%s","level":"%s","message":"%s","pid":%d%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$level" \
        "$message" \
        "$$" \
        "$extra" | tee -a "$LOG_FILE"
}

log_json "INFO" "Starting deployment" "env" "prod" "tag" "v1.2.3"
# {"timestamp":"2024-01-15T10:30:00Z","level":"INFO","message":"Starting deployment","pid":1234,"env": "prod", "tag": "v1.2.3"}

# Log rotation
rotate_log() {
    local log_file="$1"
    local max_size_mb=${2:-100}
    local max_files=${3:-10}

    if [[ $(du -sm "$log_file" | cut -f1) -gt $max_size_mb ]]; then
        for ((i=max_files-1; i>=1; i--)); do
            [[ -f "${log_file}.${i}" ]] && mv "${log_file}.${i}" "${log_file}.$((i+1))"
        done
        mv "$log_file" "${log_file}.1"
        touch "$log_file"
        log "Log rotated: $log_file"
    fi
}

# Syslog integration
log_syslog() {
    local priority="${1:-info}"
    local message="$2"
    logger -p "user.$priority" -t "$SCRIPT_NAME" "$message"
}
```

---

## 4. CI/CD Integration

### How – Scripts trong CI/CD Pipelines

```bash
# Environment detection
is_ci() {
    [[ -n "${CI:-}" || -n "${JENKINS_URL:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${GITLAB_CI:-}" ]]
}

# Disable interactive prompts trong CI
if is_ci; then
    export DEBIAN_FRONTEND=noninteractive
    INTERACTIVE=0
else
    INTERACTIVE=1
fi

# GitHub Actions integration
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    # Group logs
    echo "::group::Deployment Steps"
    # ... deployment ...
    echo "::endgroup::"

    # Set output
    echo "image_tag=$TAG" >> "$GITHUB_OUTPUT"

    # Add to step summary
    cat >> "$GITHUB_STEP_SUMMARY" << EOF
## Deployment Summary
- **Environment**: $ENV
- **Tag**: $TAG
- **Status**: ✅ Success
EOF

    # Annotate errors
    error() {
        echo "::error file=${BASH_SOURCE[1]},line=$LINENO::$*" >&2
    }
    warn() {
        echo "::warning::$*"
    }
fi

# Jenkins integration
if [[ -n "${JENKINS_URL:-}" ]]; then
    # Jenkins-specific env vars: BUILD_NUMBER, JOB_NAME, WORKSPACE
    log "Building on Jenkins: job=$JOB_NAME build=$BUILD_NUMBER"
fi
```

### How – Deployment Patterns

```bash
# Blue-Green deployment
blue_green_deploy() {
    local current=$(get_active_slot)
    local new=$([ "$current" = "blue" ] && echo "green" || echo "blue")

    log "Deploying to $new slot (current: $current)"
    deploy_to_slot "$new"
    health_check_slot "$new"
    switch_traffic "$new"
    log "Traffic switched to $new"

    # Warm down old slot (keep for rollback)
    stop_slot "$current"
}

# Rolling update
rolling_update() {
    local service="$1" new_image="$2"
    local instances=($(get_instances "$service"))
    local batch_size=1

    for ((i=0; i<${#instances[@]}; i+=batch_size)); do
        local batch=("${instances[@]:$i:$batch_size}")
        log "Updating batch: ${batch[*]}"

        for instance in "${batch[@]}"; do
            drain_instance "$instance"
            update_instance "$instance" "$new_image"
            health_check "$instance" || {
                error "Health check failed for $instance – rolling back"
                rollback_instance "$instance"
                return 1
            }
            enable_instance "$instance"
        done

        log "Batch complete. Pausing 10s before next batch..."
        sleep 10
    done
}

# Canary deployment
canary_deploy() {
    local service="$1" new_image="$2" percentage=${3:-10}

    log "Canary deployment: $percentage% traffic to $new_image"
    deploy_canary "$service" "$new_image" "$percentage"

    # Monitor for 10 minutes
    local start=$SECONDS
    while ((SECONDS - start < 600)); do
        local error_rate
        error_rate=$(get_error_rate "$service" "canary")
        if (( $(echo "$error_rate > 5" | bc -l) )); then
            error "Canary error rate too high: $error_rate%. Rolling back."
            rollback_canary "$service"
            return 1
        fi
        sleep 30
    done

    log "Canary stable. Promoting to 100%"
    promote_canary "$service"
}
```

---

## 5. Testing Patterns

### How – Unit Testing Bash Scripts

```bash
# BATS – Bash Automated Testing System
# File: tests/unit/test_utils.bats

setup() {
    # Runs before each test
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
    TMPDIR=$(mktemp -d)
}

teardown() {
    # Runs after each test
    rm -rf "$TMPDIR"
}

@test "trim removes leading whitespace" {
    result=$(trim "  hello")
    [ "$result" = "hello" ]
}

@test "trim removes trailing whitespace" {
    result=$(trim "hello  ")
    [ "$result" = "hello" ]
}

@test "validate_port accepts valid ports" {
    run validate_port 8080
    [ "$status" -eq 0 ]
}

@test "validate_port rejects invalid ports" {
    run validate_port 99999
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid" ]]
}

@test "create_user is idempotent" {
    run create_user testuser123
    [ "$status" -eq 0 ]
    run create_user testuser123   # second run
    [ "$status" -eq 0 ]          # should succeed, not fail
    userdel testuser123
}

# Mock external commands
@test "deploy calls docker pull" {
    # Create mock docker in temp PATH
    mkdir "$TMPDIR/bin"
    cat > "$TMPDIR/bin/docker" << 'EOF'
#!/bin/bash
echo "MOCK docker $*"
exit 0
EOF
    chmod +x "$TMPDIR/bin/docker"
    PATH="$TMPDIR/bin:$PATH"

    run deploy_image "nginx:latest"
    [[ "$output" =~ "MOCK docker pull nginx:latest" ]]
}
```

### How – Integration Testing

```bash
# test_integration.sh
#!/usr/bin/env bash

test_database_connection() {
    if psql -h "$DB_HOST" -U "$DB_USER" -c "SELECT 1" &>/dev/null; then
        echo "PASS: Database connection"
    else
        echo "FAIL: Database connection"
        return 1
    fi
}

test_api_health() {
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://$API_HOST/health")
    if [[ "$http_code" == "200" ]]; then
        echo "PASS: API health check"
    else
        echo "FAIL: API returned HTTP $http_code"
        return 1
    fi
}

run_tests() {
    local failed=0
    local tests=(test_database_connection test_api_health)
    for test in "${tests[@]}"; do
        $test || ((failed++))
    done
    echo "Tests: $((${#tests[@]} - failed))/${#tests[@]} passed"
    return $failed
}

run_tests
```

---

## 6. Security Patterns

### How – Secure Script Practices

```bash
# Avoid eval (code injection risk)
# BAD:
eval "echo $USER_INPUT"
# GOOD:
echo "${USER_INPUT}"

# Avoid unquoted variables (word splitting, globbing)
# BAD:
ls $DIRECTORY
cp $FILE $DEST
# GOOD:
ls "$DIRECTORY"
cp "$FILE" "$DEST"

# Sanitize input
sanitize_filename() {
    local filename="$1"
    filename="${filename//[^a-zA-Z0-9._-]/}"  # only allow safe chars
    filename="${filename#.}"                    # no leading dots
    echo "$filename"
}

# Prevent path traversal
validate_path() {
    local path="$1"
    local base="/var/www/html"
    local realpath
    realpath=$(realpath -m "$path")          # -m: no need to exist
    if [[ "$realpath" != "$base"/* ]]; then
        error "Path traversal detected: $path"
        return 1
    fi
}

# Secrets management
load_secrets() {
    # NEVER hardcode secrets
    # Use: environment vars, vault, AWS SSM, etc.
    if command -v aws &>/dev/null; then
        DB_PASSWORD=$(aws ssm get-parameter --name "/myapp/db/password" \
                     --with-decryption --query 'Parameter.Value' --output text)
    elif [[ -f /run/secrets/db_password ]]; then
        DB_PASSWORD=$(cat /run/secrets/db_password)
    else
        DB_PASSWORD="${DB_PASSWORD:?'DB_PASSWORD env var required'}"
    fi
}

# Temp files secure creation
TMPFILE=$(mktemp)                           # automatically random name
TMPDIR=$(mktemp -d)                         # temp directory
trap 'rm -rf "$TMPFILE" "$TMPDIR"' EXIT

# Avoid world-readable temp files
umask 077                                   # default 600 for new files
```

---

## 7. Performance Patterns

### How – Optimizing Bash Scripts

```bash
# Avoid spawning subshells in loops
# BAD (spawns subshell for each file)
for file in $(ls /tmp/*.log); do
    process "$file"
done

# GOOD (uses glob, no subshell)
for file in /tmp/*.log; do
    process "$file"
done

# Avoid calling external commands unnecessarily
# BAD
if [[ $(echo "$string" | wc -c) -gt 100 ]]; then ...

# GOOD (bash built-in)
if [[ ${#string} -gt 100 ]]; then ...

# Use builtins instead of external commands
# BAD
echo "Hello" | grep -q "Hello"

# GOOD
[[ "Hello" == *"Hello"* ]]

# Batch file operations
# BAD (one rm per file)
find . -name "*.tmp" | while read f; do rm "$f"; done

# GOOD (one rm call)
find . -name "*.tmp" -delete
# or
find . -name "*.tmp" -print0 | xargs -0 rm

# Cache expensive operations
get_server_ip() {
    if [[ -z "${_SERVER_IP_CACHE:-}" ]]; then
        _SERVER_IP_CACHE=$(dig +short myserver.internal)
    fi
    echo "$_SERVER_IP_CACHE"
}
```

---

## 8. Compare & Trade-offs

### Compare – Script Patterns

| Pattern | Khi dùng | Trade-off |
|---------|----------|-----------|
| Idempotent | CI/CD, provisioning | Code phức tạp hơn |
| Retry logic | Network operations | Có thể ẩn real failures |
| Locking | Cron jobs, background | Deadlock risk nếu cleanup fail |
| Template | New projects | Overhead cho scripts nhỏ |
| Structured logging | Production monitoring | Cần log aggregation tool |

### Trade-offs

- **set -e**: tiện nhưng có edge cases (commands trong conditions, pipes)
- **Traps**: powerful nhưng phức tạp trong nested subshells
- **Parallel execution**: nhanh hơn nhưng khó debug, race conditions
- **Bash vs Python**: Bash phù hợp cho system tasks và pipes; Python cho logic phức tạp, data processing

---

### Ghi chú – Chủ đề tiếp theo
> **13.1 systemd Deep Dive**: unit types, dependencies, targets, socket activation, timers, journald configuration
