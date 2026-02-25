#!/usr/bin/env bash
set -euo pipefail

APK_REPO_BASE_URL="${APK_REPO_BASE_URL:-}"
APK_REPO_KEY_URL="${APK_REPO_KEY_URL:-}"
APK_REPO_DOCKER_PLATFORM="${APK_REPO_DOCKER_PLATFORM:-}"

if [ -z "${APK_REPO_BASE_URL}" ]; then
  echo "APK_REPO_BASE_URL is not set"
  exit 1
fi

repo_base="${APK_REPO_BASE_URL%/}"
workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT

index_url=""
index_root=""
for candidate in "${repo_base}/aarch64/APKINDEX.tar.gz" "${repo_base}/master/aarch64/APKINDEX.tar.gz"; do
  if curl -fsSL "${candidate}" -o "${workdir}/APKINDEX.tar.gz"; then
    index_url="${candidate}"
    index_root="${candidate%/APKINDEX.tar.gz}"
    break
  fi
done

if [ -z "${index_url}" ]; then
  echo "Failed to download APKINDEX.tar.gz from ${repo_base}"
  exit 1
fi

key_candidates=()
if [ -n "${APK_REPO_KEY_URL}" ]; then
  key_candidates+=("${APK_REPO_KEY_URL}")
else
  key_candidates+=(
    "${repo_base}/pmos.samcday.com.rsa.pub"
    "${repo_base}/master/pmos.samcday.com.rsa.pub"
  )
fi

key_url=""
key_file=""
for candidate in "${key_candidates[@]}"; do
  candidate_name="$(basename "${candidate}")"
  if [ -z "${candidate_name}" ] || [ "${candidate_name}" = "/" ]; then
    candidate_name="pmos.samcday.com.rsa.pub"
  fi

  if curl -fsSL "${candidate}" -o "${workdir}/${candidate_name}"; then
    key_url="${candidate}"
    key_file="${candidate_name}"
    break
  fi
done

if [ -z "${key_url}" ] || [ -z "${key_file}" ]; then
  echo "Failed to download repository key"
  exit 1
fi

if ! grep -q "BEGIN PUBLIC KEY" "${workdir}/${key_file}"; then
  echo "Downloaded key from ${key_url} does not look like a public key"
  exit 1
fi

first_apk="$(python3 - "${workdir}/APKINDEX.tar.gz" <<'PY'
import sys
import tarfile

index_tar = sys.argv[1]

with tarfile.open(index_tar, "r:gz") as tar:
    source = tar.extractfile("APKINDEX")
    if source is None:
        raise SystemExit(1)

    pkg = None
    ver = None

    for line in source.read().decode("utf-8", errors="ignore").splitlines():
        if line.startswith("P:"):
            pkg = line[2:].strip()
            continue

        if line.startswith("V:"):
            ver = line[2:].strip()
            continue

        if line == "":
            if pkg and ver:
                print(f"{pkg}-{ver}.apk")
                raise SystemExit(0)
            pkg = None
            ver = None

    if pkg and ver:
        print(f"{pkg}-{ver}.apk")
        raise SystemExit(0)

raise SystemExit(1)
PY
)"

if [ -z "${first_apk}" ]; then
  echo "Could not determine an APK filename from ${index_url}"
  exit 1
fi

curl -fsSL "${index_root}/${first_apk}" -o "${workdir}/${first_apk}"

docker_args=(
  run --rm
  -v "${workdir}:/work:ro"
  -e "FIRST_APK=${first_apk}"
  -e "REPO_KEY_FILE=${key_file}"
)

if [ -n "${APK_REPO_DOCKER_PLATFORM}" ]; then
  docker_args+=(--platform "${APK_REPO_DOCKER_PLATFORM}")
fi

docker_args+=(
  alpine:3.20
  /bin/sh -euxc '
    apk add --no-cache apk-tools-static
    mkdir -p /keys
    cp "/work/${REPO_KEY_FILE}" "/keys/${REPO_KEY_FILE}"
    apk.static --keys-dir /keys verify /work/APKINDEX.tar.gz
    apk.static --keys-dir /keys verify "/work/${FIRST_APK}"
  '
)

docker "${docker_args[@]}"
echo "Smoke check passed for ${index_url} using key ${key_url}"
