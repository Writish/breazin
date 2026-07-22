<p align="center">
  <img src="Sources/Breazin/Resources/AppIcon.png" width="160" alt="Breazin logo">
</p>

# Breazin（呼息）

Breazin 是一款面向 macOS 的 AI 视频编辑器。当前仓库处于产品化基础改造阶段：品牌、应用身份、数据目录、更新通道与本地 MCP 服务已经按开发、预发布、生产三套环境隔离。

## 本地开发

要求 macOS 26、Xcode 26 与 Swift 6.2 或更高版本。

```bash
swift build
swift test
scripts/bundle.sh debug --fast --without-speech
open .build/Breazin.app
```

`swift run Breazin` 使用 development 配置；应用包通过 `BREAZIN_ENVIRONMENT` 选择环境：

| 环境 | 显示名 | Bundle ID | URL Scheme | MCP 端口 |
| --- | --- | --- | --- | --- |
| development | 呼息 Dev | `com.writish.breazin.dev` | `breazin-dev` | 19790 |
| staging | 呼息 Beta | `com.writish.breazin.beta` | `breazin-beta` | 19791 |
| production | 呼息 | `com.writish.breazin` | `breazin` | 19789 |

详细配置见 [本地开发说明](docs/development/local-setup.md) 与 [环境隔离 ADR](docs/architecture/adr/0001-product-environments.md)。

## 兼容与安全默认值

- 新项目使用 `.breazin`；旧 `.palmier` 项目仍可打开，便于用户迁移。
- MCP 服务只监听 loopback，并且默认关闭。
- 开发环境不启用自动更新；staging 与 production 使用彼此独立的更新源与签名配置。
- 凭据只通过 Keychain 或环境变量注入，不进入仓库。

## 上游来源与许可

本项目基于 Palmier Pro `v0.6.13`（commit `4ad06353ffaae0ea6e2cfc515e8f8920daa10d57`）建立。上游来源、基线结果和保留内容见 [UPSTREAM_BASELINE.md](UPSTREAM_BASELINE.md)；历史多语言文档作为来源证据保存在 `docs/upstream/`，不代表 Breazin 当前产品能力或发布渠道。

代码按 [GNU General Public License v3.0](LICENSE) 发布。Breazin 的商标、名称与图形资产不因代码许可证而获得额外授权。
