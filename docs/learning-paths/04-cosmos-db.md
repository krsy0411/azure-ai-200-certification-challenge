# Phase 4 — NoSQL용 Azure Cosmos DB로 AI 솔루션 개발

**MS Learn**: https://learn.microsoft.com/ko-kr/training/paths/develop-ai-solutions-azure-cosmos-db/ (3 모듈)

## 학습 경로 구성

1. **Cosmos DB for NoSQL에 대한 쿼리 빌드** — 리소스 모델, Python SDK 통합, CRUD, SQL 쿼리.
2. **벡터 검색 구현** — 벡터 포함 저장, `VectorDistance` 유사성 쿼리, 메타데이터 필터 + 하이브리드 검색, 변경 피드로 포함 동기화.
3. **쿼리 성능 최적화** — 쿼리 패턴 분석, 범위·복합 인덱스, 벡터 인덱스 유형 선택, 일관성 수준 선택.

## 이 프로젝트에서의 적용

- 기본 문서/청크/벡터 저장소가 Cosmos DB
- 파티션 키: `/workspaceId` (워크스페이스 격리 + 쓰기 분산)
- 벡터 인덱스: `quantizedFlat` 시작 → 데이터 증가 후 `diskANN` 로 비교 실험
- 변경 피드 + Azure Function → 새로 올라온 청크 자동 임베딩
- 일관성 수준: 기본 `Session`, RAG 응답 생성엔 `Eventual` 고려

## 데이터 모델 초안

```json
// documents 컨테이너 (pk: /workspaceId)
{
  "id": "doc_01H...",
  "workspaceId": "ws_default",
  "title": "보안 정책 v3",
  "sourceBlobUrl": "...",
  "createdAt": "2026-04-21T...",
  "status": "indexed"
}

// chunks 컨테이너 (pk: /workspaceId)
{
  "id": "chunk_01H...",
  "workspaceId": "ws_default",
  "documentId": "doc_01H...",
  "ordinal": 7,
  "text": "...",
  "embedding": [/* 3072-d */],
  "tokens": 512
}
```

## 실습 쿼리 (진행 중 업데이트)

```sql
-- 하이브리드 검색: 메타데이터 필터 + 벡터 거리
SELECT TOP 5 c.id, c.text,
       VectorDistance(c.embedding, @queryVec) AS score
FROM   c
WHERE  c.workspaceId = @ws
  AND  c.documentId IN (@docFilter)
ORDER BY VectorDistance(c.embedding, @queryVec)
```

## 체크리스트

- [ ] Cosmos DB 계정 + 데이터베이스 + 컨테이너 2개 생성
- [ ] azure-cosmos SDK + Managed Identity 연결
- [ ] 문서 업로드 → 청크 → 임베딩 저장 플로우
- [ ] `VectorDistance` 쿼리로 상위 K 청크 검색
- [ ] 변경 피드 구독으로 재임베딩 파이프라인 검증
- [ ] RU 사용량 측정 + 인덱싱 정책 튜닝 노트
