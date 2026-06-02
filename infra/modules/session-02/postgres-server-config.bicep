@description('Parent PostgreSQL Flexible Server name')
param serverName string

@description('Server configuration (parameter) name. 예: azure.extensions')
param configName string

@description('Configuration value. 예: VECTOR (pgvector extension 사전 허용)')
param value string

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

// azure.extensions 는 동적 파라미터 — 서버 재시작 없이 적용된다.
// CREATE EXTENSION 으로 활성화하려면 먼저 이 allowlist 에 등록되어 있어야 한다.
resource config 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: server
  name: configName
  properties: {
    value: value
    source: 'user-override'
  }
}

output name string = config.name
