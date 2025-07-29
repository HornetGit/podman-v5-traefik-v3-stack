# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Add PostgreSQL client tools for pg_isready
# for DEBUG only: dialog, curl, apt-utils (to be removed for PROD)
# Layer reduction: group all apt-get into 1 liner
# DEV mode only (remove for PROD): Adding nano
# PROD: keep PostgreSQL client tools for "pg_isready"
RUN apt-get update && \
    apt-get install -y nano dialog apt-utils postgresql-client curl && \
    rm -rf /var/lib/apt/lists/*

# for python: alpine
# RUN apk add --no-cache postgresql-client 

# DEBUG
# COPY backend/debug.sh /debug.sh
# RUN chmod +x /debug.sh

# Set the working directory in the container
WORKDIR /code/app

# Copy the requirements file into the container at /app
COPY backend/requirements.txt .

# copy main and __init__.py files into the container at /code/app
COPY backend/app .

# workaround for podman v4 (without healthchecks)
# COPY backend/wait-for-db.sh .


# Install any dependencies specified in requirements.txt
# options:
# --workers to use multiple workers for uvicorn (case of multiple containers calling a fastapi process)
# --proxy-headers is used to trust the headers from the reverse proxy (Traefik)
RUN pip install --no-cache-dir --upgrade -r requirements.txt

# Exposing the port that Fastapi will run on
EXPOSE "8001"

# Healthcheck workaround
# HEALTHCHECK CMD pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" || exit 1
# ENTRYPOINT ["./wait-for-db.sh"]

# Backend tests DB - this is the ONLY health check needed
# HEALTHCHECK --interval=15s --timeout=10s --start-period=40s --retries=3 \
#   CMD pg_isready -h "$POSTGRES_DB_HOST" -p "$POSTGRES_DB_PORT" -U "$POSTGRES_DB_USER" || exit 1

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["pg_isready", "-h", "$POSTGRES_DB_HOST", "-p", "$POSTGRES_DB_PORT", "-U", "$POSTGRES_DB_USER"]

# HEALTHCHECK --interval=15s --timeout=10s --start-period=40s --retries=3 \
#   CMD pg_isready -h "miniapp_db" -p "5432" -U "miniapp_user" || exit 1

# Command to run the backend application using Uvicorn
# PROD (no auto reload): CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
# DEV: auto-reload enabled to aoid restarting the backend cntainer if modifying files directly in the container
# NOTE: could be flagged as below for DEV/STAGING/PROD: 
# CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"%%RELOAD_FLAG%%]
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001", "--reload"]

# OR:
# ENTRYPOINT ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]