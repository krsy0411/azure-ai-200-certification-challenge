@description('Action group name')
param name string

@description('Short name (최대 12자) — 알림 메일 제목에 노출')
@maxLength(12)
param shortName string

@description('알림 수신 이메일. 비우면 수신자 없이 생성.')
param email string = ''

// Action Group 은 global 자원.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: name
  location: 'global'
  properties: {
    groupShortName: shortName
    enabled: true
    emailReceivers: empty(email)
      ? []
      : [
          {
            name: 'primaryEmail'
            emailAddress: email
            useCommonAlertSchema: true
          }
        ]
  }
}

output id string = actionGroup.id
