# Docker Deployment

## External Documentation

- [Docker Official Documentation](https://docs.docker.com/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Node.js Docker Images](https://hub.docker.com/_/node)

## Dockerfile

Create `/opt/rentcoordinator/Dockerfile`:

```dockerfile
# Build stage
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source files
COPY . .

# Build client-side CoffeeScript
RUN npm run build

# Runtime stage
FROM node:18-alpine

# Create non-root user
RUN adduser -D -s /bin/sh rentcoordinator

# Set working directory
WORKDIR /app

# Copy dependencies and built application from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/lib ./lib
COPY --from=builder /app/static ./static
COPY --from=builder /app/main.coffee ./main.coffee

# Create directories for data and logs
RUN mkdir -p /data /logs && \
    chown -R rentcoordinator:rentcoordinator /app /data /logs

# Switch to non-root user
USER rentcoordinator

# Expose port
EXPOSE 3000

# Set environment variables
ENV PORT=3000
ENV DB_PATH=/data/tenant-coordinator.db
ENV NODE_ENV=production

# Start application
CMD ["npx", "coffee", "main.coffee"]
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
      - DB_PATH=/data/tenant-coordinator.db
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
      - DB_PATH=/data/tenant-coordinator.db
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