# Android 签名材料

## 现状（需要你决策）

仓库当前**提交了** `android/key.properties` 与 `android/app/proxypin-release.jks`，
且 `android/.gitignore` 显式放行。任何拿到仓库的人都能用同一 alias/口令签出与
正式包**同签名**的 APK（Android 只认签名，因此可覆盖安装官方版本）。

代码侧已做好迁移准备：

- `android/app/build.gradle` 优先读环境变量
  `RELEASE_STORE_FILE` / `RELEASE_STORE_PASSWORD` / `RELEASE_KEY_ALIAS` / `RELEASE_KEY_PASSWORD`，
  未设置时才回退到 `key.properties`；
- `debug` buildType 已改回系统 debug 签名（此前 debug 也用 release 签名）。

## 一键生成新密钥

```bash
scripts/rotate_signing_key.sh
```

脚本会生成 `proxypin-release-v2.jks`、直接打印可粘贴的 base64、并输出需要配置的 4 个
GitHub Secret 与 workflow 片段（它不会也不能替你设置 Secret）。

## 轮换步骤（会让已装旧版本无法直接升级，需提前通知）

1. 生成新 keystore：
   ```bash
   keytool -genkeypair -v -keystore proxypin-release-v2.jks -alias proxypin \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
2. 在 GitHub 仓库 Settings → Secrets and variables → Actions 添加：
   - `RELEASE_STORE_BASE64`（`base64 -w0 proxypin-release-v2.jks`）
   - `RELEASE_STORE_PASSWORD`
   - `RELEASE_KEY_ALIAS`
   - `RELEASE_KEY_PASSWORD`
3. 在 `.github/workflows/build-apk.yml` 中加一步解码：
   ```yaml
   - name: Decode keystore
     run: echo "${{ secrets.RELEASE_STORE_BASE64 }}" | base64 -d > android/app/proxypin-release-v2.jks
   ```
   并设置 `RELEASE_STORE_FILE=proxypin-release-v2.jks` 等环境变量。
4. 确认 CI 出包签名正确后，删除仓库内的 `key.properties` / `proxypin-release.jks`，
   把 `.gitignore` 里的 `!proxypin-release.jks` 去掉，并用 `git filter-repo` 清理历史。
5. 若已上架应用商店，需按其「上传密钥重置」流程操作。

> 未完成第 4 步之前，签名材料仍可从仓库取得。
