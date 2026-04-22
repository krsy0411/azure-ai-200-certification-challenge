# Portal 스크린샷 자료

AI-200 챌린지의 Phase 1~9 는 Azure Portal GUI로 배포합니다. 각 Phase 의 Portal 스크린샷을 여기에 Phase 번호별로 모읍니다.

## 네이밍 규칙

- 디렉터리: `screenshots/0N/` (N = Phase 번호)
- 파일: `<순번 2자리>-<kebab-case-이름>.png`
  - 예) `01/01-rg-create.png`, `01/02-acr-create-basics.png`, `01/05-appservice-webapp-create.png`
- **순번**은 해당 Phase 문서(`docs/learning-paths/0N-*.md`) 내의 Portal 단계 순서와 일치시킴. 나중에 단계가 추가되면 `05a-`, `05b-` 처럼 접미사로 삽입.

## 캡처 팁

- **Chrome 권장**, 전체 Portal 창이 아니라 **의미 있는 영역만** 캡처(폼 + 필드값). 민감 값(구독 ID · 테넌트 ID · 개인 이메일)은 흐림 처리.
- PNG 저장, 해상도 1.5~2x (Retina 스크린샷 그대로 저장해도 무방).
- 한 단계에 여러 장이 필요하면 `-form`, `-review`, `-confirm` 접미어를 사용.
- 파일명은 모두 영문 소문자 + 하이픈.

## Phase 별 체크리스트

- [ ] `01/` — 컨테이너 호스팅 기초 (ACR + App Service)
- [ ] `02/` — Azure Container Apps
- [ ] `03/` — AKS
- [ ] `04/` — Cosmos DB for NoSQL
- [ ] `05/` — PostgreSQL (pgvector)
- [ ] `06/` — Azure Managed Redis
- [ ] `07/` — Service Bus / Event Grid / Functions
- [ ] `08/` — Key Vault + App Configuration
- [ ] `09/` — OpenTelemetry / Azure Monitor
