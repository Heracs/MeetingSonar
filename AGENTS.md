# AGENTS.md

MeetingSonar agent instructions for Codex and other coding agents.

本文件是当前仓库的 agent 工作入口。它根据 `CLAUDE.md`、`Documents/APP_CURRENT_STATE.md`、当前源码结构，以及 2026-06-13 v0.13 AI provider architecture 实现状态初始化。

## 指令优先级

1. 当前对话中的 system / developer / user 指令优先。
2. 本文件优先于旧的 feature spec、archive、历史 sprint 计划。
3. 当前事实以 `Documents/APP_CURRENT_STATE.md` 和源码为准。
4. `CLAUDE.md` 是本文件的来源之一；如果两者冲突，优先按本文件和当前源码重新核实。

历史文档可以用来理解需求来源，但不能直接当作当前 app 逻辑。

## 当前项目状态

- 产品：MeetingSonar，macOS 菜单栏会议录音工具。
- 当前分支：`v0.13`。
- 当前内部测试版本：`0.13.0` internal build `1841`。
- 核心能力：ScreenCaptureKit 系统音频录制、麦克风混音、智能会议检测、provider-based ASR/LLM 转录和纪要。
- 数据目录：`~/Documents/MeetingSonar_Data/`。
- 当前 AI 架构：provider-based。ASR/LLM 通过 `AIProviderConfigStore`、runtime protocol 和 `AIProviderRuntimeFactory` 解析；既有云端 provider 通过 adapter 保持兼容。
- 本地 whisper.cpp 是外部 local ASR provider：MeetingSonar 只调用用户配置的 `whisper-cli` 和模型，不安装、不下载、不维护 whisper.cpp。不要恢复旧的本地 Whisper/Llama 主路径；local LLM 不属于 v0.13 第一版范围。
- 当前 metadata：JSON 文件，不是 Core Data。

每次开始较大改动前先读：

- `Documents/APP_CURRENT_STATE.md`
- 相关模块源码
- 相关模块内的 `README.md`，如果存在
- 最近的 `Documents/superpowers/` 计划、规格或报告，如果任务与这些内容相关

## 协作规则

### 新功能或非平凡改动

当用户提出新功能或非平凡行为修改时，先给出方案确认，不要直接编辑代码，除非用户明确说“直接做”“开始实现”“按照建议处理”等。

```markdown
## 方案确认
**需求理解**: 一句话说明用户要什么
**计划修改的文件**: 将创建、修改或删除哪些文件
**实现思路**: 核心设计和关键取舍
**风险点**: 可能影响的模块、兼容性和测试风险
```

等待用户确认后再进入实现。

### Bug 修复

修 bug 前先做根因分析。不要在没有证据的情况下猜测式修改。

```markdown
## 影响分析
**问题**: 当前故障现象
**根因**: 已确认或待验证的根因，尽量写到文件/行
**修复方案**: 准备怎么改
**影响范围**: 受影响模块和调用链
**测试计划**: 如何验证修复不会引入回归
```

等待用户确认后再修复，除非用户已经明确授权继续。

### 改动粒度

- 一次只做一个可验证的逻辑改动。
- 大任务拆成阶段，每个阶段应可编译、可回退、可解释。
- 不要顺手重构无关文件。
- 不要恢复或覆盖用户已有改动。
- 不要把生成文件或本地环境噪音提交为功能改动。

## 构建和测试

标准 Debug build：

```bash
xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar -configuration Debug build
```

标准 unit test gate：

```bash
xcodebuild -project MeetingSonar.xcodeproj -scheme MeetingSonar \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/MeetingSonarDerivedDataPhaseFinal \
  -parallel-testing-enabled NO \
  -only-testing:MeetingSonarTests test
```

当前 UI test gate：

```bash
xcodebuild -quiet -project MeetingSonar.xcodeproj -scheme MeetingSonar \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/MeetingSonarDerivedDataPhaseFinalUI \
  -only-testing:MeetingSonarUITests build-for-testing
```

注意：

- Unit tests 当前需要 `-parallel-testing-enabled NO`。
- 测试仍可能触碰 singleton、UserDefaults、真实数据目录、DetectionService 和部分 audio capture 路径。
- Xcode 可能输出 CoreSimulator、通知权限、Login Items 权限、Swift 6 concurrency warnings。这些不应自动混入当前任务，除非任务就是处理这些问题。
- Build/test 可能重写 ignored 的 `MeetingSonar/Supporting Files/BuildInfo.generated.swift`，不应提交该生成物。

## 代码规范

### 日志

必须使用 `LoggerService`。不要用 `print()` 写运行日志。

