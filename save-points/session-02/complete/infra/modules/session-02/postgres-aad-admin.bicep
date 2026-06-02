@description('Parent PostgreSQL Flexible Server name')
param serverName string

@description('Entra ID principal object id. administrators 자원의 name 으로 사용된다.')
param principalObjectId string

@description('Principal display name 또는 UPN (예: user@contoso.com, UAMI 이름)')
param principalName string

@description('Principal type')
@allowed([
  'User'
  'Group'
  'ServicePrincipal'
])
param principalType string = 'User'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

// Entra ID 관리자 — passwordAuth 가 꺼진 서버는 최소 한 명의 Entra 관리자가 있어야
// 접속이 가능하다. administrators 자원의 name 은 반드시 objectId 여야 한다.
resource admin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2024-08-01' = {
  parent: server
  name: principalObjectId
  properties: {
    principalType: principalType
    principalName: principalName
    tenantId: subscription().tenantId
  }
}

output name string = admin.name
