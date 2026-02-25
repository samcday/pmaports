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
  - publishes APK repo content to hosted object storage
  - uploads build artifacts
  - smoke-checks the hosted binary repo endpoint
  - uses workflow-level concurrency to cancel superseded in-progress runs

- `.github/workflows/build-fajita-rootfs-erofs.yml`
  - manual (`workflow_dispatch`) image build for fajita using `pmbootstrap install --split`
  - exports PMOS boot + root sparse images
  - compresses with `xz --block-size=1MiB` and uploads `.img.xz` artifacts plus checksums

## Binary APK repo

Hosted repo base URL: `https://pmos.samcday.com`

Repository variables configured in `samcday/pmaports`:

- `APK_REPO_BASE_URL=https://pmos.samcday.com`
- `APK_REPO_KEY_URL=https://pmos.samcday.com/pmos.samcday.com.rsa.pub`
- `APK_REPO_BUCKET=samcday-pmos`
- `APK_REPO_S3_ENDPOINT=https://s3.eu-central-003.backblazeb2.com`
- `APK_REPO_S3_REGION=eu-central-003`

Required secrets in `samcday/pmaports`:

- `APK_REPO_SIGNING_KEY` (stable private key used by `pmbootstrap` package signing and `APKINDEX` signing)
- `APK_REPO_ACCESS_KEY_ID` (Backblaze application key ID)
- `APK_REPO_SECRET_ACCESS_KEY` (Backblaze application key secret)

On push to `master`, the workflow builds packages, signs `APKINDEX.tar.gz`, publishes to the hosted endpoint, then runs smoke checks against the published repo.
