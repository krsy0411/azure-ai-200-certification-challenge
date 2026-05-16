using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'

// 접미사 — Phase 1·4·5 와 동일해야 같은 자원 가리킴
param acrSuffix = '04'
param cosmosSuffix = '04'
param aoaiSuffix = '04'
param pgSuffix = '05'

// Redis 신규 — soft-delete 충돌 시 dev07 로 ↑
param redisSuffix = '06'

// Phase 6 새 이미지 (redis 클라이언트 + chat.py RAG 포함). 실제 푸시 후 갱신.
param imageTag = '0.6.3'

param pgDatabaseName = 'kb'

// 학습 경로 dev/test 권장 — MemoryOptimized_M10
param redisSkuName = 'MemoryOptimized_M10'
