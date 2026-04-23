// Container App
// - UAMI 기반 ACR pull (registries[].identity = UAMI resourceId)
// - HTTP concurrency 스케일 규칙
// - readiness/liveness probe
// - Single Revision Mode (Phase 7 에서 Multiple + 트래픽 분할로 전환)

@description('Container App 이름')
param name string

@description('리전')
param location string

@description('공통 태그')
param tags object = {}

@description('ACA Managed Environment resource ID')
param environmentId string

@description('ACR login server (e.g. acrai200challengedev04.azurecr.io)')
param acrLoginServer string

@description('UAMI resource ID — ingress·registry·Key Vault 등 공용 ID')
param userAssignedIdentityId string

@description('이미지 이름 (ACR 레포지토리 명, 예: api / web)')
param imageName string

@description('이미지 태그')
param imageTag string = '0.1.0'

@description('컨테이너가 노출하는 포트')
param targetPort int

@description('external = 퍼블릭 노출, false = Environment 내부에서만 도달')
param ingressExternal bool = true

@description('HTTP probe 경로 (readiness/liveness 공용)')
param healthProbePath string = '/'

@description('최소 복제본 수')
@minValue(0)
@maxValue(25)
param minReplicas int = 1

@description('최대 복제본 수')
@minValue(1)
@maxValue(25)
param maxReplicas int = 5

@description('HTTP 동시 요청 임계값 — 이 값을 초과하면 새 복제본 프로비저닝')
param httpConcurrency int = 30

@description('컨테이너에 주입할 환경 변수 {name: value} 맵')
param envVars object = {}

@description('CPU (vCPU, 0.25 단위)')
param cpu string = '0.5'

@description('메모리 (Gi, CPU 의 2배가 표준)')
param memory string = '1.0Gi'

// 환경 변수 object → ACA 가 요구하는 [{name, value}] 배열 변환
var envArray = [for key in objectKeys(envVars): {
  name: key
  value: envVars[key]
}]

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: ingressExternal
        targetPort: targetPort
        transport: 'Auto'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: acrLoginServer
          identity: userAssignedIdentityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: imageName
          image: '${acrLoginServer}/${imageName}:${imageTag}'
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: envArray
          probes: [
            {
              type: 'Readiness'
              httpGet: {
                path: healthProbePath
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Liveness'
              httpGet: {
                path: healthProbePath
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 15
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: string(httpConcurrency)
              }
            }
          }
        ]
      }
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output latestRevisionName string = app.properties.latestRevisionName
