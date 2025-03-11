---
title: php5.3连接oracle的客户端及pdo_oci模块安装
date: 2015-03-10 01:21:25
aliases:
- /2015/03/10/install-pdo-oci-oci8-phpext/
updated: 2015-03-10 10:46:23
tags: [oracle, php]
categories: Linux
---

php连接oracle数据库虽然不是最佳拍档，但组内开发确实有这样需求。如果没有参考合适的文档，这个过程还是挺折磨人的，下面是一个记录，原型是国外的一篇博客 [Installing PDO_OCI and OCI8 PHP extensions on CentOS 6.4 64bit](http://shiki.me/blog/installing-pdo_oci-and-oci8-php-extensions-on-centos-6-4-64bit/)。

假设你已经安装好php的环境，php版本为5.3，要连接的oracle服务器是 11g R2，操作系统版本CentOS 6.4 x86_64。如果没有安装php，可以通过以下命令安装：
```
# yum install php php-pdo
# yum install php-devel php-pear php-fpm php-gd php-ldap \
php-mbstring php-xml php-xmlrpc  php- zlib zlib-devel bc libaio glibc
```
假如web服务器使用apache。

## 1. 安装InstantClient ##
instantclient是oracle的连接数据库的简单客户端，不用安装一个500Moracle客户端就可以连接oracle数据库，有windows和linux版本。从 [这里](http://www.oracle.com/technetwork/topics/linuxx86-64soft-092277.html) 选择需要的版本下载，只需Basic和Devel两个rpm包。
```
安装
# rpm -ivh oracle-instantclient11.2-basic-11.2.0.4.0-1.x86_64.rpm
# rpm -ivh oracle-instantclient11.2-devel-11.2.0.4.0-1.x86_64.rpm

软链接
# ln -s /usr/include/oracle/11.2/client64 /usr/include/oracle/11.2/client
# ln -s /usr/lib/oracle/11.2/client64 /usr/lib/oracle/11.2/client
```
64位系统需要创建32位的软链接，这里可能是一个遗留bug，不然后面编译会出问题。

接下来还要让系统能够找到oracle客户端的库文件，修改LD_LIBRARY_PATH：
```
# vi /etc/profile.d/oracle.sh
export ORACLE_HOME=/usr/lib/oracle/11.2/client64
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
```

执行`source /etc/profile.d/oracle.sh`使环境变量生效。

<!-- more -->

## 2. 安装PDO_OCI ##
在连接互联网的情况下，通过pecl在线安装php的扩展非常简单，参考 [How to install oracle instantclient and pdo_oci on ubuntu machine](http://stackoverflow.com/questions/21936091/how-to-install-oracle-instantclient-and-pdo-oci-on-ubuntu-machine) 。

从https://pecl.php.net/package/PDO_OCI下载 PDO_OCI-1.0.tgz 源文件。
```
# wget https://pecl.php.net/get/PDO_OCI-1.0.tgz
# tar -xvf PDO_OCI-1.0.tgz
# cd PDO_OCI-1.0
```
由于PDO_OCI很久没有更新，所以下面需要编辑`ODI_OCI-1.0`文件夹里的`config.m4`文件来让它支持11g：
```
# 在第10行左右找到与下面类似的代码，添加这两行：
elif test -f $PDO_OCI_DIR/lib/libclntsh.$SHLIB_SUFFIX_NAME.11.2; then
  PDO_OCI_VERSION=11.2

# 在第101行左右添加这几行：
11.2)
  PHP_ADD_LIBRARY(clntsh, 1, PDO_OCI_SHARED_LIBADD)
  ;;
```

编译安装pdo_oci扩展：（安装完成后可在 /usr/lib64/php/modules/pdo_oci.so 找到这个模块）
```
$ phpize
$ ./configure --with-pdo-oci=instantclient,/usr,11.2
$ make
$ sudo make install
```

要启用这个扩展，在`/etc/php.d/`下新建一个`pdo_oci.ini`文件，内容：
```
extension=pdo_oci.so
```
验证安装成功：
```
# php -i|grep oci
看到类似下面的内容则安装成功:
/etc/php.d/pdo_oci.ini,
PDO drivers => oci, sqlite

或
# php -m
```

## 3. 安装OCI8 ##
从 https://pecl.php.net/package/oci8 下载oci8-2.0.8.tgz源文件。
```
# wget https://pecl.php.net/get/oci8-2.0.8.tgz
# tar -xvf oci8-2.0.8.tgz
# cd oci8-2.0.8
```
编译安装oci8扩展：
```
# phpize
# ./configure --with-oci8=shared,instantclient,/usr/lib/oracle/11.2/client64/lib
# make
# make install
```

要启用这个扩展，在`/etc/php.d/`下新建一个`oci8.ini`文件，内容：
```
extension=oci8.so
```
验证安装成功：
```
# php -i|grep oci8
/etc/php.d/oci8.ini,
oci8
oci8.connection_class => no value => no value
oci8.default_prefetch => 100 => 100
oci8.events => Off => Off
oci8.max_persistent => -1 => -1
oci8.old_oci_close_semantics => Off => Off
oci8.persistent_timeout => -1 => -1
oci8.ping_interval => 60 => 60
oci8.privileged_connect => Off => Off
oci8.statement_cache_size => 20 => 20
OLDPWD => /usr/local/src/oci8-2.0.8
_SERVER["OLDPWD"] => /usr/local/src/oci8-2.0.8
```

最后别忘了重启逆web服务器如apache，可以通过phpinfo()来确保扩展是否成功安装。

## 4. 测试连接 ##
在你web服务器如apache的php目录下创建`testoci.php`：
```
<?php

$conn = oci_connect('username', 'password', '172.29.88.178/DBTEST');

$stid = oci_parse($conn, 'select table_name from user_tables');
oci_execute($stid);

echo "<table>\n";
while (($row = oci_fetch_array($stid, OCI_ASSOC+OCI_RETURN_NULLS)) != false) {
    echo "<tr>\n";
    foreach ($row as $item) {
        echo "  <td>".($item !== null ? htmlentities($item, ENT_QUOTES) : "&nbsp;")."</td>\n";
    }
    echo "</tr>\n";
}
echo "</table>\n";

?>
```
访问这个页面就应该可以得到结果了。

**参考**

- [Installing PDO_OCI and OCI8 PHP extensions on CentOS 6.4 64bit](http://shiki.me/blog/installing-pdo_oci-and-oci8-php-extensions-on-centos-6-4-64bit/)
- [在 Linux 和 Windows 上安装 PHP 和 Oracle Instant Client](http://www.oracle.com/technetwork/cn/articles/dsl/technote-php-instant-090922-zhs.html)
- [php5.3安装oracle的扩展oci8与pdo_oci](http://iceeggplant.blog.51cto.com/1446843/1052512)
