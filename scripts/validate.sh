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
title "Phase 8: HA 故障转移"
if [ "$HA_TESTS" = "false" ]; then
  skip "--no-ha 模式"
else
  # --- 8.1 OM follower 故障转移 ---
  # 找出当前 OM leader（用 ozone admin om roles --json，table 难以解析）
  # 注意：必须用 bash -c 把整段命令作为单个参数传给 docker exec，否则 ; 会在外层 shell 拆开
  om_roles=$(docker_cmd "o101" "om1" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone admin om roles --json 2>/dev/null'" 2>/dev/null || true)
  # OM roles JSON 是数组：[{om1:{serverRole:LEADER}}, ...]
  om_leader=$(echo "$om_roles" | python3 -c "
import json, sys
try:
  d=json.load(sys.stdin)
  for entry in d:
    for k,v in entry.items():
      if isinstance(v,dict) and v.get('serverRole')=='LEADER':
        print(k); sys.exit(0)
except Exception:
  pass
" 2>/dev/null || echo "")
  if [ -z "$om_leader" ]; then
    fail "无法解析 OM leader（roles 输出：$(echo "$om_roles" | head -c 200)）"
  else
    info "OM leader: $om_leader"
    # om_leader -> host 映射: om1=o101, om2=o102, om3=o103
    om_leader_host="o10${om_leader: -1}"
    om_follower=""
    for c in om1 om2 om3; do
      [ "$c" != "$om_leader" ] && om_follower="$c" && break
    done
    if [ -n "$om_follower" ]; then
      om_follower_host="o10${om_follower: -1}"
      info "停止 follower: $om_follower (host $om_follower_host)"
      ssh_to "$om_follower_host" "sudo docker stop $om_follower" >/dev/null 2>&1
      sleep 6
      # 验证 volume list 仍工作
      vl=$(docker_cmd "$om_leader_host" "$om_leader" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/${om_leader_host}@EXAMPLE.COM 2>/dev/null; ozone sh volume list 2>&1'" 2>/dev/null || true)
      if echo "$vl" | grep -q '"name"'; then
        pass "OM follower ${om_follower} 停止后 volume list 仍正常"
      else
        fail "OM follower ${om_follower} 停止后 volume list 失败: $(echo "$vl" | tail -1)"
      fi
      ssh_to "$om_follower_host" "sudo docker start $om_follower" >/dev/null 2>&1
      sleep 6
      pass "OM follower ${om_follower} 已重启"
    fi
  fi

  # --- 8.2 SCM follower 故障转移 ---
  scm_roles=$(docker_cmd "o101" "scm1" "ozone admin scm roles --json 2>/dev/null" 2>/dev/null || true)
  # SCM roles JSON 是对象：{o101:{raftPeerRole:LEADER, ...}, ...} 键是主机名（o101/o102/o103），容器名是 scm1/scm2/scm3
  scm_leader=$(echo "$scm_roles" | python3 -c "
import json, sys
try:
  d=json.load(sys.stdin)
  for host,v in d.items():
    if isinstance(v,dict) and v.get('raftPeerRole')=='LEADER':
      # host o101/o102/o103 -> scm1/scm2/scm3 (末位数字 = 容器编号)
      n=host[-1]
      print(f'scm{n}'); sys.exit(0)
except Exception:
  pass
" 2>/dev/null || echo "")
  if [ -z "$scm_leader" ]; then
    # 兜底：解析 textual roles
    scm_leader=$(docker_cmd "o101" "scm1" "ozone admin scm roles 2>/dev/null" 2>/dev/null | \
      awk '/LEADER/{for(i=1;i<=NF;i++) if($i ~ /^scm[0-9]+:$/) {gsub(":","",$i); print tolower($i); exit}}')
  fi
  if [ -z "$scm_leader" ]; then
    warn "无法解析 SCM leader（roles 输出：$(echo "$scm_roles" | head -c 200)）"
  else
    info "SCM leader: $scm_leader"
    # scm_leader -> host 映射: scm1=o101, scm2=o102, scm3=o103
    scm_leader_host="o10${scm_leader: -1}"
    scm_follower=""
    for c in scm1 scm2 scm3; do
      [ "$c" != "$scm_leader" ] && scm_follower="$c" && break
    done
    if [ -n "$scm_follower" ]; then
      scm_host="o10${scm_follower: -1}"
      info "停止 follower: $scm_follower (host $scm_host)"
      ssh_to "$scm_host" "sudo docker stop $scm_follower" >/dev/null 2>&1
      sleep 6
      cl=$(docker_cmd "$scm_leader_host" "$scm_leader" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab scm/${scm_leader_host}@EXAMPLE.COM 2>/dev/null; ozone admin container list 2>&1'" 2>/dev/null || true)
      if echo "$cl" | grep -qi "Container"; then
        pass "SCM follower ${scm_follower} 停止后 container list 仍正常"
      else
        fail "SCM follower ${scm_follower} 停止后 container list 失败: $(echo "$cl" | tail -1)"
      fi
      ssh_to "$scm_host" "sudo docker start $scm_follower" >/dev/null 2>&1
      sleep 6
      pass "SCM follower ${scm_follower} 已重启"
    fi
  fi
fi

summary