```swift
LoggerService.shared.log(category: .recording, level: .info, message: "Recording started")
```

常用 category：

- `.general`
- `.audio`
- `.recording`
- `.permission`
- `.detection`
- `.ui`
- `.ai`
- `.system`

### 错误处理

- 不要 silent `catch`。
- 业务错误优先使用 `MeetingSonarError`。
- 捕获错误时必须记录或向上抛出。

### 并发

- `RecordingService`、`MetadataManager`、`SettingsManager`、`DetectionService` 主要运行在 `@MainActor` 边界。
- `CloudAIModelManager` 和 `PromptManager` 是 actor。
- 新异步代码使用 `async/await`，不要新增 completion handler 风格。
- 跨 actor 类型需要考虑 `Sendable`。

### 本地化

所有用户可见字符串必须本地化。不要硬编码中文或英文 UI 文案。

```swift
Text("menu.action.startRecording")
```

### 注释

- 修改公开或 internal 方法时，必要注释应说明设计意图和约束，不要复述代码。
- 不要为了“补注释”批量改动无关文件。

## 项目结构速览

```text
MeetingSonar/
├── MeetingSonarApp.swift
├── Core/
├── Models/
├── Services/
│   ├── AI/
│   │   ├── Recording/
│   │   │   ├── RecordingService.swift
│   │   │   ├── AudioCaptureService.swift
│   │   │   ├── MicrophoneService.swift
│   │   │   └── AudioMixerService.swift
│   │   ├── AIProcessingCoordinator.swift
│   │   ├── ASRService.swift
│   │   ├── AIProviderConfigStore.swift
│   │   ├── AIProviderRuntimeFactory.swift
│   │   ├── CloudAIModelManager.swift
│   │   ├── PromptManager.swift
│   │   ├── Runtimes/
│   │   ├── WhisperCpp/
│   │   └── Providers/
│   ├── AudioProcessing/
│   ├── Detection/
│   └── MetadataManager.swift
├── Utilities/
│   └── SettingsManager.swift
└── Views/
```

当前只有一个有效的 SettingsManager：

```text
MeetingSonar/Utilities/SettingsManager.swift
```

不要恢复旧的 split `SettingsManager` 目录实现。

## 录音链路

当前录音链路：

```text
RecordingService
  -> AudioCaptureService       // ScreenCaptureKit system audio
  -> MicrophoneService         // microphone
  -> AudioMixerService         // 48kHz stereo mix
  -> AVAssetWriter             // AAC M4A
  -> MetadataManager           // metadata.json
```

当前 crash-safe recording 是 partial：

- `AVAssetWriter.movieFragmentInterval = 2s`
- 启动时 `cleanupStaleRecordingStatus()`
- 没有实现完整 `.tmp/{sessionID}`、segment recovery 或 recovered 文件恢复。

当前 `AudioMixerService` lifecycle 已收敛：

- `start/stop/pause/resume` 状态和 `DispatchSourceTimer` ownership 已串行化。
- `pause/resume` 不再 suspend/resume timer，避免并发 lifecycle 下释放 inactive dispatch source。
- 2026-06-12 targeted AudioMixer tests 和 full `MeetingSonarTests` 已覆盖该修复。

## AI Provider 架构现状

当前 AI 主链路：

```text
AudioFile (.m4a)
  -> selected ASR AIProviderConfig
  -> ASRRuntime
     -> LocalWhisperCppASRRuntime   // external whisper.cpp, temporary WAV
     -> CloudASRRuntimeAdapter      // existing cloud ASR providers
  -> AIProcessingCoordinator
  -> VersionManager transcript version
  -> selected LLMRuntime
     -> CloudLLMRuntimeAdapter      // existing cloud LLM providers
  -> VersionManager summary version
```

关键约束：

- 原始录音继续保存为 AAC M4A，不要改成长期保存 WAV。
- ASR 需要 WAV 时，只在 `~/Library/Caches/MeetingSonar/ASRJobs/` 下创建临时 16kHz mono WAV，并在处理结束后清理。
- `CloudAIModelManager` 仍是云端配置和 API key 兼容层，不要在 v0.13 第一版中直接删除。
- `SettingsManager.availableASRModels` / `availableLLMModels` 已由 provider-backed config 生成。
- 新 UI 入口是 `AIProviderSettingsView` / `AIProviderConfigSheet`；旧 `CloudAISettingsView` 和 `CloudModelConfigSheet` 只作为兼容背景看待。

## 智能会议检测现状

当前检测链路已经从 raw signal 直接驱动，改为 signal interpretation + reducer：

