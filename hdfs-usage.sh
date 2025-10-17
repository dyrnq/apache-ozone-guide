#!/usr/bin/env bash


hadoop_home="/opt/hadoop"
ozone_home="/opt/ozone"
# hadoop_user="vagrant"
# hadoop_group="vagrant"

sudo_cmd="sudo"

if [ "$(id --user)" = "0" ]; then sudo_cmd=""; fi;

echo "sudo_cmd=$sudo_cmd"

install_hadoop(){
if [ ! -e ${hadoop_home}/bin/hadoop ]; then
pushd /tmp || exit 1
wget https://archive.apache.org/dist/hadoop/common/hadoop-3.4.2/hadoop-3.4.2.tar.gz


${sudo_cmd} mkdir -p ${hadoop_home}
${sudo_cmd} tar -xvf hadoop-3.4.2.tar.gz --strip-components 1 --directory ${hadoop_home}
popd || exit 1
fi



cat <<EOF | ${sudo_cmd} tee /etc/profile.d/my.sh
export HADOOP_HOME=${hadoop_home}
export PATH=\$PATH:\$HADOOP_HOME/libexec:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
EOF
cat < /etc/profile.d/my.sh
}

install_java(){
    ${sudo_cmd} apt install openjdk-21-jdk -y
    java --version
}

config_hadoop(){
if ! grep -E "^export JAVA_HOME" /opt/hadoop/etc/hadoop/hadoop-env.sh; then
cat <<EOF | ${sudo_cmd} tee --append /opt/hadoop/etc/hadoop/hadoop-env.sh
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
EOF
fi

if ! grep -E "^export HADOOP_CLASSPATH" /opt/hadoop/etc/hadoop/hadoop-env.sh; then
cat <<EOF | ${sudo_cmd} tee --append /opt/hadoop/etc/hadoop/hadoop-env.sh
export HADOOP_CLASSPATH=$ozone_home/share/ozone/lib/ozone-filesystem-hadoop3-*.jar:\$HADOOP_CLASSPATH
EOF
fi
# 或者 cp $ozone_home/share/ozone/lib/ozone-filesystem-hadoop3-*.jar $hadoop_home/share/hadoop/common/
########################
cat <<EOF | ${sudo_cmd} tee /opt/hadoop/etc/hadoop/core-site.xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property><name>fs.AbstractFileSystem.o3fs.impl</name><value>org.apache.hadoop.fs.ozone.OzFs</value></property>
<property><name>fs.AbstractFileSystem.ofs.impl</name><value>org.apache.hadoop.fs.ozone.RootedOzFs</value></property>
<property><name>hadoop.security.authentication</name><value>kerberos</value></property>
</configuration>
EOF

cat <<EOF | ${sudo_cmd} tee /opt/hadoop/etc/hadoop/ozone-site.xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property><name>ozone.security.enabled</name><value>true</value></property>
<property><name>ozone.scm.block.client.address</name><value>192.168.69.101</value></property>
<property><name>ozone.om.kerberos.principal</name><value>om/_HOST@EXAMPLE.COM</value></property>
<property><name>ozone.recon.kerberos.principal</name><value>recon/_HOST@EXAMPLE.COM</value></property>
<property><name>hdds.scm.kerberos.principal</name><value>scm/_HOST@EXAMPLE.COM</value></property>
<property><name>ozone.om.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>ozone.metadata.dirs</name><value>/data/metadata</value></property>
<property><name>ozone.recon.address</name><value>o108:9891</value></property>
<property><name>ozone.scm.nodes.cluster1</name><value>scm1,scm2,scm3</value></property>
<property><name>ozone.scm.primordial.node.id</name><value>scm1</value></property>
<property><name>ozone.scm.service.ids</name><value>cluster1</value></property>
<property><name>ozone.s3g.kerberos.principal</name><value>s3g/o108@EXAMPLE.COM</value></property>
<property><name>ozone.scm.address.cluster1.scm1</name><value>192.168.69.101</value></property>
<property><name>ozone.scm.address.cluster1.scm2</name><value>192.168.69.102</value></property>
<property><name>ozone.scm.address.cluster1.scm3</name><value>192.168.69.103</value></property>
<property><name>ozone.scm.names</name><value>o101,o102,o103</value></property>
<property><name>hdds.datanode.kerberos.principal</name><value>dn/dn@EXAMPLE.COM</value></property>
<property><name>ozone.recon.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>hdds.datanode.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>hdds.scm.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>ozone.scm.client.address</name><value>192.168.69.101</value></property>
<property><name>hadoop.security.authentication</name><value>KERBEROS</value></property>
<property><name>ozone.s3g.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>ozone.om.address.cluster1.om1</name><value>192.168.69.101</value></property>
<property><name>ozone.om.address.cluster1.om2</name><value>192.168.69.102</value></property>
<property><name>ozone.om.address.cluster1.om3</name><value>192.168.69.103</value></property>
<property><name>ozone.om.address</name><value>0.0.0.0:9862</value></property>
<property><name>ozone.om.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
<property><name>ozone.om.kerberos.principal</name><value>om/om@EXAMPLE.COM</value></property>
<property><name>ozone.om.nodes.cluster1</name><value>om1,om2,om3</value></property>
<property><name>ozone.om.service.ids</name><value>cluster1</value></property>
</configuration>
EOF


cat <<EOF | ${sudo_cmd} tee /opt/hadoop/etc/hadoop/hdfs-site.xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property><name>dfs.datanode.kerberos.principal</name><value>om/_HOST@EXAMPLE.COM</value></property>
<property><name>dfs.datanode.kerberos.keytab.file</name><value>/etc/security/keytabs/ozone.keytab</value></property>
</configuration>
EOF


if ! grep -E "^export JAVA_HOME" /opt/ozone/etc/hadoop/ozone-env.sh; then
cat <<EOF | ${sudo_cmd} tee --append /opt/ozone/etc/hadoop/ozone-env.sh
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
EOF
fi

cat <<EOF | ${sudo_cmd} tee /opt/ozone/etc/hadoop/core-site.xml
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
<property><name>hadoop.security.authentication</name><value>kerberos</value></property>
</configuration>
EOF

${sudo_cmd} rm -rf /opt/ozone/etc/hadoop/ozone-site.xml
${sudo_cmd} ln -s /opt/hadoop/etc/hadoop/ozone-site.xml /opt/ozone/etc/hadoop/ozone-site.xml

}

