// Cosmos DB for NoSQL 계정
// - capacity mode = Serverless (학습 트래픽, 비용 최소화)
// - capabilities = EnableNoSQLVectorSearch (컨테이너 vector index 사용 위해 필수)
//                + EnableServerless
// - disableLocalAuth = true → AAD data-plane RBAC 만 허용. 키는 발급되지만 사용 불가.
// - publicNetworkAccess = Enabled (Phase 9 까지는 Private Endpoint 도입하지 않음)
// - 단일 region writes (학습용)
//
// 데이터 plane 권한 (Cosmos DB Built-in Data Contributor) 부여는 별도 모듈
// (role-assignment-cosmos-data-contributor.bicep) 에서 sqlRoleAssignments 로 처리.

@description('Cosmos DB 계정 이름 (3-44자, 소문자/숫자/-)')
@minLength(3)
@maxLength(44)
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('백업 정책 모드')
@allowed([
  'Periodic'
  'Continuous'
])
param backupPolicyType string = 'Periodic'

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      { name: 'EnableServerless' }
      { name: 'EnableNoSQLVectorSearch' }
    ]
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: 'Tls12'
    backupPolicy: backupPolicyType == 'Continuous'
      ? {
          type: 'Continuous'
          continuousModeProperties: {
            tier: 'Continuous7Days'
          }
        }
      : {
          type: 'Periodic'
          periodicModeProperties: {
            backupIntervalInMinutes: 240
            backupRetentionIntervalInHours: 8
            backupStorageRedundancy: 'Local'
          }
        }
  }
}

output id string = account.id
output name string = account.name
output documentEndpoint string = account.properties.documentEndpoint
