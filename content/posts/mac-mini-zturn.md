---
title: 记一次Mac mini折腾过程（鼠键共享，更换SSD）
date: 2016-01-18 16:32:49
tags: [Mac, 鼠标键盘, synergy]
categories: 
- Mac OSX
updated: 2016-01-18 16:32:49
---


从公司网管那捣鼓来一个“遗弃” Mac mini，说其它人觉得用起来太卡，正好我的工作PC( CPU 4×i3，MEM 8G, HDD 500G)软件开多了也觉得有些卡，特别是我使用浏览器的习惯不太好，每次搜索统一结果都要打开好多标签页对比，文章性质的觉得有用想将来记录下来就没关闭页面，一两个星期下来只Chrome使用的内存就达到4G多。不用也浪费，于是就拿Mac mini分摊一下压力。

![macmini-a1347.jpg][1]

刚拿到手时心想得有多不堪配置才使得的Mac mini卡到嫌弃的地步，看了下底面的型号，A1347——这是2014年底出的新款，没有我想象的那么旧，还好。于是找来显示器、鼠键准备开用了（在某宝上买根八字电源线）。

但是开机密码没有啊！虽然简单重装是个办法，但我还是想看看里面现在是什么样的，杀鸡焉用牛刀。直接Crack root...

---

# 1. 破解Mac root密码
找到这篇文章 http://wowking.blog.51cto.com/1638252/753774 。我们平头百姓手头哪会有刻录的Mac OS光盘，而且也没移动光驱，所以方法一就不考虑了。方法二是单用户模式，毕竟 OS X 也是*nix血统，命令行几个命令倒难不到我。

可是众所周知，Mac的键盘跟普通键盘是不一样的，开机启动的时候`command + S`在一般美式键盘下到底能不能进入单用户模式呢？嗯，行的，按下mini的开机按钮之后不断 `win + S`。进入Single user model之后提示符#root>，逐步输入以下命令：

```
    # 执行硬盘检测（只读）, 这一步可以省略
    /sbin/fsck -y

    # 加载文件系统（读/写）
    /sbin/mount -uaw

    # 删除初始化设置时的OSX生成的隐藏文件”.applesetupdone”
    rm /var/db/.AppleSetupDone

    # 重启
    reboot
```

<!-- more -->

重启后开机画面会指导你创建一个新的**管理员**账号，然后这个新的账号密码登陆。就是这么简单，接下来删用户抹除一切使用痕迹😄。

进去之后着实令我窃喜：OS X Yosemite, 2.6 GHZ Intel Core i5, 8G DDR3, Intel Iris 1536 MB, 1TB HDD，就这配置比得上我当前的Win PC了，高兴得捡了块宝似的。优胜美地系统与我自己的Mac Book Pro一样，无缝立马开始用。

然而面临的一个问题来了，现在2台工作电脑，配有2套鼠标键盘，切换太不方便了。于是我用大腿想了想，嗯，应该有专门的多台电脑间共享鼠键的软件。啪啪啪几下锁定两款`Sharemouse`、`Synergy`。

---

# 2. 跨平台共享鼠标键盘-synergy
先来简单说一下Sharemouse，收费，但你懂的，但这东西毕竟用的人少，要分别在在windows和Mac两个平台上找到相同版本的破解版是多么不容易。中间折腾就不说了，成功使用 V2.0.53 版本。但号称的拖拽文件我始终没看到，我猜还是不同系统的缘故。sharemouse是有阉割了拖拽和加密功能的免费版的，而且配置超级简单，基本上只要在同一局域网，各自把软件装上，就可以用其中随便哪一电脑的鼠键来回在两个显示器之间滑动，而且还有dimmy效果。（抱歉，因为文章是后写的，没截图）