```text
ApplicationMonitor / LogMonitorService
  -> AppSignalSnapshot
  -> DetectionPolicy
  -> SignalInterpreter
  -> DetectionBusinessEvent
  -> DetectionStateReducer
  -> DetectionService side effects
```

核心文件：

- `MeetingSonar/Services/Detection/DetectionService.swift`
- `MeetingSonar/Services/Detection/ApplicationMonitor.swift`
- `MeetingSonar/Services/Detection/DetectionStateTypes.swift`
- `MeetingSonar/Services/Detection/MeetingSignalTypes.swift`
- `MeetingSonar/Services/Detection/DetectionPolicy.swift`
- `MeetingSonar/Services/Detection/SignalInterpreter.swift`
- `MeetingSonar/Services/Detection/DetectionStateReducer.swift`
- `MeetingSonar/Services/Detection/ParticipantCountExtractor.swift`

当前状态机三态：

- `monitoringAll`
- `recordingLocked`
- `cooldown`

当前关键约束：

- raw mic/window/process signal 不能直接启动或停止录音。
- 只有解释后的 `MeetingStartConfirmed` 才能启动自动录音。
- 录音中只允许 trigger app 的信号结束本次自动录音。
- 可靠会议窗口仍存在时，不能因为 mic inactive 自动停止。
- cooldown 必须检查残留信号，不能在 trigger app 残留信号仍存在时立即重新开放触发。
- manualStop cooldown 必须在稳定离会边界确认后再释放 trigger app suppression，避免同一会议内重启，也避免阻塞下一次会议。
- 自动停止、手动停止、最大时长、app crash/disabled 必须保留清晰 stop reason。

当前 policy 概况：

- Zoom：可靠会议 UI，已完成单人会议自动录音验证。
- Webex：已从 v0.13 active detection support 中移除，不再作为当前监控目标；如未来重新需要，应先做诊断采集和 policy 设计。
- Teams New：当前按弱窗口标题 + mic policy 处理；这是当前唯一 active Microsoft Teams target。2026-06-12 实测确认入会窗口标题形如 `test | Microsoft Teams`，主界面标题形如 `Calendar | Microsoft Teams`。`| Microsoft Teams` 已作为弱会议窗口模式，Calendar、Chat、Calls、Files 等主界面标题已加入排除；`Microsoft Teams ModuleHost` 已加入 `com.microsoft.teams2` alias。start-candidate 和 suppression-clear 已增加周期性重评估；manualStop cooldown 会在连续稳定非会议窗口 + inactive mic 后释放 trigger app suppression。单人会议自动启动、离会自动停止、手动停止后离会不重启、manualStop 后下一次入会恢复触发均已通过现场复测。多人会议、设备切换和更长离会残留仍需继续覆盖。
- Teams Classic：已从 v0.13 active detection support 中移除，不再作为当前监控目标。
- Tencent Meeting：已按 AX 子节点分类和可靠会议 UI policy 处理；idle/pre-join/waiting 不触发，会中布局可在 mic inactive 时确认会议 UI，现场单人会议复测已通过。
- Feishu/Lark：已按 2026-06-13 现场误触发结果完成二次收紧并通过真实 App 现场复测。Feishu helper 为 `com.electron.lark.iron` / `Lark Helper (Iron)`，preview 和会中都可能暴露标题 `飞书会议`；因此标题单独出现只作为 candidate，不启动录音。当前 Feishu-specific policy 要求 `meetingUI` + active helper audio session 才确认会议开始，triggerSource 为 `.combined`；主窗口 `飞书` + mic active 不允许 debounce 后启动。现场复测已覆盖主窗口不触发、preview/pre-join 不触发、单人会议静音入会自动触发、静音切换不停止、离会自动停止且不重启、手动停止后离会不重启、下一次入会恢复自动触发。
- Multi-app concurrent meetings：当前自动录音是 single-trigger app lock。若一个会议 app 先触发录音，另一个会议 app 随后入会，后者不会接管当前录音；当前 trigger app 离会时会先停止本段录音，cooldown 后如果另一个会议仍在会中会启动下一段录音。该行为暂按已知设计取舍记录，不直接视为 bug；缺点是两段录音之间可能少掉数秒。需要产品确认后再考虑 multi-app aggregate / handoff。
- WeChat：默认关闭，当前主要是 mic-only opt-in；旧文档提到进程数量线索，但当前实现仍需重新验证和设计。

诊断工具：

```bash
swift Tools/Diagnostics/collect_meeting_signals.swift \
  --bundle us.zoom.xos \
  --process zoom.us \
  --label zoom-main \
  --duration 60 \
  --out /private/tmp/meetingsonar-signals.jsonl
```

