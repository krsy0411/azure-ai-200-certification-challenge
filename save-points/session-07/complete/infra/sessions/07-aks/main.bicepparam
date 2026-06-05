using './main.bicep'

// 환경 라벨 — session-00 과 동일한 값을 사용합니다.
param env = 'dev'

// 프로젝트 식별자 — session-00 과 동일한 값을 사용합니다.
param projectId = 'ai200ws'

// Azure 자원 기본 리전. 본 세션의 자원은 session-00 의 Resource Group 안에 배포됩니다.
param location = 'koreacentral'

// 워크로드 ServiceAccount (namespace:name) — 매니페스트의 ServiceAccount 와 일치시킵니다.
param workloadServiceAccount = 'default:apps-api-sa'

// userObjectId 는 여기 작성하지 않습니다. 배포 명령을 실행할 때마다 --parameters
// userObjectId=$(az ad signed-in-user show --query id -o tsv) 로 직접 전달합니다.
param userObjectId = ''