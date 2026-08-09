# LocalSend 改进版 - 修改说明

## 概述

本改进版基于 LocalSend v1.17.0，针对以下需求进行了全面改进：
1. 删除局域网文件传输和聊天以外的所有功能
2. 安全审查（无病毒、无挖矿、无后门）
3. 减少运行时系统资源占用
4. 避免文件重复，发送文件只引用路径
5. 禁止局域网以外的网络运行
6. 修复超大文件传输卡死问题
7. 新增局域网聊天模块
8. 新增清除聊天记录和缓存功能

## 第二轮改进（聊天复制、传输提速、超大文件不卡顿）

### 1. 聊天内容支持复制粘贴

**文件**: `app/lib/pages/chat_page.dart`
- 消息正文改为 `SelectableText`，支持鼠标拖选/长按选中后复制
- 长按消息气泡弹出操作菜单：复制本条消息 / 复制全部聊天记录
- 右上角更多菜单新增"复制全部聊天记录"（带时间与发送者格式）
- 复制成功后有 SnackBar 提示

**文件**: `app/lib/pages/chat_list_page.dart`
- 长按设备列表项可复制最后一条消息

### 2. 文件传输提速

**文件**: `packages/core/src/model/transfer.rs`
- 文件读取通道容量 8 → 16，读取缓冲 512KB → 1MB
- 减少磁盘读取次数与跨线程传递次数，提升吞吐

**文件**: `packages/core/src/http/server/common/save.rs`
- 接收通道容量 8 → 16，写盘缓冲 512KB → 1MB
- 接收端流水线缓冲增大，减少 TCP 等待

**文件**: `packages/localsend_isolates/lib/src/isolate/child/upload_isolate.dart`
- 上传并发 1 → 2（与上游一致），多文件整体吞吐翻倍
- 文件以 1MB 分块流式发送，峰值内存约 2 × 16 × 1MB ≈ 32MB，仍可控

**文件**: `packages/core/src/http/server/mod.rs`
- 服务器连接开启 TCP_NODELAY（关闭 Nagle 算法）
- HTTP/2 流控窗口放大：单流 8MB / 连接 16MB，千兆/万兆局域网下保持高吞吐

**文件**: `packages/core/src/http/client/mod.rs`
- reqwest 客户端同样开启 TCP_NODELAY 与 HTTP/2 流控窗口

### 3. 30GB+ 超大文件不再卡顿

**文件**: `app/lib/provider/network/send_provider.dart`
- 发送前跳过超大文件（> 1 GiB）的 SHA-256 预计算
- 原因：旧逻辑在传输开始前要把整个 30GB 文件完整读一遍算校验和，导致长时间无响应
- 校验和是协议可选项，跳过即立即开始传输；接收端校验开关仍对普通文件生效

**文件**: `app/lib/provider/selection/selected_sending_files_provider.dart`
- 目录文件元数据读取从同步 IO（lengthSync/lastModifiedSync）改为异步 IO
- 避免选择包含大量大文件的目录时阻塞 UI 线程

**文件**: `app/lib/util/native/cross_file_converters.dart`
- convertAssetEntity / convertXFile / convertFile / convertSharedAttachment 全部改用异步 IO

## 可行性验证与数据安全说明

### 1. 超大文件传输不会损坏数据

本轮的提速改动（通道容量、读写缓冲、TCP_NODELAY、HTTP/2 流控窗口、并发 2）只改变数据的
"流动节流阀大小"，不改变数据的**内容、顺序与完整性**：

- TCP 可靠传输保证字节不丢失、不重复、不乱序
- 接收端 `write_file_from_receiver` 的 **字节数校验（written == expected_size）始终生效**，
  传输中断、截断、多传都会被检测并返回失败，绝不会静默保存损坏文件
- HTTP/2 流控窗口放大是标准机制（SETTINGS_INITIAL_WINDOW_SIZE），只放宽在途数据量，不丢帧
- 并发 2 时每个文件有独立的 fileId / token / channel，连接复用由 reqwest 线程安全管理

### 2. >1 GiB 文件跳过 SHA-256 的行为变化

