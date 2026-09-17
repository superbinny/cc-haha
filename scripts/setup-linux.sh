#!/usr/bin/env bash
# ============================================================
# Claude Code Haha — Ubuntu/Debian 一键安装、编译与运行脚本
# ============================================================
# 用法:
#   bash scripts/setup-linux.sh              # 安装 + 编译（桌面端）
#   bash scripts/setup-linux.sh vps          # VPS/无桌面环境一键安装+编译+运行 CLI
#   bash scripts/setup-linux.sh run          # 启动 CLI
#   bash scripts/setup-linux.sh desktop      # 编译桌面端并打包
#   bash scripts/setup-linux.sh server       # 启动 Web 服务器 + Web UI
#   bash scripts/setup-linux.sh update       # 检查并升级到最新版本
#   bash scripts/setup-linux.sh service      # 安装为 systemd 服务
#   bash scripts/setup-linux.sh service-stop # 停止 systemd 服务
#   bash scripts/setup-linux.sh clean        # 清理构建产物
#   bash scripts/setup-linux.sh --help       # 显示帮助
#
# 环境变量:
#   LINUX_ARCH=x64|arm64      目标架构 (默认 x64)
#   GITHUB_USER=NanmiCoder    GitHub 用户名/组织 (用于版本检查)
#   GITHUB_REPO=cc-haha       GitHub 仓库名
#   SKIP_DESKTOP=1            跳过桌面端编译 (VPS 模式默认启用)
#   SKIP_ADAPTERS=1           跳过 adapters 安装
#   SKIP_RUST=1               跳过 Rust 安装
#   SKIP_NODE=1               跳过 Node.js 安装
#   SERVICE_USER=$USER        systemd 服务运行用户
# ============================================================

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo; echo -e "${CYAN}============================================================"; echo "  $*"; echo -e "${CYAN}============================================================"; echo; }
step()    { echo -e "${MAGENTA}[STEP]${NC} $*"; }

# ── 全局变量 ──────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_ARCH="${LINUX_ARCH:-x64}"
GITHUB_USER="${GITHUB_USER:-NanmiCoder}"
GITHUB_REPO="${GITHUB_REPO:-cc-haha}"
SERVICE_USER="${SERVICE_USER:-$(whoami)}"

# ── 自动更新配置 ──────────────────────────────────────────
INSTALL_TIMESTAMP_FILE="$HOME/.claude-haha-install-timestamp"
LAST_UPDATE_CHECK_FILE="$HOME/.claude-haha-last-update-check"

usage() {
  cat <<EOF
用法: bash scripts/setup-linux.sh [命令]

命令:
  install     安装所有依赖（桌面端）(默认)
  build       编译项目（桌面端）
  vps         【VPS优化】一键安装+编译+运行 CLI（跳过桌面端）
  run [args]  运行 CLI 模式
  desktop     编译并打包桌面端
  server      启动 Web 服务器 + Web UI
  update      检查并升级到最新版本
  service     安装为 systemd 服务（后台自运行）
  service-stop 停止并卸载 systemd 服务
  clean       清理构建产物
  full        安装 -> 编译 -> 打包桌面端（一站式）
  --help      显示此帮助

VPS 模式说明:
  vps 命令专为无桌面环境的服务器设计:
  - 跳过 Electron/桌面端编译（节省 60%+ 编译时间）
  - 跳过 ripgrep sidecar（使用系统 rg）
  - 只安装 CLI 运行所需的最小依赖
  - 编译完成后直接运行 claude-haha
  - 支持 update 命令自动保持最新版本

环境变量:
  LINUX_ARCH       x64 或 arm64 (默认: x64)
  GITHUB_USER      GitHub 用户名 (默认: NanmiCoder)
  GITHUB_REPO      GitHub 仓库名 (默认: cc-haha)
  SKIP_DESKTOP     跳过桌面端编译 (设为 1)
  SKIP_ADAPTERS    跳过 adapters 安装 (设为 1)
  SKIP_RUST        跳过 Rust 安装 (设为 1)
  SKIP_NODE        跳过 Node.js 安装 (设为 1)
  SERVICE_USER     systemd 服务运行用户 (默认: 当前用户)

示例:
  # VPS 一键安装
  bash scripts/setup-linux.sh vps

  # VPS 模式 + 自动更新
  bash scripts/setup-linux.sh update

  # 安装为 systemd 服务（开机自启）
  sudo bash scripts/setup-linux.sh service

  # 仅安装依赖
  SKIP_DESKTOP=1 bash scripts/setup-linux.sh install

  # ARM64 桌面端编译
  LINUX_ARCH=arm64 bash scripts/setup-linux.sh desktop
EOF
}

