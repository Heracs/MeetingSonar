# Feature Tracking

| ID | Feature Name | Priority | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **F-1.0** | **基础录音架构** | P0 | ✅ Released | SCK + AVFoundation |
| **F-2.1** | **智能会议检测 (Smart Detection)** | P0 | ✅ Released | 漏斗模型：进程 -> 窗口特征 (AX) -> 麦克风 |
| **F-2.2** | **自动录音与提醒 (Auto-Action)** | P0 | ✅ Released | 自动/提醒模式切换，自动结束保存 |
| **F-2.3** | **诊断日志系统 (Diagnostics)** | P1 | ✅ Released | ApplicationMonitor 已集成日志 |

---

## 🟢 v0.3.1: Custom Overlay (Released)
> **目标**: 通过自定义悬浮窗替代不可靠的系统通知，解决自动录音时用户感知缺失问题。

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-2.4a** | **录音开始提示弹窗 (Start Overlay)** | P0 | ✅ Released | NSPanel 悬浮窗，屏幕正中上方，5秒消失 |
| **F-2.4b** | **录音进行中指示器 (Status Pill)** | P1 | ✅ Released | 右下角常驻红点+时长，Menu支持Pause/Resume |
| **F-2.4c** | **录音结束提示** | P2 | ✅ Released | 复用系统通知，无需新增 Overlay |
| **F-2.2-opt** | **通知降级策略** | P2 | ✅ Released | 系统通知仅作为后备 |

---

## 🟡 v0.3.2: Dynamic Menu Icon (Active Sprint)
> **目标**: 优化菜单栏图标状态反馈，支持 Idle/Recording/Paused 三态显示。
> **相关文档**: `Documents/ProdReq-v0.3.2.md`

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-2.5** | **动态菜单栏图标** | P1 | 🚧 Ready for QA | CoreGraphics 动态合成，支持 Pause 状态 |

---

## 🟣 v0.4.0 Epic: AI Core & Infrastructure
> **目标**: 建立数据规范，验证 AI 核心技术链路 (PoC)。
> **详细规范**: `Documents/ProdReq-v0.4.0.md`

### 🔵 v0.4.1: Data Infrastructure (Storage Layer)
> **Focus**: 目录结构与数据规范化。

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-4.5** | **目录结构初始化 (MeetingSonar_Data)** | P0 | 🚧 Verify | `~/Documents/MeetingSonar_Data/{Recordings,Transcripts,Models}` |
| **F-4.7** | **标准化命名策略** | P1 | 🚧 Verify | `{YYYYMMDD}-{HHmm}_{Source}.m4a` |

### 🟣 v0.4.2: The Ear (ASR PoC)
> **Focus**: 听觉能力验证 (Whisper.cpp)。

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-5.0a** | **Whisper.cpp 离线推理脚本** | P0 | ✅ Released | Metal 硬件加速验证，性能基准测试 (Passed) |
| **F-5.0b** | **Transcripts/Raw 输出格式定义** | P1 | ✅ Released | JSON (with timestamps) & Forced Simplified Chinese |

### 🟣 v0.4.3: The Brain (LLM PoC)
> **Focus**: 理解能力验证 (Llama/MLX)。

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-5.1a** | **Llama 3 摘要推理脚本** | P0 | ✅ Released | 8B 量化模型内存占用与推理速度测试 (Using Qwen3-4B) |
| **F-5.3** | **Prompt Engineering (Prompt Set)** | P0 | ✅ Released | V2: ChatML + Chinese Enforcement System Prompt |
| **F-5.4** | **SmartNotes 结构化输出** | P1 | ✅ Released | 生成标准 Markdown 格式纪要 (Tested) |

### 🟣 v0.4.4: Pipeline Automation
> **Focus**: 全链路串联。

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-5.2** | **End-to-End Pipeline Script** | P1 | ✅ Released | `Audio` -> `ASR` (w/ VAD) -> `LLM` -> `Note` 自动化脚本 |

---

## 🟡 v0.5.0: Native AI Integration (Active Sprint)
> **目标**: 将 AI 能力原生集成到 App，实现开箱即用，无需外部依赖。
> **详细规范**: `Documents/ProdReq-v0.5.0.md`
> **技术路线**: 官方 XCFramework (whisper.cpp + llama.cpp)

