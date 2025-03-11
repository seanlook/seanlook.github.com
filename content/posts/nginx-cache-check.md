---
title: nginx做负载均衡器以及proxy缓存配置
date: 2015-06-02 01:21:25
aliases:
- /2015/06/02/nginx-cache-check/
updated: 2015-06-02 00:46:23
tags: [nignx, 负载均衡, 缓存]
categories: [Linux, Nginx]
---

关于nginx的安装和基本配置请参考[nginx](http://xgknight.com/2015/05/17/nginx-install-and-config)，本文在原基础上完成以下几个功能：

- 结合proxy和upstream模块实现nginx负载均衡
- 结合`nginx_upstream_check_module`模块实现后端服务器的健康检查
- 使用`nginx-sticky-module`扩展模块实现Cookie会话黏贴（session-sticky效果）
- 使用proxy模块实现静态文件缓存
- 使用`ngx_cache_purge`实现更强大的缓存清除功能

# 1. 安装及模块说明
上面提到的3个模块都属于第三方扩展模块，需要提前下好源码，然后编译时通过`--add-moudle=src_path`一起安装。

注意：

- 使用 nginx_upstream_check_module(简记为m1) 时要先为nginx打上相应版本的patch，我的nginx版本为 1.6.3，所以patch对应 m1 解压后目录下的`check_1.5.12+.patch`，所以进入nginx源码目录，执行 patch -p1 ...（见下方示例）
- nginx-sticky-module-ng(简记为m2) 模块可以单独使用，但是因为m1监控检查的方式是依赖于m2的，所以要使用m2，还要对m1打上patch，进入m2源码目录，执行 patch -p0...

编译示例：（CentOS 6.5 x86_64, nginx 1.6.3）

    # yum -y install gcc gcc-c++ make libtool zlib zlib-devel openssl openssl--devel pcre pcre-devel

    # cd nginx-1.6.3
    # patch -p1 < ../nginx_upstream_check_module-0.3.0/check_1.5.12+.patch

    # cd ../nginx-sticky-module-ng-1.2.5
    # patch -p0 < ../nginx_upstream_check_module-0.3.0/nginx-sticky-module.patch

    # ./configure --prefix=/usr/local/nginx-1.6 --with-pcre 
    --with-http_stub_status_module --with-http_ssl_module --with-http_gzip_static_module --with-http_realip_module 
    --add-module=../nginx_upstream_check_module-0.3.0 --add-module=../nginx-sticky-module-ng-1.2.5 --add-module=../ngx_cache_purge-2.3
    # make && make install

如果你想在已安装好的nginx上添加第三方模块，依然需要重新编译，但为了不覆盖你原有的配置，请不要make install，而是直接拷贝可执行文件：
```
# nginx -V              //可以看到原来的编译选项，下面用到
# ./configure ... --add-module=..       //你的第三方模块
# make           //make后不要install，改用手动拷贝。先备份
# cp objs/nginx /usr/local/nginx-1.6/sbin/nginx
```

# 2. nginx-sticky-module
项目地址：https://bitbucket.org/nginx-goodies/nginx-sticky-module-ng 

这个模块的作用是通过cookie黏贴的方式将来自同一个客户端（浏览器）的请求发送到同一个后端服务器上处理，这样一定程度上可以解决多个backend servers的session同步的问题 —— 因为不再需要同步，而RR轮询模式必须要运维人员自己考虑session同步的实现。

另外内置的 ip_hash 也可以实现根据客户端IP来分发请求，但它很容易造成负载不均衡的情况，而如果nginx前面有CDN网络或者来自同一局域网的访问，它接收的客户端IP是一样的，容易造成负载不均衡现象。淘宝Tengine的 ngx_http_upstream_session_sticky_module 也是类似的功能。nginx-sticky-module的cookie过期时间，默认浏览器关闭就过期，也就是会话方式。

这个模块并不合适不支持 Cookie 或手动禁用了cookie的浏览器，此时默认sticky就会切换成RR。它不能与ip_hash同时使用。

![nginx-lb-sticky.jpg][1]

<!-- more -->

## 2.1 sticky配置 ##
```
upstream backend {
    server 172.29.88.226:8080 weight=1;
    server 172.29.88.227:8080 weight=1;
    sticky;
}
```
配置起来超级简单，一般来说一个`sticky`指令就够了。

`sticky [name=route] [domain=.foo.bar] [path=/] [expires=1h] [hash=index|md5|sha1] [no_fallback];`：

- `name`: 可以为任何的 string 字符,默认是 route
- `domain`：哪些域名下可以使用这个 cookie 
- `path`：哪些路径对启用 sticky，例如 path/test，那么只有 test 这个目录才会使用 sticky 做负载均衡
- `expires`：cookie 过期时间，默认浏览器关闭就过期，也就是会话方式。
- `no_fallbackup`：如果设置了这个，cookie 对应的服务器宕机了，那么将会返回502（bad gateway 或者 proxy error），建议不启用

你在查看[官方文档](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)可能会注意到里面也有个 sticky 指令，要说它们的作用几乎是一样的，但是你可能注意到`This directive is available as part of our commercial subscription.`的说明 —— 这是nginx商业版本里才有的特性。包括后面的`check`指令，在nginx的商业版本里也有对应的`health_check`（配在 location ）实现几乎一样的监控检查功能。

## 2.2 load-balance其它调度方案 ##

这里顺带介绍一下nginx的负载均衡模块支持的其它调度算法：

- `轮询`（默认） ： 每个请求按时间顺序逐一分配到不同的后端服务器，如果后端某台服务器宕机，故障系统被自动剔除，使用户访问不受影响。Weight 指定轮询权值，Weight值越大，分配到的访问机率越高，主要用于后端每个服务器性能不均的情况下。
- `ip_hash` ： 每个请求按访问IP的hash结果分配，这样来自同一个IP的访客固定访问一个后端服务器，有效解决了动态网页存在的session共享问题。当然如果这个节点不可用了，会发到下个节点，而此时没有session同步的话就注销掉了。
- `least_conn` ： 请求被发送到当前活跃连接最少的realserver上。会考虑weight的值。
- `url_hash` ： 此方法按访问url的hash结果来分配请求，使每个url定向到同一个后端服务器，可以进一步提高后端缓存服务器的效率。Nginx本身是不支持url_hash的，如果需要使用这种调度算法，必须安装Nginx 的hash软件包 nginx_upstream_hash 。
- `fair` ： 这是比上面两个更加智能的负载均衡算法。此种算法可以依据页面大小和加载时间长短智能地进行负载均衡，也就是根据后端服务器的响应时间来分配请求，响应时间短的优先分配。Nginx本身是不支持fair的，如果需要使用这种调度算法，必须下载Nginx的 upstream_fair 模块。

# 3. 负载均衡与健康检查

严格来说，nginx自带是没有针对负载均衡后端节点的健康检查的，但是可以通过默认自带的 ngx_http_proxy_module 模块和 ngx_http_upstream_module 模块中的相关指令来完成当后端节点出现故障时，自动切换到下一个节点来提供访问。

## 3.1 load-balance示例 ##
```
upstream backend {
    ip_hash;
    server 172.29.88.226:8080 weight 2;
    server 172.29.88.226:8080 weight=1 max_fails=2 fail_timeout=30s ;
    server 172.29.88.227:8080 backup;
}
server {
    location / {
        proxy_pass http://backend;
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;
    }
```

- `weight` ： 轮询权值也是可以用在ip_hash的，默认值为1
- `max_fails` ： 允许请求失败的次数，默认为1。当超过最大次数时，返回proxy_next_upstream 模块定义的错误。
- `fail_timeout` ： 有两层含义，一是在 30s 时间内最多容许 2 次失败；二是在经历了 2 次失败以后，30s时间内不分配请求到这台服务器。
- `backup` ： 预留的备份机器。当其他所有的非backup机器出现故障的时候，才会请求backup机器，因此这台机器的压力最轻。（为什么我的1.6.3版本里配置backup启动nginx时说`invalid parameter "backup"`？）
- `max_conns`： 限制同时连接到某台后端服务器的连接数，默认为0即无限制。因为`queue`指令是commercial，所以还是保持默认吧。

- `proxy_next_upstream` ： 这个指令属于 http_proxy 模块的，指定后端返回什么样的异常响应时，使用另一个realserver

## 3.2 nginx_upstream_check_module ##
nginx_upstream_check_module 是专门提供负载均衡器内节点的健康检查的外部模块，由淘宝的姚伟斌大神开发，通过它可以用来检测后端 realserver 的健康状态。如果后端 realserver 不可用，则后面的请求就不会转发到该节点上，并持续检查几点的状态。在淘宝自己的 tengine 上是自带了该模块。项目地址：https://github.com/yaoweibin/nginx_upstream_check_module 。

下面的是一个带后端监控检查的 nginx.conf 配置：
```
upstream backend {
    sticky;     # or simple round-robin
    server 172.29.88.226:8080 weight=2;
    server 172.29.88.226:8081 weight=1 max_fails=2 fail_timeout=30s ;
    server 172.29.88.227:8080 weight=1 max_fails=2 fail_timeout=30s ;
    server 172.29.88.227:8081;
    
    check interval=5000 rise=2 fall=3 timeout=1000 type=http;
    check_http_send "HEAD / HTTP/1.0\r\n\r\n";
    check_http_expect_alive http_2xx http_3xx;
}
server {
    location / {
        proxy_pass http://backend;
    }
    location /status {
        check_status;
        access_log   off;
        allow 172.29.73.23;
        deny all;
    }
```
上面配置的意思是，对name这个负载均衡条目中的所有节点，每个5秒检测一次，请求2次正常则标记 realserver状态为up，如果检测 3 次都失败，则标记 realserver的状态为down，超时时间为1秒。

check指令只能出现在upstream中：

- `interval` ： 向后端发送的健康检查包的间隔。
- `fall` ： 如果连续失败次数达到fall_count，服务器就被认为是down。
- `rise` ： 如果连续成功次数达到rise_count，服务器就被认为是up。
- `timeout` ： 后端健康请求的超时时间。
- `default_down` ： 设定初始时服务器的状态，如果是true，就说明默认是down的，如果是false，就是up的。默认值是true，也就是一开始服务器认为是不可用，要等健康检查包达到一定成功次数以后才会被认为是健康的。
- `type`：健康检查包的类型，现在支持以下多种类型
    - `tcp`：简单的tcp连接，如果连接成功，就说明后端正常。
    - `http`：发送HTTP请求，通过后端的回复包的状态来判断后端是否存活。
    - `ajp`：向后端发送AJP协议的Cping包，通过接收Cpong包来判断后端是否存活。
    - `ssl_hello`：发送一个初始的SSL hello包并接受服务器的SSL hello包。
    - `mysql`: 向mysql服务器连接，通过接收服务器的greeting包来判断后端是否存活。
    - `fastcgi`：发送一个fastcgi请求，通过接受解析fastcgi响应来判断后端是否存活
- `port`: 指定后端服务器的检查端口。你可以指定不同于真实服务的后端服务器的端口，比如后端提供的是443端口的应用，你可以去检查80端口的状态来判断后端健康状况。默认是0，表示跟后端server提供真实服务的端口一样。该选项出现于Tengine-1.4.0。

如果 type 为 http ，你还可以使用`check_http_send`来配置http监控检查包发送的请求内容，为了减少传输数据量，推荐采用 HEAD 方法。当采用长连接进行健康检查时，需在该指令中添加keep-alive请求头，如： `HEAD / HTTP/1.1\r\nConnection: keep-alive\r\n\r\n` 。当采用 GET 方法的情况下，请求uri的size不宜过大，确保可以在1个interval内传输完成，否则会被健康检查模块视为后端服务器或网络异常。

`check_http_expect_alive`指定HTTP回复的成功状态，默认认为 2XX 和 3XX 的状态是健康的。

![nginx-check-upstream][2]

![nginx-sticky-cookie.png][3]

# 4. nginx的proxy缓存使用
nginx的页面缓存功能与上面的负载均衡和健康检查是没有关系的，放在这里一是因为懒得再起一篇文章，二是再有load-balance的地方一般都会启用缓存的。

缓存也就是将js、css、image等静态文件从tomcat缓存到nginx指定的缓存目录下，既可以减轻tomcat负担，也可以加快访问速度，但这样缓存及时清理成为了一个问题，所以需要 `ngx_cache_purge` 这个模块来在过期时间未到之前，手动清理缓存。（这里有篇 [文章](http://quenlang.blog.51cto.com/4813803/1570671)，对比使用缓存、不使用缓存、使用动静分离三种情况下，高并发性能比较。使用代理缓存功能性能会高出很多倍）

```
http {
    ... // $upstream_cache_status记录缓存命中率
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"'
                      '"$upstream_cache_status"';

    proxy_temp_path   /usr/local/nginx-1.6/proxy_temp;
    proxy_cache_path /usr/local/nginx-1.6/proxy_cache levels=1:2 keys_zone=cache_one:100m inactive=2d max_size=2g;

    server {
        listen       80; 
        server_name  ittest.example.com;
        root   html;
        index  index.html index.htm index.jsp;

        location ~ .*\.(gif|jpg|png|html|css|js|ico|swf|pdf)(.*) {
            proxy_pass  http://backend;
            proxy_redirect off;
            proxy_set_header Host $host;
            proxy_set_header   X-Real-IP   $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_cache cache_one;
            add_header Nginx-Cache $upstream_cache_status;
            proxy_cache_valid  200 304 301 302 8h;
            proxy_cache_valid 404 1m;
            proxy_cache_valid  any 2d;
            proxy_cache_key $host$uri$is_args$args;
            expires 30d;
        }

        location ~ /purge(/.*) {
            #设置只允许指定的IP或IP段才可以清除URL缓存。
            allow   127.0.0.1;
            allow   172.29.73.0/24;
            deny    all;
            proxy_cache_purge  cache_one $host$1$is_args$args;
            error_page 405 =200 /purge$1;
        }
    }
}
```
说明

- `proxy_temp_path` ： 缓存临时目录。后端的响应并不直接返回客户端，而是先写到一个临时文件中，然后被rename一下当做缓存放在 proxy_cache_path 。0.8.9版本以后允许temp和cache两个目录在不同文件系统上（分区），然而为了减少性能损失还是建议把它们设成一个文件系统上。
- `proxy_cache_path ...` ： 设置缓存目录，目录里的文件名是 cache_key 的MD5值。
`levels=1:2 keys_zone=cache_one:50m`表示采用2级目录结构，Web缓存区名称为cache_one，内存缓存空间大小为100MB，这个缓冲zone可以被多次使用。文件系统上看到的缓存文件名类似于 /usr/local/nginx-1.6/proxy_cache/**c**/**29**/b7f54b2df7773722d382f4809d650**29c** 。
`inactive=2d max_size=2g`表示2天没有被访问的内容自动清除，硬盘最大缓存空间为2GB，超过这个大学将清除最近最少使用的数据。

- `proxy_cache` ： 引用前面定义的缓存区 cache_one
- `proxy_cache_key` ： 定义cache_key
- `proxy_cache_valid` ： 为不同的响应状态码设置不同的缓存时间，比如200、302等正常结果可以缓存的时间长点，而404、500等缓存时间设置短一些，这个时间到了文件就会过期，而不论是否刚被访问过。
- `expires` ： 在响应头里设置`Expires:`或`Cache-Control:max-age`，返回给客户端的浏览器缓存失效时间。

关于缓存的失效期限上面有三个选项：`X-Accel-Expires`、`inactive`、`proxy_cache_valid`、`expires`，它们之间是有优先级的，按上面的顺序如果在header里设置 X-Accel-Expires 则它的优先级最高，否则inactive优先级最高。更多资料请参考 [nginx缓存优先级](http://www.ttlsa.com/nginx/nginx-cache-priority/) 或[这里](http://fann.im/blog/2014/12/09/nginx-proxy_cache_valid/)。
![nginx-cache-hit.png][4]

## 清除缓存 ##
上述配置的`proxy_cache_purge`指令用于方便的清除缓存，但必须按照第三方的 ngx_cache_purge 模块才能使用，项目地址：https://github.com/FRiCKLE/ngx_cache_purge/ 。

使用 ngx_cache_purge 模块清除缓存有2种办法（直接删除缓存目录下的文件也算一种办法）：

1. echo发送PURGE指令
`proxy_cache_purge PURGE from 127.0.0.1`表示只允许在来自本地的清除指令
```
# echo -e 'PURGE / HTTP/1.0\r\n' | nc 127.0.0.1 80
```
2. GET方式请求URL
即使用配置文件中的`location ~ /purge(/.*)`，浏览器访问`http://ittest.example.com/purge/your/may/path`来清除缓存，或者`echo -e 'GET /purge/ HTTP/1.0\r\n' | nc ittest.example.com 80`

![nginx-cache-purge.png][5]


**参考**

- [official documentation](http://nginx.org/en/docs/http/ngx_http_upstream_module.html)
- [Nginx实战系列之功能篇----后端节点健康检查](http://nolinux.blog.51cto.com/4824967/1594029)
- [Tengine nginx_upstream_check_module](http://tengine.taobao.org/document_cn/http_upstream_check_cn.html)
- [nginx反向代理tomcat集群做负载均衡缓存](http://quenlang.blog.51cto.com/4813803/1570352)
- [web内容缓存 nginx高性能缓存详解](http://www.ttlsa.com/nginx/nginx-high-performance-caching/)
- [使用nginx sticky实现基于cookie的负载均衡](http://www.ttlsa.com/nginx/nginx-modules-nginx-sticky-module/)


  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-lb-sticky.jpg
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-check-upstream.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-sticky-cookie.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-cache-hit.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/nginx-cache-purge.png


---

原文链接地址：http://xgknight.com/2015/05/22/nginx-cache-check/

---
