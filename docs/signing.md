# Android 签名材料

## 现状（2026-10-18）

`android/key.properties` 与 `android/app/proxypin-release.jks` **按要求随仓库提交**
（个人测试仓库，自用，不分发 APK）。需要注意：本仓库是 public，因此这等同于公开私钥，
任何拿到仓库的人都能签出同签名 APK。

同时 GitHub Actions Secrets 里存着**同一把**新密钥（`RELEASE_STORE_BASE64` 等 4 个），
CI 优先用 Secrets，仓库副本供本地构建与备份。`build-apk.yml` 的准备步骤逻辑是：

1. `RELEASE_STORE_BASE64` 存在 → 解码到 `$RUNNER_TEMP`，走 Secrets；
2. 否则若仓库内有 `android/app/proxypin-release.jks` + `android/key.properties` → 走仓库副本；
3. 两者都没有 → `exit 1`（不会静默产出 unsigned APK）。

APK 构建完成后用 `apksigner verify --print-certs` 逐个校验，要求证书 `CN=proxypin`。

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

仓库里已经有可用的 `android/key.properties`，`flutter build apk --release` 直接能签。
如需换成别的密钥，可用环境变量覆盖：



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

## 旧密钥（口令含 taffy 的那把）

历史提交里旧 keystore 与 `key.properties` 保留不动（个人测试仓库，未清理），
但它**已不再用于出包**：CI 与本地构建都只用上面这把新密钥。若哪天需要清除历史，
再执行：

```bash
git filter-repo --path android/app/proxypin-release.jks \
                --path android/key.properties --invert-paths
git push --force --all && git push --force --tags
```

这会改写所有 commit sha，影响已有 release 的 tag 指针，需单独确认后再执行。
