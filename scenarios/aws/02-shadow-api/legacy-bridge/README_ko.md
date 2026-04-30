# legacy-bridge

**난이도:** 초급  
**예상 시간:** 30분  
**카테고리:** SSRF/credential-theft

## Overview

급속한 인수합병을 거친 Prime Financial(미국 신용카드 발급사)은 여러 이질적인 인프라를 중앙화된 클라우드 환경으로 통합했습니다. 현대식 v5 고객 포탈이 주 진입점으로 배포되었지만, 하위 호환성을 위해 프라이빗 네트워크 내부에 문서화되지 않은 v1 레거시 노드들(IVR 시스템, 2018년식 모바일 앱, 야간 배치 작업)이 계속 운영 중입니다.

보안 팀은 이 레거시 서비스들이 격리되어 있다고 가정하지만, v5 포탈의 URL 포워딩 설정 오류가 "Shadow API" 브릿지를 열어두어 공격자가 공개 인터넷에서 v1 백엔드를 제어할 수 있게 됩니다.

### 공격 체인

이 시나리오는 Capital One 2019 침해 사건 패턴을 모델로 합니다:

1. **정찰 & IDOR** — `/api/v5/legacy/media-info?file_id=<N>`을 순회하여 다른 고객의 메타데이터 열거; 응답에서 v1 백엔드 URL 유출

2. **v5 포탈을 통한 SSRF** — `source=` query parameter를 주입하면 v5 포탈이 이를 그대로 v1으로 전달; v1이 서버측에서 `http://169.254.169.254/...` fetch

3. **자격증명 탈취** — IMDSv1에서 `Shadow-API-Role` STS 자격증명 반환

4. **데이터 탈취** — 역할이 PII 자격소에 대한 `s3:GetObject` 권한 보유. AWS CLI(SigV4)를 사용하여 플래그 파일 다운로드

## Learning Objectives

- 레거시 시스템 통합이 네트워크 수준의 신뢰 경계를 어떻게 도입하는지 이해
- API 설계에서 권한 없는 객체 접근(IDOR) 취약점 식별
- SSRF(Server-Side Request Forgery)를 통해 내부 서비스에 접근
- IMDSv1 메타데이터 엔드포인트를 활용하여 AWS 자격증명 탈취
- 손상된 IAM 역할을 사용하여 S3에서 민감한 데이터 탈취

## Scenario Resources

Terraform으로 생성되는 AWS 리소스:

- **EC2 x 2**
  - `Public-Gateway-Server` — `/api/v5/legacy/media-info`에 요청 포워딩 취약점이 있는 공개 v5 포탈
  - `Shadow-API-Server` — 보호되지 않은 URL fetch 엔드포인트를 실행하는 프라이빗 레거시 v1 노드

- **S3 버킷 x 1** — `prime-pii-vault-<random_suffix>` (고객 신용카드 신청 데이터 저장)

- **IAM 역할**
  - `Gateway-App-Role` — SSM 전용 권한만 가지는 진입점 역할
  - `Shadow-API-Role` — 프로덕션 PII 자격소에 대한 읽기 권한을 가지는 과권한 역할

## Setup

배포 지침은 [[setup.md](./setup.md)]를 참고하세요.

> **Note:** 이 시나리오는 실제 AWS 리소스를 생성하며 비용이 발생할 수 있습니다.

## Starting Point

학습자에게 공개 게이트웨이 URL이 제공됩니다. 인증은 필요하지 않습니다.

## Goal

플래그 파일을 S3에서 탈취하여 획득합니다.

## Infrastructure Architecture

![Architecture](./assets/legacy-bridge-architecture.png)

## Real-world Reference

> **출처** - Capital One 2019 침해 사건  
> 2019년 Capital One의 데이터 침해는 SSRF를 통한 IMDSv1 메타데이터 접근과 과권한 IAM 역할로 인한 대규모 PII 탈취로 발생했습니다.

### 참고 자료

- [AWS EC2 인스턴스 메타데이터 서비스 (IMDSv1)](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
- [Capital One 2019 침해 사건](https://www.us-cert.gov/ncas/alerts/AA19-339A) — US-CERT Advisory
- [OWASP API 보안 Top 10](https://owasp.org/www-project-api-security/) — API1, API7 (SSRF)

## Cleanup

완료 후 [[cleanup.md](./cleanup.md)]를 참고하여 모든 리소스를 제거하세요.

> **Warning:** 항상 정리를 확인하여 예상치 못한 AWS 비용을 방지하세요.

---

자세한 풀이는 [[walkthrough_ko.md](./walkthrough_ko.md)]를 참고하세요.