#!/usr/bin/env bash
# DeepSeek Harness (dsh) 国内安装脚本
# 默认从 Gitee 镜像克隆（已与 GitHub upstream 同步），所有包走 npmmirror
# 用法：bash install-dsh-cn.sh [GITEE_USER] [REPO]
#       默认 Gitee_USER=qianchilang REPO=deepseek-harness
# 依赖：Node.js ^22.19 || >=24，Git Bash / Linux / macOS

set -euo pipefail

GITEE_USER="${1:-qianchilang}"
REPO="${2:-deepseek-harness}"
GITEE_URL="https://gitee.com/${GITEE_USER}/${REPO}.git"
GITHUB_FALLBACK="https://ghfast.top/https://github.com/deepseek-ai/${REPO}.git"
NPM_MIRROR="https://registry.npmmirror.com"

# ---- 1. 终端 / 颜色 ----
if [ -t 1 ]; then RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; NC=$'\033[0m'; else RED=""; GRN=""; YLW=""; NC=""; fi
log()  { echo "${GRN}[+]${NC} $*"; }
warn() { echo "${YLW}[!]${NC} $*"; }
die()  { echo "${RED}[x]${NC} $*" >&2; exit 1; }

# ---- 2. 依赖检查 ----
command -v node >/dev/null || die "未检测到 node.js，请先安装 Node 22.19+ / 24+，建议用 fnm / nvm：https://nodejs.org/en/download"
command -v git  >/dev/null || die "未检测到 git，请先安装 Git for Windows：https://git-scm.com/download/win"

NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
if [ "$NODE_MAJOR" -lt 22 ]; then
  die "Node 版本过低（当前 v$(node -v)），需要 22.19+ 或 24+"
fi
log "Node $(node -v), Git $(git --version | awk '{print $3}')"

# ---- 3. 配置国内镜像（仅本次 export，不写全局）----
export npm_config_registry="$NPM_MIRROR"
export npm_config_disturl="https://registry.npmmirror.com/-/binary/node"
export npm_config_electron_mirror="https://registry.npmmirror.com/-/binary/electron/"
export npm_config_sharp_binary_host="https://registry.npmmirror.com/-/binary/sharp"
export npm_config_sharp_libvips_binary_host="https://registry.npmmirror.com/-/binary/sharp-libvips"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
log "npm registry → $NPM_MIRROR"

# ---- 4. 启用 corepack / pnpm ----
if ! command -v pnpm >/dev/null; then
  log "未检测到 pnpm，通过 corepack 启用"
  corepack enable pnpm 2>/dev/null || npm i -g pnpm@11.7.0
fi
PNPM_VER=$(pnpm -v)
log "pnpm $PNPM_VER"

# pnpm 也走国内
pnpm config set registry "$NPM_MIRROR"

# ---- 5. 克隆（Gitee 优先，失败回退 GitHub 加速）----
# 绕开可能存在的死代理（VPN 未开时 127.0.0.1:7890 会卡住）
GIT_PROXY_BYPASS=(-c http.proxy= -c https.proxy= -c http.sslVerify=false)
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY 2>/dev/null || true

TARGET_DIR="$REPO"
if [ -d "$TARGET_DIR/.git" ]; then
  warn "$TARGET_DIR 已存在，复用现有目录"
  # 浅克隆就地升级为完整历史（idempotent，已完整则 no-op）
  cd "$TARGET_DIR" || die "cd $TARGET_DIR failed"
  if [ -f .git/shallow ]; then
    log "浅克隆升级为完整历史..."
    git "${GIT_PROXY_BYPASS[@]}" fetch --unshallow 2>/dev/null || warn "unshallow 失败（build 应该仍可继续）"
  fi
else
  log "克隆 Gitee: $GITEE_URL"
  if ! git "${GIT_PROXY_BYPASS[@]}" clone --depth 50 "$GITEE_URL" "$TARGET_DIR" 2>/dev/null; then
    warn "Gitee 克隆失败，回退到 ghfast 加速的 GitHub"
    git "${GIT_PROXY_BYPASS[@]}" clone --depth 50 "$GITHUB_FALLBACK" "$TARGET_DIR"
  fi
  cd "$TARGET_DIR" || die "cd $TARGET_DIR failed"
  # 拉全历史（dsh 的 build / typecheck 需要完整 history）
  log "拉取完整历史..."
  git "${GIT_PROXY_BYPASS[@]}" fetch --unshallow 2>/dev/null || warn "unshallow 失败（build 应该仍可继续）"
fi

# ---- 6. 安装 + 构建 ----
log "pnpm install (首次约 2-5 分钟)"
pnpm install

log "pnpm run build"
pnpm run build

# ---- 7. 完成 ----
cat <<EOF

${GRN}================================${NC}
  安装完成 ✓
${GRN}================================${NC}

启动 Web UI:
  cd $TARGET_DIR
  pnpm dsh web
  # 浏览器打开 http://127.0.0.1:3080

后续同步上游:
  bash install-dsh-cn.sh   # 已有目录会复用

EOF
