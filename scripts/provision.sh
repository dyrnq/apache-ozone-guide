#!/usr/bin/env bash

# === 参数解析 ===
# --proxy <url>    HTTP 代理地址，如 http://192.168.6.111:7890
# --noproxy <hosts> 不走代理的地址列表，默认 localhost,127.0.0.1,192.168.69.0/24,.local
PROXY=""
NOPROXY="localhost,127.0.0.1,192.168.69.0/24,.local"
declare -a CURL_OPTS=(-A "Vagrant-Provision/1.0")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxy)   PROXY="$2"; shift 2 ;;
    --noproxy) NOPROXY="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "$PROXY" ]; then
  export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
  export no_proxy="$NOPROXY" NO_PROXY="$NOPROXY"
  CURL_OPTS=(-A "Vagrant-Provision/1.0" --noproxy "$NOPROXY" -x "$PROXY")
fi
# ====================

if command -v apt ; then
    if grep ubuntu /etc/os-release; then
        
        if [ -e /etc/apt/sources.list ]; then
        sed -i \
        -e 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' \
        -e 's@security.ubuntu.com@mirrors.ustc.edu.cn@g' /etc/apt/sources.list
        fi

        if [ -e /etc/apt/sources.list.d/ubuntu.sources ]; then
        sed -i \
        -e 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' \
        -e 's@security.ubuntu.com@mirrors.ustc.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources
        fi
    elif grep debian /etc/os-release; then
        if [ -e /etc/apt/sources.list ]; then
        sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
        sed -i -e 's|security.debian.org/\? |security.debian.org/debian-security |g' \
                    -e 's|security.debian.org|mirrors.ustc.edu.cn|g' \
                    -e 's|deb.debian.org/debian-security|mirrors.ustc.edu.cn/debian-security|g' \
                    /etc/apt/sources.list
        fi

        if [ -e /etc/apt/sources.list.d/debian.sources ]; then
        sed -i \
        -e 's/deb.debian.org/mirrors.ustc.edu.cn/g' \
        -e 's/security.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list.d/debian.sources
        fi

        for x in "/etc/apt/mirrors/debian.list" "/etc/apt/mirrors/debian-security.list"; do
            if [ -e $x ]; then
                sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' $x
            fi
        done
    fi
fi







while true; do
    apt update -y && apt install jq wget curl ntpsec -y && sleep 1s && break;
done


echo "root:vagrant" | sudo chpasswd
timedatectl set-timezone "Asia/Shanghai"
curl "${CURL_OPTS[@]}" -fsSL https://get.docker.com -o /tmp/get-docker.sh
http_proxy="$PROXY" https_proxy="$PROXY" DOWNLOAD_URL=https://mirrors.ustc.edu.cn/docker-ce sh /tmp/get-docker.sh
rm -f /tmp/get-docker.sh
usermod -aG docker vagrant
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKEREOF'
{
  "insecure-registries": [
    "192.168.6.130:5000",
    "10.5.26.11:5000"
  ],
  "registry-mirrors": ["http://192.168.6.130:5000"]
}
DOCKEREOF
systemctl restart docker
docker ps
cat /etc/docker/daemon.json

if [ -n "$PROXY" ]; then
  mkdir -p /etc/systemd/system/docker.service.d
  cat > /etc/systemd/system/docker.service.d/http-proxy.conf << PROXYEOF
[Service]
Environment="HTTP_PROXY=${PROXY}"
Environment="HTTPS_PROXY=${PROXY}"
Environment="NO_PROXY=${NOPROXY}"
PROXYEOF
  systemctl daemon-reload
  systemctl restart docker
fi



if grep ID=ubuntu < /etc/os-release ; then
if [ -e /etc/needrestart/conf.d/ ]; then
cat > /etc/needrestart/conf.d/silence_kernel.conf <<'EOF'
$nrconf{kernelhints} = 0;
$nrconf{restart} = 'l';
EOF
cat /etc/needrestart/conf.d/silence_kernel.conf
fi
fi



