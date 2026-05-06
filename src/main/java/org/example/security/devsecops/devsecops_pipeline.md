# DevSecOps Pipeline Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. DevSecOps Overview

### What – DevSecOps là gì?
DevSecOps tích hợp security vào mọi giai đoạn của SDLC (Software Development Lifecycle), thay vì security là bước cuối trước khi deploy. "Shift Left Security": phát hiện lỗ hổng sớm = rẻ hơn nhiều.

### How – Security Testing Pyramid

```
                    ┌─────────────────┐
                    │   Penetration   │ ← Expensive, slow, manual
                    │     Testing     │   (quarterly/yearly)
                   ┌┴─────────────────┴┐
                   │       DAST        │ ← Dynamic: app running
                   │ (Dynamic Testing) │   (per release)
                  ┌┴───────────────────┴┐
                  │        SCA          │ ← Known CVEs in deps
                  │ (Dependency Scan)   │   (per commit)
                 ┌┴─────────────────────┴┐
                 │         SAST          │ ← Static: source code
                 │  (Static Analysis)    │   (per commit)
                ┌┴───────────────────────┴┐
                │     Secret Scanning     │ ← Fastest, cheapest
                │    (Pre-commit hooks)   │   (per commit)
                └─────────────────────────┘

Cost of fixing bug:
- Requirements: $1
- Development: $10
- QA/Testing: $100
- Production: $1,000+
```

### How – DevSecOps Pipeline Full

```yaml
# .github/workflows/security-pipeline.yml
name: Security Pipeline

on: [push, pull_request]

jobs:
  # ── Stage 1: Secret Detection (fastest) ──────────────────────
  secret-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0    # full history cho git-secrets

    - name: Gitleaks scan
      uses: gitleaks/gitleaks-action@v2
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}
      # → Fails nếu tìm thấy secrets trong code/history

    - name: TruffleHog scan
      run: |
        docker run --rm -v "$PWD:/tmp/scan" \
          trufflesecurity/trufflehog:latest \
          git file:///tmp/scan --only-verified

  # ── Stage 2: SAST (Static Analysis) ─────────────────────────
  sast:
    runs-on: ubuntu-latest
    needs: secret-scan
    steps:
    - uses: actions/checkout@v4

    - name: Semgrep SAST
      uses: returntocorp/semgrep-action@v1
      with:
        config: |
          p/security-audit
          p/owasp-top-ten
          p/java
          p/python
          p/javascript
      env:
        SEMGREP_APP_TOKEN: ${{ secrets.SEMGREP_APP_TOKEN }}

    - name: SonarQube analysis
      uses: SonarSource/sonarqube-scan-action@master
      env:
        SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
        SONAR_HOST_URL: ${{ secrets.SONAR_HOST_URL }}
      with:
        args: >
          -Dsonar.projectKey=myapp
          -Dsonar.sources=src/
          -Dsonar.security.hotspots.maxIssues=0

    - name: CodeQL Analysis
      uses: github/codeql-action/analyze@v3
      with:
        languages: java, javascript

  # ── Stage 3: Dependency/SCA Scan ─────────────────────────────
  dependency-scan:
    runs-on: ubuntu-latest
    needs: secret-scan
    steps:
    - uses: actions/checkout@v4

    - name: Snyk vulnerability scan
      uses: snyk/actions/node@master
      with:
        args: --severity-threshold=high --fail-on=all
      env:
        SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}

    - name: OWASP Dependency-Check
      uses: dependency-check/Dependency-Check_Action@main
      with:
        project: myapp
        path: '.'
        format: 'JSON'
        args: --failOnCVSS 7    # fail nếu CVSS >= 7

    - name: License compliance
      run: |
        # Check for copyleft licenses (GPL, AGPL)
        npx license-checker --failOn "GPL;AGPL;LGPL"

  # ── Stage 4: Build + Container Scan ──────────────────────────
  container-scan:
    runs-on: ubuntu-latest
    needs: [sast, dependency-scan]
    steps:
    - uses: actions/checkout@v4

    - name: Build Docker image
      run: docker build -t myapp:${{ github.sha }} .

    - name: Trivy container scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: myapp:${{ github.sha }}
        format: sarif
        output: trivy-results.sarif
        severity: HIGH,CRITICAL
        exit-code: 1             # fail nếu có HIGH/CRITICAL

    - name: Grype scan
      run: |
        curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh
        grype myapp:${{ github.sha }} --fail-on high

    - name: Dockerfile lint
      uses: hadolint/hadolint-action@v3.1.0
      with:
        dockerfile: Dockerfile
        failure-threshold: warning

    - name: Sign image với Cosign
      if: github.ref == 'refs/heads/main'
      uses: sigstore/cosign-installer@v3
      run: |
        cosign sign --yes myapp:${{ github.sha }}

  # ── Stage 5: DAST (Dynamic Testing) ──────────────────────────
  dast:
    runs-on: ubuntu-latest
    needs: container-scan
    services:
      app:
        image: myapp:${{ github.sha }}
        ports:
          - 8080:8080
    steps:
    - name: OWASP ZAP Baseline Scan
      uses: zaproxy/action-baseline@v0.10.0
      with:
        target: http://localhost:8080
        rules_file_name: zap-rules.tsv
        cmd_options: '-a'        # include ajax spider
        fail_action: warn        # warn không fail (baseline)

    - name: ZAP Full Scan (staging only)
      if: github.ref == 'refs/heads/main'
      uses: zaproxy/action-full-scan@v0.10.0
      with:
        target: https://staging.myapp.com
        fail_action: true

  # ── Stage 6: Infrastructure as Code Scan ─────────────────────
  iac-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Checkov IaC scan
      uses: bridgecrewio/checkov-action@master
      with:
        directory: infra/
        framework: terraform,kubernetes,dockerfile
        soft_fail: false
        output_format: sarif
        output_file_path: checkov-results.sarif

    - name: tfsec Terraform scan
      uses: aquasecurity/tfsec-action@v1.0.0

    - name: KICS scan
      uses: checkmarx/kics-github-action@v1.7.0
      with:
        path: infra/,k8s/
        fail_on: high
```

