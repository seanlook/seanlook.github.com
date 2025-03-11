---
title: Docker集中化web界面管理平台shipyard
date: 2014-12-29 13:21:25
updated: 2014-12-29 15:46:23
tags: [docker, linux, shipyard]
categories: [Virtualization, Docker]
---

[Shipyard](http://shipyard-project.com/)（[github](https://github.com/shipyard/shipyard)）是建立在docker集群管理工具[Citadel](https://github.com/citadel/citadel)之上的可以管理容器、主机等资源的web图形化工具。包括[core](https://github.com/shipyard/shipyard)和[extension](https://github.com/shipyard/shipyard-extensions)两个版本，core即shipyard主要是把多个 Docker host上的 containers 统一管理（支持跨越多个host），extension即shipyard-extensions添加了应用路由和负载均衡、集中化日志、部署等。

## 1. 几个概念 ##
### engine ###
一个shipyard管理的docker集群可以包含一个或多个`engine`（引擎），一个engine就是监听tcp端口的docker daemon。shipyard管理docker daemon、images、containers完全基于Docker API，不需要做其他的修改。另外，shipyard可以对每个engine做资源限制，包括CPU和内存；因为TCP监听相比Unix socket方式会有一定的安全隐患，所以shipyard还支持通过SSL证书与docker后台进程安全通信。

### rethinkdb ###
`RethinkDB`是一个shipyard项目的一个docker镜像，用来存放账号（account）、引擎（engine）、服务密钥（service key）、扩展元数据（extension metadata）等信息，但不会存储任何有关容器或镜像的内容。一般会启动一个`shipyard/rethinkdb`容器shipyard-rethinkdb-data来使用它的`/data`作为数据卷供另外rethinkdb一个挂载，专门用于数据存储。

## 2. 搭建过程 ##

### 修改tcp监听 ###
Shipyard 要管理和控制 Docker host 的话需要先修改 Docker host 上的默认配置使其监听tcp端口(可以继续保持Unix socket）。有以下2种方式

1. `sudo docker -H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock -d` 启动docker daemon。如果为了避免每次启动都写这么长的命令，可以直接在`/etc/init/docker.conf`中修改。
2. 修改`/etc/default/docker`的`DOCKER_OPTS`
 `DOCKER_OPTS="-H tcp://127.0.0.1:4243 -H unix:///var/run/docker.sock"`。这种方式在我docker version 1.4.1 in ubuntu 14.04上并没有生效。

<!-- more -->

```
重启服务
$ sudo docker -H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock -d
验证
$ netstat -ant  |grep 4243
tcp6       0      0 :::4243                 :::*                    LISTEN
``` 
### 启动rethinkdb ###
shipyard（基于Python/Django）在v1版本时安装过程比较复杂，既可以通过在host上安装，也可以部署shipyard镜像（包括`shipyard-agent`、`shipyard-deploy`等组件）。v2版本简化了安装过程，启动两个镜像就完成：

```
获取一个/data的数据卷
$sudo docker run -it -d --name shipyard-rethinkdb-data \
  --entrypoint /bin/bash shipyard/rethinkdb -l

使用数据卷/data启动RethinkDB
docker run -it -P -d --name shipyard-rethinkdb \
  --volumes-from shipyard-rethinkdb-data shipyard/rethinkdb
```
### 部署shipyard镜像 ###
启动shipyard控制器：
```
sudo docker run -it -p 8080:8080 -d --name shipyard \
  --link shipyard-rethinkdb:rethinkdb shipyard/shipyard
```
至此已经可以通过浏览器访问`http://host:8080`来访问shipyard UI界面了。

第一次`run`后，关闭再次启动时直接使用：
```
sudo docker stop shipyard shipyard-rethinkdb shipyard-rethinkdb-data
sudo docker start shipyard-rethinkdb-data shipyard-rethinkdb shipyard
```

### 图示 ###
**登录：**
![docker-shipyard-login][1]
默认用户名/密码为 admin/shipyard

**主界面：**
![docker-shipyard][2]
Dashboard展示在添加engine时指定的CPU以及内存的使用情况。

**容器：**
![docker-shipyard-containers][3]
shipyard管理的所有docker主机的所有容器，包括stop和running状态的。可以直接点击DEPLOY按钮来从镜像运行出其他容器，与`docker run`的选项几乎相同，可以限制CPU和内存的使用，详见[shipyard的containers文档](http://shipyard-project.com/docs/containers/)。

**容器操作：**
![docker-shipyard-containers2][4]
可以`stop`、`start`、`restart`容器，通过`LOGS`可以看到容器日志输出，`SCALE`可以批量（规模化）部署该容器，这个操作与容器的Type属性息息相关。因为shipyard可以管理多个host的docker容器，所以启动一个容器的type可以是：service——可以在具有相同label的engine上运行；unique——一个host上只允许某个镜像的一个实例运行；host——在指定的host上运行容器，启动的时候通过`--label host:<host-id>`语法指定docker host。

**engine管理：**
![docker-shipyard-engine][5]
一个engine就是一个docker daemon，docker daemon下启动着多个containers，可以对engine限制一个整体的CPU和内存限制，shipyard通过TCP端口连接daemon。需要注意的是docker client与server的版本问题：（因为shipyard目前还在快速的完善过程，不同版本的docker应该是向下兼容的）
```
curl -X GET http://172.29.88.223:4243/v1.15/containers/json
client and server don't have same version (client : 1.15, server: 1.13)
```

## 3. shipyard-cli ##
目前图形化界面能做的操作其实很少，正在强大的是通过shipyard提供的命令行窗口（称作`Shipyard CLI`）进行管理，参考http://shipyard-project.com/docs/usage/cli/
启动命令行交互模式：

    sudo docker run --rm -it shipyard/shipyard-cli

使用它甚至可以替代docker客户端。

```
sean@seanubt:~$ sudo docker run -it shipyard/shipyard-cli
shipyard cli> shipyard help
NAME:
   shipyard - manage a shipyard cluster

USAGE:
   shipyard [global options] command [command options] [arguments...]

VERSION:
   2.0.8

COMMANDS:
   login		login to a shipyard cluster
   change-password	update your password
   accounts		show accounts
   add-account		add account
   delete-account	delete account
   containers		list containers
   inspect		inspect container
   run			run a container
   stop			stop a container
   restart		restart a container
   scale		scale a container
   logs			show container logs
   destroy		destroy a container
   engines		list engines
   add-engine		add shipyard engine
   remove-engine	removes an engine
   inspect-engine	inspect an engine
   service-keys		list service keys
   add-service-key	adds a service key
   remove-service-key	removes a service key
   extensions		show extensions
   add-extension	add extension
   remove-extension	remove an extension
   webhook-keys		list webhook keys
   add-webhook-key	adds a webhook key
   remove-webhook-key	removes a webhook key
   info			show cluster info
   events		show cluster events
   help, h		Shows a list of commands or help for one command
   
GLOBAL OPTIONS:
   --help, -h			show help
   --generate-bash-completion	
   --version, -v		print the version

登录shipyard
shipyard cli> shipyard login
URL: http://172.29.88.205:8080
Username: admin
Password:

查看containers
shipyard cli> shipyard containers

启动一个容器
shipyard cli> shipyard run --name nginx:1.7.6 --container-name web_test \
    --cpus 0.2 \
    --memory 64 \
    --type service \
    --hostname nginx-test \
    --domain example.com \
    --link redis:db \
    --port tcp/172.29.88.205:81:8081 \
    --port tcp/::8000 \
    --restart "on-failure:5" \
    --env FOO=bar \
    --label dev \

查看容器日志（只能接容器ID，暂不能使用容器名）
shipyard cli> shipyard logs ff2761d

关闭并移除容器
shipyard cli> shipyard destroy <container_id>
```
不一一列举。。。

  
  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-shipyard-login.png
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-shipyard.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-shipyard-containers.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-shipyard-containers2.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker-shipyard-engine.png