# ── 系统检查 ──────────────────────────────────────────────
check_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "$ID_LIKE" != *"ubuntu"* && "$ID_LIKE" != *"debian"* ]]; then
      warn "检测到非 Ubuntu/Debian 系统 (ID=$ID)。部分软件可能不可用。"
    fi
    info "系统: $PRETTY_NAME"
  else
    error "无法检测系统版本 (缺少 /etc/os-release)"
    exit 1
  fi
}

check_arch() {
  case "$LINUX_ARCH" in
    x64)   SIDECAR_TRIPLE="x86_64-unknown-linux-gnu"; BUILDER_ARCH="x64" ;;
    arm64) SIDECAR_TRIPLE="aarch64-unknown-linux-gnu"; BUILDER_ARCH="arm64" ;;
    *)
      error "不支持的架构: $LINUX_ARCH (仅支持 x64 或 arm64)"
      exit 1
      ;;
  esac
  info "目标架构: $LINUX_ARCH (target_triple=$SIDECAR_TRIPLE)"
}

check_systemd() {
  if command -v systemctl &>/dev/null && systemctl --version &>/dev/null 2>&1; then
    return 0
  fi
  warn "未检测到 systemd，service 命令不可用"
  return 1
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "此步骤需要 root 权限 (使用 sudo 运行)"
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" &>/dev/null; then
    error "缺少必要命令: $1"
    exit 1
  fi
}

# ── 系统依赖安装 ──────────────────────────────────────────
install_system_deps() {
  section "安装系统依赖"
  require_root

  info "更新软件包列表..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  info "安装基础构建工具..."
  apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    file \
    git \
    sudo \
    libfuse2 \
    libssl-dev \
    pkg-config \
    zlib1g-dev \
    liblzma-dev \
    libzstd-dev \
    libclang-dev \
    llvm-dev \
    libgtk-3-dev \
    libnotify-dev \
    libnss3 \
    libxss1 \
    libasound2 \
    libcups2 \
    libdbus-1-3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libc6 \
    libdrm2 \
    libgbm1 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgtk2.0-0 \
    libxdamage1 \
    libxrandr2 \
    libxi1 \
    libxtst6

  # sharp 需要 libvips
  info "安装 libvips (sharp 依赖)..."
  apt-get install -y --no-install-recommends libvips-dev 2>/dev/null || warn "libvips-dev 安装失败，sharp 可能使用预编译版本"

  ok "系统依赖安装完成"
}

# ── 轻量系统依赖（VPS 模式） ──────────────────────────────
install_system_deps_vps() {
  section "安装系统依赖（VPS 轻量模式）"
  require_root

  info "更新软件包列表..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq

  info "安装基础构建工具..."
  apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    file \
    git \
    sudo \
    libssl-dev \
    pkg-config \
    zlib1g-dev \
    liblzma-dev \
    libzstd-dev \
    libclang-dev \
    llvm-dev \
    libnss3 \
    libxss1 \
    libasound2 \
    libcups2 \
    libdbus-1-3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libc6 \
    libdrm2 \
    libgbm1 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libxdamage1 \
    libxrandr2 \
    libxi1 \
    libxtst6

  # ripgrep（VPS 模式直接从系统安装）
  info "安装 ripgrep..."
  apt-get install -y --no-install-recommends ripgrep 2>/dev/null || \
    warn "系统 ripgrep 不可用，将从 GitHub 下载"

  # sharp 需要 libvips
  info "安装 libvips (sharp 依赖)..."
  apt-get install -y --no-install-recommends libvips-dev 2>/dev/null || warn "libvips-dev 安装失败，sharp 可能使用预编译版本"

  ok "系统依赖安装完成 (VPS 轻量模式，跳过 GUI 库)"
}

