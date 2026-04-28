using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'

// 접미사 — Phase 4 와 같은 acr/cosmos/aoai 를 가리켜야 함
param acrSuffix = '04'
param cosmosSuffix = '04'
param aoaiSuffix = '04'

// PG 신규 — 다른 Phase 와 충돌 없도록 같은 '05' 접미사
param pgSuffix = '05'

// Phase 5 새 이미지 (PgStore 포함). 실제 푸시 후 갱신.
param imageTag = '0.5.1'

param pgDatabaseName = 'kb'
param postgresVersion = '16'
param pgStorageSizeGB = 32

// 사용자 IP — `curl -s https://api.ipify.org` 로 확인 후 갱신.
// 0.0.0.0 으로 두면 firewall 이 사실상 ACA outbound 만 허용.
param devClientIpAddress = '0.0.0.0'