[Synergy](http://synergy-project.org/download/free/)也是鼎鼎大名的一款，而且开源、跨平台，也能复制剪切版和拖拽文件，据说它是谷歌工程师标配，因为他们也有在多台主机间控制电脑困扰。

但synergy公司也很奇葩，工具开源，但最新版的下载不免费，你要支付之后才能看到新版下载页面（旧版本免费开放，但你明知道有bug而且已解决，纠结吧少年）。我想原因大概是synergy既要遵守开源协议，但又要维持收入吧。奇怪的是网上竟然很少有人把它共享下载。当然，如果你不嫌麻烦，可以去 https://github.com/symless/synergy 下载源码，自己编译，synergy还很友好的提供了编译指南...点到为止，我也不想再浪费无谓的折腾时间。

这里分享v1.7.4版本下载，链接: http://pan.baidu.com/s/1mhbaLza 密码: m4d7

我现在一直使用的是synergy，鼠键接在Windows主机，但有一个问题没解决：synergy即使加入了Mac mini（用户）开机启动，但用户没输密码登陆之前，是不会启动synergy的，所以还是要另外接一套鼠键来输密码，随后synergy接管，衰，不知谁有更好的办法？

下面简单介绍配置过程。

## windows作服务端
synergy跟sharemouse很大不同在于，sharemouse是不分Server和Client的，鼠键可以插在任意一台电脑上，而synergy要求鼠键在Server，需要鼠键的其它电脑可以没有。

1. 勾选 【Server】，可以看到当前ip
![macmini-synergy-server][2]

2. 点击 【设置服务端】，默认最中间显示器代表当前电脑
![macmini-synergy-server-settings][3]

从右上角拖一个到你想要展示的相对位置，双击编辑 【屏幕名】（即其它电脑的主机名）

## mac做客户端
1. 在mac【设置】里选择【安全与隐私】，点击【隐私】选项卡，【辅助功能】，勾选右边的 Synergy。

![macmini-synergy-client-pre.jpg][4]

2. 勾选【Client】，输入上一节看到的服务端ip。

![macmini-synergy-client.jpg][5]

同时注意 screen name 就是上一节要填入的屏幕名，也是主机名啦。
不要忘了 start，看到 starting cocoa loop 就正常了，享受 “一键” 的快感吧。

偷偷的往后瞥了一眼，那个同事还说2套鼠键来回用。。。

多说一句，synergy或sharemouse跟kvm切换器不同，不能实现kvm switch的屏幕扩展、录像等功能，kvm switch显示器也是共用的。


一切似乎都完美了，开开心心的typing, browsing了2个星期，卡！一直盯着那个圈转啊转啊。Mac mini上任务也不算多，活动监视器也没看到CPU消耗大户。

这就是这台Mac mini被抛弃的原因吗？难道我也要放弃它吗？我陷入了深深的沉思。

网上查了查“Mac mini 换固态硬盘”，有大批的文章。一不做二不休，给Mac mini拆机换SSD ！

---

# 3. Mac mini换SSD

跟小吴关系好，要来一个SATA接口的128G三星固态硬盘850 EVO，查了3篇文章对着看，精确每一步，这么mini的mini，拆坏一个零件或者掉个螺丝，赔不起...

就是这几篇了：

1. [教程：2014款低配Mac mini换SSD固态硬盘](http://www.feng.com/iPhone/news/2015-08-12/Match-the-Mac-mini-tutorial-2014-low-SSD-solid-state-drives_621487.shtml)  (主要看这个，作者好有耐心)
2. [2014款mac mini 拆机 更换ssd 升级硬盘 固态硬盘 记录教程](http://bbs.feng.com/read-htm-tid-9010944.html)
3. 这还有个不是2014款的[拆解视频](http://www.tudou.com/programs/view/Y25qE4t8kNY/) (没看过，写文章的时候才搜到)

但是有个问题，旧的HDD换下来，新的SSD装上去，系统资料什么的可都没了。

解决这个问题方法可多了：

1. 有硬盘盒的话最方便。用Superduper或者Carbon Copy Cloner工具直接把源OSX系统+数据整盘镜像到你的SSD中，换好之后开机直接可以用了。
2. 先手动备份（拷贝）文件到其它系统/硬盘，换上SSD后用U盘全新安装OSX，恢复数据。

好吧，好像也没有那么多方法。虽然第一种比较通用而且技术含量高，但因为这台Mac并没用多久，文稿和软件不多，备份恢复容易，于是我选择了第2种。

另外又多说一句，Mac mini因为零部件排版紧密，没有台式机或笔记本那么多插拔的口子，CPU和内存是焊死在主板上的，所以是换不了滴。

接下来就是心灵手巧的我，漫长的两个小时的肢解和还原过程了，此处略去一万字。

拆的时候**螺丝按顺序分开放**，脑子记好零件位置，不确定之前先拍个照好还原，其它也没什么了。附图：

![macmini-change-ssd-1][6]
![macmini-change-ssd-2][7]

几点说明：

1. 第一步打开黑色后盖，用刀口起子或者硬薄片轻轻在下方撬动。早前一直想转开它（老版）
2. 用到两种螺丝刀 T6H和T9，JK 6089-A
3. 第3步取下wifi天线，有3根线各自连接的圆圈比较难取，我是用镊子夹住网上提的。取天线的时候往后小幅度摇摆拉拽。
4. 第4步说的取风扇排线，我是用手一边向上空提排线，一边镊子的小尖尖在下面翘。它的排线是从上空往下“按”的，跟平常印象里的“插”不一样。这个地方堵了好久
5. 第六步把主板撬出来很关键了。千万注意啊，是**水平**的往出口方向使劲，“推”出来，文中说“撬”有点误导。我是以下面做支点撬，那两个孔让我给弄坏了😓，还好不太要紧。
6. 装回去文章倒着往前看就是了

不得不说换完之后，很有成就感。下面就是装系统，感受一下要上天的ssd了。

# 4. U盘安装OS X
跟用U盘安装windows还是有点不同的，要先在一台Mac电脑上格式化U盘。参考这里[U盘全新安装OS X](http://www.iplaysoft.com/osx-yosemite-usb-install-drive.html)

1. 下载苹果官方 OS X Yosemite 正式版，解压得到 “Install OS X Yosemite.app”，拷贝到【应用程序】目录中
2. 使用Mac的【磁盘工具】，将U盘分区划成“Mac OS扩展(日志式)”、“GUID分区表”
3. 在终端里执行下面的命令

        sudo /Applications/Install\ OS\ X\ Yosemite.app/Contents/Resources/createinstallmedia --volume \
        /Volumes/Untitled --applicationpath /Applications/Install\ OS\ X\ Yosemite.app --nointeraction

    上面`/Volumes/Untitled`是U盘的名字。回车后，系统会提示你输入管理员密码，接下来就是等待系统开始制作启动盘了。

4. 从U盘启动安装 OS X
在Mac mini上插上U盘，启动Mac，然后一直按住【option】键（即Alt键，不行就重启多试几次）。
![macmini-osx-u-install.jpg][8]

5. 在进入刚进入安装过程后，要先对ssd盘格式化才能看到它。接下来就按照 [向导](http://tu.pcpop.com/all-771688.htm) 就可以完成安装了。建议appleID完成后再添加。



  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-a1347.jpg
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-synergy-server.png
  [3]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-synergy-server-settings.png
  [4]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-synergy-client-pre.png
  [5]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-synergy-client.png
  [6]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-ssd-1.jpg
  [7]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-ssd-2.jpg
  [8]: http://github.com/seanlook/sean-notes-comment/raw/main/static/macmini-osx-u-install.jpg


---

本文链接地址：http://xgknight.com/2016/01/18/mac-mini-zturn/

---
