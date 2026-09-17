---
title: Ubuntu/Debian 编译指南
nav_title: Ubuntu 编译指南
description: 在 Ubuntu 和 Debian 系统上一键安装依赖、编译和运行 Claude Code Haha，支持 VPS 无桌面模式、自动更新和 systemd 服务。
order: 5
---

# Ubuntu / Debian 编译指南

项目提供了 `scripts/setup-linux.sh` 一键脚本，覆盖安装依赖、编译桌面端、VPS 无桌面模式和打包全流程。

> 本指南针对 Ubuntu 和 Debian 系统。其他 Linux 发行版部分命令可能需要替换。

## 快速开始

### VPS 模式（无桌面环境，推荐服务器使用）

```bash
git clone https://github.com/NanmiCoder/cc-haha.git
cd cc-haha
sudo bash scripts/setup-linux.sh vps
```

VPS 模式专为无桌面环境的服务器设计：

- 跳过 Electron/桌面端编译（节省 60%+ 编译时间）
- 只安装 CLI 运行所需的最小依赖
- 安装全局命令入口，可直接运行 `claude-haha`
- 支持 `update` 命令自动保持最新版本
- 支持 `service` 命令安装 systemd 开机自启

### 桌面端模式（带 GUI 环境）

```bash
git clone https://github.com/NanmiCoder/cc-haha.git
cd cc-haha
sudo bash scripts/setup-linux.sh full
```

桌面端模式会自动完成：

1. 安装系统级构建依赖（build-essential、libssl-dev、libvips 等）
2. 安装 Bun、Node.js 22、Rust 工具链
3. 安装项目依赖（根目录、desktop、adapters）
4. 编译桌面端（ripgrep、sidecars、Vite 渲染进程、Electron main/preload）
5. 打包 Electron（AppImage / deb / rpm）

## 命令参考

| 命令 | 说明 |
|------|------|
| `bash scripts/setup-linux.sh vps` | **VPS 一键安装+编译+运行 CLI**（推荐服务器使用） |
| `bash scripts/setup-linux.sh full` | 安装+编译+打包桌面端（一站式） |
| `bash scripts/setup-linux.sh install` | 仅安装所有依赖（桌面端） |
| `bash scripts/setup-linux.sh build` | 安装依赖后编译桌面端 |
| `bash scripts/setup-linux.sh desktop` | 编译桌面端并打包 (AppImage/deb/rpm) |
| `bash scripts/setup-linux.sh run` | 启动 CLI 模式 |
| `bash scripts/setup-linux.sh update` | **检查并升级到最新版本** |
| `bash scripts/setup-linux.sh service` | 安装为 systemd 服务（开机自启） |
| `bash scripts/setup-linux.sh service-stop` | 停止并卸载 systemd 服务 |
| `bash scripts/setup-linux.sh server` | 启动 Web 服务器 + Web UI |
| `bash scripts/setup-linux.sh clean` | 清理构建产物 |

## 保持最新版本

### 手动更新

```bash
bash scripts/setup-linux.sh update
```

`update` 命令会自动：

1. 拉取 GitHub 最新代码（切换到 main 分支）
2. 对比版本号，如有新版本则重新安装依赖
3. 记录更新状态

### 后台自动检查

每次运行 `vps` 安装后，脚本会在后台每 6 小时静默检查一次新版本。当有新版本可用时，手动运行 `update` 命令即可升级。

### 安装为 systemd 服务（开机自启 + 自动重启）

```bash
# 安装服务
sudo bash scripts/setup-linux.sh service

# 管理服务
sudo systemctl status claude-haha    # 查看状态
sudo systemctl stop claude-haha      # 停止服务
sudo systemctl restart claude-haha   # 重启服务
sudo journalctl -u claude-haha -f    # 查看日志

# 卸载服务
sudo bash scripts/setup-linux.sh service-stop
```

`service` 命令会创建 `/etc/systemd/system/claude-haha.service`，配置：

- 以指定用户运行（默认当前用户）
- 失败时自动重启（Restart=on-failure）
- 开机自启（WantedBy=multi-user.target）
- 资源限制（文件描述符 65536、进程数 4096）
- 安全加固（NoNewPrivileges、PrivateTmp）

## 环境变量

通过环境变量控制安装和编译行为：

