#!/usr/bin/env bash
#
# 轮换 Android 发布签名（会改变应用签名，已安装的旧版本无法直接升级）。
#
# 用法：
#   scripts/rotate_signing_key.sh [输出目录]
#
# 脚本只做本地能做的部分：
#   1. 生成新 keystore（RSA 2048 / 10000 天）
#   2. 输出 base64（可直接贴进 GitHub Secret）
#   3. 打印需要配置的 4 个仓库 Secret 与 workflow 片段
#
# 它不会、也不能替你：在 GitHub 仓库设置 Secret、删除历史中的旧 jks、
# 通知用户升级（旧包无法覆盖安装新包）。
set -euo pipefail

OUT_DIR="${1:-.}"
ALIAS="${RELEASE_KEY_ALIAS:-proxypin}"
STORE_FILE="${OUT_DIR%/}/proxypin-release-v2.jks"

if [[ -e "$STORE_FILE" ]]; then
  echo "错误：$STORE_FILE 已存在，请先移走（避免覆盖正在使用的密钥）" >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "错误：找不到 keytool（需要 JDK 17+）" >&2
  exit 1
fi

read -r -s -p "新 keystore 口令（至少 6 位）：" STORE_PASS
echo
read -r -s -p "再次输入：" STORE_PASS2
echo
if [[ "$STORE_PASS" != "$STORE_PASS2" ]]; then
  echo "错误：两次口令不一致" >&2
  exit 1
fi
if [[ ${#STORE_PASS} -lt 6 ]]; then
  echo "错误：口令太短" >&2
  exit 1
fi

keytool -genkeypair -v \
  -keystore "$STORE_FILE" \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$STORE_PASS" -keypass "$STORE_PASS" \
  -dname "CN=Taffy, C=CN"

chmod 600 "$STORE_FILE"

echo
echo "已生成：$STORE_FILE"
echo "别名：$ALIAS"
echo
echo "== 1. 在 GitHub 仓库 Settings → Secrets and variables → Actions 添加 =="
echo "   RELEASE_STORE_BASE64   = 下面这行输出"
echo "   RELEASE_STORE_PASSWORD = 你刚才输入的口令"
echo "   RELEASE_KEY_ALIAS      = $ALIAS"
echo "   RELEASE_KEY_PASSWORD   = 同上口令"
echo
echo "----- base64（整行复制） -----"
base64 -w0 "$STORE_FILE" 2>/dev/null || base64 "$STORE_FILE"
echo
echo "------------------------------"
echo
cat <<'YAML'
== 2. 在 .github/workflows/build-apk.yml 的构建步骤前加 ==

      - name: Decode keystore
        run: |
          echo "${{ secrets.RELEASE_STORE_BASE64 }}" | base64 -d > android/app/proxypin-release-v2.jks
      - name: Build APK
        env:
          RELEASE_STORE_FILE: proxypin-release-v2.jks
          RELEASE_STORE_PASSWORD: ${{ secrets.RELEASE_STORE_PASSWORD }}
          RELEASE_KEY_ALIAS: ${{ secrets.RELEASE_KEY_ALIAS }}
          RELEASE_KEY_PASSWORD: ${{ secrets.RELEASE_KEY_PASSWORD }}
        run: flutter build apk --release
YAML
echo
echo "== 3. 确认 CI 出包签名无误后 =="
echo "   - 删除仓库内 android/key.properties 与 android/app/proxypin-release.jks"
echo "   - 去掉 android/.gitignore 里的 !proxypin-release.jks"
echo "   - 用 git filter-repo 清理历史（旧密钥仍可从历史提交恢复）"
echo "   - 已上架商店需走「上传密钥重置」流程"