# ── Bun 安装 ──────────────────────────────────────────────
install_bun() {
  section "安装 Bun"
  if command -v bun &>/dev/null; then
    local bun_version
    bun_version="$(bun --version 2>/dev/null || echo 'unknown')"
    warn "Bun 已安装: $bun_version (跳过)"
    ok "Bun 版本: $bun_version"
    return 0
  fi

  info "安装 Bun..."
  curl -fsSL https://bun.sh/install | bash

  # 添加到 PATH
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"

  # 写入 shell profile
  for profile_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$profile_file" ]]; then
      if ! grep -q 'BUN_INSTALL' "$profile_file" 2>/dev/null; then
        echo '' >> "$profile_file"
        echo 'export BUN_INSTALL="$HOME/.bun"' >> "$profile_file"
        echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> "$profile_file"
      fi
    fi
  done

  require_command bun
  ok "Bun 安装完成: $(bun --version)"
}

# ── Node.js 安装 ──────────────────────────────────────────
install_node() {
  section "安装 Node.js 22"
  if [[ "${SKIP_NODE:-0}" == "1" ]]; then
    warn "SKIP_NODE=1，跳过 Node.js 安装"
    return 0
  fi

  if command -v node &>/dev/null; then
    local node_version
    node_version="$(node --version 2>/dev/null || echo 'unknown')"
    if [[ "$node_version" == v22.* ]] || [[ "$node_version" == 22.* ]]; then
      ok "Node.js 22 已安装 ($node_version)，跳过"
      return 0
    fi
    warn "已安装 Node.js 但不是 v22: $node_version"
  fi

  info "安装 Node.js 22 (LTS)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y --no-install-recommends nodejs

  require_command node
  ok "Node.js 安装完成: $(node --version)"

  if ! command -v npm &>/dev/null; then
    warn "npm 未安装，文档站构建可能受影响"
  fi
}

# ── Rust 安装 ─────────────────────────────────────────────
install_rust() {
  section "安装 Rust 工具链"
  if [[ "${SKIP_RUST:-0}" == "1" ]]; then
    warn "SKIP_RUST=1，跳过 Rust 安装"
    return 0
  fi

  if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
    ok "Rust 已安装: rustc $(rustc --version 2>/dev/null || echo unknown)"
    return 0
  fi

  info "安装 Rust (rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf \
    https://sh.rustup.rs | sh -s -- -y --default-toolchain stable

  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"

  require_command rustc
  require_command cargo
  ok "Rust 安装完成: rustc $(rustc --version)"
}

# ── 项目依赖安装 ──────────────────────────────────────────
install_deps() {
  section "安装项目依赖"
  cd "$REPO_ROOT"

  info "安装根目录依赖..."
  bun install --frozen-lockfile 2>/dev/null || bun install
  ok "根目录依赖安装完成"

  if [[ "${SKIP_DESKTOP:-0}" != "1" ]]; then
    info "安装桌面端依赖..."
    cd "$REPO_ROOT/desktop"
    bun install --cpu="*" --frozen-lockfile 2>/dev/null || bun install
    ok "桌面端依赖安装完成"
  fi

  if [[ "${SKIP_ADAPTERS:-0}" != "1" ]] && [[ -d "$REPO_ROOT/adapters" ]]; then
    info "安装 adapters 依赖..."
    cd "$REPO_ROOT/adapters"
    bun install --frozen-lockfile 2>/dev/null || bun install
    ok "adapters 依赖安装完成"
  fi

  section "依赖安装全部完成"
}

# ── 构建桌面端 ────────────────────────────────────────────
build_desktop() {
  section "编译桌面端"
  export PATH="$HOME/.bun/bin:$HOME/.cargo/bin:$PATH"
  cd "$REPO_ROOT/desktop"

  local sidecar_triple="${SIDECAR_TARGET_TRIPLE:-$SIDECAR_TRIPLE}"

  info "准备 ripgrep..."
  SIDECAR_TARGET_TRIPLE="$sidecar_triple" bun run prepare:ripgrep || \
    warn "ripgrep 准备失败，尝试从系统安装..."
  if ! command -v rg &>/dev/null; then
    info "安装 ripgrep..."
    curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-unknown-linux-gnu.tar.gz" \
      | tar xz -C /tmp
    mv /tmp/rg-*/rg /usr/local/bin/rg 2>/dev/null || true
    chmod +x /usr/local/bin/rg 2>/dev/null || true
  fi

  info "编译 sidecars..."
  SIDECAR_TARGET_TRIPLE="$sidecar_triple" bun run build:sidecars

  info "构建渲染进程 (Vite)..."
  bun run build

  info "构建 Electron main/preload..."
  bun run build:electron

  info "准备 node-pty..."
  bun run prepare:node-pty 2>/dev/null || warn "node-pty 准备跳过"

  # 重新编译原生依赖
  info "重建 Electron 原生模块..."
  bunx electron-builder install-app-deps

  ok "桌面端编译完成"
}

