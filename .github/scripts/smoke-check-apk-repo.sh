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

index_scan="$(python3 - "${workdir}/APKINDEX.tar.gz" <<'PY'
import sys
import tarfile

index_tar = sys.argv[1]

first_apk = ""
first_noarch_apk = ""

with tarfile.open(index_tar, "r:gz") as tar:
    source = tar.extractfile("APKINDEX")
    if source is None:
        raise SystemExit(1)

    pkg = None
    ver = None
    arch = None

    for line in source.read().decode("utf-8", errors="ignore").splitlines():
        if line.startswith("P:"):
            pkg = line[2:].strip()
            continue

        if line.startswith("V:"):
            ver = line[2:].strip()
            continue

        if line.startswith("A:"):
            arch = line[2:].strip()
            continue

        if line == "":
            if pkg and ver:
                candidate = f"{pkg}-{ver}.apk"
                if not first_apk:
                    first_apk = candidate
                if arch == "noarch" and not first_noarch_apk:
                    first_noarch_apk = candidate

                if first_apk and first_noarch_apk:
                    break
            pkg = None
            ver = None
            arch = None

    if pkg and ver:
        candidate = f"{pkg}-{ver}.apk"
        if not first_apk:
            first_apk = candidate
        if arch == "noarch" and not first_noarch_apk:
            first_noarch_apk = candidate

if not first_apk:
    raise SystemExit(1)

print(f"first_apk={first_apk}")
print(f"first_noarch_apk={first_noarch_apk}")
PY
)"

first_apk=""
first_noarch_apk=""
while IFS='=' read -r key value; do
  case "${key}" in
    first_apk)
      first_apk="${value}"
      ;;
    first_noarch_apk)
      first_noarch_apk="${value}"
      ;;
  esac
done <<< "${index_scan}"

if [ -z "${first_apk}" ]; then
  echo "Could not determine an APK filename from ${index_url}"
  exit 1
fi

curl -fsSL "${index_root}/${first_apk}" -o "${workdir}/${first_apk}"

if [ -n "${first_noarch_apk}" ]; then
  noarch_root="${index_root%/aarch64}/noarch"
  curl -fsSL "${noarch_root}/${first_noarch_apk}" -o "${workdir}/${first_noarch_apk}"
fi

docker_args=(
  run --rm
  -v "${workdir}:/work:ro"
  -e "FIRST_APK=${first_apk}"
  -e "NOARCH_APK=${first_noarch_apk}"
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
    if [ -n "${NOARCH_APK}" ]; then
      apk.static --keys-dir /keys verify "/work/${NOARCH_APK}"
    fi
  '
)

docker "${docker_args[@]}"
echo "Smoke check passed for ${index_url} using key ${key_url}"
