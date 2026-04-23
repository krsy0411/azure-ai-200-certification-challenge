// User-Assigned Managed Identity
// ACA 는 Container App 생성 시점에 --registry-identity 로 MI 를 전달해야
// ACR pull 이 가능. System-assigned 는 앱이 먼저 만들어져야 생성되므로
// "앱 생성 → MI 생성 → registry 연결" 순환이 성립하지 않는다.
// 따라서 ACA/AKS 등 레지스트리 자격이 선행되어야 하는 리소스는 UAMI 를 사용.

@description('Identity 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: name
  location: location
  tags: tags
}

output id string = identity.id
output name string = identity.name
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
