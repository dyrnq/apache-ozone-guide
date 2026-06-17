#!/usr/bin/env bash
set -o pipefail

# ===================================================================
# Ozone 集群综合验证脚本
# 用法: bash validate.sh [--no-ha]
# ===================================================================

readonly RED='\033[0;31m'; readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'; readonly BLUE='\033[0;34m'; readonly NC='\033[0m'

PASS=0; FAIL=0; SKIP=0; HA_TESTS=true
SSH_KEY="${CUSTOM_SSH_KEY:-insecure_private_key}"

[ "$1" = "--no-ha" ] && HA_TESTS=false

declare -A NODES=(
  [o80]="192.168.69.80"   [o101]="192.168.69.101" [o102]="192.168.69.102"
  [o103]="192.168.69.103" [o104]="192.168.69.104" [o105]="192.168.69.105"
  [o106]="192.168.69.106" [o107]="192.168.69.107" [o108]="192.168.69.108"
  [o211]="192.168.69.211"
)

pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (跳过)"; SKIP=$((SKIP+1)); }
info() { echo -e "  ${BLUE}→${NC} $1"; }

title() {
  echo ""; echo -e "${BLUE}══════  $1${NC}"
}

ssh_to() {
  local node="$1"; shift; local ip="${NODES[$node]}"
  [ -z "$ip" ] && return 1
  ssh -i "$SSH_KEY" -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
    -o LogLevel=ERROR "vagrant@${ip}" "$@" 2>/dev/null
}

check_port() {
  nc -z -w2 "$1" "$2" 2>/dev/null && pass "$3" || fail "$3"
}

docker_ps() {
  ssh_to "$1" "sudo docker ps --format '{{.Names}}'" 2>/dev/null | grep -qx "$2" && \
    pass "$1: $2" || fail "$1: $2"
}

docker_cmd() {
  local node="$1" container="$2"; shift 2
  ssh_to "$node" "timeout 10 sudo docker exec $container $*"
}

summary() {
  local t=$((PASS+FAIL+SKIP))
  echo -e "\n${BLUE}══════  ${GREEN}${PASS}✓${NC} ${RED}${FAIL}✗${NC} ${YELLOW}${SKIP}⊘${NC} (${t})${NC}"
  [ "$FAIL" -gt 0 ] && return 1 || return 0
}

# ========== Phase 1: Ports ==========
title "Phase 1: 端口连通性"
check_port 192.168.69.80  80   "o80  Nginx"
check_port 192.168.69.80  88   "o80  KDC"
check_port 192.168.69.101 9862 "o101 OM"
check_port 192.168.69.101 9894 "o101 SCM"
check_port 192.168.69.102 9862 "o102 OM"
check_port 192.168.69.103 9862 "o103 OM"
check_port 192.168.69.108 9888 "o108 Recon"
check_port 192.168.69.108 9878 "o108 S3G"

# ========== Phase 2: Containers ==========
title "Phase 2: 容器状态"
for entry in \
  "o80|krb5-server" "o80|nginx" \
  "o101|om1" "o101|scm1" \
  "o102|om2" "o102|scm2" \
  "o103|om3" "o103|scm3" \
  "o104|datanode1" "o105|datanode2" \
  "o108|recon" "o108|s3gateway"; do
  node="${entry%%|*}"
  cont="${entry##*|}"
  docker_ps "$node" "$cont"
done
for extra in o106 o107; do
  nc -z -w1 "${NODES[$extra]}" 22 2>/dev/null && \
    docker_ps "$extra" "datanode${extra#o10}" || skip "$extra"
done

# ========== Phase 3: Keytab ==========
title "Phase 3: Kerberos Keytab"
if nc -z -w1 192.168.69.80 88 2>/dev/null; then
  docker_cmd "o101" "om1" "klist -kt /etc/security/keytabs/ozone.keytab 2>/dev/null | head -3" | \
    grep -q 'ozone.keytab' && pass "Keytab 可用" || fail "Keytab 不可用"
else
  skip "KRB5 未启用"
fi

# ========== Phase 4: Ozone CLI ==========
title "Phase 4: Ozone CLI"
vlist=$(docker_cmd "o101" "om1" "ozone sh volume list 2>/dev/null" || true)
if echo "$vlist" | grep -q '"name"'; then
  pass "ozone sh volume list 成功"
  vol_count=$(echo "$vlist" | grep -c '"name"' || echo 0)
  info "现有 ${vol_count} 个 Volume"
else
  fail "ozone sh volume list 失败"
fi

# ========== Phase 5: Recon / S3 ==========
title "Phase 5: Recon & S3 Gateway"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://192.168.69.108:9888/ 2>/dev/null || echo 0)
[ "$r" != "0" ] && pass "Recon  HTTP ${r}" || fail "Recon 不可达"

s=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://192.168.69.108:9878/ 2>/dev/null || echo 0)
[ "$s" != "0" ] && pass "S3 GW  HTTP ${s}" || fail "S3 GW 不可达"

# ========== Phase 6: o211 ==========
title "Phase 6: o211 HDFS"
if nc -z -w1 192.168.69.211 22 2>/dev/null; then
  if ssh_to "o211" "test -f /opt/hadoop/bin/hdfs 2>/dev/null"; then
    pass "o211 Hadoop 已安装"
  else
    skip "o211 未安装 Hadoop"
  fi
else
  skip "o211 不可达"
fi

# ========== Phase 7: HA (optional) ==========
if [ "$HA_TESTS" = true ]; then
  title "Phase 7: HA 故障恢复 (跳过)"
  skip "HA 测试暂不可用"
else
  title "Phase 7: HA (跳过)"
  skip "--no-ha"
fi

summary
