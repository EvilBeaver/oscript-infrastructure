#!/usr/bin/env bash
# Проверка каркаса Ansible без доступа к боевым хостам.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

IMAGE="${ANSIBLE_TEST_IMAGE:-python:3.12-bookworm}"
echo "==> Docker: ${IMAGE}"

docker run --rm \
  -v "${ROOT}:/work:ro" \
  -w /work \
  "${IMAGE}" \
  bash -euxo pipefail -c '
    apt-get update -qq
    apt-get install -y -qq git
    pip install --quiet "ansible-core==2.18.11" "ansible-lint==25.9.0"
    ansible-galaxy collection install -r ansible/requirements.yml

    ansible-galaxy collection list | grep -E "community\.(docker|general)\s+[0-9]"
    ansible-galaxy collection list community.docker | grep "4.8.2"
    ansible-galaxy collection list community.general | grep "10.7.6"

    export ANSIBLE_CONFIG=/work/ansible.cfg
    ansible-playbook --syntax-check -i ansible/inventory.example.ini ansible/site.yml

    ansible-lint ansible/site.yml ansible/roles

    ansible-playbook --list-tasks -i ansible/inventory.example.ini ansible/site.yml --tags firewall,never | grep -q "Цепочка DOCKER-USER"
    ansible-playbook --list-tasks -i ansible/inventory.example.ini ansible/site.yml --tags wg,never | grep -q "Конфиг wg0"
    ansible-playbook --list-tasks -i ansible/inventory.example.ini ansible/site.yml --tags firewall_confirm,never | grep -q "подтверждённый"

    git check-ignore -v ansible/inventory.ini ansible/vault.yml vault_pass.txt

    if command -v gitleaks >/dev/null 2>&1; then
      gitleaks detect --source /work --no-git -v
    else
      echo "gitleaks не установлен в образе, пропуск"
    fi
  '

echo "==> OK"
