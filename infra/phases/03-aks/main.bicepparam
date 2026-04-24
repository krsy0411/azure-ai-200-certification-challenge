using 'main.bicep'

param location = 'koreacentral'
param environment = 'dev'
param projectId = 'ai200challenge'
param acrSuffix = '04'

// 민감값은 레포에 박지 않는다. 배포 전 셸에서 export 필요:
//   export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)
//   export AKS_ADMIN_OBJECT_IDS=$(az ad signed-in-user show --query id -o tsv)
// 여러 사용자를 admin 으로 지정하려면 쉼표로 구분:
//   export AKS_ADMIN_OBJECT_IDS='<guid1>,<guid2>'
//
// readEnvironmentVariable 의 두 번째 인자는 default. zero-GUID 를 넣어 둬서
// env 가 없을 때 에디터가 BCP427 로 빨간 줄을 긋지 않게 한다. 대신 실제 배포
// 시 AAD 가 zero-GUID 를 거절하므로 "export 없이 배포 금지" gate 는 유지된다.
param aadTenantId = readEnvironmentVariable('AZURE_TENANT_ID', '00000000-0000-0000-0000-000000000000')
param adminGroupObjectIDs = split(readEnvironmentVariable('AKS_ADMIN_OBJECT_IDS', '00000000-0000-0000-0000-000000000000'), ',')
param adminPrincipalType = 'User'

param systemNodeVmSize = 'Standard_D2s_v3'
param systemNodeCount = 2
param kubernetesVersion = ''
