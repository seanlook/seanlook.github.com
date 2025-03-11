---
title: apache+3tomcat+jk+memcached集群环境搭建
date: 2014-10-29 10:21:25
aliases:
- /2014/10/29/apache-3tomcat-cluster-jk-memcached/
updated: 2015-03-26 00:46:23
tags: [apache, tomcat, 集群, mod_jk, memcached, centos]
categories: [Linux, Web_Server]
---

注意本文不讨论原理，只讲述具体的搭建过程，而且步骤都经过了整理，否则过程可能会出现其他异常，请自行google。apache与tomcat整合的方式除了jk之外，使用apache自带的mod_ajp_proxy模块也可以很方便的完成。
先来看一下架构图：
![apache_tomcat_cluster_msm][1]
属于正式环境中原session复制方案的改进。

# 1. 所需软件包 #
```
jrrt-3.1.2-1.6.0-linux-x64.bin（或jdk1.6.0_33）   jvm
httpd-2.2.26.tar.gz                              web服务器，处理静态资源
apache-tomcat-6.0.32.tar.gz                      应用服务器，Servlet容器处理动态请求
tomcat-connectors-1.2.30-src.tar.gz              apache与tomcat整合插件mod_jk.so
tomcat-native.tar.gz                             APR加速tomcat，提高线程并发能力。使用tomcat自带版本。
memcached-session-manager                        使用msm解决多tomcat集群时session同步问题所需jar包
    asm-3.2.jar, couchbase-client-1.2.2.jar, 
    kryo-1.04.jar, kryo-serializers-0.11.jar
    msm-kryo-serializer-1.6.5.jar
    memcached-session-manager-1.6.5.jar
    memcached-session-manager-tc6-1.6.5.jar
    minlog-1.2.jar, reflectasm-1.01.jar
    spymemcached-2.10.2.jar
```

<!-- more -->

# 2. 安装过程 #
## 2.1 JDK ##
下载将JRockit二进制安装文件，赋予可执行权限
```
# pwd
/apps/test/java
# chmod o+x jrrt*.bin
# ./jrrt-3.1.2-1.6.0-linux-x64.bin
```
可不必为整个linux环境设置`JAVA_HOME="/apps/test/java/jrrt-3.1.2-1.6.0"`，在tomcat中指定即可。

## 2.2 编译安装apache ##
因为`tomcat-native`依赖于apr，所以这里先直接从 httpd-2.2.26/srclib 目录下安装apache自带的`apr`和`apr-util`。
```
[root@cachets httpd-2.2.26]# pwd
/apps/test/soft_src/httpd-2.2.26
[root@test httpd-2.2.26]# cd srclib/apr
[root@test apr]# ./configure --prefix=/usr/local/apr
[root@test apr]# make && make install
[root@test apr]# cd ../apr-util/
[root@test apr-util]# ./configure --prefix=/usr/local/apr-util --with-apr=/usr/local/apr
[root@test apr-util]# make && make install
```
建议将srclib下的`pcre`也装上，主要是考虑后面转发请求时可能要使用地址rewrite，需要正则语法的支持。默认CentOS6.x已经安装了这个库。

安装apache：
```
[root@test httpd-2.2.26]# ./configure --prefix=/apps/test/apache2 --enable-mods-shared=all --enable-modules=so --enable-rewrite --enable-deflate --with-mpm=worker --with-apr=/usr/local/apr --with-apr-util=/usr/local/apr-util
[root@test httpd-2.2.26]# make && make install
```
## 2.3 安装tomcat ##
解压apache-tomcat-6.0.32.tar.gz拷贝至/app/test/tomcat0，不建议使用root用户管理tomcat.
```
[test@cachets soft_src]$ tar -zxvf apache-tomcat-6.0.32.tar.gz
[test@cachets soft_src]$ cp -a apache-tomcat-6.0.32 /app/crm/tomcat0

// 安装tomcat-native（不用单独下载，在tomcat的bin目录中自带）
# yum install -y openssl-devel apr-devel
[root@cachets ~]# cd /app/test/soft_src/apache-tomcat-6.0.32/bin
[root@cachets bin]# tar -zxvf tomcat-native.tar.gz
[root@cachets bin]# cd tomcat-native-1.1.20-src/jni/native/
[root@cachets native]# ./configure --with-apr=/usr/local/apr/bin/apr-1-config --with-ssl --with-java-home=/apps/test/java/jrrt-3.1.2-1.6.0
[root@cachets native]# make && make install
```
配置tomcat：

