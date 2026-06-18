# syntax=docker/dockerfile:1.7
# Multi-stage build — wheel 빌드용 stage + 슬림 런타임 stage 분리.
#
# 빌드 명령 (ARM Mac 환경 안전을 위해 --platform 옵션 필수):
#   docker build --platform linux/amd64 -t <acr>.azurecr.io/api:s01 .

FROM python:3.12-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /build

# 의존성만 먼저 복사해 layer 캐시 활용
COPY pyproject.toml ./
COPY src/ ./src/

RUN pip install --upgrade pip build && \
    pip wheel --wheel-dir=/wheels .

# ----------------------------------------------------------------------------

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# wheel 만 복사해 런타임 이미지 슬림하게 유지
COPY --from=builder /wheels /wheels
COPY pyproject.toml ./

RUN pip install --no-cache-dir --no-index --find-links=/wheels \
    ai200-workshop-api && \
    rm -rf /wheels

# OpenTelemetry 자동 계측 환경변수 (APPLICATIONINSIGHTS_CONNECTION_STRING 등) 는
# Azure Container Apps 가 envVars 로 주입한다.

EXPOSE 8000

# 비루트 사용자로 실행
RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
