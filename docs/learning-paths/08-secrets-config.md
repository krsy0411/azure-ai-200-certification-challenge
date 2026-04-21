# Phase 8 — AI 솔루션용 애플리케이션 비밀·구성 관리

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/manage-app-secrets-configuration/ (2 모듈)

## 학습 경로 구성

1. **Key Vault 로 애플리케이션 비밀 관리** — 관리형 ID 기반 SDK 비밀 검색, 비밀 버전 관리·회전, 자격 증명 캐싱 전략.
2. **App Configuration 으로 애플리케이션 설정 관리** — 관리형 ID 연결, 레이블(환경별 변형) + 기능 플래그, Key Vault 참조.

## 이 프로젝트에서의 적용

- 모든 연결 문자열/키를 Key Vault 로 이관
- App Configuration의 **레이블**로 `dev` / `prod` 구성 분리
- 기능 플래그 예:
  - `enable_semantic_cache` (Phase 6 기능 온/오프)
  - `use_pg_for_vector_search` (Cosmos vs PG 벡터 A/B)
  - `rollout_new_ranker` (Phase 9 퍼센트 롤아웃)
- `DefaultAzureCredential` 로 로컬·배포 모두 동일 코드 경로

## 코드 골격

```python
# apps/api/src/config/azure_config.py
from azure.identity import DefaultAzureCredential
from azure.appconfiguration.provider import load

cred = DefaultAzureCredential()
config = load(
    endpoint="https://ac-ai200challenge-dev.azconfig.io",
    credential=cred,
    key_vault_options={"credential": cred},
    feature_flag_enabled=True,
    selects=[SettingSelector(key_filter="*", label_filter="dev")],
)
COSMOS_ENDPOINT = config["cosmos:endpoint"]
```

## 체크리스트

- [ ] Key Vault 생성 + 사용자 지정 Managed Identity에 `Key Vault Secrets User` 롤 부여
- [ ] App Configuration 생성 + Key Vault 참조 설정
- [ ] 레이블 `dev`/`prod` 로 구성 분리
- [ ] 기능 플래그 3개 등록 + 런타임에서 토글 검증
- [ ] `.env` 완전 제거, 로컬 실행도 Managed Identity / AZ CLI 자격으로
