# ClassLink backend image. Build from the backend/ directory:
#   docker build -t classlink-backend backend
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv
COPY pyproject.toml ./
COPY app ./app
RUN pip install .

# Run as an unprivileged user.
RUN useradd --system --uid 10001 --no-create-home appuser
USER appuser

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=4s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=3)"

# --proxy-headers: the platform terminates TLS in front of the container.
CMD ["uvicorn", "app.main:app_from_env", "--factory", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
