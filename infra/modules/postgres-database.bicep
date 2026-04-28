// PostgreSQL Flexible Server 안의 데이터베이스 생성
// 학습 경로 모듈 1 단원 4 "스키마 만들기 및 관리" 의 사전 컨테이너.
// 테이블·인덱스 DDL 자체는 앱 부트스트랩(SQL) 으로 처리하고 여기서는 DB 만 생성.

@description('상위 Flexible Server 이름')
param serverName string

@description('데이터베이스 이름')
@minLength(1)
@maxLength(63)
param databaseName string

@description('charset')
param charset string = 'UTF8'

@description('collation')
param collation string = 'en_US.utf8'

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: server
  name: databaseName
  properties: {
    charset: charset
    collation: collation
  }
}

output name string = database.name
