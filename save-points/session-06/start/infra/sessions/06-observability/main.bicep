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
// 본 세션에서 할 일:
//   아래 모듈 호출과 출력 블록을 직접 채운다. 모듈 본체는 ../../modules/session-06/ 에,
//   workbookData(워크북 정의)는 아래에 이미 완성되어 있다.
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

// -------- 워크북 정의 (scaffolding — 그대로 사용) ------------------------------

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

// -------- 1) Action Group 모듈 호출하기 --------------------------------------
// 힌트: monitor-action-group.bicep (name=actionGroupName, shortName='ai200alert',
// email=alertEmail).

// -------- 2) Log Search Alert (오류율) 모듈 호출하기 -------------------------
// 힌트: monitor-scheduled-query-alert.bicep. appInsightsId=appInsights.id,
// query='requests | where success == false | summarize FailedCount = count()',
// metricMeasureColumn='FailedCount', timeAggregation='Total', threshold=5,
// actionGroupId=actionGroup.outputs.id.

// -------- 3) Log Search Alert (p95 지연) 모듈 호출하기 ----------------------
// 힌트: 같은 모듈. query='requests | summarize p95 = percentile(duration, 95)',
// metricMeasureColumn='p95', timeAggregation='Average', threshold=3000, severity=3.

// -------- 4) Workbook 모듈 호출하기 ------------------------------------------
// 힌트: monitor-workbook.bicep. name=guid(resourceGroup().id, 'session-06-workbook'),
// appInsightsId=appInsights.id, serializedData=string(workbookData).

// -------- 출력 -----------------------------------------------------------------
// 힌트: actionGroupId, workbookId.
