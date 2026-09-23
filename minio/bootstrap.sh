#!/bin/sh
set -e

POLICIES_DIR="/etc/minio/policies"

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${JENKINS_S3_ACCESS_KEY:?JENKINS_S3_ACCESS_KEY is required}"
: "${JENKINS_S3_SECRET_KEY:?JENKINS_S3_SECRET_KEY is required}"
: "${OPENHUB_S3_ACCESS_KEY:?OPENHUB_S3_ACCESS_KEY is required}"
: "${OPENHUB_S3_SECRET_KEY:?OPENHUB_S3_SECRET_KEY is required}"

export MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@127.0.0.1:9000"

echo "Waiting for MinIO..."
i=0
while ! mc ready local 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -gt 120 ]; then
    echo "MinIO did not become ready in time" >&2
    exit 1
  fi
  sleep 1
done

# has_policy <access key> <policy name>
# Точное совпадение имени в строке "PolicyName: a,b,c"
has_policy() {
  mc admin user info local "$1" \
    | grep '^PolicyName:' | cut -d: -f2- | tr ',' '\n' | tr -d ' ' \
    | grep -qx -- "$2"
}

# setup_bucket_user <bucket/policy name> <access key> <secret key>
# Политика берётся из $POLICIES_DIR/<name>.json
setup_bucket_user() {
  name="$1"
  access="$2"
  secret="$3"

  echo "[$name] bucket..."
  mc mb --ignore-existing "local/${name}"

  echo "[$name] policy..."
  mc admin policy create local "$name" "${POLICIES_DIR}/${name}.json"

  echo "[$name] user ${access}..."
  mc admin user add local "$access" "$secret"

  if ! has_policy "$access" "$name"; then
    mc admin policy attach local "$name" --user "$access"
  fi
}

setup_bucket_user jenkins-artifacts "$JENKINS_S3_ACCESS_KEY" "$JENKINS_S3_SECRET_KEY"
setup_bucket_user openhub "$OPENHUB_S3_ACCESS_KEY" "$OPENHUB_S3_SECRET_KEY"

# ILM только для jenkins-artifacts
ilm_rules="$(mc ilm rule ls local/jenkins-artifacts 2>/dev/null || true)"
case "$ilm_rules" in
  *Expiration*) ;;
  *)
    echo "Applying ILM to jenkins-artifacts: expire objects after 10 days..."
    mc ilm rule add local/jenkins-artifacts --expire-days 10
    ;;
esac

echo "Bootstrap completed."

