# 高可用Ozone集群部署项目

## 项目概述

本项目提供了一个完整的高可用Apache Ozone集群部署方案，包含8个节点的配置和部署脚本。

## 集群架构

集群由以下节点组成：

| IP地址 | 节点角色 | 组件 |
|--------|----------|------|
| 192.168.69.80  | krb5-server | krb5-server, nginx |
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
- `kadmin-init.sh`: 创建principal并生成keytab文件

## 部署步骤

1. 确保所有节点都已安装Docker
2. 启动o80, 并部署kerb5-server并生成keytab

```bash
   vagrant up o80
   vagrant ssh o80
   cd /vagrant
   bash ./install.sh
   docker exec -it krb5-server sh
   在krb5-server容器中,手工执行kadmin-init.sh脚本中的内容,执行一次即可
```

3. 启动启动o101~o108, 并在每个节点上运行 `install.sh` 脚本来启动相应的服务：
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
   # 在任意OM节点执行
   docker exec -it om1 bash
   ozone sh volume create /vol1
   ozone sh bucket create /vol1/bucket1
   echo "Hello Ozone" > test.txt
   ozone sh key put /vol1/bucket1/key1 test.txt
   ozone sh key get /vol1/bucket1/key1 downloaded.txt
   cat downloaded.txt
   ```
4. 使用 aws命令测试s3


```bash
## 注意此时没有开启任何认证,所以AWS_ACCESS_KEY_ID和AWS_SECRET_ACCESS_KEY为任意值即可,但是得有
## 参考 https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-hdds/docs/content/interface/S3.md#security
## bucket2会在s3v这个vol内
## S3 buckets are stored under the /s3v volume.


export AWS_ACCESS_KEY_ID=testuser/scm@EXAMPLE.COM
export AWS_SECRET_ACCESS_KEY=c261b6ecabf7d37d5f9ded654b1c724adac9bd9f13e247a235e567e8296d2999
aws s3api --endpoint http://o108:9878 create-bucket --bucket bucket2
{
    "Location": "http://o108:9878/bucket2"
}

aws s3 ls --endpoint http://o108:9878 s3://bucket2
aws s3 cp /etc/os-release --endpoint http://o108:9878  s3://bucket2/
upload: ../../etc/os-release to s3://bucket2/os-release
aws s3 ls --endpoint http://o108:9878 s3://bucket2
2025-10-10 03:57:33        507 os-release
```


```bash
## 如果开启了kerberos认证按照一下拿到awsAccessKey和awsSecret
## https://ozone.apache.org/docs/2.0.0/interface/s3.html
kinit -kt /etc/security/keytabs/testuser.keytab testuser/scm@EXAMPLE.COM
ozone s3 getsecret
awsAccessKey=testuser/scm@EXAMPLE.COM
awsSecret=c261b6ecabf7d37d5f9ded654b1c724adac9bd9f13e247a235e567e8296d2999
```


## 故障恢复测试

可以通过停止某个OM或SCM节点来测试集群的高可用性，观察集群是否仍能正常工作。

## 安全

- <https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-hdds/docs/content/security/SecureOzone.md>
- <https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-hdds/docs/content/security/SecuringDatanodes.md>
- <https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-hdds/docs/content/security/SecuringOzoneHTTP.md>
- <https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-hdds/docs/content/security/SecuringS3.md>