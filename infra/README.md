# infra/

Azure AI-200 챌린지의 **Bicep IaC** 디렉터리. Phase 1 부터 각 Phase 의 리소스를 여기서 선언·배포하고, Phase 10 에서 전체를 `main.bicep` 으로 상위 조립한다.

## 레이아웃

```
infra/
├── main.bicep                        # Phase 10 — 상위 조립 (subscription 스코프)
├── envs/
│   └── dev.bicepparam                # Phase 10 통합 파라미터
├── modules/                          # 재사용 Bicep 모듈
│   ├── acr.bicep
│   ├── app-service-plan.bicep
│   ├── app-service-container.bicep   # WebApp + System-assigned MI + ACR pull 설정
│   └── role-assignment-acrpull.bicep # MI → ACR AcrPull 역할
└── phases/
    └── 01-container-hosting/
        ├── main.bicep                # Phase 1 엔트리 (subscription 스코프: RG 도 이 안에서 생성)
        └── main.bicepparam
```

Phase 번호별로 하위 디렉터리가 늘어난다 (`02-container-apps/`, `03-aks/`, ...). 각 Phase 문서는 해당 `main.bicep` 의 핵심 블록을 마크다운 코드 블록으로 인용한다.

## 일반 규칙

- **네이밍**: `CLAUDE.md` 규칙 따라 `<약어>-ai200challenge-<env>` / 하이픈 금지 리소스는 `<약어>ai200challenge<env><접미사>`
- **리전**: `koreacentral`
- **스코프**: Phase 1 은 RG 도 같이 만들어야 하므로 `targetScope = 'subscription'`. Phase 2 이후는 `resourceGroup` 스코프가 기본.
- **출력(output)**: 모듈은 해당 리소스의 `id`, 필요한 속성만 선별 출력. 상위 `main.bicep` 이 다음 모듈에 이를 전달.
- **Managed Identity**: 웹앱·Function 등은 시스템 할당 MI 를 기본으로. 다른 리소스에 대한 역할은 `modules/role-assignment-*.bicep` 으로 분리.

## 배포 표준 절차

```bash
# 1) 빌드 검증 (경고도 없어야 함)
az bicep build --file infra/phases/01-container-hosting/main.bicep

# 2) what-if (subscription 스코프)
az deployment sub what-if \
  --location koreacentral \
  --template-file infra/phases/01-container-hosting/main.bicep \
  --parameters infra/phases/01-container-hosting/main.bicepparam

# 3) 실제 배포
az deployment sub create \
  --location koreacentral \
  --template-file infra/phases/01-container-hosting/main.bicep \
  --parameters infra/phases/01-container-hosting/main.bicepparam
```

resourceGroup 스코프(Phase 2 이후)는 `sub` 자리를 `group --resource-group rg-ai200challenge-dev` 로 바꾸면 된다.
