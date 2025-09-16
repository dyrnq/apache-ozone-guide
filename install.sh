#!/bin/bash

# 获取本机IP地址
get_local_ip() {
  /sbin/ip -o -4 addr list "enp0s8" | awk '{print $4}' | cut -d/ -f1 | head -n1
}

# 获取本机IP
LOCAL_IP=$(get_local_ip)

echo "本机IP地址: $LOCAL_IP"
# https://ozone.apache.org/docs/edge/concept/networkports.html
# OM和SCM服务启动函数
start_om() {
  ip4=$(/sbin/ip -o -4 addr list "enp0s8" | awk '{print $4}' | cut -d/ -f1 | head -n1)
  local om_node=$1
  
  # 清理已存在的容器
  docker rm -f "${om_node}" >/dev/null 2>&1 || true
  
  # 创建数据持久化目录
  sudo mkdir -p "/data/ozone/${om_node}/data/metadata"
  # sudo rm -rf "/data/ozone/${om_node}/data/metadata"
  
  # 设置目录权限
  sudo chown -R 1000:1000 "/data/ozone/${om_node}/data"

  # 启动OM容器
  docker run -d \
    --network host \
    --name "${om_node}" \
    --restart always \
    --add-host o101:192.168.69.101 \
    --add-host o102:192.168.69.102 \
    --add-host o103:192.168.69.103 \
    --add-host o104:192.168.69.104 \
    --add-host o105:192.168.69.105 \
    --add-host o106:192.168.69.106 \
    --add-host o107:192.168.69.107 \
    --add-host o108:192.168.69.108 \
    -v /etc/timezone:/etc/timezone \
    -v "/data/ozone/${om_node}/data:/data" \
    -e "ENSURE_OM_INITIALIZED=/data/metadata/om/current/VERSION" \
    -e "OZONE-SITE.XML_ozone.om.service.ids=cluster1" \
    -e "OZONE-SITE.XML_ozone.om.nodes.cluster1=om1,om2,om3" \
    -e "OZONE-SITE.XML_ozone.om.address.cluster1.om1=192.168.69.101" \
    -e "OZONE-SITE.XML_ozone.om.address.cluster1.om2=192.168.69.102" \
    -e "OZONE-SITE.XML_ozone.om.address.cluster1.om3=192.168.69.103" \
    -e "OZONE-SITE.XML_ozone.om.address=0.0.0.0:9862" \
    -e "OZONE-SITE.XML_ozone.metadata.dirs=/data/metadata" \
    -e "OZONE-SITE.XML_ozone.scm.service.ids=cluster1" \
    -e "OZONE-SITE.XML_ozone.scm.nodes.cluster1=scm1,scm2,scm3" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm1=192.168.69.101" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm2=192.168.69.102" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm3=192.168.69.103" \
    -e "WAITFOR=192.168.69.103:9894" \
    apache/ozone:2.0.0 \
    ozone om

}


start_scm() {
  ip4=$(/sbin/ip -o -4 addr list "enp0s8" | awk '{print $4}' | cut -d/ -f1 | head -n1)
  local scm_node=$1
  
  # 清理已存在的容器
  docker rm -f "${scm_node}" >/dev/null 2>&1 || true
  
  # 创建数据持久化目录
  sudo mkdir -p "/data/ozone/${scm_node}/data/metadata"
  # sudo rm -rf "/data/ozone/${scm_node}/data/metadata"
  
  # 设置目录权限
  sudo chown -R 1000:1000 "/data/ozone/${scm_node}/data"
  
  # 启动SCM容器
  docker run -d \
    --network host \
    --name "${scm_node}" \
    --restart always \
    --add-host o101:192.168.69.101 \
    --add-host o102:192.168.69.102 \
    --add-host o103:192.168.69.103 \
    --add-host o104:192.168.69.104 \
    --add-host o105:192.168.69.105 \
    --add-host o106:192.168.69.106 \
    --add-host o107:192.168.69.107 \
    --add-host o108:192.168.69.108 \
    -v /etc/timezone:/etc/timezone \
    -v "/data/ozone/${scm_node}/data:/data" \
    -e "OZONE-SITE.XML_ozone.scm.service.ids=cluster1" \
    -e "OZONE-SITE.XML_ozone.scm.primordial.node.id=scm1" \
    -e "OZONE-SITE.XML_ozone.scm.nodes.cluster1=scm1,scm2,scm3" \
    -e "OZONE-SITE.xml_ozone.scm.client.address=${ip4}" \
    -e "OZONE-SITE.XML_ozone.scm.block.client.address=${ip4}" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm1=192.168.69.101" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm2=192.168.69.102" \
    -e "OZONE-SITE.XML_ozone.scm.address.cluster1.scm3=192.168.69.103" \
    -e "OZONE-SITE.XML_ozone.metadata.dirs=/data/metadata" \
    apache/ozone:2.0.0 \
    bash -c "ozone scm --init;ozone scm --bootstrap;exec ozone scm"
}

