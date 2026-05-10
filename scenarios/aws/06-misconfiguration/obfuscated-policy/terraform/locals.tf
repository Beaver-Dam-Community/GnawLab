resource "random_string" "scenario_id" {
  length  = 8
  special = false
  upper   = false
}

locals {
  scenario_id   = random_string.scenario_id.result
  scenario_name = "gnawlab-iampoly"

  # Resource naming
  iam_user_name        = "${local.scenario_name}-attacker-${local.scenario_id}"
  iam_user_policy_name = "${local.scenario_name}-attacker-policy-${local.scenario_id}"
  flag_bucket_name     = "${local.scenario_name}-flag-${local.scenario_id}"
  trail_bucket_name    = "${local.scenario_name}-trail-${local.scenario_id}"
  trail_name           = "${local.scenario_name}-trail-${local.scenario_id}"
  detector_role_name   = "${local.scenario_name}-detector-role-${local.scenario_id}"
  detector_lambda_name = "${local.scenario_name}-detector-${local.scenario_id}"
  eventbridge_rule     = "${local.scenario_name}-rule-${local.scenario_id}"

  # IP whitelist: use provided or auto-detected
  whitelist_cidr = var.whitelist_ip != "" ? var.whitelist_ip : "${chomp(data.http.my_ip.response_body)}/32"

  # Common tags
  common_tags = {
    Scenario    = "obfuscated-policy"
    Project     = "GnawLab"
    Environment = "training"
    ManagedBy   = "terraform"
    ScenarioID  = local.scenario_id
  }

  # Detection Lambda source code
  # Uses literal string matching with re.IGNORECASE.
  # Bypassable only via IAM Action wildcards (?, *).
  detector_lambda_code = <<-PYTHON
import json
import re
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam = boto3.client('iam')

# Patterns checked against the policy JSON document.
# IGNORECASE prevents trivial case-variant bypasses (S3:GetObject, s3:getobject, ...).
# The intended bypass is via IAM wildcard characters (?, *) in Action values.
#
# Scope is intentionally narrow: only patterns relevant to the scenario goal
# (S3 reads on the flag bucket). Other escalation paths (iam, lambda, cloudtrail,
# ec2, etc.) are blocked by the attacker user's Permission Boundary, which acts
# as the single-account equivalent of an SCP.
BLOCKED_PATTERNS = [
    # Full wildcards
    r'"\*:\*"',
    r'"s3:\*"',
    # Common verb-prefix wildcards that any pentester would try first
    r'"s3:Get\*"',
    r'"s3:List\*"',
    r'"s3:Put\*"',
    r'"s3:Delete\*"',
    r'"s3:GetObject\*"',
    r'"s3:GetBucket\*"',
    # Sensitive S3 action literals
    r'"s3:ListAllMyBuckets"',
    r'"s3:ListBucket"',
    r'"s3:GetObject"',
    r'"s3:GetObjectVersion"',
]


def is_dangerous(policy_document):
    policy_str = json.dumps(policy_document)
    return any(re.search(p, policy_str, re.IGNORECASE) for p in BLOCKED_PATTERNS)


def get_policy_document(policy_arn):
    policy = iam.get_policy(PolicyArn=policy_arn)['Policy']
    version_id = policy['DefaultVersionId']
    version = iam.get_policy_version(PolicyArn=policy_arn, VersionId=version_id)
    return version['PolicyVersion']['Document']


def detach_and_delete(policy_arn):
    try:
        attached = iam.list_entities_for_policy(PolicyArn=policy_arn)
        for u in attached.get('PolicyUsers', []):
            iam.detach_user_policy(UserName=u['UserName'], PolicyArn=policy_arn)
        for g in attached.get('PolicyGroups', []):
            iam.detach_group_policy(GroupName=g['GroupName'], PolicyArn=policy_arn)
        for r in attached.get('PolicyRoles', []):
            iam.detach_role_policy(RoleName=r['RoleName'], PolicyArn=policy_arn)
        versions = iam.list_policy_versions(PolicyArn=policy_arn)['Versions']
        for v in versions:
            if not v['IsDefaultVersion']:
                iam.delete_policy_version(PolicyArn=policy_arn, VersionId=v['VersionId'])
        iam.delete_policy(PolicyArn=policy_arn)
        logger.info(f"Deleted dangerous policy: {policy_arn}")
    except Exception as e:
        logger.error(f"Failed to delete policy {policy_arn}: {e}")


def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    detail = event.get('detail', {})
    event_name = detail.get('eventName')

    if event_name == 'CreatePolicy':
        policy_arn = detail.get('responseElements', {}).get('policy', {}).get('arn')
    elif event_name == 'AttachUserPolicy':
        policy_arn = detail.get('requestParameters', {}).get('policyArn')
    else:
        return {'status': 'ignored', 'eventName': event_name}

    if not policy_arn or policy_arn.startswith('arn:aws:iam::aws:policy/'):
        return {'status': 'skipped', 'reason': 'managed or missing'}

    try:
        document = get_policy_document(policy_arn)
    except Exception as e:
        logger.error(f"Could not read policy {policy_arn}: {e}")
        return {'status': 'error'}

    if is_dangerous(document):
        detach_and_delete(policy_arn)
        return {'status': 'deleted', 'policyArn': policy_arn}

    return {'status': 'allowed', 'policyArn': policy_arn}
PYTHON
}
