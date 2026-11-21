#!/usr/bin/env bash
# Smoke test for the redirect-server image.
# Starts the image, then checks every redirect rule from nginx.conf.
#
# Usage: scripts/smoke-test.sh [image]    (default: redirect-server:test)
set -euo pipefail

IMAGE="${1:-redirect-server:test}"
NAME="redirect-smoke-$$"

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Publish on a random free port so the test never clashes with anything local.
docker run -d --name "$NAME" -p 127.0.0.1::80 "$IMAGE" >/dev/null
PORT="$(docker port "$NAME" 80/tcp | head -n1 | awk -F: '{print $NF}')"
BASE="http://127.0.0.1:${PORT}"

echo "Image:  $IMAGE"
echo "Server: $(docker exec "$NAME" nginx -v 2>&1)"

ready=0
for _ in $(seq 1 40); do
  if curl -s -o /dev/null "$BASE/"; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "$ready" -ne 1 ]]; then
  echo "FAIL nginx did not become ready"
  docker logs "$NAME" || true
  exit 1
fi

MAIN="https://razborpoletov.mave.digital/"
FEED="https://cloud.mave.digital/69770"

failures=0
check() {
  local path="$1" expected="$2" actual
  actual="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "${BASE}${path}")" || actual="curl failed"
  if [[ "$actual" == "301 ${expected}" ]]; then
    echo "ok   ${path} -> ${expected}"
  else
    echo "FAIL ${path}: expected '301 ${expected}', got '${actual}'"
    failures=$((failures + 1))
  fi
}

# Episode pages: /YYYY/MM/episode-NNN.html -> /ep-NNN
check /2020/05/episode-50.html  "${MAIN}ep-50"
check /2012/11/episode-1.html   "${MAIN}ep-1"
check /2019/03/episode-123.html "${MAIN}ep-123"

# RSS/Atom feeds
check /itunes.xml        "$FEED"
check /rss_full.xml      "$FEED"
check /atom_full.xml     "$FEED"
check /atom.xml          "$FEED"
check "/itunes.xml?x=1"  "$FEED"

# Everything else -> main page
check /                           "$MAIN"
check /some/unknown/path          "$MAIN"
check /2020/05/episode-abc.html   "$MAIN"

if [[ "$failures" -ne 0 ]]; then
  echo "${failures} check(s) failed"
  docker logs "$NAME" || true
  exit 1
fi
echo "All checks passed"
