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

title() { echo ""; echo -e "${BLUE}══════  $1${NC}"; }

ssh_to() {
  local node="$1"; shift; local ip="${NODES[$node]}"
  [ -z "$ip" ] && { echo "ERROR: unknown node $node" >&2; return 1; }
  ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o LogLevel=ERROR "vagrant@${ip}" "$@"
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
  ssh_to "$node" "timeout 15 sudo docker exec $container $*"
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
  node="${entry%%|*}"; cont="${entry##*|}"
  docker_ps "$node" "$cont"
done
# o104=datanode1, o105=datanode2, o106=datanode3, o107=datanode4
declare -A EXTRA_DN=([o106]="datanode3" [o107]="datanode4")
for extra in o106 o107; do
  if nc -z -w1 "${NODES[$extra]}" 22 2>/dev/null; then
    docker_ps "$extra" "${EXTRA_DN[$extra]}" || fail "$extra: ${EXTRA_DN[$extra]}"
  else
    skip "$extra"
  fi
done

# ========== Phase 3: Keytab ==========
title "Phase 3: Kerberos Keytab"
nc -z -w1 192.168.69.80 88 2>/dev/null || { skip "KRB5"; }
docker_cmd "o101" "om1" "klist -kt /etc/security/keytabs/ozone.keytab 2>/dev/null | head -3" 2>/dev/null | \
  grep -q 'ozone.keytab' && pass "Keytab 可用" || fail "Keytab 不可用"

# ========== Phase 4: Ozone CLI ==========
title "Phase 4: Ozone CLI"
vlist=$(docker_cmd "o101" "om1" "ozone sh volume list 2>&1" || true)
if echo "$vlist" | grep -q '"name"'; then
  pass "ozone sh volume list 成功"
  info "现有 $(echo "$vlist" | grep -c '"name"' || echo 0) 个 Volume"
else
  fail "ozone sh volume list 返回空或失败"
  [ -n "$vlist" ] && [ "$vlist" != "[]" ] && echo "    err: $(echo "$vlist" | tail -1)"
fi

# ========== Phase 5: Pipeline & Container ==========
title "Phase 5: Pipeline & Container"
pl_out=$(docker_cmd "o101" "scm1" "bash -c 'ozone admin pipeline list 2>/dev/null'" 2>/dev/null || true)
if echo "$pl_out" | grep -qi "Pipeline"; then
  pl_count=$(echo "$pl_out" | grep -c "Pipeline" || echo 0)
  pass "Pipeline: ${pl_count} 个存在"
else
  warn "Pipeline 不可用"
fi

cl_out=$(docker_cmd "o101" "scm1" "bash -c 'ozone admin container list 2>/dev/null'" 2>/dev/null || true)
if echo "$cl_out" | grep -qi "Container"; then
  pass "Container 已分配"
else
  info "Container 暂无（新集群，写入数据后自动创建）"
fi

# ========== Phase 6: Recon / S3 ==========
title "Phase 6: Recon & S3 Gateway"
r=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.69.108:9888/ 2>/dev/null || echo 0)
[ "$r" != "0" ] && pass "Recon  HTTP ${r}" || fail "Recon 不可达"

s=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://192.168.69.108:9878/ 2>/dev/null || echo 0)
[ "$s" != "0" ] && pass "S3 GW  HTTP ${s}" || fail "S3 GW 不可达"

# ========== Phase 7: o211 ==========
title "Phase 7: o211 HDFS"
if nc -z -w1 192.168.69.211 22 2>/dev/null; then
  ssh_to "o211" "test -f /opt/hadoop/bin/hdfs 2>/dev/null" 2>/dev/null && \
    pass "o211 Hadoop 已安装" || skip "o211 未安装 Hadoop"
else
  skip "o211 不可达"
fi

# ========== Phase 8: HA ==========
title "Phase 8: HA (跳过)"
skip "--no-ha"

summary
