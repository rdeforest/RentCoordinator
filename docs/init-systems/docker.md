# Docker Deployment

## External Documentation

- [Docker Official Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Deno Docker Images](https://github.com/denoland/deno_docker)

## Dockerfile

Create `/opt/rentcoordinator/Dockerfile`:

```dockerfile
# Build stage
FROM denoland/deno:1.40.0 AS builder

# Set working directory
WORKDIR /app

# Copy source files
COPY . .

# Build application
RUN deno task build

# Runtime stage
FROM denoland/deno:1.40.0

# Create non-root user
RUN useradd -m -s /bin/bash rentcoordinator

# Set working directory
WORKDIR /app

# Copy built application from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/static ./static
COPY --from=builder /app/deno.json ./deno.json

# Create directories for data and logs
RUN mkdir -p /data /logs && \
    chown -R rentcoordinator:rentcoordinator /app /data /logs

# Switch to non-root user
USER rentcoordinator

# Expose port
EXPOSE 3000

# Set environment variables
ENV PORT=3000
ENV DB_PATH=/data/db.kv

# Start application
CMD ["deno", "run", "--allow-read", "--allow-write", "--allow-env", "--allow-net", "--unstable-kv", "dist/main.js"]
```

## Docker Compose

Create `/opt/rentcoordinator/docker-compose.yml`:

```yaml
version: '3.8'

services:
  rentcoordinator:
    build: .
    container_name: rentcoordinator
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - ./data:/data
      - ./logs:/logs
    environment:
      - PORT=3000
      - DB_PATH=/data/db.kv
      - NODE_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

## Build and Run

### Using Docker

```bash
# Build image
docker build -t rentcoordinator .

# Run container
docker run -d \
  --name rentcoordinator \
  -p 3000:3000 \
  -v $(pwd)/data:/data \
  -v $(pwd)/logs:/logs \
  --restart unless-stopped \
  rentcoordinator

# View logs
docker logs -f rentcoordinator

# Stop container
docker stop rentcoordinator

# Start container
docker start rentcoordinator

# Remove container
docker rm rentcoordinator
```

### Using Docker Compose

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Rebuild and restart
docker-compose up -d --build

# Scale service (if configured)
docker-compose up -d --scale rentcoordinator=3
```

## Docker Swarm (Production)

Create `/opt/rentcoordinator/docker-stack.yml`:

```yaml
version: '3.8'

services:
  rentcoordinator:
    image: rentcoordinator:latest
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
    ports:
      - "3000:3000"
    volumes:
      - rentcoordinator-data:/data
    environment:
      - PORT=3000
      - DB_PATH=/data/db.kv
      - NODE_ENV=production
    networks:
      - rentcoordinator-net

volumes:
  rentcoordinator-data:
    driver: local

networks:
  rentcoordinator-net:
    driver: overlay
```

Deploy to swarm:

```bash
# Initialize swarm (if not already)
docker swarm init

# Deploy stack
docker stack deploy -c docker-stack.yml rentcoordinator

# List services
docker service ls

# View service logs
docker service logs -f rentcoordinator_rentcoordinator

# Update service
docker service update --image rentcoordinator:v2 rentcoordinator_rentcoordinator

# Remove stack
docker stack rm rentcoordinator
```