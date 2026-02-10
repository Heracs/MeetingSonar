# MeetingSonar 🎙️

> 🤖 **Intelligent Meeting Audio Recorder for macOS**
>
> *Current Version: v0.9.4 (Development)*

MeetingSonar 是一款运行在 macOS 菜单栏的轻量级工具，旨在为您提供无感、高效的会议录音体验。

它无需安装任何虚拟驱动，兼容性好，能够录制系统音频，并结合麦克风输入，完美还原会议现场，同时保持极低的资源占用。

## ✨ 核心功能 (Key Features)

- **🖥️ 菜单栏常驻 (Menu Bar App)**: 纯净的菜单栏应用，不占用 Dock 空间，随时待命
- **🔇 静默录音**: 采用 ScreenCaptureKit 技术，无需虚拟声卡即可录制系统声音
- **🤖 智能检测**: 自动检测会议应用（Zoom、Teams 等）并开始/停止录音
- **🎙️ 混合录音**: 同时录制系统音频和麦克风输入
- **⏸️ 暂停/恢复**: 录音过程中支持暂停和恢复功能
- **🌐 AI 转录**: 离线语音识别，支持多种语言模型
- **📝 智能纪要**: 自动生成会议摘要和关键要点
- **🌍 多语言支持**: 完整支持 **简体中文** 和 **English**
- **🔒 安全隐私**: 所有录音数据仅保存在本地沙盒目录，绝不上传云端

## 🛠️ 系统要求 (Requirements)

- **macOS**: 13.0 (Ventura) 或更高版本
- **Xcode**: 15.0+ (用于构建)

## 🚀 快速开始 (Getting Started)

### 开发构建

```bash
# 1. 克隆仓库
git clone https://github.com/Heracs/MeetingSonar.git
cd MeetingSonar

# 2. 打开项目
open MeetingSonar.xcodeproj

# 3. 构建运行
# 在 Xcode 中按 CMD + R
# 首次运行时，请授予屏幕录制和麦克风权限
```

### 运行测试

```bash
# 运行所有单元测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/Unit

# 运行所有集成测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/Integration

# 运行所有测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS'
```

## 📅 版本历史 (Version History)

### v0.9.4 (开发中) - 架构改进 Phase 4
- ✅ 异步 I/O 优化
- ✅ MetadataManager 文件操作改为 async/await
- ✅ 全面自动化测试套件

### v0.9.3 (开发中) - 架构改进 Phase 3
- ✅ 依赖注入改造
- ✅ Mock 实现创建

### v0.9.2 (开发中) - 架构改进 Phase 2
- ✅ 协议抽象层创建
- ✅ 服务接口定义

### v0.9.1 (开发中) - 架构改进 Phase 1
- ✅ 错误类型统一
- ✅ MeetingSonarError 层次结构

### v0.8.4 (已发布)
- 🔧 Bug Fixes + 多版本历史支持
- ✅ ASR 模型名称显示修复
- ✅ 本地模型过滤
- ✅ UI 调整

## 🏗️ 架构概览 (Architecture)

```
MeetingSonar/
├── MeetingSonar/              # 主应用
│   ├── Core/                  # 核心组件
│   │   ├── ServiceContainer.swift      # 服务容器和协议定义
│   │   └── MeetingSonarError.swift     # 统一错误类型
│   ├── Models/                # 数据模型
│   ├── Services/              # 业务服务
│   │   ├── Recording/         # 录音服务
│   │   ├── Detection/         # 智能检测
│   │   ├── AI/                # AI 处理
│   │   └── Audio/             # 音频处理
│   ├── Views/                 # SwiftUI 视图
│   │   ├── Dashboard/         # 主界面
│   │   ├── Overlay/           # 录音状态浮窗
│   │   └── Preferences/       # 偏好设置
│   └── mocks/                # 测试 Mock
└── MeetingSonarTests/         # 测试套件
    ├── Unit/                  # 单元测试
    ├── Integration/           # 集成测试
    └── Resources/             # 测试数据
```

## 🧪 测试 (Testing)

### 测试覆盖

| 类型 | 覆盖率 | 文件数 |
|------|--------|--------|
| 单元测试 | 70% | 8 |
| 集成测试 | 60% | 2 |
| UI 测试 | 待实现 | - |

### 测试命令

```bash
# 单元测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/Unit

# 集成测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS' -only-testing:MeetingSonarTests/Integration

# 全部测试
xcodebuild test -scheme MeetingSonar -destination 'platform=macOS'
```

## 📚 文档 (Documentation)

### 核心文档

| 文档 | 说明 |
|------|------|
| `Documents/ProjectContext.md` | 项目概览和导航 |
| `Documents/SessionProgress.md` | 当前进度和状态 |
| `Documents/FeatureTracking.md` | 功能开发跟踪 |
| `Documents/TechArch.md` | 技术架构 |
| `Documents/ProdReq.md` | 产品需求 |

### 开发指南

| 文档 | 说明 |
|------|------|
| `Documents/CodeQualityProgress.md` | 代码质量改进进度 |
| `Documents/TestingPlan_Phase1-4.md` | 测试计划 |
| `Documents/AutomationTestReport.md` | 自动化测试报告 |

## 🔧 开发指南 (Development Guide)

### 会话恢复

下次会话开始时，按顺序阅读：
1. `Documents/ProjectContext.md`
2. `Documents/SessionProgress.md`
3. `Documents/Session_Summary_YYYY-MM-DD.md` (最新)

### 代码规范

- Swift 5.0+ 语法
- SwiftUI 声明式 UI
- 协议导向编程 (Protocol-Oriented)
- 依赖注入 (Dependency Injection)
- 异步/并发 (async/await)

### 提交规范

```bash
# 功能开发
git commit -m "feat: add new feature description"

# Bug 修复
git commit -m "fix: resolve issue description"

# 测试
git commit -m "test: add test coverage for X"

# 文档
git commit -m "docs: update documentation for Y"
```

## 🤝 贡献 (Contributing)

欢迎贡献！请查看 `Documents/DevLog.md` 了解开发历史。

## 📄 许可证 (License)

Copyright © 2026 MeetingSonar. All rights reserved.
