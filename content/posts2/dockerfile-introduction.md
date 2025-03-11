---
title: Dockerfile指令详解
date: 2014-11-17 15:21:25
updated: 2014-11-17 15:46:23
tags: [docker, dockerfile, linux]
categories: [Virtualization, Docker]
---
Docker可以从`Dockerfile`中一步一步的读取指令来自动的创建镜像，常使用Dockerfile来创建用户自定义的镜像。格式如下：
```
# Comment
INSTRUCTION arguments
```
虽然前面的指令大小写不敏感，但习惯性的还是建议大写。docker是严格按照顺序（`#`注释起来的忽略）运行指令的。
下面逐个来介绍几个必要的指令。

### FROM ###
```
FROM  <image>
或
FROM <image>:<tag>
```
在Dockerfile中第一条非注释INSTRUCTION一定是`FROM`，它决定了以哪一个镜像作为基准，`<image>`首选本地是否存在，如果不存在则会从公共仓库下载（当然也可以使用私有仓库的格式）。

### RUN ###
```
RUN <commnad>
或
RUN ["executable", "param1", "param2"]
```
`RUN`指令会在当前镜像的顶层执行任何命令，并commit成新的（中间）镜像，提交的镜像会在后面继续用到。
上面看到`RUN`后的格式有两种写法。

<!-- more -->

shell格式，相当于执行`/bin/sh -c "<command>"`：
```
RUN apt-get install vim -y
```
exec格式，不会触发shell，所以`$HOME`这样的环境变量无法使用，但它可以在没有`bash`的镜像中执行，而且可以避免错误的解析命令字符串：
```
RUN ["apt-get", "install", "vim", "-y"]
或
RUN ["/bin/bash", "-c", "apt-get install vim -y"]  与shell风格相同
```

### ENTRYPOINT ###
`ENTRYPOINT`命令设置在容器启动时执行命令，如果有多个`ENTRYPOINT`指令，那只有最后一个生效。有以下两种命令格式：
```
ENTRYPOINT ["executable", "param1", "param2"]  数组/exec格式，推荐
或
ENTRYPOINT command param1 param2    shell格式
```

比如：
```
docker run -i -t --rm -p 80:80 nginx
```
使用exec格式，在`docker run <image>`的所有参数，都会追加到`ENTRYPOINT`之后，并且会覆盖`CMD`所指定的参数（如果有的话）。当然可以在`run`时使用`--entrypoint`来覆盖`ENTRYPOINT`指令。
使用shell格式，`ENTRYPOINT`相当于执行`/bin/sh -c <command..>`，这种格式会忽略`docker run`和`CMD`的所有参数。

以推荐使用的exec格式为例：
我们可以使用`ENTRYPOINT`来设置基本不会变化的命令，用`CMD`来设置其它的可能改变的默认启动命令或选项（`docker run`会覆盖的）。
```
FROM ubuntu
ENTRYPOINT ["top", "-b"]
CMD ["-c"]
```
`docker build -t registry.tp-link.net:8000/ubuntu:dockerfile_test .`
运行
```
$ docker run -it --rm --name test 44f178c416b0 -H
这里的top后的选项会追加到上面的ENTRYPOINT，同时会覆盖CMD的，所以实际相当于执行top -b -H，没有-c：
top - 04:32:07 up 10 days, 11:27,  0 users,  load average: 0.01, 0.03, 0.00
Threads:   1 total,   1 running,   0 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.1 us,  0.1 sy,  0.0 ni, 99.7 id,  0.2 wa,  0.0 hi,  0.0 si,  0.0 st
KiB Mem:   4056784 total,  3749188 used,   307596 free,   209372 buffers
KiB Swap:        0 total,        0 used,        0 free.   571388 cached Mem

  PID USER      PR  NI    VIRT    RES    SHR S %CPU %MEM     TIME+ COMMAND
    1 root      20   0   19688   1208    940 R  0.0  0.0   0:00.01 top
```
如果在使用的docker版本在v1.3及以上，则可以使用`docker exec`继续在容器中验证，看到完整的top命令`docker exec -it test ps aux`


### CMD ###
```
CMD ["executable","param1","param2"]  （数组/exec格式）
CMD ["param1","param2"]  (as default parameters to ENTRYPOINT)
CMD command param1 param2  (shell格式)
```
一个Dockerfile里只能有一个CMD，如果有多个，只有最后一个生效。`CMD`指令的主要功能是在build完成后，为了给`docker run`启动到容器时提供默认命令或参数，这些默认值可以包含可执行的命令，也可以只是参数（此时可执行命令就必须提前在`ENTRYPOINT`中指定）。

它与`ENTRYPOINT`的功能极为相似，区别在于如果`docker run`后面出现与`CMD`指定的相同命令，那么CMD会被覆盖；而`ENTRYPOINT`会把容器名后面的所有内容都当成参数传递给其指定的命令（不会对命令覆盖）。另外`CMD`还可以单独作为`ENTRYPOINT`的所接命令的可选参数。
`CMD`与`RUN`的区别在于，`RUN`是在`build`成镜像时就运行的，先于`CMD`和`ENTRYPOINT`的，`CMD`会在每次启动容器的时候运行，而`RUN`只在创建镜像时执行一次，固化在image中。

