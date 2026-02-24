#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:?usage: publish-apk-repo.sh <apk-dir>}"
APK_REPO="${APK_REPO:-}"
APK_REPO_BRANCH="${APK_REPO_BRANCH:-main}"
APK_REPO_PUSH_TOKEN="${APK_REPO_PUSH_TOKEN:-}"
APK_REPO_SIGNING_KEY="${APK_REPO_SIGNING_KEY:-}"
APK_REPO_DOCKER_PLATFORM="${APK_REPO_DOCKER_PLATFORM:-}"
SOURCE_REF="${GITHUB_REPOSITORY:-local/pmaports}@${GITHUB_SHA:-unknown}"

if [ ! -d "${SRC_DIR}" ]; then
  echo "APK source directory does not exist: ${SRC_DIR}"
  exit 1
fi

SRC_DIR="$(realpath "${SRC_DIR}")"

if [ -z "${APK_REPO}" ]; then
  echo "APK_REPO is not set"
  exit 1
fi

if [ -z "${APK_REPO_PUSH_TOKEN}" ]; then
  echo "APK_REPO_PUSH_TOKEN is not set"
  exit 1
fi

shopt -s nullglob
apk_files=("${SRC_DIR}"/*.apk)
src_pub_keys=("${SRC_DIR}"/*.pub)
if [ "${#apk_files[@]}" -eq 0 ]; then
  echo "No APK files found in ${SRC_DIR}"
  exit 1
fi

if [ "${#src_pub_keys[@]}" -eq 0 ]; then
  echo "No .pub key files found in ${SRC_DIR}"
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

git clone "https://x-access-token:${APK_REPO_PUSH_TOKEN}@github.com/${APK_REPO}.git" "${workdir}/repo"
cd "${workdir}/repo"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

git checkout -B "${APK_REPO_BRANCH}"

mkdir -p aarch64
dst_apk_files=(aarch64/*.apk)
dst_pub_keys=(./*.pub)

unchanged=true
if [ "${#dst_apk_files[@]}" -ne "${#apk_files[@]}" ]; then
  unchanged=false
else
  for src in "${apk_files[@]}"; do
    dst="aarch64/$(basename "${src}")"
    if [ ! -f "${dst}" ] || ! cmp -s "${src}" "${dst}"; then
      unchanged=false
      break
    fi
  done
fi

if [ "${#dst_pub_keys[@]}" -ne "${#src_pub_keys[@]}" ]; then
  unchanged=false
else
  for src in "${src_pub_keys[@]}"; do
    dst="./$(basename "${src}")"
    if [ ! -f "${dst}" ] || ! cmp -s "${src}" "${dst}"; then
      unchanged=false
      break
    fi
  done
fi

if [ "${unchanged}" = true ]; then
  echo "No APK payload changes to publish"
  exit 0
fi

rm -f aarch64/*.apk aarch64/APKINDEX.tar.gz aarch64/APKINDEX.tar.gz.sig ./*.pub
cp -f "${apk_files[@]}" aarch64/
cp -f "${src_pub_keys[@]}" ./

docker_args=(
  run --rm
  -v "${PWD}:/repo"
  -e APK_REPO_SIGNING_KEY="${APK_REPO_SIGNING_KEY}"
)
if [ -n "${APK_REPO_DOCKER_PLATFORM}" ]; then
  docker_args+=(--platform "${APK_REPO_DOCKER_PLATFORM}")
fi

docker_args+=(
  alpine:3.20
  /bin/sh -euxc '
    apk add --no-cache alpine-sdk openssl
    cd /repo/aarch64
    apk index --allow-untrusted -o APKINDEX.tar.gz *.apk
    if [ -n "${APK_REPO_SIGNING_KEY}" ]; then
      printf "%s\n" "${APK_REPO_SIGNING_KEY}" > /tmp/repo.rsa
      chmod 600 /tmp/repo.rsa
      abuild-sign -k /tmp/repo.rsa APKINDEX.tar.gz
      openssl rsa -in /tmp/repo.rsa -pubout > /repo/pmaports-fastboop.rsa.pub
    fi
  '
)

docker "${docker_args[@]}"

cat > index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>pmaports-fastboop-apk</title>
</head>
<body>
  <h1>pmaports-fastboop-apk</h1>
  <p>Aarch64 APK repo for fastboop-related downstream pmaports builds.</p>
  <ul>
    <li><a href="aarch64/">aarch64/</a></li>
  </ul>
</body>
</html>
EOF

git add aarch64 index.html
if compgen -G "*.pub" > /dev/null; then
  git add ./*.pub
fi

if git diff --cached --quiet; then
  echo "No package repository changes to publish"
  exit 0
fi

git commit -m "publish aarch64 packages from ${SOURCE_REF}"
git push origin "${APK_REPO_BRANCH}"
