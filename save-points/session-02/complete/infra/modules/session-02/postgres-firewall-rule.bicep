@description('Parent PostgreSQL Flexible Server name')
param serverName string

@description('Firewall rule name')
param name string = 'dev-client-ip'

@description('Allowed start IP address')
param startIpAddress string

@description('Allowed end IP address. 빈 값이면 startIpAddress 와 동일한 단일 IP 허용.')
param endIpAddress string = ''

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: serverName
}

resource firewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: server
  name: name
  properties: {
    startIpAddress: startIpAddress
    endIpAddress: empty(endIpAddress) ? startIpAddress : endIpAddress
  }
}

output name string = firewallRule.name