# ── Electron 打包 ─────────────────────────────────────────
package_electron() {
  section "打包 Electron 应用"
  cd "$REPO_ROOT/desktop"

  local targets="AppImage deb"
  [[ "$LINUX_ARCH" == "x64" ]] && targets="AppImage deb rpm"

  info "打包目标: $targets ($LINUX_ARCH)"

  bunx electron-builder \
    --linux $targets \
    --"$BUILDER_ARCH" \
    --publish never

  local output_dir="$REPO_ROOT/desktop/build-artifacts/electron"
  if [[ -d "$output_dir" ]]; then
    info "构建产物:"
    ls -lh "$output_dir"/ 2>/dev/null || true
  fi

  ok "Electron 打包完成"
}

# ── VPS 模式：轻量编译（只编译 CLI，跳过桌面端） ─────────
build_vps() {
  section "编译项目（VPS 轻量模式）"
  cd "$REPO_ROOT"

  # 确保 ripgrep 可用
  if ! command -v rg &>/dev/null; then
    warn "ripgrep 未安装，尝试从 GitHub 下载..."
    local rg_url="https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-unknown-linux-gnu.tar.gz"
    if [[ "$LINUX_ARCH" == "arm64" ]]; then
      rg_url="https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-aarch64-unknown-linux-musl.tar.gz"
    fi
    curl -fsSL "$rg_url" | tar xz -C /tmp 2>/dev/null || true
    local rg_bin
    rg_bin=$(find /tmp -name 'rg' -type f 2>/dev/null | head -1)
    if [[ -n "$rg_bin" ]]; then
      mv "$rg_bin" /usr/local/bin/rg 2>/dev/null || true
      chmod +x /usr/local/bin/rg 2>/dev/null || true
      ok "ripgrep 安装完成"
    else
      warn "无法安装 ripgrep，文件搜索功能可能受限"
    fi
  fi

  # 确保 Node.js 可用（VPS 模式可选，但文档站需要）
  if command -v node &>/dev/null; then
    info "Node.js 已安装: $(node --version)"
  else
    warn "Node.js 未安装，文档站构建将跳过"
  fi

  ok "VPS 模式编译完成（跳过桌面端）"
}

# ── 运行 CLI ──────────────────────────────────────────────
run_cli() {
  section "运行 CLI"
  cd "$REPO_ROOT"
  export PATH="$HOME/.bun/bin:$PATH"

  info "启动 Claude Code Haha CLI..."
  echo ""
  echo "  提示: 配置 .env 文件或桌面端 Provider 以使用模型"
  echo "  运行 'bun run claude-haha --help' 查看 CLI 选项"
  echo ""

  bun run claude-haha "$@"
}

# ── 运行服务器 ────────────────────────────────────────────
run_server() {
  section "启动 Web 服务器 + Web UI"
  cd "$REPO_ROOT"
  export PATH="$HOME/.bun/bin:$PATH"

  info "启动服务器模式..."
  bash "$REPO_ROOT/scripts/start-web-ui.sh" "$@"
}

