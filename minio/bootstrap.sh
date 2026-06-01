#!/bin/sh
set -e

MARKER="/data/.minio-bootstrap-done"
POLICY_NAME="jenkins-artifacts"
BUCKET="jenkins-artifacts"
POLICY_FILE="/etc/minio/policies/jenkins-artifacts.json"

if [ -f "$MARKER" ]; then
  echo "Bootstrap marker present, skipping."
  exit 0
fi

: "${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
: "${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
: "${JENKINS_S3_ACCESS_KEY:?JENKINS_S3_ACCESS_KEY is required}"
: "${JENKINS_S3_SECRET_KEY:?JENKINS_S3_SECRET_KEY is required}"

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

echo "Creating bucket ${BUCKET}..."
mc mb --ignore-existing "local/${BUCKET}"

if ! mc admin policy info local "$POLICY_NAME" >/dev/null 2>&1; then
  echo "Creating policy ${POLICY_NAME}..."
  mc admin policy create local "$POLICY_NAME" "$POLICY_FILE"
fi

if ! mc admin user info local "$JENKINS_S3_ACCESS_KEY" >/dev/null 2>&1; then
  echo "Creating Jenkins S3 user..."
  mc admin user add local "$JENKINS_S3_ACCESS_KEY" "$JENKINS_S3_SECRET_KEY"
fi

mc admin policy attach local "$POLICY_NAME" --user "$JENKINS_S3_ACCESS_KEY"

ilm_rules="$(mc ilm rule ls "local/${BUCKET}" 2>/dev/null || true)"
case "$ilm_rules" in
  *Expiration*) ;;
  *)
    echo "Applying ILM: expire objects after 10 days..."
    mc ilm rule add "local/${BUCKET}" --expire-days 10
    ;;
esac

touch "$MARKER"
echo "Bootstrap completed."