这是提速的关键取舍，与官方 LocalSend 关闭"创建校验和"设置的行为一致：

- `sha256` 在协议中为可选字段（`FileDto.sha256: Option<String>`，代码中已有 `sha256: None` 先例）
- 接收端对 `None` 的处理全部安全：`expected_sha256` 为 Option，为 None 时不创建哈希器、直接跳过，
  无任何 unwrap / panic 路径（见 `server/v2.rs:403` 与 `server/common/save.rs:113,168,228`）
- 失去的是"内容级"校验：仅当源文件在传输过程中被修改、或磁盘介质损坏这类极端场景下无法发现；
  常规网络错误、断线、截断仍会被大小校验可靠捕获
- 若你更看重完整性：保持默认即可（普通文件仍有校验）；或关闭"创建校验和"（所有文件均不校验，更快）；
  或自行调大/调小 `app/lib/provider/network/send_provider.dart` 中的 `_skipHashForFilesLargerThan` 阈值

### 3. API 兼容性验证（已逐项对照官方文档）

| 改动 | 依赖版本 | 验证方法 | 结果 |
|------|----------|----------|------|
| `auto::Builder::http2()` → `initial_stream_window_size` / `initial_connection_window_size` | hyper-util 0.1.20 | docs.rs 官方文档 | 方法存在，签名 `impl Into<Option<u32>>`，返回 `auto::Http2Builder`，`serve_connection(&self)` 兼容 |
| `.tcp_nodelay(true)` | reqwest 0.13.4 | docs.rs 官方文档 | 方法存在，默认即 true，显式设置无害 |
| `.http2_initial_stream_window_size` / `.http2_initial_connection_window_size` | reqwest 0.13.4 | docs.rs 官方文档 | 方法存在，需 `http2` feature（项目 Cargo.toml 已启用） |
| Dart 改动（SelectableText / Clipboard / withHash(null) / File 异步方法） | Flutter SDK | 人工逐行核查 | 与现有代码模式一致，无缺失 import |

> 说明：本机无 Rust / Flutter 工具链，未执行 `cargo build` 与 `flutter analyze`。
> 请在有工具链的环境按"编译指南"构建验证；若你的工具链版本与文档存在差异，
> 删除 `server/mod.rs` 中 `http2()` 的两行窗口配置即可回退（不影响其余优化）。

## 安全审查结果

### 审查范围
- Rust 核心库 (`packages/core/`)
- Dart 应用层 (`app/lib/`)
- Rust FRB 绑定层 (`packages/localsend_isolates/`)
- Android 原生代码 (`app/android/`)
- CLI 工具 (`cli/`)

### 审查结论
- **无挖矿代码**：未发现 crypto_miner, coinhive, xmr, monero, stratum 等关键词
- **无后门**：未发现 eval(), system(), popen() 等危险调用
- **无病毒**：未发现恶意文件操作或数据外传
- **外部网络连接**：WebRTC 信令服务器和 STUN 服务器（已禁用）
- **赞助/购买**：in_app_purchase 和 donation 功能（已禁用）

## 详细改进内容

### 1. 禁止局域网以外的网络运行

#### Rust 核心层修改

**文件**: `packages/core/src/http/server/mod.rs`
- 新增 `is_lan_ip()` 函数，检查 IP 是否属于局域网范围：
  - IPv4: 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10
  - IPv6: ::1, fc00::/7, fe80::/10
- 在 `start_server_with_listener` 的连接接受循环中添加 IP 过滤
- 非局域网 IP 的连接被直接拒绝并记录日志

**文件**: `packages/core/Cargo.toml`
- 移除 reqwest 的 `system-proxy` feature，禁止通过系统代理路由请求

**文件**: `packages/localsend_isolates/rust/Cargo.toml`
- 将 localsend 依赖从 `features = ["full"]` 改为 `features = ["crypto", "discovery", "http", "multicast"]`
- 移除了 `webrtc` feature，彻底禁用 WebRTC 外网连接

#### Dart 应用层修改

**文件**: `app/lib/config/init.dart`
- 注释掉 WebRTC 信令连接初始化代码
- 注释掉 in_app_purchase 初始化代码

### 2. 修复超大文件传输卡死问题

