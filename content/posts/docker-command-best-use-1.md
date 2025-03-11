---
title: docker常用管理命令（上）
date: 2014-10-31 20:21:25
updated: 2014-11-05 15:46:23
tags: [docker, command]
categories: [Linux, Docker]
---

本文只记录docker命令在大部分情境下的使用，如果想了解每一个选项的细节，请参考官方文档，这里只作为自己以后的备忘记录下来。

根据自己的理解，总的来说分为以下几种：
容器生命周期管理 — `docker [run|start|stop|restart|kill|rm|pause|unpause]`
容器操作运维 — `docker [ps|inspect|top|attach|events|logs|wait|export|port]`
容器rootfs命令 — `docker [commit|cp|diff]`
镜像仓库 — `docker [login|pull|push|search]`
本地镜像管理 — `docker [images|rmi|tag|build|history|save|import]`
其他命令 — `docker [info|version]`

看一个变迁图
![docker_cli_stage][1]

### 1. 列出机器上的镜像（images） ###
```
# docker images 
REPOSITORY               TAG             IMAGE ID        CREATED         VIRTUAL SIZE
ubuntu                   14.10           2185fd50e2ca    13 days ago     236.9 MB
…
```
其中我们可以根据REPOSITORY来判断这个镜像是来自哪个服务器，如果没有 / 则表示官方镜像，类似于`username/repos_name`表示Github的个人公共库，类似于`regsistory.example.com:5000/repos_name`则表示的是私服。
IMAGE ID列其实是缩写，要显示完整则带上`--no-trunc`选项

### 2. 在docker index中搜索image（search） ###
`Usage: docker search TERM `
```
# docker search seanlo
NAME                DESCRIPTION           STARS     OFFICIAL   AUTOMATED
seanloook/centos6   sean's docker repos         0
```
搜索的范围是官方镜像和所有个人公共镜像。NAME列的 / 后面是仓库的名字。

<!-- more -->

### 3. 从docker registry server 中下拉image或repository（pull） ###
`Usage: docker pull [OPTIONS] NAME[:TAG]`
```
# docker pull centos
```
上面的命令需要注意，在docker v1.2版本以前，会下载官方镜像的centos仓库里的所有镜像，而从v.13开始官方文档里的说明变了：will pull the centos:latest image, its intermediate layers and any aliases  of the same id，也就是只会下载tag为latest的镜像（以及同一images id的其他tag）。
也可以明确指定具体的镜像：
```
# docker pull centos:centos6
```
当然也可以从某个人的公共仓库（包括自己是私人仓库）拉取，形如`docker pull username/repository<:tag_name>` ：
```
# docker pull seanlook/centos:centos6
```
如果你没有网络，或者从其他私服获取镜像，形如`docker pull registry.domain.com:5000/repos:<tag_name>` 
```
# docker pull dl.dockerpool.com:5000/mongo:latest
```
### 4. 推送一个image或repository到registry（push） ###
与上面的pull对应，可以推送到Docker Hub的Public、Private以及私服，但不能推送到Top Level Repository。
```
# docker push seanlook/mongo
# docker push registry.tp-link.net:5000/mongo:2014-10-27
```
registry.tp-link.net也可以写成IP，172.29.88.222。
在repository不存在的情况下，命令行下push上去的会为我们创建为私有库，然而通过浏览器创建的默认为公共库。

### 5. 从image启动一个container（run） ###
`docker run`命令首先会从特定的image创之上create一层可写的container，然后通过start命令来启动它。停止的container可以重新启动并保留原来的修改。run命令启动参数有很多，以下是一些常规使用说明，更多部分请参考http://www.cnphp6.com/archives/24899
当利用 docker run 来创建容器时，Docker 在后台运行的标准操作包括：
- 检查本地是否存在指定的镜像，不存在就从公有仓库下载
- 利用镜像创建并启动一个容器
- 分配一个文件系统，并在只读的镜像层外面挂载一层可读写层
- 从宿主主机配置的网桥接口中桥接一个虚拟接口到容器中去
- 从地址池配置一个 ip 地址给容器
- 执行用户指定的应用程序
- 执行完毕后容器被终止

`Usage: docker run [OPTIONS] IMAGE [COMMAND] [ARG...]`