对 Teams 后续 policy 调整、Feishu/Lark 修复、微信语音，或继续扩展 Tencent Meeting 覆盖前，先采集：

- app 启动但未入会
- pre-join / waiting / preview
- 单人会议或单人通话
- 多人会议，如果测试条件允许
- 静音、取消静音、切换音频设备
- 离会 / 挂断后的残留信号

不要把单个应用的行为直接推广到其他会议软件。

## 已知遗留问题

这些问题已记录，后续处理时应单独建任务，不要混入无关修复。

1. 微信语音仍需逐个实测和 policy 收紧；Webex 和 Teams Classic 已移出当前 active support，不再作为 v0.13 遗留修复项。Teams New 已完成弱窗口标题、主界面标题排除、`Microsoft Teams ModuleHost` alias、start-candidate re-evaluation timer、suppression-clear re-evaluation timer 和 manualStop cooldown 内稳定离会释放 suppression 修复；单人会议自动启动、离会自动停止、手动停止后离会不重启、manualStop 后下一次入会恢复触发均已通过现场复测。
2. Tencent Meeting 已完成 idle、pre-join、等待态、单人会议、离会残留的 AX 诊断采集、自动化 policy/classifier 覆盖和现场单人会议复测；后续仍需覆盖多人会议、设备切换和更长离会残留信号。
3. Feishu/Lark 已完成单人会议 in-meeting / leave 诊断采集、Feishu-specific policy 二次收紧和现场单人会议复测；preview/pre-join 页的 `飞书会议` 标题单独出现不再允许启动录音，必须叠加 helper audio active 才能确认会议开始。多人会议、设备切换和更长离会残留信号仍需覆盖。
4. 多个会议 app 同时在会时，当前 single-trigger lifecycle 会把不同会议拆成多段录音；现阶段可接受用户用音频合并功能自行合并，但可能存在数秒录音间隙。是否实现连续录制/多 app 聚合需要后续产品决策。
5. Zoom participant count 的 raw text 可由诊断脚本读到，但实际录音 metadata 中仍可能是 `participantCount=nil`。这是独立增强项。
6. ASR provider 未配置时，录音后自动 AI 处理会失败。这是配置/AI 链路问题，不是检测触发问题。
7. v0.13 whisper.cpp 已完成 direct local command smoke validation，但还需要 UI-driven 手工验证：从设置界面添加 provider、verify、设为默认 ASR、对现有 M4A 触发转录、确认 transcript version 创建和 ASRJobs 清理。
8. UI test runner 执行阶段存在环境风险，当前 gate 是 `build-for-testing`。
9. Unit test 隔离仍需改进，尤其是 singleton、UserDefaults、真实数据目录和真实音频/检测路径。

## 文档维护

行为、gate、版本或 feature 状态变化后，更新：

- `Documents/APP_CURRENT_STATE.md`
- 相关 `Documents/superpowers/plans/`
- 相关 `Documents/superpowers/specs/`
- 相关 `Documents/superpowers/reports/`
- 相关模块 `README.md`，如果架构或调用链改变

不要让新文档与源码不一致。对历史文档做引用时，明确它是历史背景还是当前事实。

## Git 工作流

- 大任务优先使用独立 branch 或 worktree。
- 提交应聚焦一个逻辑改动。
- 合并前运行对应 gate，并在最终说明中写清楚验证命令和结果。
- 不要 revert 用户未授权的改动。
- 遇到 dirty worktree，先判断是否与当前任务有关；无关则避开，相关则读懂后再处理。

## 常用事实入口

- 当前状态：`Documents/APP_CURRENT_STATE.md`
- 检测状态机模型：`Documents/superpowers/specs/2026-06-12-detection-state-machine-model.md`
- 检测修复方案：`Documents/superpowers/specs/2026-06-12-detection-state-machine-repair-proposal.md`
- 检测诊断报告：`Documents/superpowers/reports/2026-06-12-detection-state-machine-diagnosis.md`
- Tencent Meeting 检测报告：`Documents/superpowers/reports/2026-06-12-tencent-meeting-detection.md`
- Feishu/Lark 检测报告：`Documents/superpowers/reports/2026-06-12-feishu-lark-detection.md`
- AI provider 架构设计：`Documents/superpowers/specs/2026-06-13-v0.13-ai-provider-architecture-design.md`
- AI provider 实施报告：`Documents/superpowers/reports/2026-06-13-v0.13-ai-provider-implementation.md`
- 稳定化完成记录：`Documents/superpowers/reports/2026-06-12-stabilization-completion.md`
- AI 模块说明：`MeetingSonar/Services/AI/README.md`
