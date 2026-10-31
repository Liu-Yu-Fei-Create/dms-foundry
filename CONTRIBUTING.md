# Contributing

Thanks for helping improve DMS Foundry.

## 开发环境

- macOS 14+
- Swift 6（Xcode 16+ 的命令行工具即可）

## 本地检查

```bash
cd mac
swift test                    # 37 条引擎测试
CONFIG=debug ./build.sh       # 组装 "DMS Foundry.app"
open "DMS Foundry.app"
```

提交 PR 前请确认 `swift test` 与 `build.sh` 都通过。CI 会在 `macos-14` 上跑同样两步。

维护者同步到 GitHub 可以用：

```bash
scripts/sync.sh "说明这次改了什么"
```

它会先跑 `swift test`，再 `git add -A && git commit && git push origin main`。

## 代码约定

- `DMSEngine` 只依赖 Foundation，不 import SwiftUI/AppKit；界面代码放 `DMSFoundry`。
- 颜色与间距走 `Shell/Theme.swift` 的 token，不要写死 `Color.white` / 魔法间距。
- 新增数据表必须写明来源、抓取日期与校验方式，并在 README 的「数据来源」表里登记。
- 不要提交 `mac/.build`、`*.app`、`runs.sqlite`、`server/keys/*.pem`。

## 报告问题

请附上 macOS 版本、应用版本（设置页底部或「关于」），以及复现步骤；涉及数据的请提供脱敏后的最小样例。