#### 5.1 使用image创建container并执行相应命令，然后停止 ####
```
# docker run ubuntu echo "hello world"
hello word
```
这是最简单的方式，跟在本地直接执行`echo 'hello world'` 几乎感觉不出任何区别，而实际上它会从本地ubuntu:latest镜像启动到一个容器，并执行打印命令后退出（`docker ps -l`可查看）。需要注意的是，默认有一个`--rm=true`参数，即完成操作后停止容器并从文件系统移除。因为Docker的容器实在太轻量级了，很多时候用户都是随时删除和新创建容器。
容器启动后会自动随机生成一个`CONTAINER ID`，这个ID在后面commit命令后可以变为`IMAGE ID`
#### 使用image创建container并进入交互模式, login shell是/bin/bash ####
```
# docker run -i -t --name mytest centos:centos6 /bin/bash
bash-4.1#
```
上面的`--name`参数可以指定启动后的容器名字，如果不指定则docker会帮我们取一个名字。镜像`centos:centos6`也可以用`IMAGE ID` (68edf809afe7) 代替），并且会启动一个伪终端，但通过ps或top命令我们却只能看到一两个进程，因为容器的核心是所执行的应用程序，所需要的资源都是应用程序运行所必需的，除此之外，并没有其它的资源，可见Docker对资源的利用率极高。此时使用exit或Ctrl+D退出后，这个容器也就消失了（消失后的容器并没有完全删除？）
（那么多个TAG不同而IMAGE ID相同的的镜像究竟会运行以哪一个TAG启动呢

#### 5.2 运行出一个container放到后台运行 ####
```
# docker run -d ubuntu /bin/sh -c "while true; do echo hello world; sleep 2; done"
ae60c4b642058fefcc61ada85a610914bed9f5df0e2aa147100eab85cea785dc
```
它将直接把启动的container挂起放在后台运行（这才叫saas），并且会输出一个`CONTAINER ID`，通过`docker ps`可以看到这个容器的信息，可在container外面查看它的输出`docker logs ae60c4b64205`，也可以通过`docker attach ae60c4b64205`连接到这个正在运行的终端，此时在`Ctrl+C`退出container就消失了，按ctrl-p ctrl-q可以退出到宿主机，而保持container仍然在运行
另外，如果-d启动但后面的命令执行完就结束了，如`/bin/bash`、`echo test`，则container做完该做的时候依然会终止。而且-d不能与--rm同时使用
可以通过这种方式来运行memcached、apache等。

