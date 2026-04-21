# Phase 1 — Azure에서 컨테이너 애플리케이션 호스팅 구현

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/implement-container-app-hosting-azure/ (2 모듈)

## 학습 경로 구성

1. **Azure Container Registry에서 컨테이너 저장 및 관리**
   - ACR 레지스트리 계층 · 이미지 태깅 전략
   - ACR Tasks 로 클라우드 빌드 (`az acr build`)
   - 신뢰할 수 있는 배포를 위한 이미지 버전 관리
2. **Azure App Service에 컨테이너 배포**
   - 사용자 지정 컨테이너 원본
   - 런타임 포트 · 시작 명령 · 영구 스토리지
   - 애플리케이션 설정으로 환경별 구성 외부화
   - 진단 로그 · 컨테이너 로그 스트리밍

## 이 프로젝트에서의 적용

- FastAPI(`apps/api`), Next.js(`apps/web`) 2개의 멀티스테이지 Dockerfile 작성
- ACR 하나(예: `acrai200challenge<고유접미사>`)에 두 이미지 푸시 (`api:vX`, `web:vX`)
- Azure App Service 플랜 + 웹앱 2개로 먼저 배포해 **이미지가 정상 기동되는지 검증** → 그 다음 Phase 2에서 ACA로 이관.

## 실습 명령어 (진행 중 업데이트)

```bash
# (placeholder — Phase 1 진행 시 실제 사용한 명령어를 여기 기록)
az group create -n rg-ai200challenge-dev -l koreacentral
az acr create -n <ACR_NAME> -g rg-ai200challenge-dev --sku Basic --admin-enabled false
az acr build -r <ACR_NAME> -t api:0.1.0 apps/api
az acr build -r <ACR_NAME> -t web:0.1.0 apps/web
```

## 함정 · 교훈 (진행 후 채움)

- (TBD)

## 체크리스트

- [ ] `apps/api/Dockerfile` 멀티스테이지 작성
- [ ] `apps/web/Dockerfile` 멀티스테이지 작성
- [ ] ACR 생성, Managed Identity로 pull 권한 부여
- [ ] 두 이미지 ACR push 성공
- [ ] App Service 2개 배포, 헬스체크 200 OK
- [ ] 이 문서에 실제 사용한 명령어·삽질 포인트 업데이트