| ID | 功能点 | 优先级 | 状态 | 技术要点 |
|----|--------|--------|------|----------|
| **F-5.10** | **芯片检测与降级** | P0 | ✅ Released | Apple Silicon 检测，Intel 降级提示 |
| **F-5.11** | **模型管理器 (ModelManager)** | P0 | ✅ Released | 模型下载、断点续传、SHA256 校验 |
| **F-5.12** | **下载状态 UI** | P0 | ➡️ Moved to v0.6.0 | 迁移至 v0.6.0 实现 |
| **F-5.13** | **ASR 服务封装 (ASRService)** | P0 | ✅ Released | Whisper XCFramework C API 封装 |
| **F-5.14** | **LLM 服务封装 (LLMService)** | P0 | ✅ Released | Llama XCFramework C API 封装 |

### Out of Scope (v0.5.1+)
| 功能 | 说明 |
|------|------|
| 会议纪要查看器 UI | v0.5.0 用户手工打开 txt/md 文件 |
| LLM 流式输出 | 推迟至 v0.5.1 |
| 备用下载源 (国内镜像) | 推迟至 v0.6.x |

---

## 🔵 v0.5.2: AI Core Upgrade (Planned)
> **Goal**: Modernize AI Frameworks & Manage Models.
> **Docs**: `Documents/ProdReq-v0.5.2.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-5.21** | **Framework Upgrade (Qwen2.5)** | P0 | ⬜ Planned | Update llama.xcframework to b5401+ |
| **F-5.11+** | **Model Manager (Enhancement)** | P1 | ⬜ Planned | List, Delete, Empty State Prompt |
| **F-5.22** | **Context Chunking (Map-Reduce)** | P1 | ✅ Done | Split long transcripts > Safe Limit |
| **F-1.1** | **Max Duration Limit (2h)** | P1 | ✅ Done | Auto-stop recording at 2 hours |

### 🔵 v0.5.3: Evaluation Mode (Planned)
> **Goal**: Compare Models (A/B Testing).
> **Docs**: `Documents/ProdReq-v0.5.3.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-5.20** | **Evaluation Mode (A/B Testing)** | P2 | ⬜ Planned | Run multiple models on one recording for comparison |

---

## 🟢 v0.6.0: Dashboard & Management (Released)
> **Goal**: From hidden tool to full app. User can manage recordings.
> **Docs**: `Documents/ProdReq-v0.6.0.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-6.0** | **Metadata Index (JSON)** | P0 | ✅ Released | `metadata.json` for fast listing |
| **F-5.12** | **Model Download Status UI** | P0 | ✅ Released | Preferences Tab |
| **F-6.1** | **Main Window UI** | P0 | ✅ Released | Sidebar + List + Detail |
| **F-6.2** | **Recording List** | P0 | ✅ Released | Source, Duration, Status Icon |
| **F-6.3** | **Detail View Skeleton** | P1 | ✅ Released | Basic Info + Open in Finder Actions |
| **F-6.4** | **Basic Management** | P1 | ✅ Released | Rename, Delete (Fixed in F-11.1) |

---

## 🔵 v0.7.0: The Player (Next Sprint)
> **Goal**: Playback, Transcript Review, and Search to complete the consumption loop.
> **Docs**: `Documents/ProdReq-v0.7.0.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-7.0** | **Audio Player** | P0 | ⬜ Planned | AVPlayer integration, Scrubbing |
| **F-7.1** | **Transcript Viewer** | P0 | ⬜ Planned | Click-to-seek, JSON Parsing |
| **F-7.2** | **Summary Markdown Viewer** | P1 | ⬜ Planned | Native Markdown Rendering |
| **F-7.3** | **Basic Search** | P1 | ⬜ Planned | Filter by Title/Filename |

## 🟡 v0.8.0: UX Improvements & Online AI (Active Sprint)
> **Goal**: Improve recording UX, remove invalid options, prepare for online AI services.
> **Docs**: `Documents/ProdReq-v0.8.0.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-9.2** | **StatusPill Drag & Dismiss** | P0 | ✅ Done | Draggable pill, hover-to-close |
| **F-9.7** | **Remove MP3 Format Option** | P2 | ✅ Done | M4A only (MP3 not implemented) |
| **F-9.1** | **Manual AI Trigger** | P0 | ✅ Done | Remove auto-popup, Dashboard buttons |
| **F-9.3** | **API Key Management** | P0 | ⬜ v0.8.2 | Keychain storage |
## 🟡 v0.8.3: Online ASR & Smart Splitting (Active Sprint)
> **Goal**: Realize Online ASR for long meetings using RMS VAD Smart Splitting.
> **Docs**: `Documents/ProdReq-v0.8.3.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-9.4a** | **Online ASR Service** | P0 | 🚧 In Progress | Zhipu Multipart API |
| **F-9.4b** | **Audio Chunking (RMS VAD)** | P0 | 🚧 In Progress | 10-28s Window, Max 30s |
| **F-9.6** | **Local/Online Mode Switch** | P1 | 🚧 In Progress | Coordinator Routing |