---

## 2. SAST – Static Analysis

### How – Semgrep Custom Rules

```yaml
# .semgrep/rules/custom-java.yaml
rules:
  # Detect SQL string concatenation
  - id: sql-injection-string-concat
    patterns:
      - pattern: |
          String $QUERY = "..." + $INPUT + "...";
          ... $CONN.executeQuery($QUERY) ...
      - pattern-not: |
          String $QUERY = "..." + $SAFE + "...";
    message: "Possible SQL injection: string concatenation in query"
    languages: [java]
    severity: ERROR
    metadata:
      category: security
      cwe: CWE-89
      owasp: A03:2021

  # Detect hardcoded passwords
  - id: hardcoded-password
    patterns:
      - pattern: |
          String $X = "...password...";
      - pattern: |
          String password = "..."
    message: "Hardcoded password detected"
    languages: [java]
    severity: WARNING

  # Detect XXE vulnerability
  - id: xxe-vulnerable-xml-parser
    patterns:
      - pattern: |
          DocumentBuilderFactory $DBF = DocumentBuilderFactory.newInstance();
          ...
          DocumentBuilder $DB = $DBF.newDocumentBuilder();
      - pattern-not: |
          $DBF.setFeature("http://xml.org/sax/features/external-general-entities", false);
    message: "XML parser may be vulnerable to XXE - disable external entities"
    languages: [java]
    severity: ERROR
```

```bash
# Run Semgrep
semgrep --config=p/owasp-top-ten src/
semgrep --config=.semgrep/rules/ src/ --sarif > semgrep.sarif

# Auto-fix với semgrep (experimental)
semgrep --config=p/python --autofix src/

# Semgrep CI
semgrep ci --config=auto   # tự chọn rules phù hợp với ngôn ngữ
```

### How – SonarQube Security Rules

```yaml
# sonar-project.properties
sonar.projectKey=myapp
sonar.sources=src/main
sonar.tests=src/test
sonar.java.binaries=target/classes

# Quality Gate với security focus:
# Security Hotspots Reviewed = 100%
# Security Rating = A (0 vulnerabilities)
# New Security Hotspots Reviewed >= 100%

# Security categories SonarQube checks:
# - SQL Injection (CWE-89)
# - Cross-site Scripting (CWE-79)
# - Weak Cryptography (CWE-326, CWE-327)
# - LDAP injection (CWE-90)
# - XML External Entity (CWE-611)
# - Path traversal (CWE-22)
# - HTTP Response Splitting (CWE-113)
```

