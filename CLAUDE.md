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

Smoke test (runs every redirect rule against a throwaway container):

```bash
scripts/smoke-test.sh redirect-server:test
```

## CI/CD

GitHub Actions builds and pushes to `ghcr.io/razbor-poletov/redirect-server` on push to `main`.
Image is tagged with `latest` and commit SHA. The image is built and smoke-tested
(`scripts/smoke-test.sh`) first; it is pushed only if the smoke test passes. PRs run build + smoke test without pushing.

The nginx version is pinned in `Dockerfile`. Dependabot (`.github/dependabot.yml`, weekly) opens PRs for
the base image and GitHub Actions. For non-major Dependabot PRs the `merge-dependabot` job approves the PR and
enables auto-merge (`gh pr merge --auto --squash`); GitHub merges it once the required `build-and-push` check
(build + smoke test) passes. The job waits for the merge and then publishes the image via `workflow_dispatch`
(merges made with `GITHUB_TOKEN` do not trigger the `push` event). Major bumps need manual review.

`main` is protected by the "Main branch" ruleset (required check `build-and-push`, branch must be up to date),
so changes reach `main` through pull requests, not direct pushes. `scripts/check-ruleset.sh` (CI job
`check-ruleset`, also runnable locally as an admin) verifies that ruleset and the merge settings the automation
relies on; if you rename the `build-and-push` job, update the ruleset's required check too.

## Deployment

```bash
docker pull ghcr.io/razbor-poletov/redirect-server:latest
docker run -d --name redirect -p 80:80 --restart unless-stopped ghcr.io/razbor-poletov/redirect-server:latest
```