## 🟡 v0.8.4: UX Overhaul & Model Management (Next Sprint)
> **Goal**: 统一模型管理，支持录音版本控制，优化系统交互体验。
> **Docs**: `Documents/ProdReq-v0.8.4.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-10.0** | **UX & Management Overhaul** | P0 | ⬜ Planned | Epic |
| **F-10.1** | **ASR Detailed Logging** | P1 | ⬜ Planned | Chunk-level Observability |
| **F-10.2** | **Unified Model Manager UI** | P0 | ⬜ Planned | Replaces old Preferences UI |
| **F-10.3** | **Result Versioning** | P0 | ⬜ Planned | MeetingMeta Revision support |
| **F-10.4** | **Dynamic Dock Icon** | P1 | ⬜ Planned | Toggle Process Policy |
| **F-10.0-PromptMgmt** | **Prompt Management System** | P0 | 🚧 In Progress | Custom ASR/LLM prompt templates |


---


---

## 🟢 v0.9.0: UI/UX Revision & Enhanced Support (Active Sprint)
> **Goal**: 优化视觉干扰，统一悬浮窗，支持国内会议软件。
> **Docs**: `Documents/ProdReq-v0.9.0.md`

| ID | Feature Name | Priority | Status | Tech Notes |
|----|--------------|----------|--------|------------|
| **F-11.0** | **Recording Manager UI Redesign** | P0 | ✅ Released | Three-column layout, version management |
| **F-11.1** | **Recording Rename & Delete Fix** | P0 | ✅ Released | State hoisting for context menu actions |
| **F-11.2** | **Auto-load Latest Transcript/Summary** | P1 | ✅ Released | Auto-select latest version on recording change |
| **F-11.3** | **Version Display in Footer** | P2 | ✅ Released | Show app version and build in list column |
| **F-12.0** | **Settings & Dashboard Layout Opt** | P1 | 🚧 In Test | Better hierarchy, list views |
| **F-12.1** | **Menu Bar Icon Resize** | P1 | ⬜ Planned | 18-22pt, stroke width fix |
| **F-12.2** | **Unified Floating HUD** | P0 | ⬜ Planned | Merge Start/Timer, Auto-dim/shrink |
| **F-2.4** | **Extended Meeting Support** | P0 | ⬜ Planned | Feishu & Tencent Meeting support |
| **F-12.3** | **Remove Legacy LLM** | P2 | ⬜ Planned | Remove Qwen 0.5B from UI |

---

## 🗄 Backlog (Deferred Features)
> **说明**: 原计划中的体验优化功能，暂缓以让路给核心 AI 价值验证。

| ID | 功能点 | 原定版本 | 状态 | 说明 |
|----|--------|----------|------|------|
| **F-5.14** | **MLX Integration** | P0 | ✅ Implemented | Apple Silicon optimized backend for Qwen3-ASR |
| **F-5.14a** | **Python Bridge Service** | P0 | ✅ Implemented | Python subprocess management |
| **F-5.14b** | **MLX Backend Support** | P0 | ✅ Implemented | MLX inference for Apple Silicon |
| **F-5.14c** | **Python Setup Wizard** | P0 | ✅ Implemented | Step-by-step environment configuration |
| **F-5.14d** | **MLX Testing Suite** | P1 | ✅ Implemented | Environment validation and testing |
| **F-3.2** | **智能设置面板 (Whitelist)** | v0.4.0 | ⏸️ Deferred | 低频功能 |
| **F-4.0** | **开机自启动** | v0.4.0 | ⏸️ Deferred | 系统偏好设置可替代 |
| **F-4.1** | **文件拖拽支持** | v0.4.0 | ⏸️ Deferred | Finder 可替代 |
| **F-4.9** | **自定义数据存储路径** | v0.5+ | ⏸️ Backlog | 允许用户修改 MeetingSonar_Data 位置 |