---

## 3. Secret Scanning

### How – Pre-commit Hooks

```bash
# Cài pre-commit framework
pip install pre-commit

# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2
    hooks:
      - id: gitleaks

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: detect-private-key
      - id: check-added-large-files
        args: ['--maxkb=1000']

  - repo: local
    hooks:
      - id: check-env-files
        name: Check for .env files
        entry: bash -c 'if git diff --cached --name-only | grep -E "\.env$|\.env\." ; then echo "ERROR: .env file detected!"; exit 1; fi'
        language: system
        pass_filenames: false

# Cài hooks
pre-commit install
pre-commit run --all-files   # test trên tất cả files hiện tại
```

```toml
# .gitleaks.toml: custom rules
[extend]
useDefault = true                # dùng default rules

[[rules]]
id = "custom-api-key"
description = "Custom API Key"
regex = '''(?i)(mycompany[_-]?api[_-]?key\s*=\s*['"]?[a-zA-Z0-9]{32,}['"]?)'''
tags = ["api-key", "internal"]

[[rules]]
id = "aws-account-id"
description = "AWS Account ID"
regex = '''\b\d{12}\b'''
tags = ["aws"]

[allowlist]
description = "Global allowlist"
regexes = [
  '''EXAMPLE.*''',                    # example values
  '''test.*password''',               # test credentials
  '''REPLACE_ME''',                   # placeholder values
]
paths = [
  '''^tests/fixtures/''',
  '''\.test\.''',
]
```

---

## 4. SCA – Software Composition Analysis

### How – SBOM Generation

```bash
# Syft: generate SBOM từ Docker image hoặc source
syft myapp:latest -o spdx-json > sbom-spdx.json
syft myapp:latest -o cyclonedx-json > sbom-cyclonedx.json
syft dir:./src -o spdx-json > sbom-source.json

# SBOM formats:
# SPDX: Linux Foundation standard, XML/JSON/TV
# CycloneDX: OWASP standard, XML/JSON, tool-friendly

# Grype: vulnerability scanning từ SBOM
grype sbom:sbom-spdx.json             # scan từ SBOM
grype myapp:latest                     # scan từ image
grype dir:./src --fail-on high        # scan source

# Dependency-Track: SBOM management platform
# Upload SBOM, track vulnerabilities over time
curl -X POST \
  "https://dtrack.company.com/api/v1/bom" \
  -H "X-Api-Key: $DTRACK_API_KEY" \
  -H "Content-Type: multipart/form-data" \
  -F "autoCreate=true" \
  -F "projectName=myapp" \
  -F "projectVersion=1.0.0" \
  -F "bom=@sbom-cyclonedx.json"
```

---

## 5. DAST – Dynamic Application Security Testing

### How – OWASP ZAP Automation

```python
# zap-config.yaml (ZAP Automation Framework)
env:
  contexts:
    - name: MyApp
      urls:
        - https://staging.myapp.com
      authentication:
        method: form
        parameters:
          loginUrl: https://staging.myapp.com/login
          loginRequestData: username={%username%}&password={%password%}
        verification:
          method: response
          loggedInRegex: 'Welcome'
          loggedOutRegex: 'Login'
      users:
        - name: testuser
          credentials:
            username: testuser
            password: TestPass123!

jobs:
  - type: spider
    name: Spider
    parameters:
      maxDepth: 5
      maxChildren: 20

  - type: ajaxSpider
    name: Ajax Spider
    parameters:
      maxDuration: 5

  - type: passiveScan-wait
    name: Passive Scan

  - type: activeScan
    name: Active Scan
    parameters:
      policy: Default Policy
      context: MyApp

  - type: report
    name: Report
    parameters:
      template: traditional-html
      reportFile: zap-report.html
```

```bash
# ZAP API scan
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
  -t https://staging.myapp.com/openapi.json \
  -f openapi \
  -r zap-api-report.html \
  -I                    # không fail khi có issues (info gathering)

# ZAP với authentication và active scan:
docker run -v $(pwd):/zap/wrk/:rw \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap.sh -cmd \
  -autorun /zap/wrk/zap-config.yaml
```

