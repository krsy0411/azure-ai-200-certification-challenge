# Phase 6 — Azure Managed Redis로 AI 솔루션 향상

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/enhance-ai-solutions-azure-managed-redis/ (3 모듈)

## 학습 경로 구성

1. **Redis 데이터 작업 구현** — 클라이언트 모범 사례, 데이터 저장/검색.
2. **이벤트 메시징 구현** — Pub/Sub 알림 브로드캐스팅, Redis Streams 로 신뢰할 수 있는 비동기 작업 처리.
3. **벡터 스토리지 구현** — 벡터 인덱스, 임베딩 쿼리, 벡터 유형·인덱싱 전략.

## 이 프로젝트에서의 적용

- **시맨틱 캐시**: RAG 질문 임베딩 → Redis 벡터 인덱스로 유사 질문 검색 → 캐시된 응답 재사용
- **Pub/Sub**: 문서 인덱싱 완료 / 챗 세션 메시지 브로드캐스트 → Next.js에서 Server-Sent Events로 전달
- **Streams**: 경량 작업 큐(임베딩 재처리) — Service Bus 와 비교해 RTT/비용 확인
- `redis-py` + Azure AD 토큰 인증

## 시맨틱 캐시 키 설계

```
FT.CREATE idx:semantic ON HASH PREFIX 1 sc:
  SCHEMA
    workspaceId TAG
    question   TEXT
    embedding  VECTOR HNSW 6 DIM 3072 TYPE FLOAT32 DISTANCE_METRIC COSINE
    answer     TEXT
    tokens     NUMERIC
    createdAt  NUMERIC SORTABLE
```

- TTL 예: 24시간
- 히트 판단: 코사인 유사도 ≥ 0.92 AND 같은 `workspaceId`

## 체크리스트

- [ ] Azure Managed Redis 인스턴스 생성 (Enterprise, RediSearch 포함)
- [ ] 시맨틱 캐시 모듈 구현 + p50 지연/히트율 로깅
- [ ] Pub/Sub 채널 설계 (`ws:<workspaceId>:events`)
- [ ] Streams 컨슈머 그룹 + acknowledge + retry
- [ ] 토큰 만료 재연결 검증
