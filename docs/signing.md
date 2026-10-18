# Android 签名材料

## 现状：已迁出仓库（2026-10-18）

本仓库是 **public**，此前 `android/key.properties`（含明文口令）与
`android/app/proxypin-release.jks` 都随代码提交，`build-apk.yml` 里还写死了
`-storepass`。等于把发布私钥公开了。任何拿到仓库的人都能签出与正式包**相同签名**的
APK，而 Android 只认签名 —— 可以直接覆盖安装官方版本。

当前状态：

- 仓库内**不再包含**任何 keystore / key.properties（`android/.gitignore` 已恢复忽略）；
- 签名材料只存在于 GitHub Actions Secrets；
- `android/app/build.gradle` 完全走环境变量
  `RELEASE_STORE_FILE` / `RELEASE_STORE_PASSWORD` / `RELEASE_KEY_ALIAS` / `RELEASE_KEY_PASSWORD`；
- `build-apk.yml` 从 `RELEASE_STORE_BASE64` 解码到 `$RUNNER_TEMP`，缺任何一个 Secret
  直接 `exit 1`（不会再静默产出 unsigned APK）；
- 每个 APK 构建完都用 `apksigner verify --print-certs` 校验，确保用的是发布密钥。

### 当前发布密钥

| 项 | 值 |
|---|---|
| 主体 | `CN=proxypin, OU=Release, O=proxypin, L=Shenzhen, ST=Guangdong, C=CN` |
| 算法 | RSA 4096 / SHA384withRSA |
| 有效期 | 10950 天（约 30 年） |
| 别名 | `proxypin` |
| 证书 SHA-256 | `68:49:88:48:1C:90:C4:2D:93:C9:71:EB:15:12:54:38:08:1F:5E:71:BF:15:3B:75:D9:3A:02:43:86:63:7C:76` |

用户可用 `apksigner verify --print-certs app-release.apk` 核对该指纹。

### 需要的 4 个仓库 Secret

| Secret | 内容 |
|---|---|
| `RELEASE_STORE_BASE64` | `base64 -w0 proxypin-release.jks` 的输出 |
| `RELEASE_STORE_PASSWORD` | keystore 口令 |
| `RELEASE_KEY_ALIAS` | `proxypin` |
| `RELEASE_KEY_PASSWORD` | 密钥口令（JKS 下与 store 口令相同） |

## 本地构建

CI 之外（本地 / 自建）需要自己准备签名材料，且**不要提交**：

```bash
cat > android/key.properties <<'EOF'
storePassword=<口令>
keyPassword=<口令>
keyAlias=proxypin
storeFile=<绝对路径>/proxypin-release.jks
EOF
```

或者直接传环境变量：

```bash
export RELEASE_STORE_FILE=$HOME/keys/proxypin-release.jks
export RELEASE_STORE_PASSWORD=...
export RELEASE_KEY_ALIAS=proxypin
export RELEASE_KEY_PASSWORD=...
flutter build apk --release
```

没有任何签名材料时会产出 unsigned APK（本地开发可用，不要分发）。

## 再次轮换

```bash
scripts/rotate_signing_key.sh          # 只生成并打印
scripts/rotate_signing_key.sh --push   # 生成并用 gh CLI 直接写入 4 个 Secret
```

轮换会让**已安装的旧版本无法覆盖升级**（签名不同，系统拒绝安装）。如果已上架商店，
必须走「上传密钥重置」流程，否则新包无法上传。

## 历史提交里的旧密钥

删除文件只是让 `main` 的当前快照干净；旧 keystore 仍能从历史提交（以及所有 fork /
缓存）恢复，因此**旧密钥按已泄露处理，已作废**。要彻底抹除需要重写历史：

```bash
git filter-repo --path android/app/proxypin-release.jks \
                --path android/key.properties --invert-paths
git push --force --all && git push --force --tags
```

这会改写所有 commit sha，影响协作者与已有 release 的 tag 指针，需单独确认后再执行。
