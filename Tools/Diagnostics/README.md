# 会议信号诊断工具

这个目录用于存放独立诊断工具。当前工具只观察会议软件暴露出来的原始信号，不需要启动 MeetingSonar，也不会改变 MeetingSonar 的状态机逻辑。

## 采集 AX 和 CoreAudio 信号

Zoom 主界面示例：

```bash
swift Tools/Diagnostics/collect_meeting_signals.swift \
  --bundle us.zoom.xos \
  --process zoom.us \
  --label zoom-main \
  --duration 30 \
  --prompt-accessibility
```

脚本默认把 JSONL 写到：

```text
/private/tmp/meetingsonar-signals-<timestamp>.jsonl
```

每次采集都应该使用清晰的 `--label` 标记当时的测试场景，例如：

- `zoom-main`
- `zoom-preview`
- `zoom-single-person`
- `zoom-two-person`
- `zoom-muted`
- `zoom-settings-open`
- `zoom-after-leave`

## 常用参数

```bash
--duration 60          # 采集时长，单位秒
--interval 2           # AX 采样间隔
--depth 3              # AX 子节点遍历深度
--max-nodes 250        # 每个窗口最多采集的 AX 节点数量
--no-audio             # 只采集进程和 AX，不采集 CoreAudio 日志
--out /path/file.jsonl # 指定输出文件
```

## 权限

AX 窗口和控件细节需要 macOS Accessibility 权限。授权对象通常是运行脚本的 Terminal，或者 Swift 解释器所在进程。

如果输出显示 Accessibility 不可信，使用：

```bash
--prompt-accessibility
```

然后在 System Settings 中授权，再重新运行采集命令。

CoreAudio 事件通过以下命令采集：

```bash
/usr/bin/log stream --style compact --predicate "message CONTAINS 'setPlayState'"
```

当传入已知 bundle id 时，脚本会用内置进程别名过滤音频日志，避免无关 app 的 `setPlayState` 噪声进入结果。

## 建议测试顺序

先从 Zoom 开始，每个状态单独运行一次采集：

```bash
# 1. Zoom 主界面
swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-main --duration 20

# 2. 加入前预览页
swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-preview --duration 20

# 3. 单人会议
swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-single-person --duration 30

# 4. 多人会议
swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-two-person --duration 30

# 5. 离开会议后但 Zoom 仍打开
swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-after-leave --duration 30
```

这些输出用于判断：哪些 AX 标题、控件、mic active/inactive 组合可以稳定代表“已进入会议/通话界面”。
