# hugegraph-mirror

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/PROJECT-bitflicker/hugegraph-mirror)

A single, continuously-updated mirror of the active Apache HugeGraph repos,
maintained so it can be pointed at DeepWiki (or anything else) as one
source of truth instead of five.

## What's in here

| Directory              | Upstream                          | Default branch |
|------------------------|------------------------------------|-----------------|
| `hugegraph/`            | apache/hugegraph                   | master |
| `hugegraph-ai/`         | apache/hugegraph-ai                | main |
| `hugegraph-computer/`   | apache/hugegraph-computer          | master |
| `hugegraph-toolchain/`  | apache/hugegraph-toolchain         | master |
| `hugegraph-doc/`        | apache/hugegraph-doc               | master |

**Not included:** `hugegraph-commons` and `hugegraph-tools` — both are
archived on the Apache side. `hugegraph-commons`'s own description says
it has been folded into `apache/hugegraph`, so mirroring it separately
would just be a stale duplicate.

Each subdirectory is a flat snapshot of that repo's default branch —
no `.git` history, no submodules. This repo's own commit history *is*
the changelog (one commit per upstream repo per real change).

## How it stays fresh

`.github/workflows/sync.yml` runs `scripts/sync.sh` hourly (plus on-demand
via the Actions tab, and automatically whenever the script itself is
edited). Each run:

1. Asks the GitHub API for each repo's current default-branch SHA.
2. Compares it to `sync/state.json`. Unchanged → skip, no clone, no commit.
3. Changed → shallow-clones that one repo, `rsync`s it into its
   subdirectory, updates `sync/state.json`, commits.
4. Pushes anything that changed.

One repo failing to sync (network blip, upstream rename, whatever) is
logged and skipped — it does not block the other repos in the same run.

## Manual re-index

Whenever you want DeepWiki to pick up the latest state, just trigger a
DeepWiki re-index against this repo directly — the mirror itself is
already kept current independently of that, on its own hourly cycle.
