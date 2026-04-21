# Phase 3 — Azure Kubernetes Service에서 애플리케이션 배포 및 모니터링

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/deploy-monitor-apps-azure-kubernetes-service/ (3 모듈)

## 학습 경로 구성

1. **AKS에 애플리케이션 배포** — Deployment 매니페스트, Service로 노출.
2. **AKS에서 애플리케이션 구성** — ConfigMap 로 구성 외부화, Secret 으로 중요 설정 보호, PV/PVC로 상태 저장 워크로드 스토리지.
3. **AKS에서 모니터링 · 문제 해결** — 로그 · 메트릭, Pod/Service 문제 해결, AI 워크로드 연결 검증.

## 이 프로젝트에서의 적용

- **백그라운드 임베딩 워커**를 AKS에 배포 (메인 API는 그대로 ACA). AKS 경로를 자연스럽게 채우면서 "왜 ACA가 아니라 AKS인가"에 대한 결정 배경을 기록(대용량·GPU 확장 유연성 시나리오 가정).
- AKS 클러스터 + ACR 통합(`az aks update --attach-acr`)
- Workload Identity 로 Key Vault · Cosmos DB 접근 (Phase 8 이후 연결)
- ConfigMap: 청크 사이즈, 임베딩 모델 이름
- Secret: 초기엔 kubernetes Secret → Phase 8에서 Key Vault CSI Driver로 전환
- Container Insights 활성화 → 파드 로그/메트릭을 Azure Monitor로

## 실습 명령어 (진행 중 업데이트)

```bash
az aks create -g rg-ai200challenge-dev -n aks-ai200challenge-dev \
  --node-count 1 --node-vm-size Standard_B2ms \
  --enable-managed-identity --enable-oidc-issuer --enable-workload-identity \
  --attach-acr <ACR_NAME>

az aks get-credentials -g rg-ai200challenge-dev -n aks-ai200challenge-dev
kubectl apply -f infra/aks/worker.yaml
```

## 함정 · 교훈

- (TBD)

## 체크리스트

- [ ] AKS 클러스터 생성(Workload Identity · OIDC 활성화)
- [ ] 워커 Deployment/Service + ConfigMap/Secret/PVC 매니페스트
- [ ] Container Insights 활성화 확인
- [ ] Pod `Running` 상태 · 큐 메시지 처리 로그 확인
- [ ] 네트워크 경로 검증(Cosmos/Redis private endpoint 등)
