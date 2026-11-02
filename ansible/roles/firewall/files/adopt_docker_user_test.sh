#!/bin/bash
# Проверка adopt_docker_user.sh на макетах after.rules. Не для хоста.
set -euo pipefail
adopt=$1
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/etc/ufw"
export FIREWALL_AFTER_RULES="$workdir/etc/ufw/after.rules"

export FIREWALL_DOCKER_USER_BEGIN='# BEGIN oscript DOCKER-USER'
export FIREWALL_DOCKER_USER_END='# END oscript DOCKER-USER'

edge_rules='-A DOCKER-USER -j RETURN -m conntrack --ctstate RELATED,ESTABLISHED
-A DOCKER-USER -i eth0 -p tcp -m multiport --dports 80,443,50000 -j RETURN
-A DOCKER-USER -i eth0 -j DROP
-A INPUT -i docker0 -p tcp --dport 8888 -j ACCEPT
-A INPUT -i br+ -p tcp --dport 8888 -j ACCEPT'

worker_rules='-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i wg0 -j RETURN
-A DOCKER-USER -i eth0 -j DROP'

run_adopt() {
  local profile=$1
  local rules=$2
  local rules_file
  rules_file=$(mktemp)
  printf '%s\n' "$rules" > "$rules_file"
  FIREWALL_PROFILE=$profile bash "$adopt" "$rules_file"
  rm -f "$rules_file"
}

decls() { grep -c '^:DOCKER-USER[ \t]' "$FIREWALL_AFTER_RULES"; }

expect_unchanged() {
  local out=$1
  printf '%s' "$out" | grep -qx 'unchanged' || { echo "expected unchanged, got: $out"; exit 1; }
}
expect_changed() {
  local out=$1
  printf '%s' "$out" | grep -qx 'changed' || { echo "expected changed, got: $out"; exit 1; }
}

# A: цепочка объявлена сверху, правила без маркеров.
cat > "$FIREWALL_AFTER_RULES" <<'EOF'
*filter
:ufw-after-input - [0:0]
:DOCKER-USER - [0:0]
-A ufw-before-input -i lo -j ACCEPT
-A DOCKER-USER -j RETURN -m conntrack --ctstate RELATED,ESTABLISHED
-A DOCKER-USER -i eth0 -p tcp -m multiport --dports 80,443,50000 -j RETURN
-A DOCKER-USER -i eth0 -j DROP
-A INPUT -i docker0 -p tcp --dport 8888 -j ACCEPT
-A INPUT -i br+ -p tcp --dport 8888 -j ACCEPT
COMMIT
EOF
out=$(run_adopt edge "$edge_rules")
expect_changed "$out"
test "$(decls)" -eq 1
grep -q '^:DOCKER-USER - \[0:0\]$' "$FIREWALL_AFTER_RULES"
# объявление осталось до правил ufw, не уехало в блок
awk '
  $0 == "# BEGIN oscript DOCKER-USER" { exit }
  $0 ~ /^:DOCKER-USER[ \t]/ { found=1 }
  END { exit !found }
' "$FIREWALL_AFTER_RULES"
# старые -A вне блока исчезли
awk '
  $0 == "# BEGIN oscript DOCKER-USER" { inside=1; next }
  $0 == "# END oscript DOCKER-USER" { inside=0; next }
  !inside && $0 ~ /^-A DOCKER-USER[ \t]/ { bad=1 }
  !inside && $0 ~ /--dport 8888 / { bad=1 }
  END { exit bad }
' "$FIREWALL_AFTER_RULES"
out=$(run_adopt edge "$edge_rules")
expect_unchanged "$out"

# B: объявление уже внутри блока роли.
cat > "$FIREWALL_AFTER_RULES" <<'EOF'
*filter
:ufw-after-input - [0:0]
# BEGIN oscript DOCKER-USER
:DOCKER-USER - [0:0]
-A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
-A DOCKER-USER -i wg0 -j RETURN
-A DOCKER-USER -i eth0 -j DROP
# END oscript DOCKER-USER
COMMIT
EOF
cp "$FIREWALL_AFTER_RULES" "$workdir/b-before"
out=$(run_adopt worker "$worker_rules")
expect_unchanged "$out"
cmp -s "$workdir/b-before" "$FIREWALL_AFTER_RULES"
test "$(decls)" -eq 1

# Пустой файл: объявление появляется один раз, внутри блока.
cat > "$FIREWALL_AFTER_RULES" <<'EOF'
*filter
:ufw-after-input - [0:0]
-A ufw-after-input -j ACCEPT
COMMIT
EOF
out=$(run_adopt worker "$worker_rules")
expect_changed "$out"
test "$(decls)" -eq 1
awk '
  $0 == "# BEGIN oscript DOCKER-USER" { inside=1; next }
  $0 == "# END oscript DOCKER-USER" { inside=0; next }
  inside && $0 ~ /^:DOCKER-USER[ \t]/ { found=1 }
  END { exit !found }
' "$FIREWALL_AFTER_RULES"
out=$(run_adopt worker "$worker_rules")
expect_unchanged "$out"

# Сломанный файл: два объявления. Остаётся первое, вне блока.
cat > "$FIREWALL_AFTER_RULES" <<'EOF'
*filter
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 -j DROP
# BEGIN oscript DOCKER-USER
:DOCKER-USER - [0:0]
-A DOCKER-USER -i eth0 -j DROP
# END oscript DOCKER-USER
COMMIT
EOF
out=$(run_adopt edge "$edge_rules")
expect_changed "$out"
test "$(decls)" -eq 1
out=$(run_adopt edge "$edge_rules")
expect_unchanged "$out"

# Worker не забирает чужие строки 8888.
cat > "$FIREWALL_AFTER_RULES" <<'EOF'
*filter
:ufw-after-input - [0:0]
:DOCKER-USER - [0:0]
-A INPUT -i docker0 -p tcp --dport 8888 -j ACCEPT
COMMIT
EOF
out=$(run_adopt worker "$worker_rules")
expect_changed "$out"
grep -q '^-A INPUT -i docker0 -p tcp --dport 8888 -j ACCEPT$' "$FIREWALL_AFTER_RULES"
test "$(decls)" -eq 1

if command -v iptables-restore >/dev/null 2>&1; then
  iptables-restore --test < "$FIREWALL_AFTER_RULES"
fi

echo OK
