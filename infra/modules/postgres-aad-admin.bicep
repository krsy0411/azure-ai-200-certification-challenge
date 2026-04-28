// PostgreSQL Flexible Server — Microsoft Entra ID administrator 등록
// 학습 경로 모듈 1 단원 3 "PostgreSQL에 연결" 의 핵심: server 자체에 AAD admin 이 하나 이상 있어야
// Entra 토큰으로 로그인 가능. UAMI principalId 를 ServicePrincipal 로 등록한다.
//
// administrators sub-resource 의 name 은 등록 대상의 objectId 여야 한다.
// principalName 은 RBAC 표시용 라벨 — pg_catalog.pg_authid 안에 만들어지는 role 이름이 된다.

@description('상위 Flexible Server 이름')
param serverName string

@description('AAD admin 으로 등록할 principal 의 objectId (UAMI 면 principalId)')
param principalObjectId string

@description('PostgreSQL role 이름으로 표시될 라벨 (UAMI display name 또는 임의 식별자)')
param principalName string

@description('principal 종류')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param principalType string = 'ServicePrincipal'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource admin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: server
  name: principalObjectId
  properties: {
    principalType: principalType
    principalName: principalName
    tenantId: subscription().tenantId
  }
}

output objectId string = admin.name
