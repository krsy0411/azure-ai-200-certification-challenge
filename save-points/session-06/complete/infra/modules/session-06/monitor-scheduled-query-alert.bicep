@description('Scheduled query rule (log search alert) name')
param name string

@description('Azure region')
param location string

@description('대상 Application Insights 자원 id (쿼리가 실행될 범위)')
param appInsightsId string

@description('KQL 쿼리 — 단일 숫자 컬럼을 반환하도록 작성')
param query string

@description('임계값과 비교할 컬럼명')
param metricMeasureColumn string

@description('컬럼 집계 방식')
@allowed([
  'Average'
  'Count'
  'Maximum'
  'Minimum'
  'Total'
])
param timeAggregation string = 'Total'

@description('비교 연산자')
@allowed([
  'GreaterThan'
  'GreaterThanOrEqual'
  'LessThan'
  'LessThanOrEqual'
])
param operator string = 'GreaterThan'

@description('임계값')
param threshold int

@description('심각도 (0 가장 높음 ~ 4)')
@minValue(0)
@maxValue(4)
param severity int = 2

@description('발화 시 호출할 Action Group id')
param actionGroupId string

// AI 워크로드는 p95·토큰·오류율 같은 KQL 집계 조건이 필요하므로 metric alert 대신
// log search alert(scheduledQueryRules)를 사용한다.
resource alert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: name
  location: location
  properties: {
    severity: severity
    enabled: true
    scopes: [
      appInsightsId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: query
          timeAggregation: timeAggregation
          metricMeasureColumn: metricMeasureColumn
          operator: operator
          threshold: threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output id string = alert.id
