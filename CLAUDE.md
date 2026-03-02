# Redirect Server

Lightweight nginx-based Docker image that redirects traffic from razborpoletov.com to razborpoletov.mave.digital.

## Project Structure

- `nginx.conf` — nginx redirect rules
- `Dockerfile` — Docker image definition (nginx:alpine based)
- `.github/workflows/docker-publish.yml` — CI/CD pipeline

## Redirect Rules

1. `/YYYY/MM/episode-NNN.html` → `https://razborpoletov.mave.digital/ep-NNN`
2. `/itunes.xml` → `https://cloud.mave.digital/69770`
3. Everything else → `https://razborpoletov.mave.digital/`

## Build & Test

```bash
# Build for x86
docker build --platform linux/amd64 -t redirect-server:test .

# Run locally
docker run -d --name redirect-test -p 8888:80 redirect-server:test

# Test redirects
curl -I http://localhost:8888/2020/05/episode-50.html
curl -I http://localhost:8888/itunes.xml
curl -I http://localhost:8888/

# Cleanup
docker stop redirect-test && docker rm redirect-test
```

## CI/CD

GitHub Actions builds and pushes to `ghcr.io/razbor-poletov/redirect-server` on push to `main`.
Image is tagged with `latest` and commit SHA.

## Deployment

```bash
docker pull ghcr.io/razbor-poletov/redirect-server:latest
docker run -d --name redirect -p 80:80 --restart unless-stopped ghcr.io/razbor-poletov/redirect-server:latest
```
