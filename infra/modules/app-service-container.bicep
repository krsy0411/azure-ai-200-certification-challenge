// Linux Web App (컨테이너). 시스템 할당 MI + ACR pull via MI + appSettings.
//
// - linuxFxVersion = 'DOCKER|<loginServer>/<image>:<tag>' 형식으로 컨테이너 지정
// - acrUseManagedIdentityCreds = true 로 MI 기반 ACR pull 활성화
//   (ACR 에 대한 AcrPull 역할 할당은 role-assignment-acrpull.bicep 에서 별도 수행)

@description('웹앱 이름')
param name string

@description('배포 리전')
param location string

@description('상위 App Service Plan 리소스 ID')
param planId string

@description('ACR Login server (ex: myacr.azurecr.io)')
param acrLoginServer string

@description('컨테이너 이미지 이름 (ex: api)')
param imageName string

@description('이미지 태그 (ex: 0.1.0)')
param imageTag string

@description('앱에 주입할 appSettings 키/값 (WEBSITES_PORT 포함)')
param appSettings object

@description('공통 태그')
param tags object = {}

var linuxFxVersion = 'DOCKER|${acrLoginServer}/${imageName}:${imageTag}'

// appSettings (object) 를 Bicep 이 기대하는 name/value 배열로 변환
var appSettingsArray = [for key in objectKeys(appSettings): {
  name: key
  value: appSettings[key]
}]

resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      acrUseManagedIdentityCreds: true  // MI 로 ACR pull
      alwaysOn: false                    // B1 은 기본 Off 가 합리적 (비용)
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: appSettingsArray
    }
  }
}

output id string = site.id
output name string = site.name
output principalId string = site.identity.principalId
output defaultHostName string = site.properties.defaultHostName
