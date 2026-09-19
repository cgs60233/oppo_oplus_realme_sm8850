---
name: sm8850-droidspaces-kernel
description: Detects Android device/kernel compatibility and builds this repository's SM8850/MT6993 DroidSpaces kernel with GitHub Actions. Use for Xiaomi, OPPO, OnePlus, or Realme kernel builds, especially the device-tested Xiaomi 17 Pro Max popsicle Android 16 GKI 6.12.69 recipe; includes safe GitHub authentication, workflow dispatch, artifact verification, and recovery guidance.
compatibility: Requires network access and GitHub CLI (`gh`) for automated dispatch. Android detection may require root/nsenter. Flashing is intentionally not automated.
metadata:
  author: cgs60233
  tested-device: Xiaomi 17 Pro Max (popsicle/2509FPN0BC)
  tested-workflow: fastbuild_6.12.69_gki.yml
---

# SM8850 DroidSpaces kernel build

Use this skill to select and run a compatible workflow from this repository. Treat kernel flashing as a separate destructive operation.

## One-command path

After confirming that the target is the tested `popsicle` configuration, run from a clone of this repository:

```bash
.agents/skills/sm8850-droidspaces-kernel/scripts/dispatch-build.sh
```

The script installs `gh` when a supported package manager is available, reuses an existing GitHub authorization, or starts the official one-time device authorization when needed. It then selects/creates a writable fork, enables and registers Actions, dispatches the known-good recipe, waits for completion, downloads artifacts, and prints SHA-256 hashes.

The only unavoidable first-use interaction is approving GitHub's device authorization in a browser. Subsequent builds reuse the locally stored `gh` credential and can run unattended. Set `WAIT_FOR_BUILD=false` to return after dispatch, `DOWNLOAD_RESULT=false` to skip downloading, `OUTPUT_DIR=/path` to choose the artifact destination, or `SETUP_ONLY=true` to validate authorization/repository/Actions without dispatching a build.

## Hard safety rules

1. Never ask for, accept, echo, commit, or store a GitHub password or token. Use `gh auth login --web` (device authorization).
2. Never select a workflow from the phone model alone. Match SoC, GKI/vendor type, Android kernel base, and exact `uname -r` major/minor/patch.
3. Never flash automatically. Building/downloading is not permission to write `boot`, `init_boot`, `vendor_boot`, `dtbo`, `vbmeta`, or `recovery`.
4. Before any later flashing operation, back up the active-slot boot image and verify that fastboot or an independently bootable recovery is available.
5. Prefer `fastboot boot <test.img>` from a second device/PC when supported. An AnyKernel ZIP performs a persistent boot-partition modification and is not a temporary boot.
6. Do not promise automatic recovery. A/B slots do not guarantee rollback after a boot image is modified.

## Known successful build

The following combination was built successfully and then reported by the device owner as successfully flashed/booted:

| Item | Value |
|---|---|
| Device | Xiaomi 17 Pro Max |
| Model | `2509FPN0BC` |
| Product/device | `popsicle` |
| SoC/platform | Qualcomm SM8850, `canoe` |
| Kernel before test | `6.12.69-android16-6-g586bfab1b9c5-abogki537510563-4k` |
| Workflow | `.github/workflows/fastbuild_6.12.69_gki.yml` |
| DroidSpaces mode | `standard` |
| Kernel suffix | `popsicle-droidspaces` |
| Successful Actions run | `35441095129` |
| Run URL | <https://github.com/cgs60233/oppo_oplus_realme_sm8850/actions/runs/35441095129> |
| Release tag | `OPPO-OPlus-Realme-build-260919195257` |
| Result | build/release succeeded; owner reported successful direct flash and boot |

Known artifact:

```text
AnyKernel3_ReSukiSU_35158_6.12_popsicle-droidspaces.zip
size: 20453218 bytes
GitHub Actions artifact SHA-256: faa1719b2494029449207f54f1ca4cd8de60cb998838d7e30bcffef14666aed6
```

The digest above applies to that exact historical artifact only. Always calculate and record a new digest for every new build.

## 1. Detect the device

When running inside a rooted Android-hosted container where `getprop` is not on `PATH`, enter PID 1's mount namespace:

```bash
nsenter -t 1 -m -- /system/bin/getprop ro.product.marketname
nsenter -t 1 -m -- /system/bin/getprop ro.product.model
nsenter -t 1 -m -- /system/bin/getprop ro.product.device
nsenter -t 1 -m -- /system/bin/getprop ro.board.platform
nsenter -t 1 -m -- /system/bin/getprop ro.build.version.release
nsenter -t 1 -m -- /system/bin/getprop ro.boot.slot_suffix
uname -r
tr '\0' ' ' </proc/device-tree/model; echo
zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_(SYSVIPC|USER_NS|PID_NS|IPC_NS|NTSYNC|KVM|ANDROID_BINDERFS|OVERLAY_FS)='
```

Also inspect boot/recovery layout without writing anything:

```bash
nsenter -t 1 -m -- sh -c \
  'ls -l /dev/block/by-name | grep -E " (boot|init_boot|vendor_boot|recovery|dtbo|vbmeta)(_[ab])? ->"'
```

Expected values for the tested recipe:

```text
market name: Xiaomi 17 Pro Max
model: 2509FPN0BC
device: popsicle
platform: canoe
SoC/device tree: SM8850
kernel: 6.12.69, Android 16 GKI base
bootloader: unlocked
```

