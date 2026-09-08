![](https://github.com/hooke007/mpv_PlayKit/blob/lite/Temp/mpv_PK.jpg)

# mpv播放器折腾记录

_从萌新到大白，<s>用前嫌麻烦</s> 用后真香_  
[命令行播放器 mpv](https://github.com/mpv-player/mpv) 的设置历史存档（windows10/11）

前往上方的 [**📖Wiki 维基版块📖**](../../wiki) 查看文档导航和关于子目录中各文件的说明

如有自定义的需求，建议在原档文件基础上修改；如果另自行新建文本，注意编码最好为 **UTF-8** ，换行符为 **LF** ，否则mpv可能无法识别  

从零开始接触mpv且不使用懒人包的话可参考
- [《win10/11 mpv播放器通用教程》](https://hooke007.github.io/unofficial/mpv_start.html)  

## 主要分支

- [**main**](https://github.com/hooke007/mpv_PlayKit/tree/main) 当前使用与曾使用过的全部文件（附详细说明、持续维护）
- [**lite**](https://github.com/hooke007/mpv_PlayKit/tree/lite) 懒人包的核心设置同步

## 懒人包 mpv-lazy

懒人包是解压即可使用的完整解决方案  
使用前务必完整阅读 [《新快速说明》](https://github.com/hooke007/mpv_PlayKit/discussions/194)  

下载请见 [**🏷发布版块 Releases🏷**](../../releases)  
反馈前往 [**💬讨论版块 Discussions🗨️**](../../discussions)

## Linux 配置包

GitHub Actions 也会随同 Windows 发布 Linux 配置包。仓库中的
`packaging/portable_config` 是 Windows/Linux 共用的标准配置来源。构建时先从 fork
复制这组配置，再从原始项目取得需要的外部辅助文件，最后 Windows 应用
`packaging/windows.patch`、Linux 应用 `packaging/linux.patch`。播放器和 Linux 的其它
运行时由用户按发行版自行安装，例如 Fedora、RHEL 等系统可以先执行：

```bash
sudo dnf install mpv yt-dlp
```

解压发布包后，把其中的 `portable_config` 复制到 `~/.config/mpv/`，再按实际使用的
滤镜安装可选的 VapourSynth、模型和其它依赖。

## 自动发布

`.github/workflows/build-release.yml` 会在每周日生成一次 GitHub pre-release，并在每月
1 日生成一次正式 release。Windows 发布 noVS、标准版和 vsNV 叠加包；Linux 发布配置
包，不捆绑播放器二进制。Windows 的 mpv、umpv、yt-dlp、VapourSynth、K7sfunc 和
vs-mlrt 均从各自的原始项目 release 下载，手动运行时可以覆盖版本来源；构建记录会
写入每个 release 的元数据文件。

## 预览

![](https://github.com/hooke007/mpv_PlayKit/blob/lite/Temp/mpv-lazy-lite.png)  
![](https://github.com/hooke007/mpv_PlayKit/blob/obs/Temp/IMG/index-%E6%96%B0%E7%95%8C%E9%9D%A2%E4%B8%8E%E4%B8%8A%E4%B8%8B%E6%96%87%E8%8F%9C%E5%8D%95.webp)
