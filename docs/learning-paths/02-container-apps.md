# Phase 2 — Azure Container Apps에서 앱 배포 및 관리

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/deploy-manage-apps-azure-container-apps/ (3 모듈)

## 학습 경로 구성

1. **Azure Container Apps에 컨테이너 배포** — 환경(Environment), 런타임 구성, 레지스트리 인증, 배포 확인.
2. **Azure Container Apps에서 컨테이너 관리** — 이미지 업데이트, 리비전 관리, 실패 배포 진단, 리소스/스케일 조정, 로그·상태 프로브 기반 문제 해결.
3. **Azure Container Apps에서 컨테이너 크기 조정** — HTTP/TCP/CPU/메모리 스케일 규칙, KEDA 이벤트 기반 스케일링, 리비전 모드와 트래픽 관리.

## 이 프로젝트에서의 적용

- 중앙 ACA Environment 하나에 `api`, `web` 컨테이너 앱 2개 배포
- **Single Revision Mode**로 시작 → Phase 7에서 Multiple Revisions + 트래픽 분할로 업그레이드
- readiness/liveness 프로브로 Azure OpenAI 연결 실패 시 앱 재시작
- HTTP 스케일 규칙(동시 요청 ≥ 30 → 2~5 복제본)
- KEDA: Service Bus 큐 길이 기반 워커 스케일 (Phase 7에서 적용)
- Managed Identity로 ACR pull + Azure OpenAI 접근

## 실습 명령어 (진행 중 업데이트)

```bash
az containerapp env create -n cae-ai200challenge-dev -g rg-ai200challenge-dev -l koreacentral \
  --logs-workspace-id <LA_WORKSPACE_ID>

az containerapp create -n api -g rg-ai200challenge-dev --environment cae-ai200challenge-dev \
  --image <ACR>/api:0.1.0 \
  --user-assigned <UAMI_ID> \
  --registry-server <ACR>.azurecr.io --registry-identity <UAMI_ID> \
  --ingress external --target-port 8000 \
  --min-replicas 1 --max-replicas 5
```

## 함정 · 교훈

- (TBD)

## 체크리스트

- [ ] ACA Environment + Log Analytics 작업 영역 생성
- [ ] api/web 컨테이너 앱 배포 + Managed Identity 연결
- [ ] readiness/liveness 프로브 추가
- [ ] HTTP 스케일 규칙 검증(부하 주입 후 복제본 증가 확인)
- [ ] 리비전 교체(새 이미지 배포 → 리비전 라벨 확인)
- [ ] 로그 스트림으로 요청 추적 확인
