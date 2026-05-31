@description('Container App name')
param name string

@description('Azure region')
param location string

@description('Azure Container Apps Environment resource ID')
param environmentId string

@description('User Assigned Managed Identity resource ID')
param userAssignedIdentityId string

@description('User Assigned Managed Identity client ID (코드의 AZURE_CLIENT_ID 환경변수로 전달)')
param userAssignedIdentityClientId string

@description('Azure Container Registry login server (예: acrai200wsdev.azurecr.io)')
param acrLoginServer string

@description('Container image (loginServer 제외, 예: api:s01)')
param containerImage string

@description('Container port (FastAPI 기본 8000, Next.js 기본 3000)')
param targetPort int = 8000

@description('External ingress 사용 여부')
param externalIngress bool = true

@description('Min replicas')
@minValue(0)
param minReplicas int = 0

@description('Max replicas')
@minValue(1)
param maxReplicas int = 3

@description('CPU cores')
param cpu string = '0.5'

@description('Memory')
param memory string = '1Gi'

@description('환경변수 — 시크릿이 아닌 일반 설정 (Azure OpenAI endpoint 등)')
param envVars array = []

@description('Tags')
param tags object = {}

resource app 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: userAssignedIdentityId
        }
      ]
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          name: name
          image: '${acrLoginServer}/${containerImage}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: concat(envVars, [
            {
              // DefaultAzureCredential 이 ACA 안에서 어떤 UAMI 를 쓸지 결정
              name: 'AZURE_CLIENT_ID'
              value: userAssignedIdentityClientId
            }
          ])
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
