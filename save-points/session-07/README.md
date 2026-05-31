# save-points/session-07/ — Azure Kubernetes Service 대안 배포

예정 스냅샷 — `start/` 와 `complete/` 의 차이는 다음 파일들의 핵심 로직.

- `infra/sessions/07-aks/main.bicep`
- `apps/worker/main.py` — embedding 재처리 워커. Cosmos null embedding chunk 조회 · 임베드 · upsert · exit 본문이 anchor 주석
- `apps/worker/Dockerfile` — 완성본 그대로
- `infra/sessions/07-aks/manifests/worker-job.yaml` — image, serviceAccountName, env 등이 anchor 주석

세션 docs — [docs/sessions/07-aks.md](../../docs/sessions/07-aks.md)
