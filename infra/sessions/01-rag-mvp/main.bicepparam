using './main.bicep'

// 환경 라벨 — session-00 과 동일한 값을 사용합니다.
param env = 'dev'

// 프로젝트 식별자 — session-00 과 동일한 값을 사용합니다.
param projectId = 'ai200ws'

// Azure 자원 기본 리전. 미지정 시 Resource Group 의 리전을 따릅니다.
// 본 세션의 자원은 session-00 의 Resource Group 안에 배포됩니다.
param location = 'koreacentral'

// 컨테이너 이미지 태그.
// 본 세션 docs 의 'docker build → docker push' 명령에서 사용한 태그와 일치시킵니다.
param apiImageTag = ''
param webImageTag = ''

// Cosmos DB 데이터베이스 / 컨테이너 이름
param cosmosDatabaseName = 'appdb'
param cosmosChunksContainerName = 'chunks'

// Vector 임베딩 차원 — text-embedding-3-large 가 반환하는 차원 수
param vectorDimensions = 3072

// ⚠️ userObjectId 는 여기 작성하지 않습니다. 배포 명령을 실행할 때마다 직접 전달:
//   --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv)
// 여기 작성해두면 git history 에 영구히 남아 포트폴리오 공개 시 노출됩니다.
param userObjectId = ''