#### 5.3 映射host到container的端口和目录 ####
映射主机到容器的端口是很有用的，比如在container中运行memcached，端口为11211，运行容器的host可以连接container的 internel_ip:11211 访问，如果有从其他主机访问memcached需求那就可以通过-p选项，形如`-p <host_port:contain_port>`，存在以下几种写法：
```
-p 11211:11211 这个即是默认情况下，绑定主机所有网卡（0.0.0.0）的11211端口到容器的11211端口上
-p 127.0.0.1:11211:11211 只绑定localhost这个接口的11211端口
-p 127.0.0.1::5000
-p 127.0.0.1:80:8080
```
目录映射其实是“绑定挂载”host的路径到container的目录，这对于内外传送文件比较方便，在搭建私服那一节，为了避免私服container停止以后保存的images不被删除，就要把提交的images保存到挂载的主机目录下。使用比较简单，`-v <host_path:container_path>`，绑定多个目录时再加`-v`。
```
-v /tmp/docker:/tmp/docker
```
另外在两个container之间建立联系可用`--link`，详见高级部分或[官方文档](http://docs.docker.com/v1.1/reference/commandline/cli/#run)。
下面是一个例子：
```
# docker run --name nginx_test \
> -v /tmp/docker:/usr/share/nginx/html:ro \
> -p 80:80 -d \
> nginx:1.7.6
```
在主机的/tmp/docker下建立index.html，就可以通过`http://localhost:80/`或`http://host-ip:80`访问了。

### 6. 将一个container固化为一个新的image（commit） ###
当我们在制作自己的镜像的时候，会在container中安装一些工具、修改配置，如果不做commit保存起来，那么container停止以后再启动，这些更改就消失了。
`docker commit <container> [repo:tag]`
后面的repo:tag可选
只能提交正在运行的container，即通过`docker ps`可以看见的容器，
```
查看刚运行过的容器
# docker ps -l
CONTAINER ID   IMAGE     COMMAND      CREATED       STATUS        PORTS   NAMES
c9fdf26326c9   nginx:1   nginx -g..   3 hours ago   Exited (0)..     nginx_test

启动一个已存在的容器（run是从image新建容器后再启动），以下也可以使用docker start nginx_test代替  
[root@hostname docker]# docker start c9fdf26326c9
c9fdf26326c9


docker run -i -t --sig-proxy=false 21ffe545748baf /bin/bash
nginx服务没有启动


# docker commit -m "some tools installed" fcbd0a5348ca seanlook/ubuntu:14.10_tutorial
fe022762070b09866eaab47bc943ccb796e53f3f416abf3f2327481b446a9503
```
-a "seanlook7@gmail.com" 
请注意，当你反复去commit一个容器的时候，每次都会得到一个新的`IMAGE ID`，假如后面的`repository:tag`没有变，通过`docker images`可以看到，之前提交的那份镜像的`repository:tag`就会变成`<none>:<none>`，所以尽量避免反复提交。
另外，观察以下几点
- commit container只会pause住容器，这是为了保证容器文件系统的一致性，但不会stop。如果你要对这个容器继续做其他修改：
  - 你可以重新提交得到新image2，删除次新的image1
  - 也可以关闭容器用新image1启动，继续修改，提交image2后删除image1
  - 当然这样会很痛苦，所以一般是采用`Dockerfile`来`build`得到最终image，参考[]
- 虽然产生了一个新的image，并且你可以看到大小有100MB，但从commit过程很快就可以知道实际上它并没有独立占用100MB的硬盘空间，而只是在旧镜像的基础上修改，它们共享大部分公共的“片”。

下文继续：

# 参考 #
- [Official Command Line Reference](http://docs.docker.com/v1.1/reference/commandline/cli/)
- [docker中文指南cli-widuu翻译](http://www.widuu.com/docker/)
- [Docker —— 从入门到实践](http://www.dockerpool.com/static/books/docker_practice/)
- [Docker基础与高级](http://17173ops.com/2014/10/13/docker%E5%9F%BA%E7%A1%80%E4%B8%8E%E9%AB%98%E7%BA%A7.shtml)

    [1]本文只记录docker命令在大部分情境下的使用，如果想了解每一个选项的细节，请参考官方文档，这里只作为自己以后的备忘记录下来。

根据自己的理解，总的来说分为以下几种：

- 容器生命周期管理 — `docker [run|start|stop|restart|kill|rm|pause|unpause]`
- 容器操作运维 — `docker [ps|inspect|top|attach|events|logs|wait|export|port]`
- 容器rootfs命令 — `docker [commit|cp|diff]`
- 镜像仓库 — `docker [login|pull|push|search]`
- 本地镜像管理 — `docker [images|rmi|tag|build|history|save|import]`
- 其他命令 — `docker [info|version]`

看一个变迁图
![docker_cli_stage][1]
### 1. 列出机器上的镜像（images） ###
```
# docker images 
REPOSITORY               TAG             IMAGE ID        CREATED         VIRTUAL SIZE
ubuntu                   14.10           2185fd50e2ca    13 days ago     236.9 MB
…
```
其中我们可以根据REPOSITORY来判断这个镜像是来自哪个服务器，如果没有 / 则表示官方镜像，类似于`username/repos_name`表示Github的个人公共库，类似于`regsistory.example.com:5000/repos_name`则表示的是私服。
IMAGE ID列其实是缩写，要显示完整则带上`--no-trunc`选项

### 2. 在docker index中搜索image（search） ###
`Usage: docker search TERM `
```
# docker search seanlo
NAME                DESCRIPTION           STARS     OFFICIAL   AUTOMATED
seanloook/centos6   sean's docker repos         0
```
搜索的范围是官方镜像和所有个人公共镜像。NAME列的 / 后面是仓库的名字。

### 3. 从docker registry server 中下拉image或repository（pull） ###
`Usage: docker pull [OPTIONS] NAME[:TAG]`
```
# docker pull centos
```
上面的命令需要注意，在docker v1.2版本以前，会下载官方镜像的centos仓库里的所有镜像，而从v.13开始官方文档里的说明变了：will pull the centos:latest image, its intermediate layers and any aliases  of the same id，也就是只会下载tag为latest的镜像（以及同一images id的其他tag）。
也可以明确指定具体的镜像：
```
# docker pull centos:centos6
```
当然也可以从某个人的公共仓库（包括自己是私人仓库）拉取，形如`docker pull username/repository<:tag_name>` ：
```
# docker pull seanlook/centos:centos6
```
如果你没有网络，或者从其他私服获取镜像，形如`docker pull registry.domain.com:5000/repos:<tag_name>` 
```
# docker pull dl.dockerpool.com:5000/mongo:latest
```
### 4. 推送一个image或repository到registry（push） ###
与上面的pull对应，可以推送到Docker Hub的Public、Private以及私服，但不能推送到Top Level Repository。
```
# docker push seanlook/mongo
# docker push registry.tp-link.net:5000/mongo:2014-10-27
```
registry.tp-link.net也可以写成IP，172.29.88.222。
在repository不存在的情况下，命令行下push上去的会为我们创建为私有库，然而通过浏览器创建的默认为公共库。

### 5. 从image启动一个container（run） ###
`docker run`命令首先会从特定的image创之上create一层可写的container，然后通过start命令来启动它。停止的container可以重新启动并保留原来的修改。run命令启动参数有很多，以下是一些常规使用说明，更多部分请参考http://www.cnphp6.com/archives/24899
当利用 docker run 来创建容器时，Docker 在后台运行的标准操作包括：
- 检查本地是否存在指定的镜像，不存在就从公有仓库下载
- 利用镜像创建并启动一个容器
- 分配一个文件系统，并在只读的镜像层外面挂载一层可读写层
- 从宿主主机配置的网桥接口中桥接一个虚拟接口到容器中去
- 从地址池配置一个 ip 地址给容器
- 执行用户指定的应用程序
- 执行完毕后容器被终止

`Usage: docker run [OPTIONS] IMAGE [COMMAND] [ARG...]`

#### 5.1 使用image创建container并执行相应命令，然后停止 ####
```
# docker run ubuntu echo "hello world"
hello word
```
这是最简单的方式，跟在本地直接执行`echo 'hello world'` 几乎感觉不出任何区别，而实际上它会从本地ubuntu:latest镜像启动到一个容器，并执行打印命令后退出（`docker ps -l`可查看）。需要注意的是，默认有一个`--rm=true`参数，即完成操作后停止容器并从文件系统移除。因为Docker的容器实在太轻量级了，很多时候用户都是随时删除和新创建容器。
容器启动后会自动随机生成一个`CONTAINER ID`，这个ID在后面commit命令后可以变为`IMAGE ID`
#### 使用image创建container并进入交互模式, login shell是/bin/bash ####
```
# docker run -i -t --name mytest centos:centos6 /bin/bash
bash-4.1#
```
上面的`--name`参数可以指定启动后的容器名字，如果不指定则docker会帮我们取一个名字。镜像`centos:centos6`也可以用`IMAGE ID` (68edf809afe7) 代替），并且会启动一个伪终端，但通过ps或top命令我们却只能看到一两个进程，因为容器的核心是所执行的应用程序，所需要的资源都是应用程序运行所必需的，除此之外，并没有其它的资源，可见Docker对资源的利用率极高。此时使用exit或Ctrl+D退出后，这个容器也就消失了（消失后的容器并没有完全删除？）
（那么多个TAG不同而IMAGE ID相同的的镜像究竟会运行以哪一个TAG启动呢

#### 5.2 运行出一个container放到后台运行 ####
```
# docker run -d ubuntu /bin/sh -c "while true; do echo hello world; sleep 2; done"
ae60c4b642058fefcc61ada85a610914bed9f5df0e2aa147100eab85cea785dc
```
它将直接把启动的container挂起放在后台运行（这才叫saas），并且会输出一个`CONTAINER ID`，通过`docker ps`可以看到这个容器的信息，可在container外面查看它的输出`docker logs ae60c4b64205`，也可以通过`docker attach ae60c4b64205`连接到这个正在运行的终端，此时在`Ctrl+C`退出container就消失了，按ctrl-p ctrl-q可以退出到宿主机，而保持container仍然在运行
另外，如果-d启动但后面的命令执行完就结束了，如`/bin/bash`、`echo test`，则container做完该做的时候依然会终止。而且-d不能与--rm同时使用
可以通过这种方式来运行memcached、apache等。

#### 5.3 映射host到container的端口和目录 ####
映射主机到容器的端口是很有用的，比如在container中运行memcached，端口为11211，运行容器的host可以连接container的 internel_ip:11211 访问，如果有从其他主机访问memcached需求那就可以通过-p选项，形如`-p <host_port:contain_port>`，存在以下几种写法：
```
-p 11211:11211 这个即是默认情况下，绑定主机所有网卡（0.0.0.0）的11211端口到容器的11211端口上
-p 127.0.0.1:11211:11211 只绑定localhost这个接口的11211端口
-p 127.0.0.1::5000
-p 127.0.0.1:80:8080
```
目录映射其实是“绑定挂载”host的路径到container的目录，这对于内外传送文件比较方便，在搭建私服那一节，为了避免私服container停止以后保存的images不被删除，就要把提交的images保存到挂载的主机目录下。使用比较简单，`-v <host_path:container_path>`，绑定多个目录时再加`-v`。
```
-v /tmp/docker:/tmp/docker
```
另外在两个container之间建立联系可用`--link`，详见高级部分或[官方文档](http://docs.docker.com/v1.1/reference/commandline/cli/#run)。
下面是一个例子：
```
# docker run --name nginx_test \
> -v /tmp/docker:/usr/share/nginx/html:ro \
> -p 80:80 -d \
> nginx:1.7.6
```
在主机的/tmp/docker下建立index.html，就可以通过`http://localhost:80/`或`http://host-ip:80`访问了。

### 6. 将一个container固化为一个新的image（commit） ###
当我们在制作自己的镜像的时候，会在container中安装一些工具、修改配置，如果不做commit保存起来，那么container停止以后再启动，这些更改就消失了。
`docker commit <container> [repo:tag]`
后面的repo:tag可选
只能提交正在运行的container，即通过`docker ps`可以看见的容器，
```
查看刚运行过的容器
# docker ps -l
CONTAINER ID   IMAGE     COMMAND      CREATED       STATUS        PORTS   NAMES
c9fdf26326c9   nginx:1   nginx -g..   3 hours ago   Exited (0)..     nginx_test

启动一个已存在的容器（run是从image新建容器后再启动），以下也可以使用docker start nginx_test代替  
[root@hostname docker]# docker start c9fdf26326c9
c9fdf26326c9


docker run -i -t --sig-proxy=false 21ffe545748baf /bin/bash
nginx服务没有启动


# docker commit -m "some tools installed" fcbd0a5348ca seanlook/ubuntu:14.10_tutorial
fe022762070b09866eaab47bc943ccb796e53f3f416abf3f2327481b446a9503
```
-a "seanlook7@gmail.com" 
请注意，当你反复去commit一个容器的时候，每次都会得到一个新的`IMAGE ID`，假如后面的`repository:tag`没有变，通过`docker images`可以看到，之前提交的那份镜像的`repository:tag`就会变成`<none>:<none>`，所以尽量避免反复提交。
另外，观察以下几点:

- commit container只会pause住容器，这是为了保证容器文件系统的一致性，但不会stop。如果你要对这个容器继续做其他修改：
  - 你可以重新提交得到新image2，删除次新的image1
  - 也可以关闭容器用新image1启动，继续修改，提交image2后删除image1
  - 当然这样会很痛苦，所以一般是采用`Dockerfile`来`build`得到最终image，参考[]
- 虽然产生了一个新的image，并且你可以看到大小有100MB，但从commit过程很快就可以知道实际上它并没有独立占用100MB的硬盘空间，而只是在旧镜像的基础上修改，它们共享大部分公共的“片”。

下文继续：

# 参考 #
- [Official Command Line Reference](http://docs.docker.com/v1.1/reference/commandline/cli/)
- [docker中文指南cli-widuu翻译](http://www.widuu.com/docker/)
- [Docker —— 从入门到实践](http://www.dockerpool.com/static/books/docker_practice/)
- [Docker基础与高级](http://17173ops.com/2014/10/13/docker%E5%9F%BA%E7%A1%80%E4%B8%8E%E9%AB%98%E7%BA%A7.shtml)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/docker_cli_stage.png
