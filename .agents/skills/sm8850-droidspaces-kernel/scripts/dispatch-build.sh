#!/usr/bin/env bash
set -euo pipefail

workflow="fastbuild_6.12.69_gki.yml"
branch="${BRANCH:-main}"
repo="${REPO:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: GitHub CLI (gh) is required" >&2
  exit 127
fi

gh auth status --hostname github.com >/dev/null

if [[ -z "$repo" ]]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi

# Guard against accidentally dispatching this device-specific recipe elsewhere.
if ! gh api "repos/$repo/contents/.github/workflows/$workflow?ref=$branch" >/dev/null 2>&1; then
  echo "error: $workflow was not found in $repo at ref $branch" >&2
  exit 2
fi

cat <<EOF
Repository: $repo
Workflow:   $workflow
Branch:     $branch
Device:     Xiaomi 17 Pro Max (popsicle/2509FPN0BC)
Kernel:     Android 16 GKI 6.12.69
DroidSpaces: standard
EOF

gh workflow run "$workflow" -R "$repo" --ref "$branch" \
  -f ksu_type=resukisu \
  -f susfs_enable=true \
  -f kpm_enable=false \
  -f lz4_enable=true \
  -f lz4kd_enable=false \
  -f bbr_enable=false \
  -f droidspaces_enable=standard \
  -f better_net=true \
  -f adios_enable=true \
  -f rekernel_enable=false \
  -f baseband_guard=false \
  -f ccache_update=false \
  -f ccache_debug=false \
  -f kernel_suffix=popsicle-droidspaces

sleep 3
gh run list -R "$repo" --workflow "$workflow" --limit 1 \
  --json databaseId,status,conclusion,url,createdAt \
  --jq '.[0]'
