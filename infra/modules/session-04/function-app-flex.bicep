@description('Function App name (globally unique — forms <name>.azurewebsites.net)')
param name string

@description('Azure region')
param location string

@description('Flex Consumption plan resource id')
param planId string

@description('공용 User Assigned Managed Identity 자원 id / clientId')
param uamiId string
param uamiClientId string

@description('Storage — Flex deployment + AzureWebJobsStorage (키 인증 off, MI 사용)')
param storageAccountName string
param storageBlobEndpoint string
param deploymentContainerName string

@description('Application Insights 연결 문자열')
param appInsightsConnectionString string

@description('Service Bus FQDN (identity 기반 트리거 연결)')
param serviceBusFqdn string

@description('적재 대상 — Azure OpenAI · Cosmos · PostgreSQL')
param aoaiEndpoint string
param cosmosEndpoint string
param cosmosDatabaseName string
param postgresHost string

@description('PostgreSQL Entra 사용자명 — session-02 에서 PG 관리자로 등록한 UAMI 이름')
param postgresUser string

@description('Tags')
param tags object = {}

// Flex Consumption — functionAppConfig 신 스키마. FUNCTIONS_WORKER_RUNTIME 환경변수가 아니라
// runtime.name 으로 런타임을 지정한다. 모든 자원 접근은 User Assigned Managed Identity.
resource site 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: planId
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageBlobEndpoint}${deploymentContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uamiId
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
    siteConfig: {
      appSettings: [
        // AzureWebJobsStorage — 키 대신 Managed Identity (allowSharedKeyAccess=false 대응)
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uamiClientId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        // Service Bus 트리거 — identity 기반 연결
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: serviceBusFqdn
        }
        {
          name: 'ServiceBusConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'ServiceBusConnection__clientId'
          value: uamiClientId
        }
        // Cosmos change feed 트리거 — identity 기반 연결
        {
          name: 'CosmosDbConnection__accountEndpoint'
          value: cosmosEndpoint
        }
        {
          name: 'CosmosDbConnection__credential'
          value: 'managedidentity'
        }
        {
          name: 'CosmosDbConnection__clientId'
          value: uamiClientId
        }
        // 코드에서 DefaultAzureCredential 이 UAMI 를 선택하도록
        {
          name: 'AZURE_CLIENT_ID'
          value: uamiClientId
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: aoaiEndpoint
        }
        {
          name: 'AZURE_OPENAI_EMBED_DEPLOYMENT'
          value: 'text-embedding-3-large'
        }
        {
          name: 'AZURE_OPENAI_API_VERSION'
          value: '2024-08-01-preview'
        }
        {
          name: 'COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        {
          name: 'COSMOS_DATABASE'
          value: cosmosDatabaseName
        }
        {
          name: 'POSTGRES_HOST'
          value: postgresHost
        }
        {
          name: 'POSTGRES_DATABASE'
          value: 'appdb'
        }
        {
          name: 'POSTGRES_USER'
          value: postgresUser
        }
        {
          name: 'STORAGE_BLOB_ENDPOINT'
          value: storageBlobEndpoint
        }
      ]
    }
  }
}

output id string = site.id
output name string = site.name