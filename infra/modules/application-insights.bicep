// Application Insights (workspace-based) — Function App 의 built-in 모니터링
//
// Microsoft Learn (monitor-functions): "Azure Functions has built-in integration with
// Application Insights to monitor function executions." 새 Function App 은 자동 연결되지
// 않으므로 App Insights 자원 생성 + connection string 명시 박아야 trace/exception/dependency
// 자동 수집됨.
//
// Phase 7 의 책임: 자원 생성 + Function App 기본 연결 (built-in integration).
// Phase 9 의 책임: 사용자 정의 OpenTelemetry span + KQL 워크북 + 알림.
//
// workspace-based — 기존 LAW (Phase 2 산출물) 에 데이터 저장. AppTraces / AppExceptions /
// AppRequests / AppDependencies 테이블에 자동 수집.

@description('Application Insights 자원 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('연결할 Log Analytics Workspace 의 resource ID')
param workspaceResourceId string

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: workspaceResourceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = appInsights.id
output name string = appInsights.name
output connectionString string = appInsights.properties.ConnectionString
output instrumentationKey string = appInsights.properties.InstrumentationKey
