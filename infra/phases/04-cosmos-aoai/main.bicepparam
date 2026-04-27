using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'
param acrSuffix = '04'
param cosmosSuffix = '04'
param aoaiSuffix = '04'
param imageTag = '0.4.0'

param cosmosDatabaseName = 'kb'

param aoaiChatDeploymentName = 'gpt-4o-mini'
param aoaiChatModelVersion = '2024-07-18'
param aoaiChatCapacity = 30

param aoaiEmbedDeploymentName = 'text-embedding-3-large'
param aoaiEmbedModelVersion = '1'
param aoaiEmbedCapacity = 30
