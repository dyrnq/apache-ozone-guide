# High-Availability Ozone Cluster Deployment

## Overview

A complete high-availability Apache Ozone cluster deployment with 10 nodes, configuration scripts,
and automated validation.

## Cluster Architecture

| IP | Role | Components |
|----|------|------------|
| 192.168.69.80  | KRB5 Server | krb5-server, nginx |
| 192.168.69.101 | OM/SCM node | OM1, SCM1 |
| 192.168.69.102 | OM/SCM node | OM2, SCM2 |
| 192.168.69.103 | OM/SCM node | OM3, SCM3 |
| 192.168.69.104 | Datanode | Datanode1 |
| 192.168.69.105 | Datanode | Datanode2 |
| 192.168.69.106 | Datanode | Datanode3 |
| 192.168.69.107 | Datanode | Datanode4 |
| 192.168.69.108 | Recon / S3 Gateway | Recon, S3 Gateway |
| 192.168.69.211 | HDFS demo node | hadoop, ozone, krb5-user, awscli |

## Files

- `install.sh` — Deployment script. Starts Ozone services based on node IP.
- `Vagrantfile` — Vagrant configuration for the test environment.
- `scripts/provision.sh` — Vagrant provision script. Installs Docker and base dependencies.
- `scripts/validate.sh` — Automated cluster validation. Use `--no-ha` to skip disruptive HA tests.
- `kadmin-init.sh` — Creates Kerberos principals and generates keytab files.
- `hdfs-usage.sh` — Installs and configures Hadoop / Ozone client + AWS CLI on o211.

## Deployment

1. Ensure Docker is installed on all nodes.
2. Start o80, deploy the KRB5 server, and generate keytabs:

   ```bash
   vagrant up o80
   vagrant ssh o80
   cd /vagrant
   bash ./install.sh
   ```

   Generate principals inside the KRB5 container:

   ```bash
   docker exec krb5-server sh -c "$(cat /vagrant/kadmin-init.sh)"
   ```

3. Start o101–o108 and run `install.sh` on each node:

   ```bash
   cd /vagrant
   bash ./install.sh
   ```

   The script auto-detects the node role based on its IP:
   - 192.168.69.101 → OM1 + SCM1
   - 192.168.69.102 → OM2 + SCM2
   - 192.168.69.103 → OM3 + SCM3
   - 192.168.69.104 → Datanode1
   - 192.168.69.105 → Datanode2
   - 192.168.69.106 → Datanode3
   - 192.168.69.107 → Datanode4
   - 192.168.69.108 → Recon + S3 Gateway

4. For a minimal demo, skip o106/o107 (two Datanodes are sufficient for read-only tests):

   ```bash
   vagrant up o80 o101 o102 o103 o104 o105 o108 o211
   ```

5. On o211, run `hdfs-usage.sh` to install Hadoop / Ozone client and AWS CLI:

   ```bash
   vagrant ssh o211
   cd /vagrant
   bash ./hdfs-usage.sh --mirror https://mirrors.ustc.edu.cn/apache
   ```

## Validation

### One-Click (recommended)

```bash
bash scripts/validate.sh --no-ha
```

### Manual Checks

1. Verify containers are running:

   ```bash
   docker ps
   ```

2. Open the Recon web UI: http://192.168.69.108:9888

3. Test Ozone CLI (Kerberos is enabled, so `kinit` first):

   ```bash
   docker exec -it om1 bash
   kinit -kt /etc/security/keytabs/ozone.keytab om/o101@EXAMPLE.COM
   ozone sh volume create /vol1
   ozone sh bucket create /vol1/bucket1
   echo "Hello Ozone" > test.txt
   ozone sh key put /vol1/bucket1/key1 test.txt
   ozone sh key get /vol1/bucket1/key1 downloaded.txt
   cat downloaded.txt
   ```

4. Test S3 (with Kerberos, obtain credentials first):

   ```bash
   kinit -kt /etc/security/keytabs/testuser.keytab testuser/scm@EXAMPLE.COM
   ozone s3 getsecret
   # awsAccessKey=testuser/scm@EXAMPLE.COM
   # awsSecret=c261b6ecabf7d37d5f9ded654b1c724adac9bd9f13e247a235e567e8296d2999

   export AWS_ACCESS_KEY_ID=testuser/scm@EXAMPLE.COM
   export AWS_SECRET_ACCESS_KEY=c261b6ecabf7d37d5f9ded654b1c724adac9bd9f13e247a235e567e8296d2999
   aws s3api --endpoint http://o108:9878 create-bucket --bucket bucket2
   ```

## Notes

- The default `RATIS/THREE` replication requires **3 Datanodes** for writes.
  A minimal demo (2 DNs) supports read-only cluster validation.
- Full deployment: `vagrant up o80 o101 o102 o103 o104 o105 o106 o107 o108 o211`

## HA Failover

Stop an OM or SCM container to observe Ratis leader election and verify the cluster
remains operational.

## Security

- <https://github.com/apache/ozone/blob/ozone-2.1.0/hadoop-hdds/docs/content/security/SecureOzone.md>
- <https://github.com/apache/ozone/blob/ozone-2.1.0/hadoop-hdds/docs/content/security/SecuringDatanodes.md>
- <https://github.com/apache/ozone/blob/ozone-2.1.0/hadoop-hdds/docs/content/security/SecuringOzoneHTTP.md>
- <https://github.com/apache/ozone/blob/ozone-2.1.0/hadoop-hdds/docs/content/security/SecuringS3.md>

---

[中文文档](README.zh.md)
