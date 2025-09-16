# 高可用Ozone集群部署项目

## 项目概述

本项目提供了一个完整的高可用Apache Ozone集群部署方案，包含8个节点的配置和部署脚本。

## 集群架构

集群由以下节点组成：

| IP地址 | 节点角色 | 组件 |
|--------|----------|------|
| 192.168.69.101 | OM/SCM节点 | OM1, SCM1 |
| 192.168.69.102 | OM/SCM节点 | OM2, SCM2 |
| 192.168.69.103 | OM/SCM节点 | OM3, SCM3 |
| 192.168.69.104 | Datanode节点 | Datanode1 |
| 192.168.69.105 | Datanode节点 | Datanode2 |
| 192.168.69.106 | Datanode节点 | Datanode3 |
| 192.168.69.107 | Datanode节点 | Datanode4 |
| 192.168.69.108 | Recon/S3 Gateway节点 | Recon, S3 Gateway |

## 文件说明

- `install.sh`: 部署脚本，用于在各节点上启动相应的Ozone服务
- `Vagrantfile`: Vagrant配置文件，用于创建测试环境

## 部署步骤

1. 确保所有节点都已安装Docker
2. 在每个节点上运行 `install.sh` 脚本来启动相应的服务：
   ```bash
   cd /vagrant
   bash ./install.sh
   ```
   
   脚本会根据节点的IP地址自动确定节点角色并启动相应的服务：
   - 192.168.69.101: 启动OM1和SCM1服务
   - 192.168.69.102: 启动OM2和SCM2服务
   - 192.168.69.103: 启动OM3和SCM3服务
   - 192.168.69.104: 启动Datanode1服务
   - 192.168.69.105: 启动Datanode2服务
   - 192.168.69.106: 启动Datanode3服务
   - 192.168.69.107: 启动Datanode4服务
   - 192.168.69.108: 启动Recon和S3 Gateway服务

## 验证集群状态

可以通过以下方式验证集群状态：

1. 检查容器是否正常运行：
   ```bash
   docker ps
   ```

2. 访问Recon管理界面：
   - http://192.168.69.108:9888

3. 使用Ozone客户端测试文件操作：
   ```bash
   # 在任意SCM节点执行
   docker exec -it scm1 bash
   ozone sh volume create /vol1
   ozone sh bucket create /vol1/bucket1
   echo "Hello Ozone" > test.txt
   ozone sh key put /vol1/bucket1/key1 test.txt
   ozone sh key get /vol1/bucket1/key1 downloaded.txt
   cat downloaded.txt
   ```

## 故障恢复测试

可以通过停止某个OM或SCM节点来测试集群的高可用性，观察集群是否仍能正常工作。