# Phase 7 — AI 솔루션용 백엔드 서비스 통합

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/integrate-backend-services-ai-solutions/ (3 모듈)

## 학습 경로 구성

1. **Service Bus 로 AI 작업 큐·처리** — 큐/토픽+구독, DLQ, 경쟁 소비자, AI 페이로드 메시지 구조화, Python SDK 기반 신뢰성 처리.
2. **Event Grid 이벤트 기반 AI 워크플로** — 이벤트 구독, CloudEvents, 배달 정책, 사용자 지정 이벤트 게시.
3. **Azure Functions 서버리스 AI 백엔드** — 추론 엔드포인트, 이벤트 프로세서, 다른 Azure 서비스와의 보안 통합.

## 이 프로젝트에서의 적용

- **Blob 업로드 → Event Grid → Azure Function** 훅 체인
- Function이 문서를 청크로 분할하고 `inference-queue` (Service Bus) 에 메시지 등록
- AKS 워커 / ACA 워커가 큐에서 꺼내 임베딩 수행 (경쟁 소비자 패턴)
- DLQ 분리 + 재시도 정책 (지수 백오프)
- Event Grid 사용자 지정 토픽: 인덱싱 완료 이벤트 → Redis Pub/Sub + Next.js 알림

## 토픽·큐 이름 규칙

| 리소스 | 이름 |
|---|---|
| Service Bus 네임스페이스 | `sb-ai200challenge-dev` |
| 큐: 임베딩 작업 | `inference-queue` |
| 큐: DLQ(자동) | `inference-queue/$DeadLetterQueue` |
| Event Grid 시스템 토픽 | Blob Storage → `documents` 컨테이너 |
| Event Grid 사용자 토픽 | `egt-ai200challenge-dev` (`ai200challenge.document.indexed` 이벤트) |
| Azure Functions | `func-ai200challenge-dev` (Flex Consumption) |

## 체크리스트

- [ ] Service Bus Standard 네임스페이스 + 큐 생성
- [ ] Azure Function(Flex Consumption) + Storage 계정
- [ ] Event Grid 시스템 토픽 구독 → Function 트리거
- [ ] 업로드 → Function → Service Bus enqueue 흐름 검증
- [ ] 워커 컨슈머: 메시지 처리 + completed/abandoned 전략
- [ ] DLQ 메시지 재처리 스크립트
