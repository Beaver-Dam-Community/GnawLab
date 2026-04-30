# legacy-bridge

**난이도:** 초급  
**예상 시간:** 30분  
**카테고리:** SSRF/credential-theft

## Overview

미국 신용카드 발급사인 Prime Financial은 급속한 인수합병으로 여러 다른 시스템을 클라우드에 통합했습니다. 최신의 v5 고객 포탈이 공개 진입점이지만, 기존 서비스와의 호환성을 위해 내부 네트워크에서는 문서화되지 않은 v1 레거시 시스템들(IVR, 구형 모바일 앱, 배치 작업)이 계속 운영 중입니다.

보안팀은 이 레거시 시스템이 격리되어 있다고 생각했지만, v5 포탈의 URL 포워딩 설정 오류가 "Shadow API"라는 내부 연결을 노출시켜 공격자가 공개 인터넷에서 v1 백엔드에 접근할 수 있게 되었습니다.

## Learning Objectives

- 레거시 시스템 통합이 만드는 보안 위험 이해
- API 설계의 접근 제어 결함(IDOR) 찾기
- SSRF 취약점을 통한 내부 서비스 접근
- IMDSv1 메타데이터 서비스에서 AWS 자격증명 탈취
- 탈취한 자격증명으로 S3 데이터에 접근

## Scenario Resources

Terraform이 배포하는 AWS 리소스:

- **EC2 2개**
  - `Public-Gateway-Server` — 포워딩 취약점이 있는 공개 v5 포탈
  - `Shadow-API-Server` — 내부 네트워크의 보호되지 않은 v1 노드

- **S3 버킷 1개** — `prime-pii-vault-<random_suffix>` — 고객 신용카드 신청 정보 저장

- **IAM 역할 2개**
  - `Gateway-App-Role` — SSM 접근만 허용
  - `Shadow-API-Role` — S3 버킷 접근 권한 보유

## Setup

배포 방법은 [[setup.md](./setup.md)]를 참고하세요.

> **Note:** 실제 AWS 리소스가 생성되며 비용이 발생할 수 있습니다.

## Starting Point

공개 게이트웨이 URL이 제공됩니다. 별도의 인증은 필요하지 않습니다.

## Goal

S3에서 플래그 파일을 다운로드하세요.

## Infrastructure Architecture

![Architecture](./assets/legacy-bridge-architecture.png)

## Real-world Reference

> **Source - Capital One 2019 침해 사건** (SSRF를 통해 EC2 메타데이터에 접근한 후, 임시 보안 자격증명을 탈취하고, 과권한 IAM 역할로 대규모 고객 데이터에 접근한 실제 사례. 관련: Optus 2018 문서화되지 않은 API 노출, Stripe deprecated 엔드포인트 악용)

- [Capital One 2019 사건](https://www.capitalone.com/digital/facts2019/)
- [AWS EC2 메타데이터 서비스](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [API 보안 침해 사례](https://www.apisec.ai/blog/real-world-api-security-breaches-lessons-from-major-attacks)

## Cleanup

실습 종료 후 [[cleanup.md](./cleanup.md)]를 따라 모든 리소스를 제거하세요.

> **Warning:** 예상치 못한 AWS 비용을 피하기 위해 정리가 완료되었는지 반드시 확인하세요.

---

자세한 풀이는 [[walkthrough_ko.md](./walkthrough_ko.md)]를 참고하세요.