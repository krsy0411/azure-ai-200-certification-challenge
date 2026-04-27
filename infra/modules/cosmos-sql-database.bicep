// Cosmos DB for NoSQL — SQL Database
// - Serverless 계정이므로 throughput(options.throughput) 미설정.
//   설정 시 'Setting throughput on a Serverless account is not allowed' 에러로 배포 실패.
// - DB 단위 throughput 도 동일 이유로 사용 불가. 모든 컨테이너가 계정 capacity 를 공유.

@description('상위 Cosmos DB 계정 이름')
param accountName string

@description('SQL DB 이름 (예: kb)')
@minLength(1)
@maxLength(255)
param databaseName string

@description('공통 태그')
param tags object = {}

resource account 'Microsoft.DocumentDB/databaseAccounts@2024-08-15' existing = {
  name: accountName
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-08-15' = {
  parent: account
  name: databaseName
  tags: tags
  properties: {
    resource: {
      id: databaseName
    }
  }
}

output id string = database.id
output name string = database.name
