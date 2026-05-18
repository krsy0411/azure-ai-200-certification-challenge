// Azure Functions Flex Consumption plan (Microsoft.Web/serverfarms)
//
// 학습 경로 모듈 3 단원 2 매핑:
// - sku.name='FC1', sku.tier='FlexConsumption' (학습 경로 신규 기본값)
// - Linux 전용, reserved=true
// - 1 plan = 1 app (Flex 제약)
// - koreacentral 지원 확인됨 (Step 0)

@description('Flex Consumption plan 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

output id string = plan.id
output name string = plan.name
