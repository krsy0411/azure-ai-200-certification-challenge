// PostgreSQL Flexible Server — server parameter (configuration) 일괄 설정
//
// 학습 경로 모듈 2 단원 2 "pgvector 임베딩 저장" 과 모듈 3 단원 6 "연결 최적화" 를 충족:
// - azure.extensions = VECTOR  → CREATE EXTENSION vector 허용 (allowlist)
// - pgbouncer.enabled = true   → 내장 PgBouncer 활성 (port 6432)
// - pgbouncer.pool_mode = transaction
// - pgbouncer.default_pool_size = 50
//
// configurations resource 의 name 은 PostgreSQL parameter 이름과 정확히 일치해야 한다 (대소문자 포함).
// 'azure.extensions' 처럼 dot 이 들어가는 이름도 그대로 사용.

@description('상위 Flexible Server 이름')
param serverName string

@description('parameter 이름 → 값 매핑. 모든 값은 string 으로 전달')
param parameters object

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

@batchSize(1)
resource configs 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = [
  for paramName in items(parameters): {
    parent: server
    name: paramName.key
    properties: {
      value: string(paramName.value)
      source: 'user-override'
    }
  }
]
