#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-oneplus-fajita}"
UI="${2:-phosh}"
RUNNER_TMP="${RUNNER_TEMP:-/tmp}"
PMB_DIR="${RUNNER_TMP}/pmbootstrap"
APK_REPO_SIGNING_KEY="${APK_REPO_SIGNING_KEY:-}"
APK_REPO_SIGNING_KEY_NAME="${APK_REPO_SIGNING_KEY_NAME:-pmos.samcday.com.rsa}"
APK_REPO_SIGNING_PUB_NAME="${APK_REPO_SIGNING_PUB_NAME:-pmos.samcday.com.rsa.pub}"

if [[ "${DEVICE}" != *-* ]]; then
  echo "Device must use vendor-codename format (got: ${DEVICE})"
  exit 1
fi

DEVICE_VENDOR="${DEVICE%%-*}"
DEVICE_CODENAME="${DEVICE#*-}"

sudo apt-get update
sudo apt-get install -y git python3 rsync wget ca-certificates xz-utils openssl

if [ ! -d "${PMB_DIR}" ]; then
  git clone --depth=1 https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "${PMB_DIR}"
fi

# pmbootstrap expects the pmaports checkout to have a remote that points to
# the canonical postmarketOS GitLab URL.
if ! git -C "${GITHUB_WORKSPACE}" remote -v | grep -q 'https://gitlab.postmarketos.org/postmarketOS/pmaports.git'; then
  if git -C "${GITHUB_WORKSPACE}" remote get-url upstream >/dev/null 2>&1; then
    git -C "${GITHUB_WORKSPACE}" remote set-url upstream https://gitlab.postmarketos.org/postmarketOS/pmaports.git
  else
    git -C "${GITHUB_WORKSPACE}" remote add upstream https://gitlab.postmarketos.org/postmarketOS/pmaports.git
  fi
fi

git -C "${GITHUB_WORKSPACE}" fetch --depth=1 upstream \
  +refs/heads/master:refs/remotes/upstream/master

PMB="${PMB_DIR}/pmbootstrap.py"
chmod +x "${PMB}"

mkdir -p "${HOME}/.config"
cat > "${HOME}/.config/pmbootstrap_v3.cfg" <<EOF
[pmbootstrap]
aports = ${GITHUB_WORKSPACE}
device = ${DEVICE}
extra_packages =
is_default_channel = False
systemd = never
ui = ${UI}
user = user
work = ${HOME}/.local/var/pmbootstrap
jobs = $(nproc)

[providers]

[mirrors]
EOF

echo "PMBOOTSTRAP=${PMB}" >> "${GITHUB_ENV}"
echo "PMB_WORK=${HOME}/.local/var/pmbootstrap" >> "${GITHUB_ENV}"

python3 "${PMB}" --version

python3 "${PMB}" init <<EOF
${HOME}/.local/var/pmbootstrap
${GITHUB_WORKSPACE}
edge
${DEVICE_VENDOR}
${DEVICE_CODENAME}
user
default
default
default
${UI}
never
n
none
y
en_US











EOF

if [ -n "${APK_REPO_SIGNING_KEY}" ]; then
  key_name="$(basename "${APK_REPO_SIGNING_KEY_NAME}")"
  pub_name="$(basename "${APK_REPO_SIGNING_PUB_NAME}")"

  if [[ "${key_name}" != *.rsa ]]; then
    key_name="${key_name}.rsa"
  fi

  if [[ "${pub_name}" != *.pub ]]; then
    pub_name="${pub_name}.pub"
  fi

  work_dir="$(python3 "${PMB}" config work)"
  key_tmp="$(mktemp)"
  pub_tmp="$(mktemp)"

  printf "%s\n" "${APK_REPO_SIGNING_KEY}" > "${key_tmp}"

  if ! grep -q "PRIVATE KEY" "${key_tmp}"; then
    echo "APK_REPO_SIGNING_KEY is not a private key"
    rm -f "${key_tmp}" "${pub_tmp}"
    exit 1
  fi

  mkdir -p "${work_dir}/config_abuild" "${work_dir}/config_apk_keys"
  install -m 0644 "${key_tmp}" "${work_dir}/config_abuild/${key_name}"

  openssl rsa -in "${key_tmp}" -pubout > "${pub_tmp}"
  install -m 0644 "${pub_tmp}" "${work_dir}/config_abuild/${key_name}.pub"
  install -m 0644 "${pub_tmp}" "${work_dir}/config_apk_keys/${pub_name}"

  printf 'PACKAGER_PRIVKEY="/home/pmos/.abuild/%s"\n' "${key_name}" > "${work_dir}/config_abuild/abuild.conf"

  rm -f "${key_tmp}" "${pub_tmp}"
fi
