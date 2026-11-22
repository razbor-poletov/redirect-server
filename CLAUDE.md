# Redirect Server

Lightweight nginx-based Docker image that redirects traffic from razborpoletov.com to razborpoletov.mave.digital.

## Project Structure

- `nginx.conf` — nginx redirect rules
- `Dockerfile` — Docker image definition (nginx alpine image, version pinned)
- `scripts/smoke-test.sh` — smoke test of the built image
- `.github/workflows/` — CI/CD pipeline and Dependabot auto-merge
- `.github/config/`, `mise.toml` — declarative GitHub repo configuration and the task that applies it

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
the base image and GitHub Actions. Workflows, one concern per file:

- `docker-publish.yml` — build, smoke test, push (the `build-and-push` job).
- `dependabot-automerge.yml` — approves non-major Dependabot PRs and enables auto-merge; GitHub merges once the
  required `build-and-push` check passes. The job waits for the merge and dispatches `docker-publish.yml`,
  because merges made with `GITHUB_TOKEN` do not trigger the `push` event. Major bumps need manual review.

**Don't rename the `build-and-push` job:** the "Main branch" ruleset requires a check with this name, so a rename
silently stops protecting `main`.

## GitHub repository configuration

Repo settings are declared in `.github/config/` (GitHub API payloads) and applied with the
[gh repo-config](https://github.com/twelvelabs/gh-repo-config) extension:

- `repo.json` — repository settings (merge methods, delete branch on merge, ...)
- `topics.json` — topics
- `actions-permissions.json` — default workflow permissions `read`; Actions may approve PRs (needed by
  `dependabot-automerge.yml`)
- Apply: `mise run repo:apply` (once: `gh extension install twelvelabs/gh-repo-config`)
- Change these settings in the files and apply them, not in the UI
- Protection of `main` is not in these files: it is the "Main branch" ruleset (deletion, no force push, required
  check `build-and-push`, branch up to date), configured in the repository settings

## Deployment

```bash
docker pull ghcr.io/razbor-poletov/redirect-server:latest
docker run -d --name redirect -p 80:80 --restart unless-stopped ghcr.io/razbor-poletov/redirect-server:latest
```