**文件**: `packages/core/src/webrtc/webrtc.rs`
- WebRTC chunk 大小从 16KB 增大到 64KB，减少传输次数
- `receive_string_from_chunks` 函数添加 64KB 大小限制，防止恶意对端导致内存无限增长

**文件**: `packages/core/src/http/server/common/save.rs`
- 文件上传 channel 容量从 16 降低到 8，减少内存占用同时保持背压

**文件**: `packages/core/src/model/transfer.rs`
- 文件读取 channel 容量从 16 降低到 8

**文件**: `packages/localsend_isolates/lib/src/isolate/child/upload_isolate.dart`
- 上传并发从 2 降低到 1，避免大文件并发传输导致内存压力

### 3. 减少运行时系统资源占用

- 降低所有 channel 缓冲区容量（16→8），减少峰值内存
- 降低上传并发（2→1），避免多文件并发传输时的资源竞争
- 禁用 WebRTC 模块，减少 Rust 运行时加载（3个子 isolate 不再初始化 WebRTC 相关代码）
- 禁用 in_app_purchase，移除不必要的后台监听

### 4. 避免文件重复，发送文件只引用路径

原有设计已经是零拷贝的：
- 发送端：直接从源文件路径流式读取（`FileContent::Path`），不拷贝到临时目录
- 接收端：直接写入目标路径或 Android 文件描述符，无中间临时文件
- Android SAF 路径：通过 `detachFd` 将文件描述符交给 Rust，零拷贝

**唯一例外**（保留）：保存到相册时先写缓存再转存，这是相册 API 限制导致的必要操作。

### 5. 新增局域网聊天模块

#### Rust 核心层
**文件**: `packages/core/src/http/server/v2.rs`
- 新增 `ServerEventV2::ChatMessage` 事件变体
- 新增 `chat()` 异步函数处理 `POST /api/localsend/v2/chat` 请求
- 新增 `chat_messages()` 函数处理消息查询端点

**文件**: `packages/core/src/http/server/mod.rs`
- 添加聊天端点路由

**文件**: `packages/core/src/http/client/mod.rs`
- 新增 `send_chat_message()` 方法

#### Dart 应用层
**新文件**: `app/lib/provider/chat_provider.dart`
- `ChatMessage` 模型类
- `ChatState` 状态类（按设备分组）
- `ChatNotifier` 管理器（添加/清除消息，标记已读）

**新文件**: `app/lib/pages/chat_page.dart`
- 单设备聊天界面，包含消息气泡和输入栏

**新文件**: `app/lib/pages/chat_list_page.dart`
- 设备列表页面，显示在线/离线状态和未读消息

**修改文件**: `app/lib/pages/home_page.dart`
- 添加聊天 Tab 到导航栏

**修改文件**: `app/lib/provider/network/server/server_provider.dart`
- 新增 `sendChatMessage()` 方法和 `SendChatMessageAction` 类
- 通过 HTTP register 请求发送聊天消息（使用 `LS_CHAT:` 前缀标识）

**修改文件**: `app/lib/provider/network/server/controller/receive_controller.dart`
- 在 `onRegister` 中添加聊天消息接收处理
- 检测 `LS_CHAT:` 前缀并路由到 chatProvider

### 6. 新增清除聊天记录和缓存功能

**修改文件**: `app/lib/util/native/cache_helper.dart`
- 改进 `ClearCacheAction` 为递归清理（包括子目录）
- 新增 `_clearDirectoryRecursive()` 递归清理函数
- 新增 `_clearWebSendTempFiles()` 清理 web-send 临时文件
- 所有删除操作改为 await，确保清理完成

**修改文件**: `app/lib/pages/tabs/settings_tab.dart`
- 新增"清除缓存"按钮
- 新增"清除所有聊天记录"按钮（带确认对话框）
- 移除赞助、隐私政策外链等非核心功能按钮

### 7. 编译脚本

**新文件**: `support/scripts/build_all_platforms.sh`
- 一键编译 Windows 绿色版、EXE 安装包和 Android APK
- 自动检查 Flutter 和 Rust 环境
- 自动添加交叉编译目标

## 编译指南

