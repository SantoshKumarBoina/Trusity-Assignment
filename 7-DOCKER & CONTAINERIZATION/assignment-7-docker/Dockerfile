# Use a small official Python image; pinning the minor version improves reproducibility.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install dependencies separately so Docker can reuse this layer when app code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Run as an unprivileged user.
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser app/ ./app/

USER appuser
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
