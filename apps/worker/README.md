# `apps/worker/` — AKS 워커 (S07)

K8s Job 으로 실행되는 embedding 재처리 워커. Cosmos 에서 `embedding=null` 인 chunk 를 모아 AOAI 로 다시 임베드.

예정 파일:
- `main.py` — `RUN_ONCE=true` 일회성 모드 (Job 의 의도), `BATCH_SIZE` 환경변수
- `Dockerfile` (Python 3.12-slim, `--platform linux/amd64`)
- `requirements.txt` (`azure-identity`, `azure-cosmos`, `openai`)

> placeholder — 실제 코드는 후속 구현 단계.
> K8s 매니페스트는 `infra/sessions/07-aks/manifests/worker-job.yaml` 에.
