#!/usr/bin/env bash
# Flutter Web 构建并上传到阿里云 OSS
# 用法: ./scripts/deploy-web-oss.sh

set -euo pipefail

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# OSS 配置
OSS_BUCKET="${OSS_BUCKET:-qdbot-bucket01}"
OSS_REGION="${OSS_REGION:-cn-beijing}"
OSS_ENDPOINT="${OSS_ENDPOINT:-oss-cn-beijing.aliyuncs.com}"
OSS_ACCESS_KEY_ID="${OSS_ACCESS_KEY_ID:-}"
OSS_ACCESS_KEY_SECRET="${OSS_ACCESS_KEY_SECRET:-}"

# CDN 域名（可选，留空则用 OSS 地址）
CDN_BASE_URL="${CDN_BASE_URL:-}"

# 上传目录
REMOTE_PATH="app_web"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_deps() {
  if ! command -v ossutil &> /dev/null; then
    log_warn "ossutil 未安装，正在安装..."
    if [[ "$(uname)" == "Darwin" ]]; then
      brew install aliyun-ossutil
    else
      wget -O /usr/local/bin/ossutil https://gossp.alicdn.com/ossutil/ossutil?filename=ossutil64 && chmod +x /usr/local/bin/ossutil
    fi
  fi
}

# 配置 ossutil
configure_ossutil() {
  ossutil config --endpoint "$OSS_ENDPOINT" \
    --accessKeyID "$OSS_ACCESS_KEY_ID" \
    --accessKeySecret "$OSS_ACCESS_KEY_SECRET" \
    --stsToken "" \
    --configFile ~/.ossutilconfig
}

# 构建 Flutter Web
build_flutter() {
  log_info "构建 Flutter Web..."
  cd "$SCRIPT_DIR"

  # 禁用 PWA service worker
  flutter build web --release --base-href=/app_web/ --pwa-strategy=none 2>&1

  # 删除 service worker
  rm -f build/web/flutter_service_worker.js

  # 添加版本号到 bootstrap JS 防止缓存
  sed -i '' "s/flutter_bootstrap.js?v=[0-9]*/flutter_bootstrap.js?v=$(date +%s)/" build/web/index.html 2>/dev/null \
    || sed -i "s/flutter_bootstrap.js?v=[0-9]*/flutter_bootstrap.js?v=$(date +%s)/" build/web/index.html

  log_info "构建完成: build/web/"
}

# 上传到 OSS
upload_to_oss() {
  log_info "上传到 OSS..."

  local build_dir="${SCRIPT_DIR}/build/web"
  local oss_path="oss://${OSS_BUCKET}/${REMOTE_PATH}/"

  # 上传所有文件，删除目标路径下不在源路径中的文件
  ossutil cp --delete "$build_dir" "$oss_path" --force --recursive

  log_info "上传完成: $oss_path"
}

# 生成 CDN URL
get_cdn_url() {
  if [[ -n "$CDN_BASE_URL" ]]; then
    echo "$CDN_BASE_URL"
  else
    echo "https://${OSS_BUCKET}.${OSS_ENDPOINT}"
  fi
}

# 主流程
main() {
  log_info "Flutter Web 部署到阿里云 OSS"
  log_info "Bucket: $OSS_BUCKET"
  log_info "Region: $OSS_REGION"

  check_deps
  configure_ossutil
  build_flutter
  upload_to_oss

  local cdn_url="$(get_cdn_url)"
  log_info "部署完成！"
  log_info "访问地址: ${cdn_url}/${REMOTE_PATH}/"
}

main "$@"
