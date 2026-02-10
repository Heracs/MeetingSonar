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



