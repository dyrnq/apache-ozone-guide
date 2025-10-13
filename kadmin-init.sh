#!/usr/bin/env sh
## 参考 https://www.cnblogs.com/longtds/p/18581922
# 添加管理员
# kadmin.local addprinc -pw admin@example admin/admin@EXAMPLE.COM

# 创建ozone服务使用的princ
kadmin.local -q "addprinc -randkey scm/scm@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey om/om@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey s3g/s3g@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey recon/recon@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey dn/dn@EXAMPLE.COM"

# 生成princ对应的keytab文件
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab scm/scm@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab om/om@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab s3g/s3g@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab recon/recon@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab dn/dn@EXAMPLE.COM"

# 为ozone中http服务生成princ
kadmin.local -q "addprinc -randkey HTTP/scm@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey HTTP/om@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey HTTP/s3g@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey HTTP/recon@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey HTTP/dn@EXAMPLE.COM"

# 生成keytab文件，注意必须命名为HTTP.keytab（官方文档和测试中验证）
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/scm@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/om@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/s3g@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/recon@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/dn@EXAMPLE.COM"



for _HOST in "o101" "o102" "o103" "o104" "o105" "o106" "o107" "o108"; do
echo $_HOST;
kadmin.local -q "addprinc -randkey scm/$_HOST@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey om/$_HOST@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey s3g/$_HOST@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey recon/$_HOST@EXAMPLE.COM"
kadmin.local -q "addprinc -randkey dn/$_HOST@EXAMPLE.COM"

# 生成princ对应的keytab文件
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab scm/$_HOST@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab om/$_HOST@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab s3g/$_HOST@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab recon/$_HOST@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/ozone.keytab dn/$_HOST@EXAMPLE.COM"
done

for _HOST in "o101" "o102" "o103" "o104" "o105" "o106" "o107" "o108"; do
echo $_HOST;
kadmin.local -q "addprinc -randkey HTTP/$_HOST@EXAMPLE.COM"
kadmin.local -q "ktadd -k /etc/security/keytabs/HTTP.keytab HTTP/$_HOST@EXAMPLE.COM"
done