# ── 自动版本检查与更新 ────────────────────────────────────
get_latest_version() {
  local api_url="https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/releases/latest"
  local version

  if command -v curl &>/dev/null; then
    version=$(curl -fsSL --connect-timeout 5 --max-time 15 "$api_url" 2>/dev/null \
      | bun -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')); console.log(d.tag_name||d.name||'')" 2>/dev/null || true)
  fi

  if [[ -z "$version" ]] || [[ "$version" == "undefined" ]] || [[ "$version" == "null" ]]; then
    version=$(curl -fsSL --connect-timeout 5 --max-time 15 "$api_url" 2>/dev/null \
      | grep -oP '"tag_name":\s*"\K[^"]+' 2>/dev/null || true)
  fi

  if [[ -z "$version" ]]; then
    version=$(curl -fsSL --connect-timeout 5 --max-time 15 "https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/tags" 2>/dev/null \
      | grep -oP '"name":\s*"\K[^"]+' 2>/dev/null | head -1 || true)
  fi

  echo "${version:-unknown}"
}

check_version_update() {
  local current_version
  current_version=$(bun -e "console.log(require('./package.json').version)" 2>/dev/null || echo "local")

  local latest_version
  latest_version="$(get_latest_version)"

  if [[ "$latest_version" == "unknown" ]] || [[ -z "$latest_version" ]]; then
    warn "无法获取最新版本信息（GitHub API 可能不可达）"
    return 1
  fi

  if [[ "$current_version" == "$latest_version" ]]; then
    ok "已是最新版本: $current_version"
    return 0
  fi

  warn "检测到新版本: $current_version -> $latest_version"
  return 1
}

do_update() {
  section "检查并升级到最新版本"
  export PATH="$HOME/.bun/bin:$PATH"

  cd "$REPO_ROOT"

  # 记录上次检查时间
  date +%s > "$LAST_UPDATE_CHECK_FILE" 2>/dev/null || true

  # 拉取最新代码
  info "拉取最新代码..."
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

  if [[ "$current_branch" != "main" ]]; then
    warn "当前在 $current_branch 分支，切换到 main..."
    git checkout main 2>/dev/null || true
    current_branch="main"
  fi

  if ! git pull --ff-only 2>/dev/null; then
    warn "git pull 失败，尝试 force rebase..."
    git fetch origin main 2>/dev/null || { error "无法获取最新代码"; return 1; }
    git reset --hard origin/main 2>/dev/null || { error "无法重置到最新版本"; return 1; }
  fi
  ok "代码已更新"

  if check_version_update; then
    ok "无需更新，已是最新"
  else
    info "重新安装依赖..."
    bun install --frozen-lockfile 2>/dev/null || bun install
    ok "根目录依赖已更新"

    if [[ "${SKIP_DESKTOP:-0}" != "1" ]]; then
      cd "$REPO_ROOT/desktop"
      bun install --cpu="*" --frozen-lockfile 2>/dev/null || bun install
    fi

    if [[ -d "$REPO_ROOT/adapters" ]] && [[ "${SKIP_ADAPTERS:-0}" != "1" ]]; then
      cd "$REPO_ROOT/adapters"
      bun install --frozen-lockfile 2>/dev/null || bun install
    fi

    ok "依赖已更新"
  fi

  date +%s > "$INSTALL_TIMESTAMP_FILE" 2>/dev/null || true

  local new_version
  new_version=$(bun -e "console.log(require('./package.json').version)" 2>/dev/null || echo "unknown")
  ok "更新完成，当前版本: $new_version"
}

# ── systemd 服务管理 ──────────────────────────────────────
install_service() {
  section "安装 systemd 服务"
  require_root

  if ! check_systemd; then
    error "当前系统没有 systemd，无法安装服务"
    exit 1
  fi

  local service_name="claude-haha"
  local service_file="/etc/systemd/system/${service_name}.service"
  local user="$SERVICE_USER"
  local home
  home=$(eval ~$user 2>/dev/null || echo "$HOME")

  if [[ -z "$home" ]] || [[ "$home" == "~$user" ]]; then
    home="$HOME"
  fi

  info "服务名称: ${service_name}"
  info "运行用户: ${user}"
  info "安装路径: ${REPO_ROOT}"

  if ! command -v bun &>/dev/null; then
    error "Bun 未安装，请先运行 'bash scripts/setup-linux.sh vps'"
    exit 1
  fi

  cat > "$service_file" <<SERVICE_EOF
[Unit]
Description=Claude Code Haha - AI Assistant CLI Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${user}
Group=${user}
Environment=HOME=${home}
Environment=PATH=${home}/.bun/bin:/usr/local/bin:/usr/bin:/bin
Environment=BUN_INSTALL=${home}/.bun
WorkingDirectory=${REPO_ROOT}
ExecStart=${home}/.bun/bin/bun run claude-haha
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=claude-haha

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096

# 安全加固
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE_EOF

  info "重载 systemd 配置..."
  systemctl daemon-reload

  info "启用服务（开机自启）..."
  systemctl enable "${service_name}"

  info "启动服务..."
  systemctl start "${service_name}"

  ok "服务安装完成: ${service_name}"
  echo ""
  echo "  管理服务:"
  echo "    sudo systemctl status ${service_name}    # 查看状态"
  echo "    sudo systemctl stop ${service_name}      # 停止服务"
  echo "    sudo systemctl restart ${service_name}   # 重启服务"
  echo "    sudo journalctl -u ${service_name} -f    # 查看日志"
  echo ""
  echo "  卸载服务:"
  echo "    bash scripts/setup-linux.sh service-stop"
}

uninstall_service() {
  section "卸载 systemd 服务"
  require_root

  local service_name="claude-haha"

  info "停止服务..."
  systemctl stop "${service_name}" 2>/dev/null || true

  info "禁用服务..."
  systemctl disable "${service_name}" 2>/dev/null || true

  info "删除服务文件..."
  rm -f "/etc/systemd/system/${service_name}.service"

  info "重载 systemd 配置..."
  systemctl daemon-reload

  ok "服务已卸载: ${service_name}"
}

# ── 一键更新检查（后台静默） ──────────────────────────────
auto_check_update() {
  local now
  now=$(date +%s)
  local last_check=0

  if [[ -f "$LAST_UPDATE_CHECK_FILE" ]]; then
    last_check=$(cat "$LAST_UPDATE_CHECK_FILE" 2>/dev/null || echo "0")
  fi

  local check_interval=$((6 * 3600))
  if (( now - last_check < check_interval )); then
    return 0
  fi

  (
    check_version_update 2>/dev/null || true
    date +%s > "$LAST_UPDATE_CHECK_FILE" 2>/dev/null || true
  ) &>/dev/null &
}

# ── 创建 claude-haha 命令入口 ─────────────────────────────
install_cli_command() {
  section "安装 claude-haha 命令行入口"

  local cli_path="/usr/local/bin/claude-haha"
  local bun_path="$HOME/.bun/bin/bun"

  if [[ ! -f "$bun_path" ]]; then
    warn "Bun 不在 $HOME/.bun/bin，跳过命令入口安装"
    return
  fi

  cat > "$cli_path" <<'CLI_EOF'
#!/usr/bin/env bash
# Claude Code Haha — 全局命令行入口
# 自动检测并加载 Bun
if [ -n "$HOME" ] && [ -f "$HOME/.bun/bin/bun" ]; then
  export PATH="$HOME/.bun/bin:$PATH"
fi
exec bun run claude-haha "$@"
CLI_EOF

  chmod +x "$cli_path"
  ok "claude-haha 命令已安装到 $cli_path"
  echo "  现在可以直接运行: claude-haha"
}

# ── 清理 ──────────────────────────────────────────────────
clean() {
  section "清理构建产物"

  for dir in "$REPO_ROOT" "$REPO_ROOT/desktop" "$REPO_ROOT/adapters"; do
    if [[ -d "$dir/node_modules" ]]; then
      info "清理 $dir/node_modules"
      rm -rf "$dir/node_modules"
    fi
  done

  for d in "$REPO_ROOT/desktop/dist" "$REPO_ROOT/desktop/electron-dist" \
           "$REPO_ROOT/desktop/build-artifacts" "$REPO_ROOT/desktop/src-tauri/target" \
           "$REPO_ROOT/desktop/src-tauri/binaries" "$REPO_ROOT/artifacts"; do
    if [[ -d "$d" ]]; then
      info "清理 $d"
      rm -rf "$d"
    fi
  done

  rm -f "$REPO_ROOT/desktop/tsconfig.tsbuildinfo" 2>/dev/null || true

  ok "清理完成"
}

clean_all() {
  section "完全清理"
  clean
  [[ -d "$HOME/.bun/install/cache" ]] && { info "清理 Bun 缓存"; rm -rf "$HOME/.bun/install/cache"; }
  ok "完全清理完成"
}

# ── 一站式安装+编译+运行 ──────────────────────────────────
run_full() {
  section "一站式安装 -> 编译 -> 运行"

  check_os
  check_arch

  install_system_deps
  install_bun
  install_node
  install_rust

  install_deps
  build_desktop
  [[ "$LINUX_ARCH" == "x64" ]] && package_electron

  section "安装和编译完成!"
  echo ""
  echo "  你可以运行以下命令启动:"
  echo ""
  echo "    # CLI 模式"
  echo "    cd $REPO_ROOT && bun run claude-haha"
  echo ""
  echo "    # Web UI 模式"
  echo "    cd $REPO_ROOT && bash scripts/start-web-ui.sh"
  echo ""
  echo "  桌面端构建产物位于:"
  echo "    $REPO_ROOT/desktop/build-artifacts/"
  echo ""
}

# ── VPS 一站式流程 ────────────────────────────────────────
run_vps() {
  section "VPS 一键安装 -> 编译 -> 运行"

  check_os
  check_arch

  # 1. 安装轻量系统依赖
  install_system_deps_vps

  # 2. 安装 Bun
  install_bun

  # 3. 安装 Node.js（仅文档站需要，可选）
  install_node

  # 4. 安装项目依赖（跳过桌面端）
  SKIP_DESKTOP=1 install_deps

  # 5. VPS 轻量编译
  build_vps

  # 6. 安装全局命令入口
  install_cli_command

  # 7. 自动版本检查（后台运行，不阻塞）
  auto_check_update

  # 8. 记录安装状态
  date +%s > "$INSTALL_TIMESTAMP_FILE" 2>/dev/null || true

  section "VPS 安装完成!"
  echo ""
  echo -e "  ${GREEN}==================== 使用方式 ====================${NC}"
  echo ""
  echo -e "  ${MAGENTA}CLI 模式（直接运行）:${NC}"
  echo "    cd $REPO_ROOT && bun run claude-haha"
  echo "    # 或安装全局命令后:"
  echo "    claude-haha"
  echo ""
  echo -e "  ${MAGENTA}Web UI 模式:${NC}"
  echo "    bash scripts/start-web-ui.sh"
  echo ""
  echo -e "  ${MAGENTA}保持最新版本:${NC}"
  echo "    bash scripts/setup-linux.sh update"
  echo ""
  echo -e "  ${MAGENTA}开机自启服务:${NC}"
  echo "    sudo bash scripts/setup-linux.sh service"
  echo ""
  echo -e "  ${MAGENTA}查看服务状态:${NC}"
  echo "    sudo systemctl status claude-haha"
  echo "    sudo journalctl -u claude-haha -f"
  echo ""
  echo "  ================================================"
  echo ""
}

# ── 主入口 ────────────────────────────────────────────────
main() {
  local cmd="${1:-install}"

  case "$cmd" in
    --help|-h|help)
      usage
      exit 0
      ;;
    install)
      check_os
      check_arch
      install_system_deps
      install_bun
      install_node
      install_rust
      install_deps
      ok "安装完成。运行 'bash scripts/setup-linux.sh build' 开始编译。"
      ;;
    build)
      check_os
      check_arch
      install_bun
      install_node
      install_rust
      install_deps
      build_desktop
      [[ "$LINUX_ARCH" == "x64" ]] && package_electron
      ok "编译完成。"
      ;;
    vps)
      run_vps
      ;;
    run)
      shift
      check_os
      check_arch
      install_bun
      install_node
      install_deps
      run_cli "$@"
      ;;
    desktop)
      check_os
      check_arch
      install_bun
      install_node
      install_rust
      install_deps
      build_desktop
      package_electron
      ok "桌面端打包完成。产物位于 $REPO_ROOT/desktop/build-artifacts/"
      ;;
    server)
      shift
      check_os
      check_arch
      install_bun
      install_node
      install_deps
      run_server "$@"
      ;;
    update)
      check_os
      check_arch
      install_bun
      do_update
      ;;
    service)
      check_os
      install_service
      ;;
    service-stop)
      check_os
      uninstall_service
      ;;
    clean)
      check_os
      clean
      ;;
    clean-all)
      check_os
      clean_all
      ;;
    full)
      run_full
      ;;
    *)
      error "未知命令: $cmd"
      echo ""
      usage
      exit 1
      ;;
  esac
}

main "$@"