install_ozone(){
if [ ! -e ${ozone_home}/bin/ozone ]; then
pushd /tmp || exit 1
rm -rf ozone-2.0.0.tar.gz
wget https://archive.apache.org/dist/ozone/2.0.0/ozone-2.0.0.tar.gz


${sudo_cmd} mkdir -p ${ozone_home}
${sudo_cmd} tar -xvf ozone-2.0.0.tar.gz --strip-components 1 --directory ${ozone_home}
popd || exit 1
fi
}

install_kerberos(){
${sudo_cmd} apt install krb5-user -y;
${sudo_cmd} mkdir -p /etc/security/keytabs
for f in "HTTP.keytab" "ozone.keytab"; do
if [[ $(curl -s -o /dev/null -w "%{http_code}" http://192.168.69.80/${f}) -eq 200 ]]; then
echo "${f} File exists and is accessible"
${sudo_cmd} curl -o /etc/security/keytabs/${f} -f#SL http://192.168.69.80/${f}
else
echo "${f} File does not exist or is not accessible"
fi
done

if ! grep krb5 /etc/hosts; then
cat <<EOF | ${sudo_cmd} tee --append /etc/hosts
192.168.69.80 krb5
EOF
fi

grep krb5 /etc/hosts

echo "https://github.com/apache/ozone/blob/ozone-2.0.0/hadoop-ozone/dist/src/main/compose/ozonesecure/krb5.conf"
cat <<EOF | ${sudo_cmd} tee /etc/krb5.conf
[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_canonicalize_hostname = false
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 default_realm = EXAMPLE.COM

[realms]
 EXAMPLE.COM = {
  kdc = krb5
  admin_server = krb5
 }

[domain_realm]
 .example.com = EXAMPLE.COM
 example.com = EXAMPLE.COM

EOF
(
echo "nc -vz -t krb5 88"
echo "nc -vz -u krb5 88"
echo "kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM"
echo "klist"
echo "hdfs dfs -ls ofs://cluster1/"
)
}

install_awscli(){
pushd /tmp || exit 1;
if [ -f /vagrant/awscliv2.zip ]; then
    /bin/cp --verbose --force /vagrant/awscliv2.zip .
else
curl -f#SL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi

if ! type -P unzip; then
    $sudo_cmd apt install unzip -y;
fi
unzip awscliv2.zip
$sudo_cmd ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
popd || exit 1;
aws --version
}

install_ozone
install_java
install_hadoop
config_hadoop
install_kerberos

install_awscli


# hdfs version
# Hadoop 3.4.2
# Source code repository https://github.com/apache/hadoop.git -r 84e8b89ee2ebe6923691205b9e171badde7a495c
# Compiled by ahmarsu on 2025-08-20T10:30Z
# Compiled on platform linux-x86_64
# Compiled with protoc 3.23.4
# From source with checksum fa94c67d4b4be021b9e9515c9b0f7b6
# This command was run using /opt/hadoop/share/hadoop/common/hadoop-common-3.4.2.jar


# docker run \
# -it \
# --network host \
# --name "hadoop" \
# --add-host o101:192.168.69.101 \
# --add-host o102:192.168.69.102 \
# --add-host o103:192.168.69.103 \
# --add-host o104:192.168.69.104 \
# --add-host o105:192.168.69.105 \
# --add-host o106:192.168.69.106 \
# --add-host o107:192.168.69.107 \
# --add-host o108:192.168.69.108 \
# --add-host krb5:192.168.69.80 \
# -v /vagrant/krb5.conf:/etc/krb5.conf \
# -v /etc/security/keytabs:/etc/security/keytabs \
# apache/hadoop:3.4.1 bash

# vagrant@o211: kinit -kt /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM 
# vagrant@o211:/opt/ozone$ bin/ozone s3 getsecret
# WARNING: HADOOP_HOME has been deprecated by OZONE_HOME.
# awsAccessKey=om/om@EXAMPLE.COM
# awsSecret=60cdb0968faef7c4ef6710904ec48efbb475f93fa3460a032aa40343de525a17

# export AWS_ACCESS_KEY_ID=om/om@EXAMPLE.COM
# export AWS_SECRET_ACCESS_KEY=60cdb0968faef7c4ef6710904ec48efbb475f93fa3460a032aa40343de525a17
# aws s3api --endpoint http://192.168.69.108:9878 create-bucket --bucket bucket2
# An error occurred (500) when calling the CreateBucket operation (reached max retries: 2): Internal Server Error