tomcat默认参数是为开发环境制定，而非适合生产环境，尤其是内存和线程的配置，默认都很低，容易成为性能瓶颈。下面是一些配置示例，需要根据实际需要更改。
```
[crm@cachets tomcat0]$ vi bin/setenv.sh
JAVA_OPTS="-XX:PermSize=128M -XX:MaxPermSize=256M -Xms1536M -Xmx2048M -verbosegc "
CATALINA_OPTS="-Dcom.sun.management.jmxremote.port=7091 -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.authenticate=false -Djava.rmi.server.hostname=192.168.10.100"
JAVA_HOME="/apps/test/java/jrrt-3.1.2-1.6.0"
CATALINA_OPTS="$CATALINA_OPTS -Djava.library.path=/usr/local/apr/lib"
[crm@cachets tomcat0]$ chmod 755 bin/setenv.sh
```
bin目录下新建的可执行文件`setenv.sh`会由tomcat自动调用。上面的`jmxremote.authenticate`在正式环境中请务必设为true并设置用户名/密码，减少安全隐患，或者注释掉`CATALINA_OPTS`。（有时候出于性能调优的目的，才需要设置JMX）。对于具体的连接协议有不同的优化属性，参考如下：
对HTTP：

    <Connector port="8080" 
               protocol="org.apache.coyote.http11.Http11NioProtocol"
               URIEncoding="UTF-8"
               enableLookups="false"

               maxThreads="400"
               minSpareTheads="50"   
               acceptCount="400"
               acceptorThreadCount="2"              
               connectionTimeout="30000" 
               disableUploadTimeout="true"

               compression="on"
               compressionMinSize="2048"
               maxHttpHeaderSize="16384"
               redirectPort="8443"
     />
对AJP：

    <Connector port="8009" protocol="AJP/1.3" 
               maxThreads="300" minSpareThreads="50"
               connectionTimeout="30000"
               keepAliveTimeout="30000"
               acceptCount="200"
               URIEncoding="UTF-8"
               enableLookups="false"
               redirectPort="8443" />
## 2.4 安装jk ##
```
[crm@test soft_src]$ tar -zxvf tomcat-connectors-1.2.30-src.tar.gz
[crm@test soft_src]$ cd tomcat-connectors-1.2.30-src/native
[root@test native]# ./configure --with-apxs=/apps/test/apache2/bin/apxs
[root@test native]# make && make install
```
此时可以看到在`/apps/test/apache2/modules`下有`mod_jk.so`文件，用于连接apache与tomcat。

## 2.5 配置（集群）负载均衡选项 ##
### 2.5.1 apache ###
建立配置文件`httpd-jk.conf`：
```
[root@cachets ~]# cd /app/test/
[root@cachets crm]# vi apache2/conf/extra/httpd-jk.conf
# Load mod_jk module
LoadModule jk_module modules/mod_jk.so
# 指定保存了worker相关工作属性定义的配置文件
JkWorkersFile conf/extra/workers.properties
# Specify jk log file
JkLogFile /app/test/apache2/logs/mod_jk.log
# Specify jk log level [debug/error/info]
JkLogLevel info
#指定哪些请求交给tomcat处理,"controller"为在workers.properties里指定的负载分配控制器名

JkMount /servlet/* controller
JkMount /*.jsp controller
JkMount /*.do controller

// 在conf/httpd.conf最后加上
Include conf/extra/httpd-vhosts.conf
Include conf/extra/httpd-jk.conf
```
建立工作文件`workers.properties`：
```
[root@cachets crm]# vi apache2/conf/extra/workers.properties
# servers
worker.list=controller
# ====== tomcat0 =======
worker.tomcat0.port=8009
worker.tomcat0.host=192.168.10.100
worker.tomcat0.type=ajp13
worker.tomcat0.lbfactor=1
# ====== tomcat1 =======
worker.tomcat1.port=8109
worker.tomcat1.host=192.168.10.100
worker.tomcat1.type=ajp13
worker.tomcat1.lbfactor=1
# ====== tomcat2 =======
worker.tomcat2.port=8209
worker.tomcat2.host=192.168.10.100
worker.tomcat2.type=ajp13
worker.tomcat2.lbfactor=1
# ====== controller ====
worker.controller.type=lb
worker.controller.balance_workers=tomcat0,tomcat1,tomcat2
worker.controller.sticky_session = 1
```
以上是3个tomcat的做负载均衡的情况，负载因子`lbfactor`都为1，session为sticky模式，apache与tomcat连接的协议采用AJP/1.3，同一台服务器上通过端口来区分tomcat0/tomcat1/tomcat2。