---

## 6. Infrastructure as Code Security

### How – Terraform Security

```hcl
# INSECURE Terraform:
resource "aws_security_group" "bad" {
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]   # SSH open to world!
  }
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # all ports open!
  }
}

resource "aws_s3_bucket" "bad" {
  bucket = "my-bucket"
  acl    = "public-read"          # public!
}

resource "aws_db_instance" "bad" {
  publicly_accessible = true      # DB accessible from internet!
  storage_encrypted   = false     # not encrypted!
}
```

```bash
# tfsec: Terraform security scanner
tfsec ./infra --minimum-severity HIGH
tfsec ./infra --format sarif > tfsec.sarif

# Checkov: multi-framework IaC scanner
checkov -d ./infra --framework terraform --quiet --compact
checkov -f ./k8s/deployment.yaml --framework kubernetes

# Terrascan
terrascan scan -i terraform -d ./infra -t aws
terrascan scan -i k8s -d ./k8s

# OPA + Conftest: custom policy enforcement
# policy/terraform/deny_public_sg.rego:
package main
deny[msg] {
  resource := input.resource.aws_security_group[name]
  ingress := resource.ingress[_]
  ingress.cidr_blocks[_] == "0.0.0.0/0"
  msg := sprintf("Security group '%v' allows SSH from anywhere", [name])
}

conftest test --policy policy/ ./infra/main.tf
```

---

### Compare – SAST Tools

| Tool | Languages | Rules | Free? | Best For |
|------|-----------|-------|-------|---------|
| Semgrep | 30+ | Community + custom | ✅ (OSS) | Custom rules, multi-lang |
| SonarQube | 30+ | Built-in | ✅ (Community) | Code quality + security |
| CodeQL | 7 | Built-in | ✅ (GitHub) | Deep semantic analysis |
| Checkmarx | 40+ | Enterprise | ❌ | Enterprise, compliance |
| Fortify | 30+ | HP rules | ❌ | Enterprise |

### Compare – DAST Tools

| Tool | Type | Auth Support | Free? | Best For |
|------|------|-------------|-------|---------|
| OWASP ZAP | Proxy/Scanner | Yes | ✅ | CI/CD integration |
| Burp Suite Pro | Proxy/Scanner | Yes | ❌ | Manual + automated |
| Nikto | Scanner | No | ✅ | Quick server checks |
| Nuclei | Scanner | Templates | ✅ | Fast, community templates |

### Trade-offs
- SAST false positives: nhiều tools tạo nhiều findings → alert fatigue; tune rules + triage workflow
- DAST trong CI: chạy full scan chậm (30-60 phút); dùng baseline scan cho PRs, full scan cho main
- Secret scanning history: scan full git history lần đầu chậm nhưng quan trọng; rotate leaked secrets ngay

### Real-world Usage
```bash
# Security debt tracking:
# 1. Chạy tất cả scanners, collect findings
# 2. Deduplicate (same vuln từ nhiều tools)
# 3. Prioritize theo CVSS + exploitability + asset criticality
# 4. Assign to teams, set SLAs:
#    Critical (CVSS 9+): fix trong 24h
#    High (CVSS 7-9): fix trong 7 ngày
#    Medium (CVSS 4-7): fix trong 30 ngày
#    Low: next sprint

# Dependency update workflow:
# 1. Renovate/Dependabot → auto PRs cho updates
# 2. CI runs SCA scan trên PR
# 3. Auto-merge nếu: patch version + green tests + no new CVEs
# 4. Manual review cho major versions

# Metrics để track DevSecOps maturity:
# - Mean Time To Remediate (MTTR) per severity
# - % builds với security gates
# - Vuln density: vulns per 1000 lines of code
# - False positive rate per scanner
```

### Ghi chú – Chủ đề tiếp theo
> CTF Techniques – Web CTF (SQLi/XSS/SSRF/deserialization challenges), Crypto CTF (classical + modern), Forensics CTF (steganography, memory, network), Pwn cơ bản (Buffer Overflow, ret2win)

---

*Cập nhật lần cuối: 2026-05-06*
