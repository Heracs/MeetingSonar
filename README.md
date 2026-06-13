# MeetingSonar 🎙️

> 🤖 **Intelligent Meeting Audio Recorder for macOS**
>
> *Current Version: v0.13.0 Internal (Build 1841)*

MeetingSonar 是一款运行在 macOS 菜单栏的轻量级工具，旨在为您提供无感、高效的会议录音体验。

它无需安装任何虚拟驱动，兼容性好，能够录制系统音频，并结合麦克风输入，完美还原会议现场，同时保持极低的资源占用。

## 📌 当前状态文档 (Current State)

当前实现状态、版本/build、测试 gate、已知遗留问题和历史文档使用规则，以 [Documents/APP_CURRENT_STATE.md](Documents/APP_CURRENT_STATE.md) 为准。

历史 FeatureSpecs、Archive 文档和旧 sprint 计划可用于理解需求来源，但不一定反映当前代码逻辑。

## ✨ 核心功能 (Key Features)

- **🖥️ 菜单栏常驻 (Menu Bar App)**: 纯净的菜单栏应用，不占用 Dock 空间，随时待命
- **🔇 静默录音**: 采用 ScreenCaptureKit 技术，无需虚拟声卡即可录制系统声音
- **🤖 智能检测**: 自动检测会议应用（Zoom、Teams 等）并开始/停止录音
- **🎙️ 混合录音**: 同时录制系统音频和麦克风输入
- **⏸️ 暂停/恢复**: 录音过程中支持暂停和恢复功能
- **🌐 Provider-based AI 转录**: 通过云端 ASR 或外部 whisper.cpp 本地 ASR 生成转录
- **📝 智能纪要**: 通过 provider-based LLM 生成会议摘要和关键要点
- **🌍 多语言支持**: 完整支持 **简体中文** 和 **English**
- **🔒 本地优先**: 录音和元数据保存在本地；启用 AI 处理时按用户配置调用云端服务

## 🛠️ 系统要求 (Requirements)

- **macOS**: 13.0 (Ventura) 或更高版本
- **Xcode**: 15.0+ (用于构建)



## 📅 版本历史 (Version History)

### v0.13.0 Internal - Build 1841
- ✅ AI provider 架构落地：ASR 和 LLM 通过独立 runtime/provider 配置解析
- ✅ 新增外部 whisper.cpp 本地 ASR provider 配置入口
- ✅ 保持现有云端 ASR/LLM provider 兼容
- ✅ ASR 临时 WAV cache 仅在处理时创建，原始录音继续保存为 M4A
- ✅ Webex 和 Teams Classic 已从当前 Smart Detection 支持矩阵移除

### v0.12.0 Internal - Build 1839
- ✅ Zoom、Teams New、Tencent Meeting、Feishu/Lark 自动会议检测链路完成内部复测
- ✅ Feishu/Lark preview/pre-join 误触发修复，静音入会可自动录音
- ✅ Teams New 手动停止后离会不重启、下一次入会恢复触发

### v0.11.0 Internal - Build 1838
- ✅ 会议检测和自动录音流程增强
- ✅ 最大录音时长提醒和录音评估定时器
- ✅ 云端 ASR/LLM 处理链路作为当前 AI 架构方向

### v0.10.5 Internal - Build 1687
- ✅ 云端 AI 架构和多版本转录/纪要能力
- ✅ Dashboard 录音管理和详情查看

### v0.9.5 Internal - Build 1498
- ✅ 早期录音、元数据和本地模型架构能力
