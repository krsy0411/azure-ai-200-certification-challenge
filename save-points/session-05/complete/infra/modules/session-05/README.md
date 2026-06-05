# `infra/modules/session-05/` — session-05 Bicep 모듈 (후속 작성)

[session-05](../../../docs/sessions/05-app-config-flags.md) 의 App Configuration 자원을 구성할 모듈.

예정 모듈:

- `app-configuration.bicep` — Standard 등급
- `app-configuration-keyvalue.bicep` — 일반 키/값 (`aoai:endpoint`, `cosmos:endpoint`, …)
- `app-configuration-keyvault-ref.bicep` — Key Vault reference (시크릿성 값)
- `app-configuration-feature-flag.bicep` — `enable_semantic_cache`, `enable_pg_backend`
- `role-assignment-appconfig-data-reader.bicep` — App Configuration Data Reader 부여

세션 엔트리 — `infra/sessions/05-app-config-flags/main.bicep` (후속 작성)