| 变量 | 值 | 说明 |
|------|---|------|
| `LINUX_ARCH` | `x64`（默认）/ `arm64` | 目标 CPU 架构 |
| `GITHUB_USER` | `NanmiCoder`（默认） | GitHub 用户名/组织 |
| `GITHUB_REPO` | `cc-haha`（默认） | GitHub 仓库名 |
| `SKIP_DESKTOP` | `1` | 跳过桌面端编译 |
| `SKIP_ADAPTERS` | `1` | 跳过 adapters 安装 |
| `SKIP_RUST` | `1` | 跳过 Rust 安装 |
| `SKIP_NODE` | `1` | 跳过 Node.js 安装 |
| `SERVICE_USER` | `$USER`（默认） | systemd 服务运行用户 |

示例 — 在 ARM64 机器上编译桌面端：

```bash
LINUX_ARCH=arm64 bash scripts/setup-linux.sh desktop
```

示例 — 仅安装 CLI 依赖（跳过桌面端）：

```bash
SKIP_DESKTOP=1 SKIP_RUST=1 bash scripts/setup-linux.sh install
bun run claude-haha
```

## 各步骤详解

### 系统依赖

#### 桌面端模式

脚本需要 root 权限安装以下系统包：

- `build-essential` — C/C++ 编译器
- `libssl-dev`、`pkg-config`、`zlib1g-dev`、`lzma-dev`、`zstd-dev` — 压缩/加密库
- `libclang-dev`、`llvm-dev` — Rust 编译后端
- `libgtk-3-dev`、`libnotify-dev`、`libnss3`、`libxss1` — Electron GUI 依赖
- `libasound2`、`libcups2` — 音频/打印支持
- `libvips-dev` — sharp 图片库依赖

#### VPS 轻量模式

只安装 CLI 必需的系统包：

- `build-essential` — C/C++ 编译器
- `libssl-dev`、`pkg-config`、`zlib1g-dev`、`lzma-dev`、`zstd-dev` — 压缩/加密库
- `libclang-dev`、`llvm-dev` — Rust 编译后端
- `libnss3`、`libxss1` — Electron CLI 依赖（最小 GUI）
- `libasound2`、`libcups2` — 音频/打印支持
- `ripgrep` — 文件搜索（系统包或 GitHub 下载）
- `libvips-dev` — sharp 图片库依赖

如果 `libvips-dev` 安装失败，sharp 会使用预编译版本，不影响功能。

### Bun

项目使用 [Bun](https://bun.sh) 作为包管理器和运行时（`bun@1.3.14`）。脚本通过官方安装脚本安装到 `~/.bun`。

### Node.js 22

文档站构建需要 Node.js 22 LTS。如果已安装其他版本会保留不动。

### Rust

sidecar 组件使用 Rust 编写，需要稳定版工具链。

## 运行

### CLI 模式

```bash
cd /path/to/cc-haha
bun run claude-haha
```

VPS 模式安装后，也可以直接运行：

```bash
claude-haha
```

配置 `.env` 文件或通过桌面端设置 Provider 后使用。

### Web UI 模式

```bash
bash scripts/start-web-ui.sh
```

### 桌面端

编译完成后，桌面端打包产物位于 `desktop/build-artifacts/`：

- `.AppImage` — 免安装，下载即用（推荐）
- `.deb` — Debian/Ubuntu 系统安装包
- `.rpm` — Fedora/RHEL/CentOS 系统安装包（仅 x64）

## 清理

```bash
# 清理构建产物
bash scripts/setup-linux.sh clean

# 清理构建产物 + Bun 缓存
bash scripts/setup-linux.sh clean-all
```

## 常见问题

### AppImage 启动失败（FUSE 错误）

Ubuntu 22.04 及更早版本：

```bash
sudo apt install libfuse2
```

Ubuntu 24.04 及以后版本：

```bash
sudo apt install libfuse2t64
```

### sharp 编译失败

确保 `libvips-dev` 已安装：

```bash
sudo apt install libvips-dev
```

### ripgrep 准备失败

VPS 模式会自动从系统仓库下载：

```bash
sudo apt install ripgrep
```

### 内存不足

编译 sidecar 和 Electron 原生模块时可能消耗 2-4 GB 内存。低于 4 GB 的系统建议在 swap 较大的环境下编译。

VPS 模式跳过桌面端编译，内存占用可降至 1 GB 以下。

### 版本检查失败

GitHub API 可能有速率限制。如果自动版本检查失败：

```bash
# 手动检查最新版本
curl -fsSL https://api.github.com/repos/NanmiCoder/cc-haha/releases/latest \
  | grep -oP '"tag_name":\s*"\K[^"]+'

# 手动更新
bash scripts/setup-linux.sh update
```

### systemd 服务管理

```bash
# 查看服务状态
sudo systemctl status claude-haha

# 查看实时日志
sudo journalctl -u claude-haha -f

# 修改服务配置后重新加载
sudo systemctl daemon-reload
sudo systemctl restart claude-haha
```
