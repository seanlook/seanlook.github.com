---
title: markdown语法备忘笔记
date: 2014-10-25 01:21:25
tags: [markdown, hexo博客]
categories: 
- 其它
updated: 2014-10-27 10:46:23
---

##1. 什么是markdown##

##2. 我选择的markdown编辑器##
首先选择适合自己的markdown编辑器需要考虑几个方面：
平台：Mac OS X, Windows, Online, 插件形式
预览：实时预览、html预览
语法：选定某一款后，适应自己的习惯，不必太复杂
其它：如主题，快捷键，同步等

###首先来说一下以下几款为什么我没选用：（纯属个人喜好）###
- Sublime Text的插件markdown preview，编辑和预览是分离的，在浏览器里预览。
- CuteMarkEd，独立编辑器，支持多平台，不知道为什么我的编辑和预览窗口字体都那么丑。
- MarkdownPad，独立编辑器，windows下口碑比较好的，但我把曾经写好的md文章放进去，格式不太对，应该是语法上略有差别，其它都还好。它多标签页的形式可以加分。
社区活跃，新功能反馈及时，例如 toc replace
- vim或emacs的markdown插件，windows平台下我还是正常一点吧。
###习惯采用的编辑器###
- Haroopad，不得不说韩国人开发的软件体验上超赞，与segmentfault的文章写作一样，左右实时预览，多种主题可选。如果能实现多标签页就更好了。各平台上都可以使用，还有vim编辑模式。
![markdown_haroopad][1]
- 马克飞象，google浏览器插件，专为印象笔记开发的浏览器markdown扩展，用起来特别舒服，自动保存在本地缓存，没有导出html格式或浏览器在线预览的功能，但比MaDe好用多了。（现在有离线客户端版）
![markdown_makefeixiang][2]
- 在线markdown编辑器（首先你得有网络）
[github]：不用多说
[MaHua](http://mahua.jser.me/)：与Mac OS X上相传甚广的Mou风格类似
[cmd markdown](https://www.zybuluo.com/mdeditor)：大牛开发的
##3. 常用markdown语法##
### 标题/粗斜体 ###

<!-- more -->

文章内容较多时，可以用标题分段：

\# 一级标题 #
\## 大标题 ##
\### 小标题 ###
sf只有三级标题

### 粗体/斜体 ###
\*斜体文本\*　　　　　或　　\_斜体文本\_　　　　显示成　 *斜体文本*
\**粗体文本\*\*　　 　　或　　\_\_粗体文本\_\_　　　显示成　　 **粗体文本**
\*\*\*粗斜体文本\*\*\*　 　 或　　\_\_\_粗斜体文本\_\_\_　显示成　***粗斜体文本***
### 代码段 ###
行内代码：\`code here\`　显示成　`code here`
代码段落：
（可为某种语言指定高亮效果如 \` \` \`python，支持bash、javascript、java、sql、xml、html等，有的markdown不支持指定语言）
\` \` \`
$(document).ready(function () {
    alert('hello world');
});
\` \` \`
显示成
```
$(document).ready(function () {
    alert('hello world');
});
```
我觉得sf的markdown代码段前后间距太大了有木有。
### 链接和图片 ###
**文字链接**
`[seanlook](http://segmentfault.com/blog/seanlook/1190000000738685)`　显示成　[seanlook](http://segmentfault.com/blog/seanlook/1190000000738685)
如果一个网址要被多个地方引用，可用变量替代
这个链接用 1 作为网址变量 [Google]\[1]
这个链接用 yahoo 作为网址变量 [Yahoo!]\[yahoo]
然后在文档的结尾为变量赋值（网址）
  `[1]: http://www.google.com/`
  `[yahoo]: http://www.yahoo.com/`
  [1]: http://www.google.com/
  [yahoo]: http://www.yahoo.com/
最终显示成
[Google][1]
[Yahoo!][yahoo]


页内跳转实现
**图片链接**
markdown不能设置图片的尺寸，图片居中
多个空格会合并成一个，多个（广义的，包括空格和tab）空行显示成一个空行，以空行区分段落
### 多个空格显示 ###
两个全角空格　　或 &nbsp; &nbsp; &nbsp; &nbsp;八个&lt;space&gt;&amp;nbsp;　　或&emsp;&emsp;&amp;emsp;&amp;emsp;&amp;emsp;
<pre><code>加上&lt;pre>&lt;code>   文字1    任意空格  &lt;pre>&lt;code></pre></code>

        行首四个空格    自动转换成代码段  独立段落  任意空格
##4. 参考##
- [Markdown 系列应用收集](http://appinn.me/d/83)

  [1]: http://git.oschina.net/uploads/images/2016/0304/111256_dcf5a8a6_416534.png
  [2]: http://git.oschina.net/uploads/images/2016/0304/111321_cd78274a_416534.png

---

本文链接地址： http://xgknight.com/2014/10/25/markdown-tips/

---