### 2.5.2 tomcat ###
在`tomcat0/conf/server.xml`中加入`jvmRoute`属性，这个属性与上面的`workers.properties`的worker相同：
```
<Engine name="Catalina" defaultHost="localhost" jvmRoute="tomcat0">
```
设置测试应用的访问路径，在`tomcat0/conf/server.xml`的`<Host>`节点下添加如下：
```
<Context path="" docBase="/apps/test/testapp/TEST" reloadable="true" />
```
### 2.5.3 app-TEST ###
为了看到负载均衡的效果，在`/apps/test/testapp/TEST`目录下建立测试页面test.jsp：
```
<%@ page contentType="text/html; charset=UTF-8" %>
<%@ page import="java.util.*" %>
<html><head><title>Cluster App Test</title></head>
<body>
Server Info:
<%
out.println(request.getLocalAddr() + " : " + request.getLocalPort()+"<br>");%>
<%
  out.println("<br> ID " + session.getId()+"<br>");
  // 如果有新的 Session 属性设置
  String dataName = request.getParameter("dataName");
  if (dataName != null && dataName.length() > 0) {
     String dataValue = request.getParameter("dataValue");
     session.setAttribute(dataName, dataValue);
  }
  out.println("<b>Session 列表</b><br>");
  System.out.println("============================");
  Enumeration e = session.getAttributeNames();
  while (e.hasMoreElements()) {
     String name = (String)e.nextElement();
     String value = session.getAttribute(name).toString();
     out.println( name + " = " + value+"<br>");
         System.out.println( name + " = " + value);
   }
%>
  <form action="test.jsp" method="POST">
    CRM <br>
    名称:<input type=text size=20 name="dataName">
     <br>
    值:<input type=text size=20 name="dataValue">
     <br>
    <input type=submit>
   </form>
</body>
</html>
```
到这里还差一步就可以看到集群的效果，那就是3个tomcat之间session同步的问题。可以通过打开`<Engine>`节点下的`<Cluster>`标签的注释来简单的实现session复制：

      <Cluster className="org.apache.catalina.ha.tcp.SimpleTcpCluster"/>

然后在`tomcat0/conf/web.xml`的`<webapp>`根节点下加入`<distributable />`

复制tomcat0到tomcat1、tomcat2，修改<Server> <Connector>的端口避免冲突，修改对应的jvmRoute

启动apache和3个tomcat，就可以看到效果。但这里我们使用`memcached-session-manager`来同步session，所以不必打开`<Cluster>`这一步。

## 2.6 memcached-session-manager配置 ##
### 2.6.1 安装memcached服务器 ###
这里memcached搭建在另外一台服务器上（192.168.10.20），也可以安装在本地。
```
[root@cachets msm]# yum install libevent libevent-devel
[root@cachets msm]# tar -zxvf memcached-1.4.19.tar.gz
[root@cachets msm]# cd memcached-1.4.19 && ./configure && make && make install

// 启动两个memcached节点，端口分别为11211、11212
[root@cachets ~]#memcached -d -m 64 -p 11211 -u daemon -P /var/run/memcached.pid 
[root@cachets ~]#memcached -d -m 64 -p 11212 -u daemon -P /var/run/memcached2.pid 
```
如果开启了防火墙，需要加入11211、11212端口的允许规则。

### 2.6.2 再次配置tomcat ###
加入jar包

将`asm-3.2.jar`, `couchbase-client-1.2.2.jar`, `kryo-1.04.jar`, `kryo-serializers-0.11.jar`, `msm-kryo-serializer-1.6.5.jar`, `memcached-session-manager-1.6.5.jar`, `memcached-session-manager-tc6-1.6.5.jar`, `minlog-1.2.jar`, `reflectasm-1.01.jar`, `spymemcached-2.10.2.jar`这些jar包加入tomcat0/lib/下。可以看到这里选用的session序列化策略采用的是kryo。另外要注意版本之间的兼容性，这里只针对tomcat6.x。
修改`conf/server.xml`：

将<Context>节点修改成：

       <Context path="" docBase="/apps/test/testapp/TEST" reloadable="true" >
          <Manager className="de.javakaffee.web.msm.MemcachedBackupSessionManager"
             memcachedNodes="n1:192.168.10.20:11211,n2:192.168.10.20:11212"
             failoverNodes="n1"
             sticky="true"
             requestUriIgnorePattern=".*\.(png|gif|jpg|css|js)$"
             sessionBackupAsync="false"
             sessionBackupTimeout="100"
             transcoderFactoryClass="de.javakaffee.web.msm.serializer.kryo.KryoTranscoderFactory"
             copyCollectionsForSerialization="false" />
       </Context>
接着将tomcat0完整的复制2份（tomcat1，tomcat2），也可以放到另外一台服务器上。
修改为`workers.properties`中定义的AJP等端口：

|node tomcat    |Server port    |Connector port http |Connector port ajp    |Engine jvmRoute  |memcached failoverNodes|
|----------|-------|-------|-------|--- -------|--|
|tomcat0   |8005   |8080   |8009   |tomcat0    |n1|
|tomcat1   |8105   |8081   |8109   |tomcat1    |n1|
|tomcat2   |8205   |8082   |8209   |tomcat2    |n2|

# 3. 测试 #
分别启动tomcat0、tomcat1、tomcat2和apache，注意观察tomcat的启动日志和memcached服务器的日志。
```
[test@cachets ~]$ /apps/test/tomcat0/bin/startup.sh
[test@cachets ~]$ /apps/test/tomcat1/bin/startup.sh
[test@cachets ~]$ /apps/test/tomcat2/bin/startup.sh
[root@cachets ~]# /apps/test/apache2/bin/apachectl start
```
在浏览器访问`http://192.168.10.100/test.jsp`。主要测试负载均衡与session共享。


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/apache_tomcat_cluster_msm.png


**参考**

- https://people.apache.org/~mturk/docs/article/ftwai.html


---

原文链接地址：http://xgknight.com/2015/04/23/pfsense-usage/

---
