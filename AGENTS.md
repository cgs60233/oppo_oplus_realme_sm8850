# AI agent guidance

## Reusable kernel build skill

For SM8850/MT6993 kernel compatibility checks, DroidSpaces kernel builds, GitHub Actions dispatch, artifact verification, and recovery planning, load and follow:

```text
.agents/skills/sm8850-droidspaces-kernel/SKILL.md
```

The skill contains a known-good, device-tested Xiaomi 17 Pro Max (`popsicle`, `2509FPN0BC`) build recipe. Do not assume that recipe is compatible with another device or kernel version: run its detection and workflow-selection steps first.

Never request account passwords or print/store GitHub tokens. Prefer `gh auth login` device authorization. Building and downloading are allowed after authorization; flashing requires a separate explicit confirmation and a recovery backup.
