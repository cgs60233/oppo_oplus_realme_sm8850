#!/usr/bin/env bash
set -euo pipefail

upstream="${UPSTREAM_REPO:-cctv18/oppo_oplus_realme_sm8850}"
workflow="${WORKFLOW:-fastbuild_6.12.69_gki.yml}"
branch="${BRANCH:-main}"
repo="${REPO:-}"
wait_for_build="${WAIT_FOR_BUILD:-true}"
download_result="${DOWNLOAD_RESULT:-true}"
setup_only="${SETUP_ONLY:-false}"
output_dir="${OUTPUT_DIR:-$PWD/build-artifacts}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

install_gh() {
  command -v gh >/dev/null 2>&1 && return 0
  log "GitHub CLI not found; attempting installation"
  if command -v pkg >/dev/null 2>&1; then
    pkg install -y gh
  elif command -v apt-get >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y gh
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh
    else
      die "install gh first (apt-get exists but root/sudo is unavailable)"
    fi
  elif command -v brew >/dev/null 2>&1; then
    brew install gh
  else
    die "GitHub CLI is required; install it from https://cli.github.com/"
  fi
  command -v gh >/dev/null 2>&1 || die "gh installation did not succeed"
}

authenticate() {
  local status
  if ! status="$(gh auth status --hostname github.com 2>&1)"; then
    log "One-time GitHub authorization required"
    printf '%s\n' \
      "GitHub will show a one-time code and browser authorization page." \
      "Approve it personally. Never enter an account password into this script or an AI chat."
    gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow
    return 0
  fi

  # Existing logins may predate this Skill and lack permission to register a workflow.
  if ! grep -Eq "Token scopes:.*'workflow'" <<<"$status"; then
    log "Existing GitHub login needs workflow permission"
    gh auth refresh --hostname github.com --scopes workflow
  fi
}

select_repo() {
  local login current push_access fork_name
  login="$(gh api user --jq .login)"

  if [[ -n "$repo" ]]; then
    : # Respect an explicit REPO=owner/name.
  elif current="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
    push_access="$(gh api "repos/$current" --jq '.permissions.push // false')"
    if [[ "$push_access" == "true" ]]; then
      repo="$current"
    fi
  fi

  if [[ -z "$repo" ]]; then
    fork_name="${upstream#*/}"
    repo="$login/$fork_name"
    if ! gh repo view "$repo" >/dev/null 2>&1; then
      log "Creating fork $repo"
      gh repo fork "$upstream" --clone=false --remote=false
      # Fork creation can be asynchronous.
      for _ in $(seq 1 30); do
        gh repo view "$repo" >/dev/null 2>&1 && break
        sleep 2
      done
    fi
  fi

  [[ "$(gh api "repos/$repo" --jq '.permissions.push // false')" == "true" ]] || \
    die "no push access to $repo; unset REPO to let the script create/select your fork"
}

enable_and_register_actions() {
  local count sha raw encoded marker
  log "Enabling GitHub Actions in $repo"
  gh api --method PUT "repos/$repo/actions/permissions" \
    -F enabled=true -f allowed_actions=all >/dev/null

  gh api "repos/$repo/contents/.github/workflows/$workflow?ref=$branch" >/dev/null 2>&1 || \
    die "$workflow was not found in $repo at ref $branch"

  count="$(gh api "repos/$repo/actions/workflows" --jq .total_count)"
  if [[ "$count" == "0" ]]; then
    log "Registering inherited workflows in the new fork"
    sha="$(gh api "repos/$repo/contents/.github/workflows/$workflow?ref=$branch" --jq .sha)"
    raw="$(mktemp)"
    trap 'rm -f "${raw:-}" "${raw_new:-}"' EXIT
    gh api -H 'Accept: application/vnd.github.raw+json' \
      "repos/$repo/contents/.github/workflows/$workflow?ref=$branch" >"$raw"
    raw_new="$(mktemp)"
    marker="# Registered automatically for personal Actions builds"
    if grep -qxF "$marker" "$raw"; then
      cp "$raw" "$raw_new"
    else
      { printf '%s\n' "$marker"; cat "$raw"; } >"$raw_new"
    fi
    encoded="$(base64 <"$raw_new" | tr -d '\n')"
    gh api --method PUT "repos/$repo/contents/.github/workflows/$workflow" \
      -f message='Enable personal kernel build workflow' \
      -f content="$encoded" -f sha="$sha" -f branch="$branch" >/dev/null
    sleep 5
  fi

  gh workflow list -R "$repo" --all | grep -F "$workflow" >/dev/null 2>&1 || \
    gh api "repos/$repo/actions/workflows" --jq '.workflows[].path' | grep -qxF ".github/workflows/$workflow" || \
    die "GitHub has not registered $workflow yet; retry in a few seconds"
}

dispatch() {
  local before="0" newest id
  before="$(gh run list -R "$repo" --workflow "$workflow" --event workflow_dispatch \
    --limit 1 --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || printf '0')"

  cat <<EOF
Repository:  $repo
Workflow:    $workflow
Branch:      $branch
Device:      Xiaomi 17 Pro Max (popsicle/2509FPN0BC)
Kernel:      Android 16 GKI 6.12.69
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

  for _ in $(seq 1 30); do
    newest="$(gh run list -R "$repo" --workflow "$workflow" --event workflow_dispatch \
      --limit 1 --json databaseId,status,conclusion,url,createdAt --jq '.[0]')"
    id="$(gh run list -R "$repo" --workflow "$workflow" --event workflow_dispatch \
      --limit 1 --json databaseId --jq '.[0].databaseId // 0')"
    if [[ "$id" != "0" && "$id" != "$before" ]]; then
      printf '%s\n' "$newest"
      RUN_ID="$id"
      return 0
    fi
    sleep 2
  done
  die "workflow was dispatched but the new run could not be located"
}

wait_and_download() {
  [[ "$wait_for_build" == "true" ]] || return 0
  log "Waiting for run $RUN_ID"
  if ! gh run watch "$RUN_ID" -R "$repo" --exit-status; then
    gh run view "$RUN_ID" -R "$repo" --log-failed || true
    die "kernel build failed: $(gh run view "$RUN_ID" -R "$repo" --json url --jq .url)"
  fi

  [[ "$download_result" == "true" ]] || return 0
  mkdir -p "$output_dir/$RUN_ID"
  log "Downloading artifacts to $output_dir/$RUN_ID"
  gh run download "$RUN_ID" -R "$repo" --dir "$output_dir/$RUN_ID"
  find "$output_dir/$RUN_ID" -type f -print -exec sha256sum {} \;
  printf '%s\n' "Build succeeded. Artifacts were downloaded but NOT flashed."
}

install_gh
authenticate
select_repo
enable_and_register_actions
if [[ "$setup_only" == "true" ]]; then
  printf 'Setup check succeeded for %s; no build was dispatched.\n' "$repo"
  exit 0
fi
dispatch
wait_and_download
