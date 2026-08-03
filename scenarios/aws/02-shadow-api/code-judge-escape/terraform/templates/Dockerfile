FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget && \
    wget -qO- https://download.docker.com/linux/static/stable/x86_64/docker-26.1.4.tgz | \
        tar xz --strip-components=1 -C /usr/local/bin docker/docker && \
    apt-get purge -y wget && apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir flask==3.0.3 gunicorn==22.0.0

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--threads", "4", "--access-logfile", "-", "app:app"]