# Datanode服务启动函数
start_datanode() {
  local datanode=$1
  
  # 清理已存在的容器
  docker rm -f "${datanode}" >/dev/null 2>&1 || true
  
  # 创建数据持久化目录
  sudo mkdir -p "/data/ozone/${datanode}/data/metadata"
  
  # 设置目录权限
  sudo chown -R 1000:1000 "/data/ozone/${datanode}/data"
  
  # 启动Datanode容器
  docker run -d \
    --network host \
    --name "${datanode}" \
    --restart always \
    --add-host o101:192.168.69.101 \
    --add-host o102:192.168.69.102 \
    --add-host o103:192.168.69.103 \
    --add-host o104:192.168.69.104 \
    --add-host o105:192.168.69.105 \
    --add-host o106:192.168.69.106 \
    --add-host o107:192.168.69.107 \
    --add-host o108:192.168.69.108 \
    -v /etc/timezone:/etc/timezone \
    -v "/data/ozone/${datanode}/data:/data" \
    -e "OZONE-SITE.XML_ozone.scm.names=o101,o102,o103" \
    -e "OZONE-SITE.XML_hdds.datanode.dir=/data" \
    -e "OZONE-SITE.XML_hdds.datanode.http.address=0.0.0.0:9882" \
    -e "OZONE-SITE.XML_ozone.metadata.dirs=/data/metadata" \
    apache/ozone:2.0.0 \
    ozone datanode
}

# Recon服务启动函数
start_recon() {
  local recon="recon"
  
  # 清理已存在的容器
  docker rm -f "${recon}" >/dev/null 2>&1 || true
  
  # 创建数据持久化目录
  sudo mkdir -p "/data/ozone/${recon}/data/metadata"
  
  # 设置目录权限
  sudo chown -R 1000:1000 "/data/ozone/${recon}/data"
  
  # 启动Recon容器
  docker run -d \
    --network host \
    --name "${recon}" \
    --restart always \
    --add-host o101:192.168.69.101 \
    --add-host o102:192.168.69.102 \
    --add-host o103:192.168.69.103 \
    --add-host o104:192.168.69.104 \
    --add-host o105:192.168.69.105 \
    --add-host o106:192.168.69.106 \
    --add-host o107:192.168.69.107 \
    --add-host o108:192.168.69.108 \
    -v /etc/timezone:/etc/timezone \
    -v "/data/ozone/${recon}/data:/data" \
    -e "OZONE-SITE.XML_ozone.recon.om.address=cluster1" \
    -e "OZONE-SITE.XML_ozone.recon.scm.address=cluster1" \
    -e "OZONE-SITE.XML_ozone.recon.http-address=0.0.0.0:9888" \
    -e "OZONE-SITE.XML_ozone.metadata.dirs=/data/metadata" \
    apache/ozone:2.0.0 \
    ozone recon
}

# S3 Gateway服务启动函数
start_s3gateway() {
  local s3gateway="s3gateway"
  
  # 清理已存在的容器
  docker rm -f "${s3gateway}" >/dev/null 2>&1 || true
  
  # 创建数据持久化目录
  sudo mkdir -p "/data/ozone/${s3gateway}/data/metadata"
  
  # 设置目录权限
  sudo chown -R 1000:1000 "/data/ozone/${s3gateway}/data"
  
  # 启动S3 Gateway容器
  docker run -d \
    --network host \
    --name "${s3gateway}" \
    --restart always \
    --add-host o101:192.168.69.101 \
    --add-host o102:192.168.69.102 \
    --add-host o103:192.168.69.103 \
    --add-host o104:192.168.69.104 \
    --add-host o105:192.168.69.105 \
    --add-host o106:192.168.69.106 \
    --add-host o107:192.168.69.107 \
    --add-host o108:192.168.69.108 \
    -v /etc/timezone:/etc/timezone \
    -v "/data/ozone/${s3gateway}/data:/data" \
    -e "OZONE-SITE.XML_ozone.s3g.address=0.0.0.0:9878" \
    -e "OZONE-SITE.XML_ozone.s3g.domain.name=192.168.69.108" \
    -e "OZONE-SITE.XML_ozone.metadata.dirs=/data/metadata" \
    apache/ozone:2.0.0 \
    ozone s3g
}

# 根据IP地址确定节点角色并启动相应的服务
case $LOCAL_IP in
  192.168.69.101)
    echo "启动OM1和SCM1服务"
    start_om "om1"
    start_scm "scm1"
    ;;
  192.168.69.102)
    echo "启动OM2和SCM2服务"
    start_om "om2"
    start_scm "scm2"
    ;;
  192.168.69.103)
    echo "启动OM3和SCM3服务"
    start_om "om3"
    start_scm "scm3"
    ;;
  192.168.69.104)
    echo "启动Datanode1服务"
    start_datanode "datanode1"
    ;;
  192.168.69.105)
    echo "启动Datanode2服务"
    start_datanode "datanode2"
    ;;
  192.168.69.106)
    echo "启动Datanode3服务"
    start_datanode "datanode3"
    ;;
  192.168.69.107)
    echo "启动Datanode4服务"
    start_datanode "datanode4"
    ;;
  192.168.69.108)
    echo "启动Recon和S3 Gateway服务"
    start_recon
    start_s3gateway
    ;;
  *)
    echo "未知的IP地址: $LOCAL_IP"
    exit 1
    ;;
esac
