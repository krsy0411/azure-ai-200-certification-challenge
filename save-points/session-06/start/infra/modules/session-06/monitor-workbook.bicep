@description('Workbook name — 반드시 GUID 형식')
param name string

@description('Azure region')
param location string

@description('워크북에 표시될 이름')
param displayName string

@description('연결할 Application Insights 자원 id')
param appInsightsId string

@description('워크북 정의 (ARM JSON 직렬화 문자열). main 에서 string() 으로 생성.')
param serializedData string

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: name
  location: location
  kind: 'shared'
  properties: {
    displayName: displayName
    serializedData: serializedData
    category: 'workbook'
    sourceId: appInsightsId
    version: 'Notebook/1.0'
  }
}

output id string = workbook.id
