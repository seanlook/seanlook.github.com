---
title: OpenLDAP(2.4.3x)服务器搭建及配置说明
date: 2015-01-21 01:21:25
updated: 2015-01-21 10:46:23
tags: [LDAP, slapd]
categories: [Linux, OpenLDAP]
---

本文采用的是从源码编译安装，适合Ubuntu和CentOS平台，通过`apt-get`或`yum`方式安装参考补充部分。openldap原理介绍参考[这里](http://xgknight.com/2015/01/15/openldap_introduction/)。

环境：
Ubuntu: 14.04.1 (trusty), x86_64
OpenLDAP: 2.4.31
Berkery DB: 5.1.29

# 1 安装 #
## 1.1 准备编译环境和依赖包 ##
```
# apt-get install build-essential
# apt-get install libssl-dev
```

下载[`openldap-2.4.31.tgz`](ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-2.4.31.tgz)和[`db-5.1.29.NC.tar.gz`](http://download.oracle.com/berkeley-db/db-5.1.29.NC.tar.gz)并解压：

```
# cd /usr/local/src
src# wget ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-2.4.31.tgz
# wget http://download.oracle.com/berkeley-db/db-5.1.29.NC.tar.gz
# tar -zxf openldap-2.4.31.tgz
# tar -zxf db-5.1.29.NC.tar.gz

# cd db-5.1.29.NC/build_unix/
# ../dist/configure --prefix=/usr/local/berkeleydb-5.1
# make && make install
```

建议人工指定`--prefix`，默认会安装到`/usr/local/BerkeleyDB.5.1`。上面的`make`过程会比较长，另外如果gcc版本在4.7及以上，可能会出现如下[warning](http://osdir.com/ml/freebsd-current/2012-05/msg00050.html)，可以忽略：
```
../src/dbinc/atomic.h:179:19: warning: conflicting types for built-in function
 ‘__atomic_compare_exchange’ [enabled by default]
```

## 1.2 安装openldap ##
设置一些环境变量，修改`/etc/profile`或`/etc/bash.bashrc`：

<!-- more -->

```
export BERKELEYDB_HOME="/usr/local/berkeleydb-5.1"
export CPPFLAGS="-I$BERKELEYDB_HOME/include"
export LDFLAGS="-L$BERKELEYDB_HOME/lib"
export LD_LIBRARY_PATH="$BERKELEYDB_HOME/lib"

export LDAP_HOME="/usr/local/openldap-2.4"
export PATH="$PATH:$BERKELEYDB_HOME/bin:$LDAP_HOME/bin:$LDAP_HOME/sbin:$LDAP_HOME/libexec"
```
其实只要在后面编译openldap时能找到`lib`和`include`下的库就行了，不止上面设置环境变量一种办法，解决办法还有直接复制对应的库文件到`/usr/lib`和`/usr/include`，或修改`/etc/ld.so.conf.d`，选其一即可。

编译安装：
```
openldap-2.4.31# ./configure --prefix=/usr/local/openldap-2.4
# make depend
# make
# make install
```

出错提示解决：

如果没设置`CPPFLAGS`，上面的configure过程可能会提示`configure: error: BDB/HDB: BerkeleyDB not available`。

如果提示
```
configure: error: MozNSS not found - please specify the location to the NSPR and NSS header files 
in CPPFLAGS and the location to the NSPR and NSS libraries in LDFLAGS (if not in the system location)
```
或
```
configure: error: no acceptable C compiler found in $PATH
```
请检查第一步的依赖是否已经安装，查看openldap解压目录下的`README`看到REQUIRED SOFTWARE。
# 2 配置 #
## 2.1 基本配置 ##
`/usr/local/openldap-2.4`目录结构：
```
  bin/      --客户端工具如ldapadd、ldapsearch
  etc/      --包含主配置文件slapd.conf、schema、DB_CONFIG等
  include/
  lib/
  libexec/  --服务端启动工具slapd
  sbin/     --服务端工具如slappasswd
  share/
  var/      --bdb数据、log存放目录
```
### 2.1.1 配置root密码 ###
```
# slappasswd 
New password: 
Re-enter new password: 
{SSHA}phAvkua+5B7UNyIAuoTMgOgxF8kxekIk
```
### 2.1.2 修改后的slapd.conf ###
```
include		/usr/local/openldap-2.4.31/etc/openldap/schema/core.schema
include		/usr/local/openldap-2.4.31/etc/openldap/schema/cosine.schema
include		/usr/local/openldap-2.4.31/etc/openldap/schema/inetorgperson.schema

pidfile		/usr/local/openldap-2.4.31/var/run/slapd.pid
argsfile	/usr/local/openldap-2.4.31/var/run/slapd.args

loglevel 256
logfile  /usr/local/openldap-2.4.31/var/slapd.log 

database	bdb
suffix		"dc=mydomain,dc=net"
rootdn		"cn=root,dc=mydomain,dc=net"
rootpw		{SSHA}UK4eGUq3ujR1EYrOL2MRzMBJmo7qGyY3
directory	/usr/local/openldap-2.4.31/var/openldap-data
index	objectClass	eq
```
根据自己的需要加入schema，suffix一般填入域名，rootdn处是管理ldap数据的管理员用户，rootpw便是使用slappasswd生成的加密密码。

### 2.1.3 启动slapd服务 ###
```
# /usr/local/openldap-2.4.31/libexec/slapd
```
会自动使用`etc/openldap/slapd.conf`作为配置文件启动，并写入`/usr/local/openldap-2.4.31/var/run/slapd.args`中。这里有个问题未解决，配置loglevel和logfile但始终都看不到记录的日志，启动时加入`-d 256`能正常输出到屏幕上。

### 2.1.4 测试数据 ###

编辑一个添加entries的文件test.ldif：
```
dn: dc=mydomain,dc=net
objectClass: dcObject
objectClass: organization
dc: mydomain
o: mydomain.Inc

dn: cn=root,dc=mydomain,dc=net
objectClass: organizationalRole
cn: root

dn: ou=itsection,dc=mydomain,dc=net
ou: itsection
objectClass: organizationalUnit

dn: cn=sean,ou=itsection,dc=mydomain,dc=net
ou: itsection
cn: sean
sn: zhouxiao
objectClass: inetOrgPerson
objectClass: organizationalPerson
```

插入数据：
```
查看（匿名）
# ldapsearch -x -b '' -s base '(objectclass=*)' namingContexts

添加（读入密码）
# ldapadd -x -D "cn=root,dc=mydomain,dc=net" -W -f test.ldif

验证
# ldapsearch -x -b 'dc=mydomain,dc=net' '(objectClass=*)'

或手动添加条目
# ldapadd -x -D "cn=root,dc=mydomain,dc=net" -W
Enter LDAP Password: 
dn:cn=Angelababy,ou=itsection,dc=mydomain,dc=net
cn:Angelababy
sn:baby  
objectClass:inetOrgPerson
objectClass:organizationalPerson

adding new entry "cn=baby,ou=itsection,dc=mydomain,dc=net"
```
到这里，一个简易版的LDAP服务就搭建好了，下面介绍一些额外的高级配置。

## 2.2 配置TLS加密传输 ##
在某些应用环境下可能需要加密传输ldap里的信息，配置TLS难点在于证书的生成。关于SSL加密证书的介绍请参考[ssl-tls](http://xgknight.com/2015/01/18/openssl-self-sign-ca)，下面我们自己搭建CA，快速自签署ssl证书。

### 2.2.1 自签署ssl证书 ###
```
(1) 生成根密钥
# cd /etc/ssl/demoCA/
# openssl genrsa -out private/cakey.pem 2048

(2) 生成根证书，位于/etc/ssl/demoCA/下（CentOS位于/etc/pki/CA）
# openssl req -new -x509 -key private/cakey.pem -out cacert.pem

(3) 初始化CA
demoCA# mkdir private newcerts
# touch newcerts index.txt serial
# echo "00" > serial

(4) 在ldap服务器上生成ssl密钥（可以是/tmp/certs下）
# openssl genrsa -out ldap.key

(5) 为ldap生成证书签署请求（所填写内容尽量与第2步相同）
    Common Name填写主机名或域名，password留空
# openssl req -new -key ldap.key -out ldap.csr

(6) ca根据请求签发证书，得到.crt证书文件
# openssl ca -in ldap.key -out ldap.crt
```
如果在你的环境中已经有一个证书授权中心CA，那么只需要在ldap服务器上使用openssl生成密钥`.key`和签署请求`.csr`（第4、5步），然后将.csr发给CA服务器来生成证书`.crt`（第6步）。

### 2.2.2 在slapd.conf中加入TLS ###
```
可以是其它能访问的位置
# mkdir $OPENLDAP_HOME/etc/openldap/cacerts
# cp cacert.pem $OPENLDAP_HOME/etc/openldap/cacerts
# cp ldap.crt $OPENLDAP_HOME/etc/openldap/
# cp ldap.key $OPENLDAP_HOME/etc/openldap/

在etc/openldap/slapd.conf中加入以下信息
TLSCACertificateFile /usr/local/openldap-2.4/etc/openldap/cacerts/cacert.pem
TLSCertificateFile /usr/local/openldap-2.4/etc/openldap/ldap.crt
TLSCertificateKeyFile /usr/local/openldap-2.4/etc/openldap/ldap.key
```

### 2.2.3 重新启动slapd ###
```
# killall slapd     关闭slapd standalone daemon
# ./libexec/slapd -h 'ldap://0.0.0.0:389/ ldaps://0.0.0.0:636/ ldapi:///'
或只监听636加密端口
# ./libexec/slapd -h 'ldaps://0.0.0.0:636/'
```
如果是正式环境使用加密的话，389端口前的IP换成127.0.0.1。

### 2.2.4 验证 ###
**ldapsearch**
使用自带的ldapsearch或ldapadd客户端工具来连接slapd，需要设置`ldap.conf`或`~/.ldaprc`文件中的`TLS_CACERT`为信任的根证书才能使用，否则会提示
```
TLS certificate verification: Error, self signed certificate in certificate chain
TLS trace: SSL3 alert write:fatal:unknown CA
```
所以在在使用ldapsearch的服务器上修改`/etc/ldap/ldap.conf`：（`man ldap.conf`）
    
    BASE    dc=mydomain,dc=net
    URI     ldaps://apptest.mydomain.net:636
    TLS_CACERT /usr/local/openldap-2.4/etc/openldap/cacerts/cacert.pem
（当然也可以`TLS_REQCERT never`来信任根证书）

使用：
    
    ldapsearch -x -D "cn=root,dc=mydomain,dc=net" -W -LLL
    或写全
    ldapsearch -x -b 'dc=mydomain,dc=net' '(objectClass=*)' -H ldaps://apptest.mydomain.net:636 -D "cn=root,dc=mydomain,dc=net" -W
    
需要注意的是，`URI`后的 Server name 必须与签署证书使用的 Common name 一致。另外在ldap server本地执行ldapsearch默认使用的客户端配置文件是`$LDAP_HOME/etc/openldap/ldap.conf`。

**LDAPBrower**
另外一种方式是使用第三方LDAP客户端连接工具，如LDAPBrower：

连接：
![ldaps_conn_session][1]

信任根证书：
![ldaps_trust_ca.png][2]

查看（可Add entries）：
![ldaps_browser][3]

# 3 补充 #
## 3.1 apt-get安装 ##
通过`apt-get`在Ubuntu上安装OpenLDAP。
```
# dpkg -l|grep libdb    查看berkeleydb是否安装
# apt-get install slapd ldap-utils
```
安装过程中会提示输入admin密码。

安装完成后默认已经启动了slapd进程，与自己手动编译不同的是默认采用的配置文件有点区别：
```
# ps -ef|grep slapd
... /usr/sbin/slapd -h ldap:/// ldapi:/// -g openldap -u openldap -F /etc/ldap/slapd.d
```

`/etc/ldap/slapd.d` 是2.4.x版本新采用的配置文件目录，但手动编辑`slapd.d`目录下`ldif`是非常痛苦的，如果你不习惯新的配置目录格式，你可以通过修改`/etc/default/slapd`中的`SLAPD_CONF=`为`SLAPD_CONF="/etc/ldap/slapd.conf"`。

`slapd.conf`配置形式官方已经废弃了但依然支持，你还可以选择在编辑完熟悉的`slapd.conf`后使用openldap提供的slaptest工具将它转换成`slapd.d`配置目录：
```
# mv /etc/ldap/slapd.d{,.dist}      先删除（备份）原目录
# slaptest -f /etc/ldap/slapd.conf -F /etc/ldap/slapd.d/  转换成新的配置目录格式
# chown -R openldap:openldap /etc/ldap/slapd.d/     修改权限
```
## 3.2 slapd-config配置形式的说明 ##
我们把就的配置方式叫`slapd.conf`，新的配置方式叫`slapd-config`或olc（OpenLDAP Configuration，也可以理解为online config）。`slapd.d`目录内包含许多ldif文件，就是`slapd.conf`中的内容转化成ldif格式，以构成一棵根为`cn=config`的目录树，这棵树包含了许多结点，如：`cn=module{0}`, `cn=schema`, `olcDatabase={1}bdb`……所有配置信息就是这些结点的属性。结构如下图：
![openldap_config_dit][4]

使用这种新的配置目录的好处在于：

1. 通过Overlay截获修改这些目录属性的信息，然后对相应的数据结构进行修改，即管理员可以像修改其它目录属性一样修改`cn=config`目录树下的目录信息，并且修改后即时生效，无需重启服务器。
2. 管理员不用像以前那样对服务器的配置文件进行修改，而是可以在任何能够连上ldap服务器的地方对配置文件内容进行修改，没有地域的限制。

但是当你需要配置多个backend时，`slapd-config`方式需要2.4.33版本以后才支持，此前的版本还只能使用`slapd.conf`方式。

LDIF配置格式大致如下：
```
# global configuration settings
dn: cn=config
objectClass: olcGlobal
cn: config
<global config settings>

# schema definitions
dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema
<system schema>

dn: cn={X}core,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: {X}core
<core schema>

# additional user-specified schema
...

# backend definitions
dn: olcBackend=<typeA>,cn=config
objectClass: olcBackendConfig
olcBackend: <typeA>
<backend-specific settings>

# database definitions
dn: olcDatabase={X}<typeA>,cn=config
objectClass: olcDatabaseConfig
olcDatabase: {X}<typeA>
<database-specific settings>

# subsequent definitions and settings
...
```
我们有时候会发现ldif里面会有一些条目是带`{0}`这样的数字，这是因为ldap数据库本身是无序的，这些索引一样的数字是用来强制一些依赖于其他配置的设置能够按照正确的顺序先后生效。不过它不用我们去关心，在添加entries时如果有需要会自动生成。

ldif文件中大部分属性和objectClass是以`olc`开头的，与就的配置风格`slapd.conf`有着一对一的属性配置选项，如`olcDatabase: {1}hdb`与`database  bdb`对应。

更多内容请参考 [OpenLDAP Software 2.4 Administrator's Guide](http://www.openldap.org/doc/admin24/slapdconf2.html) 。
![ldap_slapd_config][5]

## 3.3 slapd-config修改示例(LDIF) ##

见 [LDIF修改ldap记录或配置示例](http://xgknight.com/2015/01/22/openldap_ldif_example/)。

## 3.4 LDAP访问控制示例 ##
待续

## 3.5 OpenLDAP复制配置（replication） ##
待续

# 4 参考 #

- [Install and Configure an OpenLDAP Server with SSL on Debian Wheezy](https://www.lisenet.com/2014/install-and-configure-an-openldap-server-with-ssl-on-debian-wheezy/)
- [openldap doc quickstart](http://www.openldap.org/doc/admin24/quickstart.html)
- [OpenLDAP的安装和配置(含TLS和复制）](http://my.oschina.net/aiguozhe/blog/151554)
- [openldap学习笔记(安装配置openldap-2.3.32)](http://huizhen.blog.51cto.com/382964/100328)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_conn_session.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_trust_ca.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_browser.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_config_dit.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/ldap_slapd_config.png
