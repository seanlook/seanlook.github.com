---
title: 搭建docker内网私服（docker-registry with nginx&ssl on centos）
date: 2014-11-13 20:21:25
updated: 2014-12-25 15:46:23
tags: [docker, centos, docker-registry, nginx, ssl]
categories: [Virtualization, Docker]
---
主要思路：
![docker-registry-deploy][1]

## 1. Docker Registry 说明 ##
关于如何创建和使用本地仓库，其实已经有很多文章介绍了。因为docker技术正处于发展和完善阶段，所以有些文章要么内容已经过时，要么给出了错误的配置，导致无法正常创建仓库。本文记录的是个人完整的搭建过程，`docker version`为1.1.2。

官方提供了[Docker Hub](https://registry.hub.docker.com/)网站来作为一个公开的集中仓库。然而，本地访问Docker Hub速度往往很慢，并且很多时候我们需要一个本地的私有仓库只供网内使用。

Docker仓库实际上提供两方面的功能，一个是镜像管理，一个是认证。前者主要由[docker-registry](https://github.com/docker/docker-registry)项目来实现，通过http服务来上传下载；后者可以通过docker-index（闭源）项目或者利用现成认证方案（如nginx）实现http请求管理。

docker-registry既然也是软件应用，自然最简单的方法就是使用官方提供的已经部署好的镜像registry。官方文档中也给出了建议，直接运行`sudo docker run -p 5000:5000 registry`命令。这样确实能启动一个registry服务器，但是所有上传的镜像其实都是由docker容器管理，放在了/var/lib/docker/....某个目录下。而且一旦删除容器，镜像也会被删除。因此，我们需要想办法告诉docker容器镜像应该存放在哪里。registry镜像中启动后镜像默认位置是`/tmp/registry`，因此直接映射这个位置即可，比如到本机的`/opt/data/registry`目录下。

<!-- more -->

## 2. 在CentOS上搭建docker私服 ##
### 2.1 安装`docker-registry` ###
方法有多种，直接运行下面的命令：
```
# docker run -d -e SETTINGS_FLAVOR=dev -e STORAGE_PATH=/tmp/registry -v /opt/data/registry:/tmp/registry  -p 5000:5000 registry
```
如果本地没有拉取过docker-registry，则首次运行会pull registry，运行时会映射路径和端口，以后就可以从`/opt/data/registry`下找到私有仓库都存在哪些镜像，通过主机的哪个端口可以访问。
你也可以把项目 https://github.com/docker/docker-registry.git 克隆到本地，然后使用Dockerfile来build镜像：
```
# git clone https://github.com/docker/docker-registry.git
# cd docker-registry && mkdir -p /opt/data/registry
# docker build -t "local-sean" .

build完成后，就可以运行这个docker-registry
我们先配置自己的config.yml文件，第一种方法是直接在run的时候指定变量
# cp config/config_sample.yml /opt/data/registry/config.yml
# vi /opt/data/registry/config.yml
##这里可以设置本地存储SETTINGS_FLAVOR=dev，local STORAGE_PATH:/tmp/registry等待

# docker run -d -v /opt/data/registry:/tmp/registry -p 5000:5000 -e  DOCKER_REGISTRY_CONFIG=/tmp/registry/config.yml registry
或
docker run -d -e SETTINGS_FLAVOR=dev -e STORAGE_PATH=/tmp/registry -v /db/docker-images:/tmp/registry -p 5000:5000 registry

```
### 2.2 客户端使用 ##
要从私服上获取镜像或向私服提交镜像，现在变得非常简单，只需要在仓库前面加上私服的地址和端口，形如`172.29.88.222:5000/centos6`。注意，这里可以选择不使用IP，而是用hostname，如registry.domain.com:5000，但不能仅用不带`.`的主机名registry，docker会认为registry是用户名，建议使用带域名的hostname加port来表示。

于是在另外一台要使用docker的主机上就可以通过这台私服拉取和推送镜像了：

```
从私服上搜索存在哪些可用镜像
# curl -X GET http://sean.domain.com:5000/v1/search
{"num_results": 2, "query": "", "results": [{"description": "", "name": "library/centos6"}, {"description": "", "name": "library/nginx"}]}

按条件搜索nginx
# curl -X GET http://sean.domain.com:5000/v1/search?q=centos6

拉取image到本地
docker pull library/centos6

## 本地对份镜像启动起来，形成container
## 给container去另外一个名字
# docker tag 68edf809afe7 registry.domain.com:5000/centos6-test

## 最后将新的docker images推送到私服上
docker push registry.domain.com:5000/centos6-test
```
第一次push到私服上时会提示用户名、密码和邮箱，创建即可。也可以在docker私服端加入认证机制。

## 3. 加入nginx认证 ##
（请在实际操作以前，先阅读完本节，再确定是否在前端加入nginx）
### 3.1 安装及配置nginx ###
从上面的过程可以看到，除非防火墙限制，否则任何主机可以创建账号并想私服推送镜像，更安全的做法是在外层加入登录认证机制。
```
最好安装1.4.x版本，不然下面的有些配置可能会不兼容
# yum install nginx

创建两个登录用户
# htpasswd -c /etc/nginx/docker-registry.htpasswd sean
New password: 
Re-type new password: 
Adding password for user sean

# htpasswd /etc/nginx/docker-registry.htpasswd itsection
```
为了让nginx使用这个密码文件，并且转发8080端口的请求到Docker Registry，新增nginx配置文件
`vi /etc/nginx/sites-enabled/docker-registry`：
```
# For versions of Nginx > 1.3.9 that include chunked transfer encoding support
# Replace with appropriate values where necessary

upstream docker-registry {
 server localhost:5000;
}

server {
 listen 8080;
 server_name sean.domain.com;  -- your registry server_name

 # ssl on;
 # ssl_certificate /etc/ssl/certs/docker-registry;
 # ssl_certificate_key /etc/ssl/private/docker-registry;

 proxy_set_header Host       $http_host;   # required for Docker client sake
 proxy_set_header X-Real-IP  $remote_addr; # pass on real client IP

 client_max_body_size 0; # disable any limits to avoid HTTP 413 for large image uploads

 # required to avoid HTTP 411: see Issue #1486 (https://github.com/dotcloud/docker/issues/1486)
 chunked_transfer_encoding on;

 location / {
     # let Nginx know about our auth file
     auth_basic              "Restricted";
     auth_basic_user_file    docker-registry.htpasswd;

     proxy_pass http://docker-registry;
 }
 location /_ping {
     auth_basic off;
     proxy_pass http://docker-registry;
 }  
 location /v1/_ping {
     auth_basic off;
     proxy_pass http://docker-registry;
 }
}
```

```
让nginx来使用这个virtual-host
# ln -s /etc/nginx/sites-enabled/docker-registry /etc/nginx/conf.d/docker-registry.conf
重启nginx来激活虚拟主机的配置
# service nginx restart
```

### 3.2 加入认证后使用docker-registry ###
此时主机的5000端口应该通过防火墙禁止访问（或者在`docker run`端口映射时只监听回环接口的IP `-p 127.0.0.1:5000:5000`）。
```
# curl localhost:5000
"docker-registry server (dev) (v0.8.1)"
```
如果直接访问访问将得到未授权的信息：
```
# curl localhost:8080
<html>
<head><title>401 Authorization Required</title></head>
<body bgcolor="white">
<center><h1>401 Authorization Required</h1></center>
<hr><center>nginx/1.4.7</center>
</body>
</html>
```
带用户认证的docker-registry：
```
# curl http://sean:sean@sean.domain.com:8080/v1/search
{"num_results": 2, "query": "", "results": [{"description": "", "name": "library/centos6"}, {"description": "", "name": "library/nginx"}]}

# docker login registry.domain.com:8080
Username: sean
Password: 
Email: zhouxiao@domain.com
Login Succeeded

# docker pull registry.domain.com:8080/library/centos6
```
不出意外的话，上面的`docker pull`会失败：
```
# docker pull registry.domain.com:8080/library/centos6
Pulling repository registry.domain.com:8080/library/centos6
2014/11/11 21:00:25 Could not reach any registry endpoint

# docker push registry.domain.com:8080/ubuntu:sean
The push refers to a repository [registry.domain.com:8080/ubuntu] (len: 1)
Sending image list
Pushing repository registry.domain.com:8080/ubuntu (1 tags)
2014/11/12 08:11:32 HTTP code 401, Docker will not send auth headers over HTTP.

nginx日志
2014/11/12 07:03:49 [error] 14898#0: *193 no user/password was provided for basic 
authenticatGET /v1/repositories/library/centos6/tags HTTP/1.1", host: "registry.domain.com:8080"
```
本文后的第1篇参考文档没有出现这个问题，但评论中有提及。
有人说是`backend storage`的问题，这里是本地存储镜像，不应该。经过查阅大量资料，并反复操作验证，是docker-registry版本的问题。从`v0.10.0`开始，`docker login`虽然Succeeded，但`pull`或`push`的时候，`~/.dockercfg`下的用户登录信息将不允许通过HTTP明文传输。（如果你愿意可以查看`v0.10.0`的源码 [registry.go](https://github.com/docker/docker/blob/v0.10.0/registry/registry.go)，在分支`v0.9.1`及以前是没有`HTTP code 401, Docker will not send auth headers over HTTP的`）
目前的办法三个：

- 撤退，这就是为什么先说明在操作前线查看到这的原因了
- 换成`v0.9.1`及以下版本。现在都`v1.3.1`了，我猜你不会这么做
- 修改源码[session.go](https://github.com/docker/docker/tree/master/registry)，去掉相应的判断行，然后git下来重新安装。我猜你更不会这么做
- 安装SSL证书，使用HTTPS传输。这是明智的选择，新版本docker也推荐我们这么做，往下看。
 
### 3.3 为nginx安装ssl证书 ###
首先打开nginx配置文件中ssl的三行注释
```
# vi /etc/nginx/conf.d/docker-registry.conf
...
server {
 listen 8000;
 server_name registry.domain.com;


 ssl on;
 ssl_certificate /etc/nginx/ssl/nginx.crt;
 ssl_certificate_key /etc/nginx/ssl/nginx.key;
...
```
保存之后，nginx会分别从`/etc/nginx/ssl/nginx.crt`和`/etc/nginx/ssl/nginx.key`读取ssl证书和私钥。如果你自己愿意花钱买一个ssl证书，那就会变得非常简单，把证书和私钥拷贝成上面一样即可。关于SSL以及签署ssl证书，请参考其他文章。
这里我们自签署一个ssl证书，把当前系统作为（私有）证书颁发中心（CA）。

创建存放证书的目录
```
# mkdir /etc/nginx/ssl
```
确认CA的一些配置文件

```
# vi /etc/pki/tls/openssl.cnf
...
[ CA_default ]

dir             = /etc/pki/CA           # Where everything is kept
certs           = $dir/certs            # Where the issued certs are kept
crl_dir         = $dir/crl              # Where the issued crl are kept
database        = $dir/index.txt        # database index file.
#unique_subject = no                    # Set to 'no' to allow creation of
                                        # several ctificates with same subject.
new_certs_dir   = $dir/newcerts         # default place for new certs.

certificate     = $dir/cacert.pem       # The CA certificate
serial          = $dir/serial           # The current serial number
crlnumber       = $dir/crlnumber        # the current crl number
                                        # must be commented out to leave a V1 CRL
crl             = $dir/crl.pem          # The current CRL
private_key     = $dir/private/cakey.pem # The private key
RANDFILE        = $dir/private/.rand    # private random number file
...
default_days    = 3650                  # how long to certify for
...
[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
countryName_default             = CN
countryName_min                 = 2
countryName_max                 = 2

stateOrProvinceName             = State or Province Name (full name)
stateOrProvinceName_default     = GD
...[ req_distinguished_name ]部分主要是颁证时一些默认的值，可以不动
```

(1) 生成根密钥
```
# cd /etc/pki/CA/
# openssl genrsa -out private/cakey.pem 2048
```
为了安全起见，修改cakey.pem私钥文件权限为600或400，也可以使用子shell生成`( umask 077; openssl genrsa -out private/cakey.pem 2048 )`，下面不再重复。

(2) 生成根证书
```
# openssl req -new -x509 -key private/cakey.pem -out cacert.pem
```
会提示输入一些内容，因为是私有的，所以可以随便输入，最好记住能与后面保持一致。上面的自签证书`cacert.pem`应该生成在`/etc/pki/CA`下。

(3) 为我们的nginx web服务器生成ssl密钥
```
# cd /etc/nginx/ssl
# openssl genrsa -out nginx.key 2048
```
我们的CA中心与要申请证书的服务器是同一个，否则应该是在另一台需要用到证书的服务器上生成。

(4) 为nginx生成证书签署请求
```
# openssl req -new -key nginx.key -out nginx.csr
...
Country Name (2 letter code) [AU]:CN
State or Province Name (full name) [Some-State]:GD
Locality Name (eg, city) []:SZ
Organization Name (eg, company) [Internet Widgits Pty Ltd]:COMPANY
Organizational Unit Name (eg, section) []:IT_SECTION
Common Name (e.g. server FQDN or YOUR name) []:your.domain.com
Email Address []:

Please enter the following 'extra' attributes
to be sent with your certificate request
A challenge password []:
An optional company name []:
...
```
同样会提示输入一些内容，其它随便，除了`Commone Name`一定要是你要授予证书的服务器域名或主机名，challenge password不填。

(5) 私有CA根据请求来签发证书
```
# openssl ca -in nginx.csr -out nginx.crt
```
上面签发过程其实默认使用了`-cert cacert.pem -keyfile cakey.pem`，这两个文件就是前两步生成的位于`/etc/pki/CA`下的根密钥和根证书。

到此我们已经拥有了建立ssl安全连接所需要的所有文件，并且服务器的crt和key都位于配置的目录下，唯有根证书`cacert.pem`位置不确定放在CentOS6下的哪个地方。
经验证以下几个位置不行：（[Adding trusted root certificates to the server](http://kb.kerio.com/product/kerio-connect/server-configuration/ssl-certificates/adding-trusted-root-certificates-to-the-server-1605.html)）
`/etc/pki/ca-trust/source/anchors`、`/etc/pki/ca-trust/source`、`/etc/pki/ca-trust/extracted`、
`/etc/pki/ca-trust/extracted/pem/`、`/etc/pki/tls/certs/cacert.crt`
都会报错：
```
# docker login https://registry.domain.com:8000
Username (sean): sean
2014/11/14 02:32:48 Error response from daemon: Invalid Registry endpoint: Get https://registry.domain.com:8000/v1/_ping: x509: certificate signed by unknown authority

# curl https://sean:sean@registry.domain.com:8000/
curl: (60) Peer certificate cannot be authenticated with known CA certificates
More details here: http://curl.haxx.se/docs/sslcerts.html
curl performs SSL certificate verification by default, using a "bundle"
 of Certificate Authority (CA) public keys (CA certs). If the default
 bundle file isn't adequate, you can specify an alternate file
 using the --cacert option.
If this HTTPS server uses a certificate signed by a CA represented in
 the bundle, the certificate verification probably failed due to a
 problem with the certificate (it might be expired, or the name might
 not match the domain name in the URL).
If you'd like to turn off curl's verification of the certificate, use
 the -k (or --insecure) option.
```

(6) 目前让根证书起作用的只发现一个办法：
```
# cp /etc/pki/tls/certs/ca-bundle.crt{,.bak}    备份以防出错
# cat /etc/pki/CA/cacert.pem >> /etc/pki/tls/certs/ca-bundle.crt

# curl https://sean:sean@registry.domain.com:8000
"docker-registry server (dev) (v0.8.1)"
```
将`cacert.pem`根证书追加到`ca-bundle.crt`后一定要重启docker后台进程才行。

如果`docker login`依然报错`certificate signed by unknown authority`，参考[Running Docker with https](https://docs.docker.com/articles/https/)，启动docker后台进程时指定信任的CA根证书：
```
# docker -d --tlsverify --tlscacert /etc/pki/CA/cacert.pem

或者将cacert.pem拷贝到~/.docker/ca.pem
# mkdir ~/.docker && cp /etc/pki/CA/cacert.pem ~/.docker/ca.pem
# docker -d
最好重启一下registry
# docker restart <registry_container_id> 
```
上面用“如果”是因为一开始总提示`certificate signed by unknown authority`，[有人说](https://github.com/docker/docker/blob/master/docs/sources/articles/certificates.md)将根证书放在`/etc/docker/certs.d`下，[还有人说]()启动docker daemon收加入`--insecure-registry ..` 但终究是因为版本差异不成功。但后来又奇迹般的不需要`--tlscacert`就好了。
这个地方挣扎了很久，重点关注一下这个下面几个issue：

- https://github.com/docker/docker-registry/issues/82
- https://github.com/docker/docker/pull/2687
- https://github.com/docker/docker/pull/2339

(7) 最终搞定：
```
# docker login https://registry.domain.com:8000
Username: sean
Password: 
Email: zhouxiao@domain.com
Login Succeeded

# curl https://sean:sean@registry.domain.com:8000
"docker-registry server (dev) (v0.8.1)"

# docker push registry.domain.com:8000/centos6:test_priv
The push refers to a repository [registry.domain.com:8000/centos6] (len: 1)
Sending image list
Pushing repository registry.domain.com:8000/centos6 (1 tags)
511136ea3c5a: Image successfully pushed 
5b12ef8fd570: Image successfully pushed 
68edf809afe7: Image successfully pushed 
40627956f44c: Image successfully pushed 
Pushing tag for rev [40627956f44c] on {https://registry.domain.com:8000/v1/repositories/centos6/tags/test_priv}

```
但还有一个小问题没解决，虽然已经可以正常使用，但每次请求在nginx的error.log中还是会有`[error] 8299#0: *27 no user/password was provided for basic authentication`，应该是这个版本docker暂未解决的bug。


### 3.3 其它问题 ###

(1) docker后台进程意外中断后，重新`docker start <container_id>`报错
```
# docker start b36bd796bd3d
Error: Cannot start container b36bd796bd3d: Error getting container b36bd796bd3d463c4fedb70d98621e7318ec3d5cd14b2f60b1d182ad3cbcc652 
from driver devicemapper: Error mounting '/dev/mapper/docker-253:0-787676-b36bd796bd3d463c4fedb70d98621e7318ec3d5cd14b2f60b1d182ad3cbcc652' 
on '/var/lib/docker/devicemapper/mnt/b36bd796bd3d463c4fedb70d98621e7318ec3d5cd14b2f60b1d182ad3cbcc652': device or resource busy
2014/11/08 15:14:57 Error: failed to start one or more containers
```
经分析产生这个问题的原因是做了一个操作：在docker后台进程启动的终端，继续回车后会临时退出后台进程的日志输出，我就在这个shell下使用yum安装软件包，但由于网络原因yum卡住不动，于是我就另起了一个终端kill了这个yum进程，不知为何会影响到表面已经退出前台输出的docker。解决办法是umount容器的挂载点：（见[这里](https://github.com/docker/docker/issues/5684)）
```
# umount /var/lib/docker/devicemapper/mnt/b36bd796bd3d463c4fedb70d98621e7318ec3d5cd14b2f60b1d182ad3cbcc652

# service docker start   正常
```
能想到的另外一个办法是，启动docker后台进程时，重定向输出`docker -d > /dev/null 2>&1`（/var/log/docker已自动记录了一份日志）。

(2) 配置完nginx的docker-registry.conf后启动报错
```
# service nginx start
[emerg] 14714#0: unknown directive "upstream" in /etc/nginx/conf.d/docker-registry.conf:4
```
原因是nginx版本太低，一些配置指令不兼容，使用`yum install nginx`默认安装了1.0.x，卸载重新下载`nginx-1.4.7-1.el6.ngx.x86_64.rpm`安装解决。

(3) 网络设置代理问题
`pull, push`官网的镜像时由于GFW的原因需要设置代理，但不是`http_proxy`而是`HTTP_PROXY`，对于docker来说同时设置这两个值就会出问题，有时出于安装软件包的需要设置`http_proxy`，就会导致冲突。在docker-registry中如果忘记了当前哪一个在起作用，找遍所有问题都发现不了原因，而docker返回给我们的错误也难以判断。切记~

TO-DO
   如何删除docker-registry的里的镜像

## 4. 参考 ##

- [部署自己的私有 Docker Registry](https://docker.cn/p/deploy-your-own-private-docker-registry/) [[英文](http://www.activestate.com/blog/2014/01/deploying-your-own-private-docker-registry)]
- [Official docker-registry README](https://github.com/docker/docker-registry)
- [How To Set Up a Private Docker Registry on Ubuntu 14.04](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-private-docker-registry-on-ubuntu-14-04)
- [The Docker Hub and the Registry spec](http://beta-docs.docker.io/reference/api/hub_registry_spec/)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-registry-deploy.png
