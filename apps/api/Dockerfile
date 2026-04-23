# syntax=docker/dockerfile:1.9
FROM python:3.12-slim-bookworm AS builder

COPY --from=ghcr.io/astral-sh/uv:0.10.3 /uv /usr/local/bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv

WORKDIR /app

# Resolve/install deps first (cache layer)
COPY pyproject.toml ./
# Optional lock file (ignored if absent)
COPY uv.lock* ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev --no-install-project

# Now copy source and install the project
COPY src ./src
COPY README.md ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev


FROM python:3.12-slim-bookworm AS runtime

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/healthz').status==200 else 1)" || exit 1

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
