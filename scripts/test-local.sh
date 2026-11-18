#!/usr/bin/env bash
# Run the test suite against a throwaway eXist-db container, mirroring CI.
#
# usage: scripts/test-local.sh [exist-version]   (default: release)
#        KEEP=1 scripts/test-local.sh latest     keep the container afterwards
#
# Tokens for the sample repositories are read from .env.test (see .env.test.example).
# If no GitHub token is set there, the token of the GitHub CLI (gh auth token) is used.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:-release}"
name="tuttle-test-${version//[^a-zA-Z0-9]/-}"
port=8443

if [[ -f .env.test ]]; then
    set -a; source .env.test; set +a
fi

# macOS: tokens can be kept in the login keychain instead of .env.test
#   security add-generic-password -U -a "$USER" -s tuttle_token_tuttle_sample_gitlab -w
if command -v security >/dev/null; then
    for var in tuttle_token_tuttle_sample_data tuttle_token_tuttle_sample_gitlab; do
        if [[ -z "${!var:-}" ]]; then
            printf -v "$var" '%s' "$(security find-generic-password -a "$USER" -s "$var" -w 2>/dev/null || true)"
        fi
    done
fi

if [[ -z "${tuttle_token_tuttle_sample_data:-}" ]] && command -v gh >/dev/null; then
    tuttle_token_tuttle_sample_data="$(gh auth token 2>/dev/null || true)"
fi

[[ -n "${tuttle_token_tuttle_sample_data:-}" ]] || echo "warning: no GitHub token, GitHub tests will fail" >&2
[[ -n "${tuttle_token_tuttle_sample_gitlab:-}" ]] || echo "warning: no GitLab token, GitLab tests will fail" >&2

# an empty autodeploy folder, so no default apps get installed (same as CI)
autodeploy="$(mktemp -d)"

cleanup() {
    if [[ -z "${KEEP:-}" ]]; then
        docker rm -f "$name" >/dev/null 2>&1 || true
    else
        echo "keeping container $name"
    fi
    rm -rf "$autodeploy"
}
trap cleanup EXIT

docker rm -f "$name" >/dev/null 2>&1 || true
docker pull -q "existdb/existdb:$version" >/dev/null
docker run -d --name "$name" -p "$port:8443" \
    -e tuttle_token_tuttle_sample_data="${tuttle_token_tuttle_sample_data:-}" \
    -e tuttle_token_tuttle_sample_gitlab="${tuttle_token_tuttle_sample_gitlab:-}" \
    -v "$autodeploy:/exist/autodeploy" \
    "existdb/existdb:$version" >/dev/null

printf 'waiting for eXist-db %s ' "$version"
for _ in $(seq 1 100); do
    if curl -sk -u admin: -o /dev/null -f "https://127.0.0.1:$port/exist/rest/db?_query=1"; then
        break
    fi
    printf '.'; sleep 3
done
echo
echo "running against eXist-db $(curl -sk -u admin: "https://127.0.0.1:$port/exist/rest/db?_query=system:get-version()&_wrap=no")"

npm test
