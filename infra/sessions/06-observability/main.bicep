// =============================================================================
// session-06 — Observability 심화 (커스텀 OTel span · KQL Workbook · Log Search Alert)
//
// 배포 명령:
//   ALERT_EMAIL=$(az ad signed-in-user show --query mail -o tsv)
//   az deployment group create \
//     --resource-group rg-ai200ws-dev \
//     --template-file workshop/infra/sessions/06-observability/main.bicep \
//     --parameters workshop/infra/sessions/06-observability/main.bicepparam \
//     --parameters alertEmail=$ALERT_EMAIL
//
// 의존성 (existing): session-00 의 Application Insights.
//
// 본 세션에서 신규 생성:
//   - Action Group (이메일 수신자)
//   - Log Search Alert 2개 (오류율 · p95 지연) — scheduledQueryRules
//   - Workbook (P95 latency · 분당 토큰 · 캐시 hit rate)
// =============================================================================

targetScope = 'resourceGroup'

@description('환경 라벨')
param env string = 'dev'

@description('프로젝트 식별자')
param projectId string = 'ai200ws'

@description('Azure 자원 기본 리전')
param location string = resourceGroup().location

@description('알림 수신 이메일. 비우면 수신자 없이 Action Group 만 생성.')
param alertEmail string = ''

// -------- 자원 이름 ------------------------------------------------------------

var aiName = 'ai-${projectId}-${env}'
var actionGroupName = 'ag-${projectId}-${env}'

// -------- existing 참조 --------------------------------------------------------

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: aiName
}

// -------- 1) Action Group -------------------------------------------------------

module actionGroup '../../modules/session-06/monitor-action-group.bicep' = {
  name: 'actionGroup'
  params: {
    name: actionGroupName
    shortName: 'ai200alert'
    email: alertEmail
  }
}

// -------- 2) Log Search Alert — 오류율 -----------------------------------------

module alertErrorRate '../../modules/session-06/monitor-scheduled-query-alert.bicep' = {
  name: 'alert-errorRate'
  params: {
    name: 'alert-error-rate-${projectId}-${env}'
    location: location
    appInsightsId: appInsights.id
    query: 'requests | where success == false | summarize FailedCount = count()'
    metricMeasureColumn: 'FailedCount'
    timeAggregation: 'Total'
    operator: 'GreaterThan'
    threshold: 5
    severity: 2
    actionGroupId: actionGroup.outputs.id
  }
}

// -------- 3) Log Search Alert — p95 지연 ---------------------------------------

module alertP95 '../../modules/session-06/monitor-scheduled-query-alert.bicep' = {
  name: 'alert-p95'
  params: {
    name: 'alert-p95-latency-${projectId}-${env}'
    location: location
    appInsightsId: appInsights.id
    query: 'requests | summarize p95 = percentile(duration, 95)'
    metricMeasureColumn: 'p95'
    timeAggregation: 'Average'
    operator: 'GreaterThan'
    threshold: 3000
    severity: 3
    actionGroupId: actionGroup.outputs.id
  }
}

// -------- 4) Workbook -----------------------------------------------------------
//             Portal 에서 만든 워크북의 ARM JSON 을 Bicep 에 임베드 (IaC 우선 룰).

var workbookData = {
  version: 'Notebook/1.0'
  '$schema': 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
  items: [
    {
      type: 1
      content: {
        json: '# AI-200 Workshop — 관측성\nP95 지연 · 분당 토큰 · 캐시 hit rate 를 한 화면에서 본다.'
      }
      name: 'title'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'requests | summarize p95 = percentile(duration, 95) by bin(timestamp, 1m) | render timechart'
        size: 0
        title: 'P95 latency (ms)'
        queryType: 0
        resourceType: 'microsoft.insights/components'
        visualization: 'timechart'
      }
      name: 'p95'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'customMetrics | where name in ("tokens.prompt", "tokens.completion") | summarize tokens = sum(value) by name, bin(timestamp, 1m) | render timechart'
        size: 0
        title: '분당 토큰 사용량'
        queryType: 0
        resourceType: 'microsoft.insights/components'
        visualization: 'timechart'
      }
      name: 'tokens'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'customMetrics | where name in ("cache.hit", "cache.total") | summarize hits = sumif(value, name == "cache.hit"), total = sumif(value, name == "cache.total") by bin(timestamp, 5m) | extend hit_rate = 100.0 * hits / total | project timestamp, hit_rate | render timechart'
        size: 0
        title: '캐시 hit rate (%)'
        queryType: 0
        resourceType: 'microsoft.insights/components'
        visualization: 'timechart'
      }
      name: 'cacheRate'
    }
  ]
}

module workbook '../../modules/session-06/monitor-workbook.bicep' = {
  name: 'workbook'
  params: {
    name: guid(resourceGroup().id, 'session-06-workbook')
    location: location
    displayName: 'AI-200 Workshop 관측성'
    appInsightsId: appInsights.id
    serializedData: string(workbookData)
  }
}

// -------- 출력 -----------------------------------------------------------------

output actionGroupId string = actionGroup.outputs.id
output workbookId string = workbook.outputs.id
