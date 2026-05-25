using './main.bicep'

// 환경 라벨 — App Configuration 라벨 (Phase 8) 과 일치해야 함.
param env = 'dev'

// 프로젝트 식별자 — 모든 자원 이름의 prefix.
param projectId = 'ai200ws'

// 기본 리전. 변경 시 RG · LAW · AI · KV · UAMI 가 이 리전으로 배포됨.
param location = 'koreacentral'

// AOAI 리전. koreacentral 에 가용한 모델이 없을 때 'eastus' 또는 'japaneast' 로.
// 분리하는 이유: AOAI 리전 제약과 다른 자원 리전을 디커플링.
param aoaiLocation = 'koreacentral'

// AOAI 모델 — chat
param chatDeploymentName = 'gpt-4o-mini'
param chatModelName = 'gpt-4o-mini'
param chatModelVersion = '2024-07-18'
param chatCapacityK = 10  // = 10K TPM. 쿼터 부족 시 낮춤.

// AOAI 모델 — embedding
param embedDeploymentName = 'text-embedding-3-large'
param embedModelName = 'text-embedding-3-large'
param embedModelVersion = '1'
param embedCapacityK = 10

// ⚠️ userObjectId 는 여기 박지 말 것. CLI override 로만 전달:
//   --parameters userObjectId=$(az ad signed-in-user show --query id -o tsv)
// 여기 박으면 git history 에 영구 남아 포트폴리오 공개 시 노출.
param userObjectId = ''
