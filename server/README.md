# 自托管更新目录

## 布局

```
server/
  stable/manifest.json          # 发布时生成
  stable/DMSFoundry-<ver>.zip   # 签名产物
  beta/manifest.json            # 可选测试通道
  keys/ed25519.pem              # 私钥（已 gitignore，绝不外传）
  keys/ed25519_pub.b64          # 公钥（build.sh 注入 Info.plist）
  example/                      # 本地演示用的示例产物
```

服务器只需要一个**公开可匿名访问的 HTTPS 静态目录**，例如：

```
https://your.domain/dmsfoundry/stable/manifest.json
```

要求：支持 Range（断点续传）、`manifest.json` 不缓存、`*.zip` 长缓存。

## 发布

```bash
cd mac
BASE_URL="https://your.domain/dmsfoundry/stable" \
  ./release.sh 0.2.1 3 "修复 xxx" "Fix xxx"
```

它会：构建 → 打包 zip → SHA-256 → Ed25519 签名 → 写 `server/stable/manifest.json`。

上传：

```bash
rsync -avz server/stable/ user@host:/path/to/dmsfoundry/stable/
```

## 密钥

- 私钥 `keys/ed25519.pem` 只留在发布机，**不要提交、不要放服务器**。
- 公钥 `keys/ed25519_pub.b64` 会被 `build.sh` 注入到 `Info.plist` 的 `DSFUpdatePublicKey`。
- 更换密钥等于更换信任根：旧客户端会拒绝新签名，需要通过一次"手动下载 + 替换"过渡。

## 客户端行为（当前 ad-hoc 阶段）

- 菜单「检查更新…」（⌘U）→ 填服务器地址 → 检查 → 下载 → **SHA-256 + Ed25519 双校验** → 落盘到 `~/Library/Application Support/DMSFoundry/updates/` → 在 Finder 中显示。
- **不做就地替换**：ad-hoc 签名下 Gatekeeper 会拦，手动把新版本拖进「应用程序」即可。
- 拿到 Developer ID + 公证后，再接 Sparkle 做真正的自动安装（M7）。
- 篡改测试已通过：改 zip → SHA-256 拒绝；改签名 → Ed25519 拒绝。