Android framework can be newer than the vendor/kernel base. Select the workflow by the kernel/vendor base, not merely `ro.build.version.release`.

## 2. Select the workflow

List workflows and inspect their inputs:

```bash
gh workflow list --all
grep -nE 'ANDROID_VERSION|KERNEL_VERSION|SUB_VERSION|droidspaces_enable' \
  .github/workflows/*.yml
```

For `popsicle` with 6.12.69 Android 16 GKI, use only:

```text
.github/workflows/fastbuild_6.12.69_gki.yml
```

Do not use the OPPO/OnePlus/Realme OKI 6.12.23, 6.12.38, or 6.12.58 workflows for this tested Xiaomi configuration. If the device patch level changes, stop and reassess rather than silently reusing 6.12.69.

## 3. Authenticate safely

Normally the bundled dispatch script handles this section. It first checks:

```bash
gh auth status --hostname github.com
```

When no reusable authorization exists, it runs:

```bash
gh auth login --hostname github.com --git-protocol https --web --scopes repo,workflow
```

GitHub prints a one-time code and authorization URL. The account owner must approve this first authorization personally; an agent cannot safely or legitimately bypass it. Do not use account passwords. After approval, GitHub CLI stores its OAuth credential locally and later Skill invocations proceed without another prompt unless the credential is revoked or expires.

For an existing login that lacks workflow scope:

```bash
gh auth refresh --hostname github.com --scopes workflow
```

Never solicit credentials in chat, put tokens in command arguments, or commit GitHub CLI configuration files.

## 4. Ensure a writable repository and registered Actions

Determine the current repository:

```bash
gh repo view --json nameWithOwner,isFork,defaultBranchRef,url
```

If working from upstream without push access, fork it:

```bash
gh repo fork cctv18/oppo_oplus_realme_sm8850 --clone=false
```

For a new fork, GitHub may show workflow files but return zero registered workflows. First enable Actions in repository settings. If workflows still are not registered, make a harmless, reviewed commit to the selected workflow (for example, a comment) with `workflow` scope, then re-list:

```bash
gh workflow list --all
```

Do not rewrite workflow logic merely to force registration.

## 5. Dispatch the tested recipe

From the repository root, the recommended fully orchestrated command is:

```bash
.agents/skills/sm8850-droidspaces-kernel/scripts/dispatch-build.sh
```

Optional environment controls:

```bash
WAIT_FOR_BUILD=false ./path/to/dispatch-build.sh  # dispatch and return
DOWNLOAD_RESULT=false ./path/to/dispatch-build.sh # wait but do not download
OUTPUT_DIR="$HOME/kernel-output" ./path/to/dispatch-build.sh
REPO="owner/oppo_oplus_realme_sm8850" ./path/to/dispatch-build.sh
SETUP_ONLY=true ./path/to/dispatch-build.sh       # no build is started
```

By default it waits, downloads, and hashes artifacts. It never flashes them.

Or dispatch manually:

```bash
gh workflow run fastbuild_6.12.69_gki.yml --ref main \
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
```

Rationale for conservative choices:

- `standard`: known successful DroidSpaces mode; use `extend` only when experimental additions are specifically needed.
- `kpm_enable=false`: avoid an unnecessary extra patch layer.
- `baseband_guard=false`: avoid unexpected partition-write restrictions during initial testing.
- `ccache_update=false`: do not overwrite shared/personal cache during a normal build.
- `better_net=true`: useful container networking options.

## 6. Monitor and verify

Find and watch the newest run:

```bash
gh run list --workflow fastbuild_6.12.69_gki.yml --limit 3
gh run watch <RUN_ID> --exit-status
```

Inspect failures if needed:

```bash
gh run view <RUN_ID> --log-failed
```

A cache reservation/save warning alone is non-fatal when both `build` and `release` jobs conclude `success`.

List artifacts:

```bash
gh api repos/{owner}/{repo}/actions/runs/<RUN_ID>/artifacts \
  --jq '.artifacts[] | {id,name,size_in_bytes,expired,archive_download_url}'
```

Download without flashing:

```bash
mkdir -p build-artifacts
gh run download <RUN_ID> --dir build-artifacts
find build-artifacts -type f -exec sha256sum {} +
```

Be aware that an Actions download can be an outer artifact archive. Confirm the actual AnyKernel ZIP and inspect it before use:

```bash
unzip -l path/to/AnyKernel3_*.zip | head -80
```

Expected core content includes an `Image` and AnyKernel scripts. Do not execute the installer as part of verification.

## 7. Report the result

Report all of the following:

- repository and commit SHA;
- workflow filename;
- complete input values;
- run ID and URL;
- build/release job conclusions;
- artifact exact filename and byte size;
- locally calculated SHA-256 after download;
- whether compatibility is merely inferred, built successfully, or device-boot tested.

Never describe a successful compile as a successful device boot. The recipe in this skill is device-tested only for the exact historical configuration stated above.

## Recovery notes for the tested device

The inspected device has independent A/B partitions including:

```text
boot_a / boot_b
init_boot_a / init_boot_b
vendor_boot_a / vendor_boot_b
recovery_a / recovery_b
```

An installed recovery may remain accessible after only the active boot partition is modified, but verify recovery independently before flashing. Keep an exact backup of the active slot's original boot image off-device. A recovery that cannot decrypt `/data` still needs a viable transfer path such as USB OTG, ADB sideload, or host fastboot.
