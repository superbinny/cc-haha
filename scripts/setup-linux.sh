#!/usr/bin/env bash
# ============================================================
# Claude Code Haha — Ubuntu/Debian 一键安装、编译与运行脚本
# ============================================================
# 用法:
#   bash scripts/setup-linux.sh              # 安装 + 编译
#   bash scripts/setup-linux.sh run          # 编译后启动 CLI
#   bash scripts/setup-linux.sh desktop      # 编译桌面端并打包
#   bash scripts/setup-linux.sh server       # 启动 Web 服务器 + Web UI
#   bash scripts/setup-linux.sh clean        # 清理构建产物
#   bash scripts/setup-linux.sh --help       # 显示帮助
#
# 环境变量:
#   LINUX_ARCH=x64|arm64   目标架构 (默认 x64)
#   SKIP_DESKTOP=1         跳过桌面端编译
#   SKIP_ADAPTERS=1        跳过 adapters 安装
#   SKIP_RUST=1            跳过 Rust 安装
#   SKIP_NODE=1            跳过 Node.js 安装
# ============================================================

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo; echo -e "${CYAN}============================================================"; echo "  $*"; echo -e "${CYAN}============================================================"; echo; }

# ── 全局变量 ──────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_ARCH="${LINUX_ARCH:-x64}"

usage() {
  cat <<EOF
用法: bash scripts/setup-linux.sh [命令]

命令:
  install    安装所有依赖 (默认)
  build      编译项目 (安装依赖后)
  run        运行 CLI 模式
  desktop    编译并打包桌面端
  server     启动服务器 + Web UI
  clean      清理构建产物
  full       安装 -> 编译 -> 运行 CLI (一站式)
  --help     显示此帮助

环境变量:
  LINUX_ARCH       x64 或 arm64 (默认: x64)
  SKIP_DESKTOP     跳过桌面端编译 (设为 1)
  SKIP_ADAPTERS    跳过 adapters 安装 (设为 1)
  SKIP_RUST        跳过 Rust 安装 (设为 1)
  SKIP_NODE        跳过 Node.js 安装 (设为 1)

示例:
  SKIP_ADAPTERS=1 bash scripts/setup-linux.sh install
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
