---
title: 完全解决Github Pages邮件两次warning（DNS解析问题）
date: 2014-11-08 01:21:25
updated: 2014-11-09 00:46:23
tags: [github,troubleshooting]
categories: Github
---
之所以有本文是由于Github前后两次发了2封不同的警告邮件，都是关于DNS配置的。因为`xgknight.com`刚申请下来时我也是参考其他博客，在`seanlook.github.com`仓库下面建立了一个`CNAME`文件，内容：`xgknight.com`，然后去DNSPod绑定域名和IP（207.97.227.245）访问也就没事了。然而几天之后每次deploy博客的时候都会受到一封`build warning`邮件（见本文最后），后来参考下面的文章：

- [解决GitHub Pages Warning邮件提醒](http://mayecn.com/blog/2014/05/17/githubpages-accelerating/)
- [一步步在GitHub上创建博客主页-最新版 — 自定义域名的新玩法](http://www.pchou.info/web-build/2014/07/04/build-github-blog-page-08.html)
- [Faster, More Awesome GitHub Pages](https://github.com/blog/1715-faster-more-awesome-github-pages) 和 [GitHub Pages Legacy IP Deprecation](https://github.com/blog/1917-github-pages-legacy-ip-deprecation)

但显然第一篇有点拆东墙补西墙，只是换了个离自己最近的服务器，CDN根本就没用上，也是因为我`dig seanlook.github.io +nostats +nocomments +nocmd`之后把IP改成了103.245.222.133，才有了第二封邮件的warning（见本文最后）。第二篇倒是跟官方（第三条）是同一个意思，但是博主放弃了原本的顶级域名而是用www子域名。
首先根据邮件提示，明确一下最终目的：
- 使用顶级域名`xgknight.com`来访问站点
- 子域名`www.xgknight.com`跳转到`xgknight.com`
- 充分Github Pages提供的cdn加速功能

两份邮件大概是同一个意思，说Github Pages正在进行重大的升级来提供更快的访问速度，所以我们指定的域名解析的IP在不就的将来将要废弃，需要指向一个合法的IP，第二封邮件说的更明确了，为了使用CDN加速功能，需要增加`CNAME`的子域名解析记录。

> 如果你正在使用顶级域名（example.com）而不是子域名（如www.example.com），并且你的DNS解析服务提供商不支持`ALIAS`记录，那么唯一的选择就是使用`A`记录，但这种配置没有办法利用CDN加速了（依然可以应对DoS攻击）。如果切换成子域名或使用支持`ALIAS`的DNS解析上，都可以利用CDN和应对DoS。

<!-- more -->

不料我现在的情形正是，使用顶级域名`xgknight.com`，DNSPod不支持`ALIAS`记录。虽然目前不使用CDN加速访问起来没感觉有多大问题，但对于我这种有轻微强迫症并追求完美的人来说，就是看不惯这个warnning。DNS解析服务不想换成付费的支持`ALIAS`的DNSimple，那么难道只能启用www子域名了吗？对于有些已经对你的网站做了链接的地方，随便修改域名可不是什么好事。于是我就尝试了下面的设置：
在DNSPod中去掉其它映射记录，添加`CNAME`记录的顶级域名映射到`seanlook.github.com`，github仓库下的CNAME文件也是顶级域名`xgknight.com`。经过这样设置后访问`xgknight.com`发现完全没有问题：
![dnspod_cname_apex](http://github.com/seanlook/sean-notes-comment/raw/main/static/dnspod_cname_apex.png)
中国境内的ping值：
```
$ ping xgknight.com
正在 Ping github.map.fastly.net [103.245.222.133] 具有 32 字节的数据:
来自 103.245.222.133 的回复: 字节=32 时间=215ms TTL=42
来自 103.245.222.133 的回复: 字节=32 时间=210ms TTL=42
来自 103.245.222.133 的回复: 字节=32 时间=205ms TTL=42
来自 103.245.222.133 的回复: 字节=32 时间=221ms TTL=42
```
美国的一个IP的ping值：
```
rhcsh> ping xgknight.com
PING github.map.fastly.net (199.27.76.133) 56(84) bytes of data.
64 bytes from 199.27.76.133: icmp_seq=1 ttl=43 time=8.15 ms
64 bytes from 199.27.76.133: icmp_seq=2 ttl=43 time=8.12 ms
64 bytes from 199.27.76.133: icmp_seq=3 ttl=43 time=8.23 ms
64 bytes from 199.27.76.133: icmp_seq=4 ttl=43 time=8.02 ms
```
可以看到是用上了CDN加速的特性。
但这样与官方给的做法是不同的，以防再出现什么问题，后来我通过邮件咨询过Github Pages的技术支持，反复告诉我说为www子域名添加CNAME记录到seanlook.github.com，为顶级域名添加A记录到[IP addresses listed here](https://help.github.com/articles/tips-for-configuring-an-a-record-with-your-dns-provider/#configuring-an-a-record-with-your-dns-provider)，仓库下的CNAME文件为子域名。来回好几封英文邮件就没有正面给出回答的。因为我还没有系统去了解过域名解析服务的原理，所以只好自己测试了。
保持上面的设置，即仓库的CNAME文件内容保持不变，为Apex domian—`xgknight.com`，DNSPod只有顶级域名的CNAME记录映射到`seanlook.github.com`，测试是可以提供CDN，但www域名无法访问，更不会跳转了。于是我分别继续了下面的测试：
(1) DNSPod再添加一条www子域名的CNAME指向`seanlook.github.com`，因为很容易理解的是访问www.xgknight.com也可以直接使用CDN加速了（官方一直建议有这样一条记录），但结果是不跳转。不行！
(2) DNSPod新添加的记录是 A record ，指向官方所建议的那个IP之一（192.30.252.153），结果达到要求，www.xgknight.com自动跳转到xgknight.com，自然顶级域名采用了CDN。

所以问题最终得到解决的方案是：

- 仓库下的CNAMEw文件内容：
```
$ cat CNAME
xgknight.com
```
- DNSPod的域名解析记录
```
主机记录  记录类型    线路类型 	        记录值 	      MX优先级    TTL
    @       CNAME       默认       seanlook.github.com.       -       600
    @       NS          默认       f1g1ns1.dnspod.net.        -       600
    @       NS          默认       f1g1ns2.dnspod.net.        -       600
    www     A           默认       192.30.252.153             -       600
```

(注意，DNSPod域名设置里有一个“域名别名”与这个`ALIAS`记录是完全不同的概念。)

## 邮件内容 ##

### 每次部署后都有一封邮件 ###

> GitHub <noreply@github.com>
11月6日 (3天前)
发送至 我 
The page build completed successfully, but returned the following warning:
GitHub Pages recently underwent some improvements (https://github.com/blog/1715-faster-more-awesome-github-pages) to make your site faster and more awesome, but we've noticed that xgknight.com isn't properly configured to take advantage of these new features. While your site will continue to work just fine, updating your domain's configuration offers some additional speed and performance benefits. Instructions on updating your site's IP address can be found at https://help.github.com/articles/setting-up-a-custom-domain-with-github-pages, and of course, you can always get in touch with a human at support@github.com. For the more technical minded folks who want to skip the help docs: your site's DNS records are pointed to a deprecated IP address.
For information on troubleshooting Jekyll see:
  https://help.github.com/articles/using-jekyll-with-pages#troubleshooting
If you have any questions please contact us at https://github.com/contact.

### 第二天的第二封邮件 ###

> GitHub Support <support@github.com>
11月7日 (2天前)
发送至 我 
Hi Sean,
The custom domain for your GitHub Pages site seanlook/seanlook.github.com needs attention. You must take immediate corrective action to ensure that your site remains available after December 1st, 2014.
Please follow the instructions for setting up a custom domain with GitHub Pages (http://github.cmail1.com/t/i-l-schrd-fkdtrjkl-y/) to update your custom domain’s DNS settings to point to the proper GitHub IP addresses.
Why the change?
Nearly a year ago, we announced improvements to how we serve GitHub Pages sites (http://github.cmail1.com/t/i-l-schrd-fkdtrjkl-j/). This week we’re making that change permanent  (http://github.cmail1.com/t/i-l-schrd-fkdtrjkl-t/)by deprecating our old GitHub Pages infrastructure. If your custom domain is pointed at these legacy IPs, you’ll need to update your DNS configuration immediately to keep things running smoothly.
How long do I have to make the switch?
Starting the week of November 10th, pushing to a misconfigured site will result in a build error and you will receive an email stating that your site’s DNS is misconfigured. Your site will remain available to the public, but changes to your site will not be published until the DNS misconfiguration is resolved.
For the week of November 17th, there will be a week-long brownout for improperly configured GitHub Pages sites. If your site is pointed to a legacy IP address, you will receive a warning message that week, in place of your site’s content. Normal operation will resume at the conclusion of the brownout.
Starting December 1st, custom domains pointed to the deprecated IP addresses will no longer be served via GitHub Pages. No repository or Git data will be affected by the change.
Okay, I’m sold. What do I need to do?
Please follow the instructions for setting up a custom domain with GitHub Pages (http://github.cmail1.com/t/i-l-schrd-fkdtrjkl-i/) to update your custom domain’s DNS settings to point to the proper GitHub IP addresses.
Questions? We’re here to help(http://github.cmail1.com/t/i-l-schrd-fkdtrjkl-d/).
Happy Publishing!
— The GitHub Pages Team
