# save-points/session-05/ — App Configuration 피처 플래그

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/05-app-config-flags/main.bicep`
- `apps/api/src/config/loader.py` — App Configuration Provider 호출 + Key Vault reference 해석 + sentinel refresh + feature_manager 평가 본문이 anchor 주석
- `apps/api/src/main.py` — 캐시 미들웨어 분기 부분 (`is_enabled("enable_semantic_cache")`) 이 anchor 주석

세션 docs — [docs/sessions/05-app-config-flags.md](../../docs/sessions/05-app-config-flags.md)
