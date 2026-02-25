#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:?usage: publish-apk-repo.sh <apk-dir>}"
APK_REPO_BUCKET="${APK_REPO_BUCKET:-}"
APK_REPO_S3_ENDPOINT="${APK_REPO_S3_ENDPOINT:-}"
APK_REPO_S3_REGION="${APK_REPO_S3_REGION:-eu-central-003}"
APK_REPO_S3_PREFIX="${APK_REPO_S3_PREFIX:-}"
APK_REPO_ACCESS_KEY_ID="${APK_REPO_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
APK_REPO_SECRET_ACCESS_KEY="${APK_REPO_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"

if [ ! -d "${SRC_DIR}" ]; then
  echo "APK source directory does not exist: ${SRC_DIR}"
  exit 1
fi

if [ -z "${APK_REPO_BUCKET}" ]; then
  echo "APK_REPO_BUCKET is not set"
  exit 1
fi

if [ -z "${APK_REPO_S3_ENDPOINT}" ]; then
  echo "APK_REPO_S3_ENDPOINT is not set"
  exit 1
fi

if [ -z "${APK_REPO_ACCESS_KEY_ID}" ] || [ -z "${APK_REPO_SECRET_ACCESS_KEY}" ]; then
  echo "APK repo S3 credentials are not set"
  exit 1
fi

shopt -s nullglob
apk_files=("${SRC_DIR}"/*.apk)
pub_keys=("${SRC_DIR}"/*.pub)

if [ "${#apk_files[@]}" -eq 0 ]; then
  echo "No APK files found in ${SRC_DIR}"
  exit 1
fi

if [ ! -f "${SRC_DIR}/APKINDEX.tar.gz" ]; then
  echo "Missing APKINDEX.tar.gz in ${SRC_DIR}"
  exit 1
fi

if [ ! -f "${SRC_DIR}/pmos.samcday.com.rsa.pub" ]; then
  echo "Missing canonical public key in ${SRC_DIR}"
  exit 1
fi

if [ "${#pub_keys[@]}" -eq 0 ]; then
  echo "No .pub keys found in ${SRC_DIR}"
  exit 1
fi

prefix="${APK_REPO_S3_PREFIX#/}"
prefix="${prefix%/}"
if [ -n "${prefix}" ]; then
  prefix="${prefix}/"
fi

stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT

mkdir -p "${stage_dir}/aarch64" "${stage_dir}/master/aarch64" "${stage_dir}/master"
cp -f "${apk_files[@]}" "${stage_dir}/aarch64/"
cp -f "${apk_files[@]}" "${stage_dir}/master/aarch64/"
cp -f "${SRC_DIR}/APKINDEX.tar.gz" "${stage_dir}/aarch64/"
cp -f "${SRC_DIR}/APKINDEX.tar.gz" "${stage_dir}/master/aarch64/"

if [ -f "${SRC_DIR}/APKINDEX.tar.gz.sig" ]; then
  cp -f "${SRC_DIR}/APKINDEX.tar.gz.sig" "${stage_dir}/aarch64/"
  cp -f "${SRC_DIR}/APKINDEX.tar.gz.sig" "${stage_dir}/master/aarch64/"
fi

cp -f "${pub_keys[@]}" "${stage_dir}/"
cp -f "${pub_keys[@]}" "${stage_dir}/master/"

export AWS_ACCESS_KEY_ID="${APK_REPO_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${APK_REPO_SECRET_ACCESS_KEY}"
export AWS_DEFAULT_REGION="${APK_REPO_S3_REGION}"

aws --endpoint-url "${APK_REPO_S3_ENDPOINT}" s3api head-bucket --bucket "${APK_REPO_BUCKET}" >/dev/null

aws --endpoint-url "${APK_REPO_S3_ENDPOINT}" s3 sync "${stage_dir}/aarch64/" "s3://${APK_REPO_BUCKET}/${prefix}aarch64/" --delete
aws --endpoint-url "${APK_REPO_S3_ENDPOINT}" s3 sync "${stage_dir}/master/aarch64/" "s3://${APK_REPO_BUCKET}/${prefix}master/aarch64/" --delete

for key_file in "${stage_dir}"/*.pub; do
  key_name="$(basename "${key_file}")"
  aws --endpoint-url "${APK_REPO_S3_ENDPOINT}" s3 cp "${key_file}" "s3://${APK_REPO_BUCKET}/${prefix}${key_name}"
  aws --endpoint-url "${APK_REPO_S3_ENDPOINT}" s3 cp "${key_file}" "s3://${APK_REPO_BUCKET}/${prefix}master/${key_name}"
done

echo "Published APK repo payload to s3://${APK_REPO_BUCKET}/${prefix}"