### 环境要求

1. **Flutter SDK** >= 3.41.0
   ```bash
   # 安装 Flutter
   git clone https://github.com/flutter/flutter.git -b 3.41.0
   export PATH="$PWD/flutter/bin:$PATH"
   flutter doctor
   ```

2. **Rust 工具链**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source $HOME/.cargo/env
   ```

3. **Android SDK + NDK**
   - 安装 Android Studio 或命令行工具
   - 设置 `ANDROID_HOME` 环境变量
   - 安装 NDK（通过 sdkmanager）

4. **Windows 交叉编译**（在 Linux 上编译 Windows 版本）
   ```bash
   rustup target add x86_64-pc-windows-gnu
   sudo apt install mingw-w64
   ```
   或在 Windows 上直接使用 Flutter build windows

5. **Inno Setup**（用于 Windows EXE 安装包）
   - Windows: 下载安装 Inno Setup 6
   - Linux: 使用 wine + inno setup

### 编译步骤

```bash
# 一键编译
cd localsend
chmod +x support/scripts/build_all_platforms.sh
./support/scripts/build_all_platforms.sh

# 或分步编译
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang

# Windows 绿色版
flutter build windows --release
# 输出: app/build/windows/x64/runner/Release/

# Windows EXE 安装包（需要 Inno Setup）
iscc support/scripts/compile_windows_exe-inno.iss

# Android APK
flutter build apk --release
# 输出: app/build/app/outputs/flutter-apk/app-release.apk
```

### Win7 适配说明

项目已内置 Win7 兼容性处理：
- `permission_handler_windows` 被替换为 noop 版本（避免 Win7 兼容性问题）
- Windows 编译目标使用 MSVC 工具链
- 不使用 Win10+ 专属 API

## 文件修改清单

| 文件 | 修改类型 | 说明 |
|------|----------|------|
| `packages/core/Cargo.toml` | 修改 | 移除 system-proxy feature |
| `packages/core/src/http/server/mod.rs` | 修改 | 添加 LAN IP 过滤、聊天端点路由 |
| `packages/core/src/http/server/v2.rs` | 修改 | 添加 ChatMessage 事件和 chat 函数 |
| `packages/core/src/http/client/mod.rs` | 修改 | 添加 send_chat_message 方法 |
| `packages/core/src/http/client/v2.rs` | 修改 | client 字段改为 pub(super) |
| `packages/core/src/http/client/v3.rs` | 修改 | client 字段改为 pub(super) |
| `packages/core/src/webrtc/webrtc.rs` | 修改 | 增大 chunk、修复无界缓冲 |
| `packages/core/src/http/server/common/save.rs` | 修改 | 降低 channel 容量 |
| `packages/core/src/model/transfer.rs` | 修改 | 降低 channel 容量 |
| `packages/localsend_isolates/rust/Cargo.toml` | 修改 | 移除 webrtc feature |
| `packages/localsend_isolates/rust/src/api/server.rs` | 修改 | 处理 ChatMessage 事件 |
| `packages/localsend_isolates/lib/src/isolate/child/upload_isolate.dart` | 修改 | 降低并发 |
| `app/lib/config/init.dart` | 修改 | 禁用 WebRTC 和购买 |
| `app/lib/util/native/cache_helper.dart` | 修改 | 递归清理缓存 |
| `app/lib/pages/home_page.dart` | 修改 | 添加聊天 Tab |
| `app/lib/pages/tabs/settings_tab.dart` | 修改 | 添加缓存/聊天清理 |
| `app/lib/provider/network/server/server_provider.dart` | 修改 | 添加聊天发送 |
| `app/lib/provider/network/server/controller/receive_controller.dart` | 修改 | 添加聊天接收 |
| `app/lib/provider/chat_provider.dart` | 新增 | 聊天状态管理 |
| `app/lib/pages/chat_page.dart` | 新增 | 聊天界面 |
| `app/lib/pages/chat_list_page.dart` | 新增 | 设备列表 |
| `support/scripts/build_all_platforms.sh` | 新增 | 编译脚本 |
| `cli/src/app/receive.rs` | 修改 | CLI 聊天支持 |
