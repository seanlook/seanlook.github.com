---
title: 关于研究生的一点担忧
date: 2014-11-30 18:21:25
aliases:
- /2014/11/30/thoughts_about_graduate_from_course/
updated: 2014-11-30 20:46:23
tags: [feelings, graduate]
categories: Feel
---

最近有个在大学玩的比较好现在在读研的同学，来询问我一些如何给老师做精品课程在线测试系统的问题，从沟通中我忍不住从个人的角度来表达一下感想和担忧。

![rate_online_test][1]

首先从我接收到的信息来看，高校导师为了给自己擅长的课程评选上学校、市级或省级精品课程，急于完成一个展示成果的平台，只要能在最短的时间内提交所能看的见的成果，那就表明有效率和实力。所以这个在线测试系统只需要能够展示一个页面，页面上有单项、多选题，提交测试后直接显示对错和总分，无需记录测试者姓名等其他任何与试题无关的信息，也就是没有数据库。差不多就是一个静态页面了，对错的判断，包括答案都固定在代码里面了。我相信稍微了解IT软件开发的人都知道，这样的系统设计可以让人感到无语，当然还有很多不是计算机类专业的，可能看不懂这些，只关心最终实现的效果达到预期就行。偏偏导师和所交予任务的学生，都不懂设计和编程。所以当我说至少应该有个数据库时，“太麻烦，不懂，周期太长”。由于是出于帮忙的目的，也就没有说太多的话来打击他的积极性，说多了反而有点表现自己有多牛B的嫌疑，就硬着头皮做了个demo。

由此可见大学老师为评上精品课程，那种急功近利的心理，只要对外宣传“我们有一个在线测评系统来检验学生学习效果，blablabla...”，然后评选小组比对评选规则里面有“在线测评”，加分！但请问像上面那样的系统意义何在？老师不知道有谁做过测试，不知道分数，只知道“当前浏览xxx次”，学生完全取决于是否主动。我想如果老师把这个测评当做一个硬性要求或作为所熟知却非常神秘的“平时成绩”的一部分，那只能是通过某种方式提交测试截图了。我心还想，在线测评系统一次性完成上线，是不是就再也不会修改了，加题减题，都要大动干戈的去修改后台代码，丝毫没有规划以后的扩展，当然也许我想多了，因为“这就是很简单的一个测试系统”，嗯，都说是测试而不是正式环境了，认真你就输了。

![rate_online_test][2]

这里做个小插曲。我们生活的环境，充斥着太多的指标、太多的名声。想起上周在我司门口早上卖炸酱面的摊贩被城管执法包围那件事。每天早上这位大叔家的炸酱面是附近最好吃的，每天都排着很长的队，如果不赶时间我和同事们都会优先选择这家。大家都生活不易，城管也是，起早贪黑，四处蹲点追赶流动摊贩，因为没有业绩没有完成指标，如何回去交差。又想起电视里报道过某地的交警每月要达到罚款20万的指标，这说多了其实就是社会问题了，我们这些小众市民除了旁观，祈祷不要发生在我们身上，还能做些什么呢。指标本应该是一个积极充满正能量的、督促机构上进的一个目标，但是如果是为了充数而不择手段去实现，急功近利，那就变质了。

<!-- more -->

就在线测评问题来说，个人觉得比较合适的做法，应该是要具有一个长远的观念，为何学校不统一做一个在线测评系统，其他各个课程申请账号，获得出题的资格，自由的在后台添加题目，是否需要记录分数和姓名，老师还可以统计对比各班的情况，甚至在评上精品课程以后，作为进一步考核的数据来源，一次投入，无限产出。相比每门课程做重复低效的工作，一眼就可以看出利弊了。导师舍不得花钱请廉价的学生开发一个拿得出手的系统，只能让手下的研究生“自己看着办”。

另外一方面是我对研究生所表现出来的担忧，是关于学习方法和学习能力。研究生最后毕业靠的是一纸论文，我相信会有高水平有独立见解的论文，但大部分论文“借鉴”的成分会不会太高呢？我们原创性的东西太少了，习惯捡现成的东西，包括我自己也是，写一份配置文档需要google许多文章，然后东抄西拆，拼接起来，但至少它都是实践有效了，对于我个人来说具有较大的参考价值。然而在大学里养成了这样的习惯，就会慢慢的丧失学习能力，遇见要解决一个全新的问题，第一反应不是自己去网上检索，而是找到会的直接问“这个怎么做？”。我该如何回答是好呢？

提问也是有智慧的，问得太宽泛，需要与回答者反复沟通来确认具体的问题，才给出什么样的答案。依然是最初的例子，同学使用ASP.NET来做一个在线测试系统，但他完全不懂编程，于是就问了我“有哪些方法，要准备啥”（还好不是宽泛的问“要怎么做”），我告诉他一些流程性的东西，要基本会一些什么，但他说他是小白，编程基础几乎为零。还是为了快速拿出成果，于是我就违心的打开了2年没有点开竟然没有卸载的Visual Studio 2010，一边搜索，一边拖拉控件，许多基本知识都忘了，做了个及其简陋的demo，拙劣的后台代码自己都不忍直视。我一直不承认自己是个程序猿，实际上也不是，但依然偶尔会兼职一下。很难说我是不是把自己同学给害了，没害是这种可快速复制、完成任务的技能已经学会了，毕竟这一次之后他再也不必学习编程，害他是我把现成的东西给他了。其实任何一本书、任何一篇博客教程都可以自己琢磨快速搞定，而不是一出现问题“表格怎么做”、“图片怎么查”，我真就回了一句“ 搜索关键字 ‘html 表格’、‘asp.net 插入图片’ ”，当然一部分原因是当时忙，没有时间手把手教。

遇到问题，自己查阅资料，自己去理解，练习独立的去面对、解决问题，琢磨不明白的再去问，这样也不会浪费对方太多时间。当然简单一句话的能搞定的问题，也没必要说让提问者去走冤枉路，大概就是这个“度”的问题区分了人与人之间的差距和性格吧，无所谓绝对的对错。

写这么多，有点不自量力了，额，请看到的同学不要对号入座，没有任何针对性和攻击性。

  [1]: http://github.com/seanlook/sean-notes-comment/raw/main/static/give_yourself_courage.jpg
  [2]: http://github.com/seanlook/sean-notes-comment/raw/main/static/rate_online_test.png
