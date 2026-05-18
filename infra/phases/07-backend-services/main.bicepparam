using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'

// 접미사 — Phase 4·5·6 과 동일해야 같은 자원 참조
param cosmosSuffix = '04'
param aoaiSuffix = '04'
param pgSuffix = '05'
param redisSuffix = '06'

// Storage 신규 — 충돌 시 dev08 로 ↑
param stSuffix = '07'

param pgDatabaseName = 'kb'
param serviceBusSku = 'Standard'
param functionInstanceMemoryMB = 2048
param functionMaximumInstanceCount = 100
