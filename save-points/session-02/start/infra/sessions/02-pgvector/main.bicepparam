using './main.bicep'

// 환경 라벨 — session-00 과 동일한 값을 사용합니다.
param env = 'dev'

// 프로젝트 식별자 — session-00 과 동일한 값을 사용합니다.
param projectId = 'ai200ws'

// Azure 자원 기본 리전. 본 세션의 자원은 session-00 의 Resource Group 안에 배포됩니다.
param location = 'koreacentral'

// PostgreSQL 데이터베이스 이름 / major version
param databaseName = 'appdb'
param postgresVersion = '16'

// 사용자 식별 정보 (userObjectId · userPrincipalName · devClientIpAddress) 는 여기
// 작성하지 않습니다. 배포 명령을 실행할 때마다 --parameters key=value 인자로 직접
// 전달합니다. 여기 작성해두면 git history 에 영구히 남아 포트폴리오 공개 시
// 본인 식별 정보가 노출됩니다.
param userObjectId = ''
param userPrincipalName = ''
param devClientIpAddress = '0.0.0.0'
