FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && useradd --uid 10001 --create-home photoparts
COPY photo_parts ./photo_parts
USER photoparts
ENV BIND=0.0.0.0 PORT=8080 OPENBLAS_NUM_THREADS=1
EXPOSE 8080
CMD ["python", "-m", "photo_parts.app"]
