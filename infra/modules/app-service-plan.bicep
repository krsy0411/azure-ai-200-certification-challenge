// Linux App Service Plan. 두 웹앱(api, web)이 공유.

@description('App Service Plan 이름')
param name string

@description('배포 리전')
param location string

@description('공통 태그')
param tags object = {}

@description('SKU. 학습용 기본 B1.')
param sku string = 'B1'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'linux'
  properties: {
    reserved: true  // Linux 플랜임을 명시 (필수)
  }
}

output id string = plan.id
output name string = plan.name
