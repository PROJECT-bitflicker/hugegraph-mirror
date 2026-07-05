#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${STATE_FILE:-sync/state.json}"
GITHUB_API="${GITHUB_API:-https://api.github.com}"
UPSTREAM_OWNER="${UPSTREAM_OWNER:-apache}"

REPOS=(
  hugegraph
  hugegraph-ai
  hugegraph-computer
  hugegraph-toolchain
  hugegraph-doc
)

curl_gh() {
  # Unauthenticated GitHub API calls are capped at 60/hour PER IP, and on a
  # shared IP (any CI runner pool, this sandbox, etc.) that quota can already
  # be gone before your first request -- confirmed live while building this
  # script (got a real 403 rate-limit body, not a guess). Authenticated calls
  # get 5000/hour and their own quota bucket, so always send a token when
  # one's available (the Actions job always has one).
  local url="$1"
  local -a hdrs=(-H "User-Agent: hugegraph-mirror-sync")
  [[ -n "${GITHUB_TOKEN:-}" ]] && hdrs+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  curl -fsSL "${hdrs[@]}" "$url"
}

resolve_branch() {
  local repo="$1"
  curl_gh "${GITHUB_API}/repos/${repo}" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['default_branch'])"
}

resolve_sha() {
  local repo="$1" branch="$2"
  curl_gh "${GITHUB_API}/repos/${repo}/commits/${branch}" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['sha'])"
}

get_state() {
  local name="$1"
  python3 -c "
import json
d = json.load(open('${STATE_FILE}'))
print(d['upstreams'].get('${name}', ''))
"
}

set_state() {
  local name="$1" sha="$2" ts="$3"
  python3 -c "
import json
p = '${STATE_FILE}'
d = json.load(open(p))
d['upstreams']['${name}'] = '${sha}'
d['last_sync'] = '${ts}'
json.dump(d, open(p, 'w'), indent=2)
"
}

# sync_repo takes an already-resolved branch+sha and an explicit clone_url
# (rather than reaching into REPOS/UPSTREAM_OWNER itself) so it can be
# unit-tested against a local fixture repo with no network involved.
sync_repo() {
  local name="$1" clone_url="$2" branch="$3" sha="$4"

  local previous
  previous=$(get_state "$name")

  if [[ "$sha" == "$previous" ]]; then
    echo "  [skip] ${name} unchanged @ ${sha:0:7}"
    return 0
  fi

  local prev_display="none"
  [[ -n "$previous" ]] && prev_display="${previous:0:7}"
  echo "  [update] ${name} ${prev_display} -> ${sha:0:7}"

  local tmp
  tmp=$(mktemp -d)
  if ! git clone --quiet --depth=1 --branch "$branch" "$clone_url" "${tmp}/src" 2>/dev/null; then
    echo "  [FAIL] ${name} clone failed, leaving previous copy in place"
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "${tmp}/src/.git"
  mkdir -p "$name"
  # rsync -a copies dotfiles correctly. `mv "$dir"/* dest/` (used in the
  # Hermes bootstrap step) silently drops .gitignore, .github/, etc. because
  # the shell glob `*` doesn't match dotfiles unless dotglob is set -- and
  # even then it's one more thing to get right in two places instead of one.
  rsync -a --delete "${tmp}/src/" "${name}/"
  rm -rf "$tmp"

  set_state "$name" "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git add "${name}" "${STATE_FILE}" 2>/dev/null || true
  git commit -m "sync(${name}): ${prev_display} -> ${sha:0:7}" --quiet 2>/dev/null || true
  return 0
}

main() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [[ -f "$STATE_FILE" ]] || echo '{"last_sync": null, "upstreams": {}}' > "$STATE_FILE"

  local failed=()
  for name in "${REPOS[@]}"; do
    local repo="${UPSTREAM_OWNER}/${name}"
    echo "=== ${repo} ==="

    local branch sha
    if ! branch=$(resolve_branch "$repo") || [[ -z "$branch" ]]; then
      echo "  [FAIL] ${name}: could not resolve default branch"
      failed+=("$name"); continue
    fi
    if ! sha=$(resolve_sha "$repo" "$branch") || [[ -z "$sha" ]]; then
      echo "  [FAIL] ${name}: could not resolve HEAD sha"
      failed+=("$name"); continue
    fi

    sync_repo "$name" "https://github.com/${repo}.git" "$branch" "$sha" || failed+=("$name")
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    echo "::warning::sync failures: ${failed[*]}"
  fi
}

# Guard so a test harness can `source sync.sh` and call sync_repo/resolve_*
# directly without main() firing.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
