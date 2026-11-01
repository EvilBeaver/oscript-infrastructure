#!/bin/bash
# Собрать в /etc/ufw/after.rules ровно одно объявление :DOCKER-USER и один блок правил.
# Первый аргумент — файл с правилами (-A …). Повторный запуск с тем же файлом after.rules не меняет.
# Если цепочка уже объявлена вне блока (ручная правка на A), второе :DOCKER-USER не добавляется:
# iptables-restore на дубле падает с "Chain already exists", и ufw reload оставляет хост без файрвола.
set -euo pipefail

rules_file=${1:?нужен путь к файлу правил}
profile=${FIREWALL_PROFILE:?}
begin=${FIREWALL_DOCKER_USER_BEGIN:?}
end=${FIREWALL_DOCKER_USER_END:?}
# FIREWALL_AFTER_RULES — только для прогона макета; на хосте переменная не задаётся.
file=${FIREWALL_AFTER_RULES:-/etc/ufw/after.rules}

test -f "$rules_file"

out=$(mktemp)
trap 'rm -f "$out"' EXIT

if ! awk -v profile="$profile" -v begin="$begin" -v end="$end" '
NR == FNR {
  if (length($0)) rules[++nrules] = $0
  next
}
$0 == begin { inside = 1; next }
$0 == end { inside = 0; next }
inside { next }
{ lines[++nlines] = $0 }
END {
  chain_seen = 0
  k = 0
  commit_at = 0
  commits = 0
  for (i = 1; i <= nlines; i++) {
    s = lines[i]
    if (s ~ /^:DOCKER-USER[ \t]/) {
      if (chain_seen) continue
      chain_seen = 1
    } else if (s ~ /^-A DOCKER-USER[ \t]/) {
      continue
    } else if (profile == "edge" && s ~ /^-A INPUT -i (docker0|br\+) / && s ~ /--dport 8888 / && s ~ /-j ACCEPT[ \t]*$/) {
      continue
    }
    kept[++k] = s
    if (s == "COMMIT") {
      commits++
      if (commit_at == 0) commit_at = k
    }
  }
  if (commits != 1) exit 2
  for (i = 1; i < commit_at; i++) print kept[i]
  print begin
  if (!chain_seen) print ":DOCKER-USER - [0:0]"
  for (i = 1; i <= nrules; i++) print rules[i]
  print end
  for (i = commit_at; i <= k; i++) print kept[i]
}
' "$rules_file" "$file" > "$out"; then
  echo "after.rules: нужен ровно один COMMIT" >&2
  exit 1
fi

if ! cmp -s "$file" "$out"; then
  cat "$out" > "$file"
  echo changed
else
  echo unchanged
fi
