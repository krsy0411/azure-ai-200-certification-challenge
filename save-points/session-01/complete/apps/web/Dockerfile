# syntax=docker/dockerfile:1.7
# Next.js 14 standalone 빌드 — multi-stage 로 슬림 런타임 이미지 생성.
#
# 빌드 명령 (ARM Mac 환경 안전을 위해 --platform 옵션 필수):
#   docker build --platform linux/amd64 -t <acr>.azurecr.io/web:s01 .

# ----- 1) deps stage: 의존성 설치 -----
FROM node:20-alpine AS deps

WORKDIR /app

# package-lock.json 이 있으면 ci 로 재현 가능한 설치
COPY package.json package-lock.json* ./
RUN npm ci || npm install

# ----- 2) builder stage: Next.js 빌드 -----
FROM node:20-alpine AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# next.config.mjs 의 output: "standalone" 이 .next/standalone/ 산출물을 생성
RUN npm run build

# ----- 3) runtime stage: 슬림 런타임 -----
FROM node:20-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# 비루트 사용자 생성
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# standalone 빌드 산출물 + 정적 파일 + public/ 만 복사
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
# public/ 은 본 워크샵에서 비어있을 수 있으므로 조건부 처리
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER nextjs

EXPOSE 3000

# Next.js standalone server.js 진입
CMD ["node", "server.js"]
