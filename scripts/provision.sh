#!/usr/bin/env bash



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







apt update -y;
apt install jq wget curl -y;



echo "root:vagrant" | sudo chpasswd
timedatectl set-timezone "Asia/Shanghai"
curl -fsSL https://ghfast.top/https://github.com/dyrnq/install-docker/raw/main/install-docker.sh | bash -s docker \
--mirror aliyun \
--version 28.0.1 \
--systemd-mirror https://ghfast.top && \
usermod -aG docker vagrant
docker ps

cat /etc/docker/daemon.json && \
sed -i "s@https://docker.mirrors.ustc.edu.cn@https://docker.m.daocloud.io@g" /etc/docker/daemon.json && \
systemctl restart docker && \
cat /etc/docker/daemon.json