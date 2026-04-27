// Azure OpenAI Service — 모델 배포 (deployment)
// - 같은 계정 안의 여러 deployment 는 동시에 PUT 하면 409 충돌 가능 → main.bicep 에서 dependsOn 으로 직렬화
// - 코드에서는 모델 ID 가 아니라 'deploymentName' 으로 호출 (예: model=gpt-4o-mini-2024-07-18 / deployment=gpt-4o-mini)
// - sku.name 옵션:
//     · Standard         — region 고정 (예: koreacentral). 데이터 주권 보장
//     · GlobalStandard   — 글로벌 라우팅, 가장 저렴. region 보장 X
//     · DataZoneStandard — 데이터 zone (EU/US 등) 내 라우팅
//   학습용 default 는 Standard (한국 region 고정).

@description('상위 AOAI 계정 이름')
param accountName string

@description('Deployment 이름 — 코드에서 호출 시 사용')
param deploymentName string

@description('모델 이름 (예: gpt-4o-mini, text-embedding-3-large)')
param modelName string

@description('모델 버전 (예: 2024-07-18, 1)')
param modelVersion string

@description('SKU 이름 — Standard / GlobalStandard / DataZoneStandard 등')
param skuName string = 'Standard'

@description('SKU capacity — Standard/GlobalStandard 의 경우 1000 TPM 단위')
@minValue(1)
param skuCapacity int = 30

@description('RAI 정책 이름 (default = Microsoft.DefaultV2)')
param raiPolicyName string = 'Microsoft.DefaultV2'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: accountName
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    raiPolicyName: raiPolicyName
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
}

output id string = deployment.id
output name string = deployment.name
