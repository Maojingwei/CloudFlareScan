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

测试覆盖分享链接格式（与样本逐字符比对）、速度筛选、端口处理、IPv6 方括号、Base64 订阅以及弹窗交互。