举例1：
```
Dockerfile:
    CMD ["echo CMD_args"]
运行
    docker run <image> echo run_arg
结果
    输出 run_arg
```
因为`echo run_arg`覆盖了`CMD`。如果`run`后没有`echo run_arg`，则输出`CMD_args`。

举例2：
```
Dockerfile:
    ENTRYPOINT ["echo", "ENTRYPOINT_args"]
运行
    docker run <image> run_arg
结果
    输出 ENTRYPOINT_args run_arg
```
因为`echo run_arg`追加到`ENTRYPOIINT`的`echo`后面了。如果在`ENTRYPOINT`后再加入一行`CMD ["CMD_args"]`，则结果依旧，除非去掉run后的所有参数。
当出现`ENTRYPOINT`指令时`CMD`指令只可能(当`ENTRYPOINT`指令使用exec方式执行时)被当做`ENTRYPOINT`指令的参数使用，其他情况则会被忽略。

### EXPOSE ###
`EXPOSE`指令告诉容器在运行时要监听的端口，但是这个端口是用于多个容器之间通信用的（links），外面的host是访问不到的。要把端口暴露给外面的主机，在启动容器时使用`-p`选项。
示例：
```
# expose memcached(s) port
EXPOSE 11211 11212
```

### ADD ###
```
ADD <src>... <dest>
```
将文件`<src>`拷贝到container的文件系统对应的路径`<dest>`下。
`<src>`可以是文件、文件夹、URL，对于文件和文件夹`<src>`必须是在Dockerfile的相对路径下（build context path），即只能是相对路径且不能包含`../path/`。
`<dest>`只能是容器中的绝对路径。如果路径不存在则会自动级联创建，根据你的需要是`<dest>`里是否需要反斜杠`/`，习惯使用`/`结尾从而避免被当成文件。
示例：
```
支持模糊匹配
ADD hom* /mydir/        # adds all files starting with "hom"
ADD hom?.txt /mydir/    # ? is replaced with any single character

ADD requirements.txt /tmp/
RUN pip install /tmp/requirements.txt
ADD . /tmp/
```

另外`ADD`支持远程URL获取文件，但官方认为是`strongly discouraged`，建议使用`wget`或`curl`代替。
`ADD`还支持自动解压tar文件，比如`ADD trusty-core-amd64.tar.gz /`会线自动解压内容再COPY到在容器的`/`目录下。

ADD只有在build镜像的时候运行一次，后面运行container的时候不会再重新加载，也就是你不能在运行时通过这种方式向容器中传送文件，`-v`选项映射本地到容器的目录。

### COPY ###
Same as 'ADD' but without the tar and remote url handling.

