# infra/

IaC(Infrastructure as Code) 디렉터리. Phase 1~9 동안은 `az` CLI 명령어로 수동 배포하고 **명령어를 각 Phase 문서에 기록**합니다. **Phase 10(옵션)** 에서 여기 Bicep 모듈로 정리합니다.

## 목표 구조 (Phase 10)

```
infra/
├── main.bicep                 # 최상위 조립
├── modules/
│   ├── acr.bicep
│   ├── aca.bicep
│   ├── aks.bicep
│   ├── cosmos.bicep
│   ├── postgres.bicep
│   ├── redis.bicep
│   ├── service-bus.bicep
│   ├── event-grid.bicep
│   ├── functions.bicep
│   ├── key-vault.bicep
│   ├── app-config.bicep
│   └── monitor.bicep
├── envs/
│   ├── dev.bicepparam
│   └── prod.bicepparam
└── aks/
    ├── namespace.yaml
    ├── worker.yaml
    └── configmap.yaml
```

현재는 사전 공간 확보만 해두었습니다.
