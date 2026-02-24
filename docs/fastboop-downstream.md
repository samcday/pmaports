# fastboop downstream layout

This repository is a downstream of postmarketOS `pmaports` with fastboop-specific overlays.

## Branch model

- `upstream-master`: exact mirror of `https://gitlab.postmarketos.org/postmarketOS/pmaports.git` `master`
- `master`: downstream overlay branch, rebased on top of `upstream-master`
- `archive/2021-master`: preserved historic branch from the old `samcday/pmaports` state

`sync-upstream-and-rebase.yml` keeps `upstream-master` fresh and rebases `master` onto it.

## GitHub Actions workflows

- `.github/workflows/sync-upstream-and-rebase.yml`
  - scheduled sync from upstream GitLab
  - force-updates `upstream-master`
  - rebases `master` on top of `upstream-master`

- `.github/workflows/build-fastboop-overrides.yml`
  - path-triggered build for package changes in:
    - `device/community/linux-postmarketos-qcom-sdm845/**`
    - `device/community/device-oneplus-fajita/**`
  - builds aarch64 APKs with `pmbootstrap`
  - uploads build artifacts
  - optionally publishes to binary repo
  - uses workflow-level concurrency to cancel superseded in-progress runs

- `.github/workflows/build-fajita-rootfs-erofs.yml`
  - manual (`workflow_dispatch`) image build for fajita using `pmbootstrap install --split`
  - exports PMOS boot + root sparse images
  - compresses with `xz --block-size=1MiB` and uploads `.img.xz` artifacts plus checksums

## Binary APK repo

Binary repo: `samcday/pmaports-fastboop-apk`

Repository variables configured in `samcday/pmaports`:

- `APK_REPO=samcday/pmaports-fastboop-apk`
- `APK_REPO_BRANCH=main`
- `APK_REPO_BASE_URL=https://raw.githubusercontent.com/samcday/pmaports-fastboop-apk/main`

### Required secrets for publishing

- `APK_REPO_PUSH_TOKEN`: PAT with write access to `samcday/pmaports-fastboop-apk`
- `APK_REPO_SIGNING_KEY` (optional): private key for `abuild-sign`

If `APK_REPO_PUSH_TOKEN` is unset, publish is skipped and only workflow artifacts are produced.
