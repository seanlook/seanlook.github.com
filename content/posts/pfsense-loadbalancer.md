---
title: 怎么用pfSense为你的web服务做负载均衡（翻译）
date: 2015-04-24 15:21:25
aliases:
- /2015/04/24/pfsense-loadbalancer/
updated: 2015-04-25 00:46:23
tags: [pfsense,vmware]
categories: Linux
---

本文翻译自Howtoforge上的一篇文章 [How To Use pfSense To Load Balance Your Web Servers](https://www.howtoforge.com/how-to-use-pfsense-to-load-balance-your-web-servers)。注意pfSense的负载均衡有两种：一是设置[多个WAN做双线负载均衡](https://doc.pfsense.org/index.php/Multi-WAN)，二是本文的为LAN内的[web服务器做inbound-loadbalancer](https://doc.pfsense.org/index.php/Inbound_Load_Balancing)。

这篇howto中展示了怎么使用pfSense 2.0 为你的多个web服务器配置负载均衡（load balancer）。这里假定在你的网络环境中已经拥有了一个pfSense服务器和2个以上的apache服务器，并且具有一定的pfSense知识。（*参考[图解pfSense软路由系统的使用（NAT功能](http://xgknight.com/2015/04/23/pfsense-usage/)*）

## 1. 前提 ##

- 一个安装好的pfSense 2.0 机器（如果它是你的外围防火墙，建议安装在物理机上）
- 至少2个apache服务器（可以是虚拟机）
- 确保在apache服务器之间代码文件是同步的（rsync、cororsync或其它可以保持web服务器间文件更新）

## 2. 配置pfSense ##
pfSense可以使用负载均衡的功能让特定的请求压力由多台服务器分担，这对于有多台应用的服务器很有帮助，因为你可以把负载压力分散到其它节点上而不是死磕一个节点。

### 2.1 Monitor ###
我们正式开始。首先点击`Services` -> `Load Balancers`，然后选择`Monitor`标签。

<!-- more -->

点击右边的`+`加号来添加一条记录，输入monitor的名字Name和描述Description（在这个示例名字和描述我都使用`ApacheClusterMon`），把类型Type设置成`HTTP`，主机地址Host设置一个还未使用的IP（后面我们将在这个IP上建立虚拟IP，这个虚拟IP会被分配到故障转移failover节点上，注：也有文章说把它设成WAN IP），`HTTP Code`保存默认的`200 OK`，然后点击`Save`保存并且使修改生效`Apply Changes`。
![image1.jpg][1]
![image2.jpg][2]
### 2.2 Pool ###
接着建立服务器池server pool。点击`Pools`标签的`+`按钮来添加一个池。

在该示例我指定`ApacheSrvPool`为服务池名称，设置`Mode`为`Load Balance`，端口80（。这个端口时你后端服务器的监听端口，你当然可以设定其它应用的其它端口，不一定非是web）。为这个池设定上一步创建的ApacheClusterMon，依次将你的所有web服务器IP添加到这个池中`Add to pool`，保存并应用。
![image3.jpg][3]
![image4.jpg][4]
### 2.3 Virtual Server ###
最后一步，选择`Virtual Servers`标签页，点击`+`来添加一条记录。填写名称`ApacheClusterVirtualServer`、描述和IP地址，这个IP地址与第1步中说的未使用的IP相同，端口80，所有发送到这个WAN IP:port的连接都会被转发到服务器池中。虚拟服务器池Virtual Server Poll选择上一步创建的。提交并应用。
![image5.jpg][5]
![image6.jpg][6]

搞定！最后不要忘记为虚拟服务器IP和池添加防火墙规则。


  [1]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image1.jpg
  [2]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image2.jpg
  [3]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image3.jpg
  [4]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image4.jpg
  [5]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image5.jpg
  [6]: https://www.howtoforge.com/images/using_pfsense_to_load_balance_your_web_servers/image6.jpg
