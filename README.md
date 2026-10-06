# CloudFlareScan (ipv4&ipv6)  

[![Downloads](https://img.shields.io/github/downloads/xiaolin-007/CloudFlareScan/total?style=flat-square&logo=github)](https://github.com/xiaolin-007/CloudFlareScan/releases)
[![Latest Version](https://img.shields.io/github/release/xiaolin-007/CloudFlareScan.svg?style=flat-square)](https://github.com/xiaolin-007/CloudFlareScan/releases)
[![License](https://img.shields.io/github/license/xiaolin-007/CloudFlareScan?style=flat-square)](https://github.com/xiaolin-007/CloudFlareScan/blob/main/LICENSE)

CloudFlare 扫描器 （简称CFS)  适配 Win  macOS  Android  Linux

软件演示视频：https://www.youtube.com/watch?v=Fw2W4B77bts

⚠️免责声明：本工具仅供学习和合法网络测速，请遵守当地法律法规，造成的一切后果自负。

<img width="611" height="476" alt="14eaeb7504c8db5685f261513fd8ecf2" src="https://github.com/user-attachments/assets/46976c98-f8ce-4d55-948b-05151c0f4d03" />


🚀 高效扫描：自动从 CloudFlare 官方 IP 段生成 IP 地址

📊 双模式测速：完全测速 + 地区测速，满足不同需求

🌍 全球覆盖：内置全球大部分机场IATA代码映射，自动识别地区

⚡ 异步处理：支持高并发测试，快速获取结果

📋 一键复制：双击表格单元格即可复制内容

📈 实时统计：显示扫描进度、速度

🔗 节点分享：按速度阈值筛选 IP，一键生成 `vless://` 分享链接（本分支新增）

使用方法：

win-X64 直接下载使用

Android 直接下载安装  

macOS arm 安装提前 需要将安全性与隐私里-选择允许从任何来源

终端输入命令：sascript -e 'do shell script "sudo spctl --master-disable" with administrator privileges'

Linux系统使用方法：解压后

chmod +x CloudFlareScan

./CloudFlareScan

## 节点分享（新增功能）

测速完成后，点击 **节点分享** 按钮，即可把“速度超过阈值”的 IP 导出为 `vless://` 分享链接。

工作流程：`IPv4/IPv6 扫描` → `完全测速 / 地区测速` → `节点分享`

筛选规则：只保留下载速度 **严格大于** 速度阈值的 IP，并按速度从高到低排序。
阈值单位与测速结果一致（MB/s），默认为 `2`，在弹窗中可随时修改，下方会实时显示命中数量。

弹窗中可配置的参数（会自动记住上次填写的内容）：

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| 速度阈值 | 只分享速度大于该值的 IP，单位 MB/s | `2` |
| UUID | 分享链接中的用户 ID | `73bcd72f-9545-4cb8-8daf-7d004501880d` |
| 伪装域名 Host | 链接中的 `host` 参数 | `mjw04.ccwu.cc` |
| SNI | 链接中的 `sni` 参数，留空则与 Host 相同 | `mjw04.ccwu.cc` |
| WS 路径 | WebSocket 路径 | `/` |
| 备注前缀 | 生成“前缀 + 序号”形式的节点名 | `CF移动优选` |
| 起始序号 | 备注起始编号 | `1` |
| 端口 | 留空表示沿用测速端口；也可填 `443,2083` 为每个 IP 生成多端口节点 | 留空 |
| ECH | 是否输出 `ech` 参数 | 开启 |
| Base64 订阅格式 | 勾选后按 Base64 订阅内容输出（部分客户端要求） | 关闭 |

输出示例（默认参数、起始序号 2）：

```
vless://73bcd72f-9545-4cb8-8daf-7d004501880d@104.17.214.222:443?path=%2F&security=tls&encryption=none&insecure=0&host=mjw04.ccwu.cc&fp=chrome&ech=cloudflare-ech.com%2Bhttps%3A%2F%2Fdns.alidns.com%2Fdns-query&type=ws&allowInsecure=0&sni=mjw04.ccwu.cc#CF%E7%A7%BB%E5%8A%A8%E4%BC%98%E9%80%892
```

点击 **复制到剪贴板** 可直接粘贴使用，点击 **导出文件** 可保存为 `.txt`。

## 测试

```bash
python test_node_share.py
```

测试覆盖分享链接格式（与样本逐字符比对）、速度筛选、端口处理、IPv6 方括号、Base64 订阅、弹窗交互，以及标准库 HTTP 解析与 Android 打包约束。

## 构建 Android 安装包 (APK)

官方工具 [`pyside6-android-deploy`](https://doc.qt.io/qtforpython-6/deployment/deployment-pyside6-android-deploy.html)
**只支持 Linux / macOS 主机**，因此提供两条路径：

### 方式一：GitHub Actions 云端构建（推荐，本机无需环境）

1. 把本目录推到 GitHub 仓库；
2. 打开仓库 **Actions → Build Android APK → Run workflow**，选择架构（默认 `aarch64`）；
3. 构建完成后在该次运行的 **Artifacts** 里下载 `CloudFlareScan-android-aarch64`（内含 APK）。

工作流文件：`.github/workflows/android.yml`。打 tag（`v*`）也会自动触发构建。

流水线做的事：装 JDK 17 → 装 `PySide6==6.10.3` → 下载 Android SDK/NDK 与 Qt for Python Android wheel
（两者都有缓存）→ 调用 `android/build_apk.sh` 打包 → 上传 APK。

### 方式二：本地 Linux / macOS 构建

前置条件：JDK 17+、**Python 3.11（必须 ≤ 3.11，3.12 及以上会被 buildozer 拒绝）**、`git`、`curl`。

```bash
python3 -m pip install "PySide6==6.10.3"
cd CloudFlareScan
bash android/build_apk.sh
```

脚本会自动下载 Android SDK/NDK（缓存到 `~/.pyside6_android_deploy`，约数 GB，仅首次）、
下载 Qt for Python Android wheel、生成并修正 `pysidedeploy.spec`，最后产出 APK。
首次构建需要编译 CPython 与依赖，耗时较长（30 分钟以上）。

> 现已确认的坑（都已处理）：
> - SDK/NDK 缓存目录是 `~/.pyside6_android_deploy`（**下划线**），Qt 文档里写的连字符版本是错的；
> - `--init` 也必须显式传 `--wheel-pyside/--wheel-shiboken`：这两个参数是否必填取决于命令行有没有 `-c`；
> - 主机 Python 必须 ≤ 3.11；
> - `main.py` 必须位于运行命令时的工作目录下（脚本会先 `cd` 到项目根目录）。

常用环境变量：`ANDROID_ARCH`（`aarch64`/`x86_64`）、`BUILDOZER_MODE`（`debug` 出 apk、`release` 出 aab）、
`ANDROID_NDK_PATH`、`ANDROID_SDK_PATH`。

### Android 适配说明

为让同一份代码能在 Android 上跑起来，做了以下调整（均通过 `IS_ANDROID` 分支隔离，不影响桌面版）：

* **去掉 aiohttp 依赖**：原先只用它发一个 HTTP GET 取地区码，现改为标准库 `asyncio` + `ssl` 实现。
  这样少掉 aiohttp/multidict/yarl/frozenlist/propcache 等 8 个需要交叉编译的 C 扩展依赖，
  显著提高 `python-for-android` 打包成功率。
* **入口文件**：新增 `main.py`（`pyside6-android-deploy` 强制要求入口名为 `main.py`），
  桌面版与 Android 版共用 `CloudFlareScan.run_app()`。
* **字体**：Android 使用系统自带 `Noto Sans CJK SC`（`DejaVu Sans` 没有中文字形）。
* **窗口尺寸**：手机屏幕按 dp 通常仅 360~420 宽，Android 下按钮宽度、Tab 宽度与最小窗口尺寸都会收窄，
  启动时铺满屏幕；节点分享弹窗的提示文字改为长按提示，避免三列布局挤压。
* **文件保存**：Android 下默认保存到应用私有目录（无需存储权限），节点分享仍可一键复制到剪贴板。


