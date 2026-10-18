#!/usr/bin/env bash
#
# 轮换 Android 发布签名（会改变应用签名，已安装的旧版本无法直接升级）。
#
# 用法：
#   scripts/rotate_signing_key.sh [输出目录] [--push]
#
#   --push   生成后用 gh CLI 直接把 4 个值写进仓库 Secrets（需要已 gh auth login）
#
# 生成物：
#   <输出目录>/proxypin-release-<日期>.jks   私钥（chmod 600，切勿提交）
#   <输出目录>/proxypin-release-<日期>.b64   base64，供 RELEASE_STORE_BASE64
#
# 仓库是 public：任何提交进 git 的 keystore 都应视为已泄露。签名材料只放 Secrets。
set -euo pipefail

usage() {
  echo "用法: scripts/rotate_signing_key.sh [输出目录] [--push]"
}

PUSH=0
OUT_DIR="."
for arg in "$@"; do
  case "$arg" in
    --push) PUSH=1 ;;
    -h|--help) usage; exit 0 ;;
    *) OUT_DIR="$arg" ;;
  esac
done

ALIAS="${RELEASE_KEY_ALIAS:-proxypin}"
STAMP="$(date +%Y%m%d)"
STORE_FILE="${OUT_DIR%/}/proxypin-release-${STAMP}.jks"
B64_FILE="${OUT_DIR%/}/proxypin-release-${STAMP}.b64"
DN="${RELEASE_DNAME:-CN=proxypin, OU=Release, O=proxypin, L=Shenzhen, ST=Guangdong, C=CN}"

if [[ -e "$STORE_FILE" ]]; then
  echo "错误：$STORE_FILE 已存在，请先移走（避免覆盖正在使用的密钥）" >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "错误：找不到 keytool（需要 JDK 17+）" >&2
  exit 1
fi

read -r -s -p "新 keystore 口令（至少 12 位）：" STORE_PASS
echo
read -r -s -p "再次输入：" STORE_PASS2
echo
if [[ "$STORE_PASS" != "$STORE_PASS2" ]]; then
  echo "错误：两次口令不一致" >&2
  exit 1
fi
if [[ ${#STORE_PASS} -lt 12 ]]; then
  echo "错误：口令太短（建议 24 位以上随机串）" >&2
  exit 1
fi

# JKS：keyPassword 必须与 storePassword 相同（PKCS12 不允许分开设置，
# 而老版本 AGP 对 PKCS12 的 alias 处理有差异，这里保持 JKS 最稳）。
keytool -genkeypair -v \
  -keystore "$STORE_FILE" \
  -storetype JKS \
  -alias "$ALIAS" \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -storepass "$STORE_PASS" -keypass "$STORE_PASS" \
  -dname "$DN"

chmod 600 "$STORE_FILE"
base64 -w0 "$STORE_FILE" > "$B64_FILE" 2>/dev/null || base64 "$STORE_FILE" > "$B64_FILE"

echo
echo "已生成：$STORE_FILE"
echo "base64：$B64_FILE"
echo "别名：$ALIAS"
echo
echo "== 证书指纹（分发后可用 apksigner verify --print-certs 核对）=="
keytool -list -v -keystore "$STORE_FILE" -storepass "$STORE_PASS" -alias "$ALIAS" \
  | grep -iE "SHA256:|有效期|Valid" || true
echo

if [[ "$PUSH" == "1" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "错误：--push 需要 gh CLI（https://cli.github.com）" >&2
    exit 1
  fi
  gh auth status >/dev/null 2>&1 || { echo "错误：请先 gh auth login" >&2; exit 1; }
  gh secret set RELEASE_STORE_BASE64 < "$B64_FILE"
  gh secret set RELEASE_STORE_PASSWORD --body "$STORE_PASS"
  gh secret set RELEASE_KEY_PASSWORD --body "$STORE_PASS"
  gh secret set RELEASE_KEY_ALIAS --body "$ALIAS"
  echo "已写入 4 个仓库 Secret：RELEASE_STORE_BASE64 / RELEASE_STORE_PASSWORD /"
  echo "  RELEASE_KEY_PASSWORD / RELEASE_KEY_ALIAS"
  echo "下一次 CI 构建即使用新密钥（可用 apksigner 核对指纹）。"
else
  cat <<'TXT'
== 手工设置（或用脚本的 --push 自动完成）==
  仓库 Settings → Secrets and variables → Actions：
    RELEASE_STORE_BASE64   = 上面 .b64 文件的整行内容
    RELEASE_STORE_PASSWORD = 刚才输入的口令
    RELEASE_KEY_ALIAS      = 别名
    RELEASE_KEY_PASSWORD   = 同一口令

  .github/workflows/build-apk.yml 已内置解码步骤，无需再改 workflow。
TXT
fi

echo
cat <<'TXT'
== 收尾 ==
  - 私钥与 b64 文件不要提交（android/.gitignore 已忽略 *.jks）
  - 旧 keystore 已在 public 仓库历史中，按已泄露处理；彻底清除用 git filter-repo
  - 已安装的旧版本无法覆盖升级；已上架商店需走「上传密钥重置」流程
TXT
