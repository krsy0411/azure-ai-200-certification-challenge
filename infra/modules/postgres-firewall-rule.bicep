// PostgreSQL Flexible Server firewall rule
// - Azure services allow:  startIp = endIp = 0.0.0.0
// - 사용자 IP 단일 allow:    startIp = endIp = <client IP>
// - 학습용으로 충분, Phase 9 에서 PE/Private DNS 로 대체 예정

@description('상위 Flexible Server 이름')
param serverName string

@description('규칙 이름')
@minLength(1)
@maxLength(80)
param ruleName string

@description('시작 IPv4')
param startIpAddress string

@description('끝 IPv4 (단일 IP 면 startIpAddress 와 동일)')
param endIpAddress string

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource rule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: ruleName
  properties: {
    startIpAddress: startIpAddress
    endIpAddress: endIpAddress
  }
}

output name string = rule.name