`COPY`的语法与功能与`ADD`相同，只是不支持上面讲到的`<src>`是远程URL、自动解压这两个特性，但是[Best Practices for Writing Dockerfiles](https://docs.docker.com/articles/dockerfile_best-practices/)建议**尽量使用`COPY`**，并使用`RUN`与`COPY`的组合来代替`ADD`，这是因为虽然`COPY`只支持本地文件拷贝到container，但它的处理比`ADD`更加透明，建议只在复制tar文件时使用`ADD`，如`ADD trusty-core-amd64.tar.gz /`。

### ENV ###
用于设置环境变量：
```
ENV <key> <value>
```
设置了后，后续的RUN命令都可以使用，当运行生成的镜像时这些环境变量依然有效，如果需要在运行时更改这些环境变量可以在运行`docker run`时添加`-env <key>=<value>`参数来修改。

### VOLUME ###
VOLUME指令用来在容器中设置一个挂载点，可以用来让其他容器挂载以实现数据共享或对容器数据的备份、恢复或迁移。请参考文章[docker容器间通信](http://seanlook/2014/12/17/docker_comun)

### WORKDIR ###
`WORKDIR指`令用于设置`Dockerfile`中的`RUN`、`CMD`和`ENTRYPOINT`指令执行命令的工作目录(默认为`/`目录)，该指令在`Dockerfile`文件中可以出现多次，如果使用相对路径则为相对于`WORKDIR`上一次的值，例如`WORKDIR /a`，`WORKDIR b`，`RUN pwd`最终输出的当前目录是`/a/b`。（`RUN cd /a/b`，`RUN pwd`是得不到`/a/b`的）

### ONBUILD ###
`ONBUILD`指令用来设置一些触发的指令，用于在当该镜像被作为基础镜像来创建其他镜像时(也就是`Dockerfile`中的`FROM`为当前镜像时)执行一些操作，`ONBUILD中`定义的指令会在用于生成其他镜像的`Dockerfile`文件的`FROM`指令之后被执行，上述介绍的任何一个指令都可以用于`ONBUILD`指令，可以用来执行一些因为环境而变化的操作，使镜像更加通用。

注意：
1. ONBUILD中定义的指令在当前镜像的build中不会被执行。
2. 可以通过查看`docker inspect <image>`命令执行结果的OnBuild键来查看某个镜像ONBUILD指令定义的内容。
3. ONBUILD中定义的指令会当做引用该镜像的Dockerfile文件的FROM指令的一部分来执行，执行顺序会按ONBUILD定义的先后顺序执行，如果ONBUILD中定义的任何一个指令运行失败，则会使FROM指令中断并导致整个build失败，当所有的ONBUILD中定义的指令成功完成后，会按正常顺序继续执行build。
4. ONBUILD中定义的指令不会继承到当前引用的镜像中，也就是当引用ONBUILD的镜像创建完成后将会清除所有引用的ONBUILD指令。
5. ONBUILD指令不允许嵌套，例如`ONBUILD ONBUILD ADD . /data`是不允许的。
6. ONBUILD指令不会执行其定义的FROM或MAINTAINER指令。

例如，`Dockerfile`使用如下的内容创建了镜像 image-A ：
```
[...]
ONBUILD ADD . /app/src
ONBUILD RUN /usr/local/bin/python-build --dir /app/src
[...]
```
如果基于 image-A 创建新的镜像时，新的`Dockerfile`中使用`FROM image-A`指定基础镜像时，会自动执行`ONBUILD`指令内容，等价于在后面添加了两条指令。
```
FROM image-A

#Automatically run the following
ADD . /app/src
RUN /usr/local/bin/python-build --dir /app/src
```

### USER ###
为运行镜像时或者任何接下来的`RUN`指令指定运行用户名或UID：

    USER daemon

### MAINTAINER ###
使用MAINTAINER指令来为生成的镜像署名作者

    MAINTAINER author's name mailaddress

### The `.dockerignore` file ###
`.dockerignore`用来忽略上下文目录中包含的一些image用不到的文件，它们不会传送到docker daemon。规则使用go语言的匹配语法。如：
```
$ cat .dockerignore
.git
tmp*
```

更多内容参考[Dockerfile最佳实践](http://xgknight.com/2014/12/20/dockerfile_best_practice1)系列。官方有个[Dockerfile tutorial](格式)练习Dockerfile的写法，非常简单但对于养成良好的格式、注释有一些帮助。

### Dockerfile示例 ###
下面的`Dockerfile`是MySQL官方镜像的构建过程。从ubuntu基础镜像开始构建，安装mysql-server、配置权限、映射目录和端口，`CMD`在从这个镜像运行到容器时启动mysql。其中`VOLUME`定义的两个可挂载点，用于在host中挂载，因为数据库保存在主机上而非容器中才是比较安全的。

```
#
# MySQL Dockerfile
#
# https://github.com/dockerfile/mysql
#

# Pull base image.
FROM dockerfile/ubuntu

# Install MySQL.
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server && \
  rm -rf /var/lib/apt/lists/* && \
  sed -i 's/^\(bind-address\s.*\)/# \1/' /etc/mysql/my.cnf && \
  sed -i 's/^\(log_error\s.*\)/# \1/' /etc/mysql/my.cnf && \
  echo "mysqld_safe &" > /tmp/config && \
  echo "mysqladmin --silent --wait=30 ping || exit 1" >> /tmp/config && \
  echo "mysql -e 'GRANT ALL PRIVILEGES ON *.* TO \"root\"@\"%\" WITH GRANT OPTION;'" >> /tmp/config && \
  bash /tmp/config && \
  rm -f /tmp/config

# Define mountable directories.
VOLUME ["/etc/mysql", "/var/lib/mysql"]

# Define working directory.
WORKDIR /data

# Define default command.
CMD ["mysqld_safe"]

# Expose ports.
EXPOSE 3306
```

使用：
```
$ docker build -t="dockerfile/mysql" github.com/dockerfile/mysql

或下载Dockerfile内容再当前目录：
$ docker build -t="dockerfile/mysql" .
```
（提示，上述第一条命令，如果你的host不可以连接Docker Hub，那么需要在启动docker服务时使用`HTTP_PROXY=`——用于build的时更新下载软件，同时执行`docker build`的终端设置`http_proxy`和`https_proxy`用于下载Dockerfile）

运行：
```
$ docker run -d --name mysql -p 3306:3306 dockerfile/mysql
或
$ docker run -it --rm --link mysql:mysql dockerfile/mysql bash -c 'mysql -h $MYSQL_PORT_3306_TCP_ADDR'
```

### 参考 ###
- [Dockerfile Reference 中文](https://github.com/HoO-Group/docker-heat/wiki/Dockerfile-Reference)
- [Dockerfile详解](http://www.leiem.com/post-222.html)
- [dockerpool-build-instructions](http://www.dockerpool.com/static/books/docker_practice/dockerfile/instructions.html)
- https://docs.docker.com/reference/builder/
- https://docs.docker.com/articles/dockerfile_best-practices/
- http://syntaxsugar.cn/2014/07/09/dockerfile/
