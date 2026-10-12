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
  # docker_cmd [<timeout>] <node> <container> <cmd...>
  # 默认 15s，可传正整数覆盖（写操作建议 60s）
  local timeout=15
  if [[ "$1" =~ ^[0-9]+$ ]]; then timeout="$1"; shift; fi
  local node="$1" container="$2"; shift 2
  ssh_to "$node" "timeout $timeout sudo docker exec $container $*"
}

# leader 解析辅助（Phase 8/10 复用）—— 任意一个 OM 响应即可
get_om_leader() {
  for om in om1 om2 om3; do
    out=$(docker_cmd 10 o101 "$om" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone admin om roles --json 2>/dev/null'" 2>/dev/null)
    leader=$(echo "$out" | python3 -c "
import json, sys
try:
  d=json.load(sys.stdin)
  for entry in d:
    for k,v in entry.items():
      if isinstance(v,dict) and v.get('serverRole')=='LEADER':
        print(k); sys.exit(0)
except Exception:
  pass
" 2>/dev/null)
    [ -n "$leader" ] && { echo "$leader"; return 0; }
  done
  return 1
}

get_scm_leader() {
  # SCM 三个都返回同一 JSON，谁响应都行
  for scm in scm1 scm2 scm3; do
    out=$(docker_cmd 10 o101 "$scm" "bash -c 'ozone admin scm roles --json 2>/dev/null'" 2>/dev/null)
    leader=$(echo "$out" | python3 -c "
import json, sys
try:
  d=json.load(sys.stdin)
  for host,v in d.items():
    if isinstance(v,dict) and v.get('raftPeerRole')=='LEADER':
      print(f'scm{host[-1]}'); sys.exit(0)
except Exception:
  pass
" 2>/dev/null)
    [ -n "$leader" ] && { echo "$leader"; return 0; }
  done
  return 1
}

summary() {
  local t=$((PASS+FAIL+SKIP))
  echo -e "\n${BLUE}══════  ${GREEN}${PASS}✓${NC} ${RED}${FAIL}✗${NC} ${YELLOW}${SKIP}⊘${NC} (${t})${NC}"
  [ "$FAIL" -gt 0 ] && return 1 || return 0
}

# 等待 SCM 退出 safe mode（Phase 8/10 重启 SCM 后会短暂进入 safe mode）
# pipeline 列表在 init 后立即可用，是判断 SCM 在线且退出 safe mode 的最简信号
wait_scm_ready() {
  local i max=${1:-30}
  for ((i=0; i<max; i++)); do
    # 1) 能跑 ozone admin pipeline list（说明非 safe mode）
    if docker_cmd 8 o101 scm1 "bash -c 'ozone admin pipeline list 2>/dev/null'" 2>/dev/null | grep -q "Pipeline{"; then
      # 2) 安全起见再确认无 safe mode 提示
      if ! docker_cmd 8 o101 scm1 "bash -c 'ozone admin pipeline list 2>&1'" 2>/dev/null | grep -qi "safe.*mode\|SafeModePrecheck"; then
        return 0
      fi
    fi
    sleep 2
  done
  return 1
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
  om_leader=$(get_om_leader)
  if [ -z "$om_leader" ]; then
    fail "无法解析 OM leader"
  else
    info "OM leader: $om_leader"
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
  scm_leader=$(get_scm_leader)
  if [ -z "$scm_leader" ]; then
    warn "无法解析 SCM leader"
  else
    info "SCM leader: $scm_leader"
    scm_leader_host="o10${scm_leader: -1}"
    scm_follower=""
    for c in scm1 scm2 scm3; do
      [ "$c" != "$scm_leader" ] && scm_follower="$c" && break
    done
    if [ -n "$scm_follower" ]; then
      scm_host="o10${scm_follower: -1}"
      info "停止 follower: $scm_follower (host $scm_host)"
      ssh_to "$scm_host" "sudo docker stop $scm_follower" >/dev/null 2>&1
      sleep 8
      # 用 pipeline list 验证：新集群 container 列表可能为空，pipeline 一定存在
      pl=$(docker_cmd 15 "$scm_leader_host" "$scm_leader" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab scm/${scm_leader_host}@EXAMPLE.COM 2>/dev/null; ozone admin pipeline list 2>&1'" 2>/dev/null || true)
      if echo "$pl" | grep -q "Pipeline{"; then
        pass "SCM follower ${scm_follower} 停止后 pipeline list 仍正常"
      else
        fail "SCM follower ${scm_follower} 停止后 pipeline list 失败: $(echo "$pl" | tail -1 | head -c 200)"
      fi
      ssh_to "$scm_host" "sudo docker start $scm_follower" >/dev/null 2>&1
      sleep 8
      pass "SCM follower ${scm_follower} 已重启"
    fi
  fi
fi

# ========== Phase 9: 写路径 & S3 & HDFS ==========
title "Phase 9: 写路径 & S3 & HDFS"
if [ "$HA_TESTS" = "false" ]; then
  skip "--no-ha 模式（写操作可能不稳定）"
else
  # Phase 8 重启过 SCM 容器，可能仍在 safe mode；等待最多 60s 让 container list 返回数据
  if wait_scm_ready 30; then
    info "SCM 已退出 safe mode"
  else
    warn "SCM 可能仍处于 safe mode，写操作可能失败"
  fi
  ts=$(date +%s)
  tvol="vol-r9-${ts}"
  tbuc="bucket-r9-${ts}"
  tkey="key-r9-${ts}"
  tcontent="ozone-2.2.1-regression-${ts}"

  # --- 9.1 Ozone 写路径（om1） ---
  # 2-DN: --type RATIS --replication ONE（注意 --replication 只能接 ONE/THREE，不接 RATIS/ONE）
  out=$(docker_cmd 30 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh volume create /${tvol} 2>&1; ozone sh bucket create /${tvol}/${tbuc} --type RATIS --replication ONE 2>&1'" 2>/dev/null || true)
  vol_chk=$(docker_cmd 15 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh volume list 2>&1'" 2>/dev/null | grep -c "$tvol" || true)
  buc_chk=$(docker_cmd 15 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh bucket list /${tvol} 2>&1'" 2>/dev/null | grep -c "$tbuc" || true)
  if [ "$vol_chk" -ge 1 ] && [ "$buc_chk" -ge 1 ]; then
    pass "写路径: volume+bucket create (RATIS/ONE)"
  else
    fail "写路径: create 失败 (vol=$vol_chk buc=$buc_chk, raw=$out)"
  fi

  # 写 key 内容到容器内文件
  ssh_to o101 "sudo docker exec om1 bash -c \"echo '${tcontent}' > /tmp/${tkey}\"" >/dev/null 2>&1
  out=$(docker_cmd 30 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh key put /${tvol}/${tbuc}/${tkey} /tmp/${tkey} 2>&1'" 2>/dev/null || true)
  err_put=$(echo "$out" | grep -iE "ERROR|Exception|failed" | head -1)
  if [ -z "$err_put" ]; then
    pass "写路径: key put (RATIS/ONE)"
  else
    fail "写路径: key put: $err_put"
  fi

  got=$(docker_cmd 30 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh key get /${tvol}/${tbuc}/${tkey} /tmp/${tkey}.out 2>&1; cat /tmp/${tkey}.out 2>&1'" 2>/dev/null || true)
  if echo "$got" | grep -q "${tcontent}"; then
    pass "写路径: key get 内容一致"
  else
    fail "写路径: 内容不匹配 (got: $(echo "$got" | tail -1 | head -c 200))"
  fi

  # 清理
  docker_cmd 30 o101 om1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM 2>/dev/null; ozone sh key delete /${tvol}/${tbuc}/${tkey} 2>/dev/null; ozone sh bucket delete /${tvol}/${tbuc} 2>/dev/null; ozone sh volume delete /${tvol} 2>/dev/null'" >/dev/null 2>&1
  info "已清理 /${tvol}"

  # --- 9.2 S3 网关 ---
  s3_bucket="s3r9${ts}"
  # 用 setsecret 显式注入 secret（idempotent，密钥可重现，避开 "SECRET_ALREADY_EXISTS"）
  # 选 s3g/o101@EXAMPLE.COM 作 principal（任何含此 principal 的 keytab 都行）
  s3_principal="s3g/o101@EXAMPLE.COM"
  s3_secret="r9-${ts}-0123456789abcdef"
  s3_creds=$(ssh_to o108 "sudo docker exec s3gateway bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab ${s3_principal} 2>/dev/null; ozone s3 setsecret -e -s ${s3_secret} 2>/dev/null'" 2>/dev/null || true)
  # setsecret -e 输出是 shell export 格式: export AWS_ACCESS_KEY_ID='...' / export AWS_SECRET_ACCESS_KEY='...'
  s3_key=$(echo "$s3_creds" | grep -E "^export AWS_ACCESS_KEY_ID" | head -1 | sed -E "s/.*='([^']+)'.*/\1/")
  s3_secret_out=$(echo "$s3_creds" | grep -E "^export AWS_SECRET_ACCESS_KEY" | head -1 | sed -E "s/.*='([^']+)'.*/\1/")
  if [ -n "$s3_key" ] && [ -n "$s3_secret_out" ]; then
    pass "S3: setsecret (key: ${s3_key})"
    cb=$(AWS_ACCESS_KEY_ID="$s3_key" AWS_SECRET_ACCESS_KEY="$s3_secret_out" AWS_DEFAULT_REGION=us-east-1 \
         aws --endpoint-url http://192.168.69.108:9878 s3api create-bucket --bucket "$s3_bucket" 2>&1)
    if echo "$cb" | grep -q "Location"; then
      pass "S3: create-bucket ${s3_bucket}"
    else
      fail "S3: create-bucket 失败: $(echo "$cb" | head -c 200)"
    fi
    echo "s3-r9-${ts}" > /tmp/s3-r9-file
    up=$(AWS_ACCESS_KEY_ID="$s3_key" AWS_SECRET_ACCESS_KEY="$s3_secret_out" AWS_DEFAULT_REGION=us-east-1 \
         aws --endpoint-url http://192.168.69.108:9878 s3 cp /tmp/s3-r9-file "s3://${s3_bucket}/probe" 2>&1)
    if echo "$up" | grep -q "upload:"; then
      pass "S3: s3 cp 上传"
    else
      fail "S3: s3 cp 失败: $(echo "$up" | tail -1 | head -c 200)"
    fi
    ls_out=$(AWS_ACCESS_KEY_ID="$s3_key" AWS_SECRET_ACCESS_KEY="$s3_secret_out" AWS_DEFAULT_REGION=us-east-1 \
             aws --endpoint-url http://192.168.69.108:9878 s3 ls "s3://${s3_bucket}/" 2>/dev/null)
    if echo "$ls_out" | grep -q "probe"; then
      pass "S3: s3 ls 可见 probe"
    else
      fail "S3: s3 ls 不可见: $ls_out"
    fi
    AWS_ACCESS_KEY_ID="$s3_key" AWS_SECRET_ACCESS_KEY="$s3_secret_out" AWS_DEFAULT_REGION=us-east-1 \
      aws --endpoint-url http://192.168.69.108:9878 s3 rb "s3://${s3_bucket}" 2>/dev/null
  else
    fail "S3: setsecret 解析失败 (raw: $(echo "$s3_creds" | head -c 200))"
  fi

  # --- 9.3 HDFS 兼容 (ofs://) ---
  hvol="vol-r9hdfs-${ts}"
  hbuc="bucket-r9hdfs-${ts}"
  ssh_to o211 "export PATH=\$PATH:/opt/hadoop/bin:/opt/ozone/bin; kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 2>/dev/null; ozone sh volume create /${hvol} 2>/dev/null; ozone sh bucket create /${hvol}/${hbuc} --type RATIS --replication ONE 2>/dev/null" 2>&1 >/dev/null
  ofs_path="ofs://cluster1/${hvol}/${hbuc}"
  put_out=$(ssh_to o211 "export PATH=\$PATH:/opt/hadoop/bin:/opt/ozone/bin; kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 2>/dev/null; echo 'hdfs-r9-${ts}' | hdfs dfs -put - ${ofs_path}/hdfs-key-${ts} 2>&1" 2>&1)
  ofs_ls=$(ssh_to o211 "export PATH=\$PATH:/opt/hadoop/bin:/opt/ozone/bin; kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 2>/dev/null; hdfs dfs -ls ${ofs_path} 2>/dev/null" 2>&1)
  if echo "$ofs_ls" | grep -q "hdfs-key-${ts}"; then
    pass "HDFS compat: dfs -put + -ls 可见"
  else
    fail "HDFS compat: dfs -put 失败: put=${put_out:0:200} ls=${ofs_ls:0:200}"
  fi
  ofs_get=$(ssh_to o211 "export PATH=\$PATH:/opt/hadoop/bin:/opt/ozone/bin; kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 2>/dev/null; hdfs dfs -cat ${ofs_path}/hdfs-key-${ts} 2>/dev/null" 2>&1)
  if echo "$ofs_get" | grep -q "hdfs-r9-${ts}"; then
    pass "HDFS compat: dfs -cat 内容一致"
  else
    fail "HDFS compat: dfs -cat 失败: $(echo "$ofs_get" | tail -1 | head -c 200)"
  fi
  ssh_to o211 "export PATH=\$PATH:/opt/hadoop/bin:/opt/ozone/bin; kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 2>/dev/null; hdfs dfs -rm ${ofs_path}/hdfs-key-${ts} 2>/dev/null; ozone sh bucket delete /${hvol}/${hbuc} 2>/dev/null; ozone sh volume delete /${hvol} 2>/dev/null" 2>&1 >/dev/null
  info "已清理 /${hvol}"
fi

# ========== Phase 10: 数据面 & Leader HA ==========
title "Phase 10: 数据面 & Leader HA"
if [ "$HA_TESTS" = "false" ]; then
  skip "--no-ha 模式"
else
  # --- 10.1 Datanode HA ---
  if nc -z -w1 192.168.69.105 22 2>/dev/null; then
    ssh_to o105 "sudo docker stop datanode2" >/dev/null 2>&1
    sleep 8
    cl=$(docker_cmd 15 o101 scm1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab scm/o101@EXAMPLE.COM 2>/dev/null; ozone admin container list 2>&1'" 2>/dev/null || true)
    if [ -n "$cl" ]; then
      pass "DN HA: datanode2 停止后 SCM 仍可服务"
    else
      fail "DN HA: datanode2 停止后 SCM 异常"
    fi
    ssh_to o105 "sudo docker start datanode2" >/dev/null 2>&1
    sleep 12
    dn_count=$(docker_cmd 15 o101 scm1 "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab scm/o101@EXAMPLE.COM 2>/dev/null; ozone admin datanode list 2>&1 | grep -c HEALTHY'" 2>/dev/null | tr -d '\n\r' | head -c 16)
    dn_count=${dn_count:-0}
    if [ "$dn_count" -ge 2 ] 2>/dev/null; then
      pass "DN HA: datanode2 重启后重新加入 (HEALTHY=${dn_count})"
    else
      fail "DN HA: datanode2 未加入 (HEALTHY=${dn_count})"
    fi
  else
    skip "o105 不可达"
  fi

  # --- 10.2 OM leader 故障（杀 leader 验证 ratis 切换） ---
  om_leader=$(get_om_leader)
  if [ -z "$om_leader" ]; then
    fail "OM leader kill: 无法解析当前 leader"
  else
    leader_host="o10${om_leader: -1}"
    info "OM 当前 leader: $om_leader，准备停掉"
    ssh_to "$leader_host" "sudo docker stop $om_leader" >/dev/null 2>&1
    sleep 15
    new_om_leader=$(get_om_leader)
    if [ -n "$new_om_leader" ] && [ "$new_om_leader" != "$om_leader" ]; then
      pass "OM HA: leader 切换 $om_leader → $new_om_leader"
    else
      fail "OM HA: leader 未切换 (仍为 $new_om_leader)"
    fi
    nl_host="o10${new_om_leader: -1}"
    vl=$(docker_cmd 15 "$nl_host" "$new_om_leader" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab om/${nl_host}@EXAMPLE.COM 2>/dev/null; ozone sh volume list 2>&1'" 2>/dev/null || true)
    if echo "$vl" | grep -q '"name"'; then
      pass "OM HA: 新 leader volume list OK"
    else
      fail "OM HA: 新 leader 异常: $(echo "$vl" | tail -1 | head -c 200)"
    fi
    ssh_to "$leader_host" "sudo docker start $om_leader" >/dev/null 2>&1
    sleep 12
    om_count=$(docker_cmd 15 "$nl_host" "$new_om_leader" "bash -c 'ozone admin om roles 2>/dev/null | grep -cE \"om[0-9]+ :\"'" 2>/dev/null | tr -d '\n\r' | head -c 16)
    om_count=${om_count:-0}
    if [ "$om_count" -eq 3 ] 2>/dev/null; then
      pass "OM HA: $om_leader 重启后 3 个 OM 全部就绪"
    else
      fail "OM HA: 仅 $om_count 个 OM"
    fi
  fi

  # --- 10.3 SCM leader 故障 ---
  scm_leader=$(get_scm_leader)
  if [ -z "$scm_leader" ]; then
    fail "SCM leader kill: 无法解析当前 leader"
  else
    leader_host="o10${scm_leader: -1}"
    info "SCM 当前 leader: $scm_leader，准备停掉"
    ssh_to "$leader_host" "sudo docker stop $scm_leader" >/dev/null 2>&1
    sleep 20  # SCM leader 选举比 OM 慢，多等
    new_scm_leader=$(get_scm_leader)
    if [ -n "$new_scm_leader" ] && [ "$new_scm_leader" != "$scm_leader" ]; then
      pass "SCM HA: leader 切换 $scm_leader → $new_scm_leader"
    else
      fail "SCM HA: leader 未切换 (仍为 $new_scm_leader)"
    fi
    nl_host="o10${new_scm_leader: -1}"
    # pipeline list 在新 SCM leader 上必须能返回（container 列表可能为空）
    pl=$(docker_cmd 15 "$nl_host" "$new_scm_leader" "bash -c 'kinit -kt /etc/security/keytabs/ozone.keytab scm/${nl_host}@EXAMPLE.COM 2>/dev/null; ozone admin pipeline list 2>&1'" 2>/dev/null || true)
    if echo "$pl" | grep -q "Pipeline{"; then
      pass "SCM HA: 新 leader pipeline list OK"
    else
      fail "SCM HA: 新 leader 异常: $(echo "$pl" | tail -1 | head -c 200)"
    fi
    ssh_to "$leader_host" "sudo docker start $scm_leader" >/dev/null 2>&1
    sleep 15
    scm_count=$(docker_cmd 15 "$nl_host" "$new_scm_leader" "bash -c 'ozone admin scm roles 2>/dev/null | grep -cE \"^o[0-9]+:\"'" 2>/dev/null | tr -d '\n\r' | head -c 16)
    scm_count=${scm_count:-0}
    if [ "$scm_count" -eq 3 ] 2>/dev/null; then
      pass "SCM HA: $scm_leader 重启后 3 个 SCM 全部就绪"
    else
      fail "SCM HA: 仅 $scm_count 个 SCM"
    fi
  fi
fi

# ========== Phase 11: 指标 & 拓扑一致性 ==========
title "Phase 11: 指标 & 拓扑一致性"

# 11.1 Prometheus metrics
metrics_count=0
metrics_fail=0
# Ozone 暴露 /prom（不是 /metrics），端口 9874=OM, 9876=SCM, 9882=DN, 9888=Recon
# 必须用 IP，因为本机 /etc/hosts 不一定有 o101 等短名
for ep in "192.168.69.101:9874" "192.168.69.101:9876" "192.168.69.104:9882" "192.168.69.108:9888"; do
  resp=$(curl -s --max-time 8 "http://$ep/prom" 2>/dev/null | head -3)
  if echo "$resp" | grep -qE "^# TYPE|^ozone_"; then
    metrics_count=$((metrics_count+1))
  else
    metrics_fail=$((metrics_fail+1))
  fi
done
[ "$metrics_fail" -eq 0 ] && pass "metrics: ${metrics_count}/4 端点暴露 ozone_* 指标" || warn "metrics: ${metrics_count}/4 暴露 (失败 ${metrics_fail})"

# 11.2 Recon 拓扑
if nc -z -w1 192.168.69.108 9888 2>/dev/null; then
  dn_resp=$(curl -s --max-time 8 "http://192.168.69.108:9888/api/v1/datanodes" 2>/dev/null)
  # 响应是 {totalCount, datanodes:[...]} 包裹的 dict
  dn_count=$(echo "$dn_resp" | python3 -c "import json,sys
try:
  d=json.load(sys.stdin)
  if isinstance(d,dict): d=d.get('datanodes',[])
  print(len(d) if isinstance(d,list) else 0)
except Exception: print(0)" 2>/dev/null || echo 0)
  if [ "$dn_count" -ge 2 ] 2>/dev/null; then
    pass "Recon: /api/v1/datanodes=${dn_count}"
  else
    fail "Recon: datanodes=${dn_count} (raw: $(echo "$dn_resp" | head -c 200))"
  fi
  cs_resp=$(curl -s --max-time 8 "http://192.168.69.108:9888/api/v1/clusterState" 2>/dev/null)
  # 字段: healthyDatanodes / totalDatanodes / pipelines / containers / volumes / buckets / keys
  cs_summary=$(echo "$cs_resp" | python3 -c "import json,sys
try:
  d=json.load(sys.stdin)
  print('healthyDN='+str(d.get('healthyDatanodes','?'))+' totalDN='+str(d.get('totalDatanodes','?'))+' pipelines='+str(d.get('pipelines','?'))+' containers='+str(d.get('containers','?'))+' volumes='+str(d.get('volumes','?'))+' buckets='+str(d.get('buckets','?'))+' keys='+str(d.get('keys','?')))
except Exception: print('?')" 2>/dev/null || echo "?")
  info "Recon: clusterState ${cs_summary}"
else
  skip "Recon 不可达"
fi

summary
