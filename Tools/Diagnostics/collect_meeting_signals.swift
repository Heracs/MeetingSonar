#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

struct Config {
    var bundleID: String?
    var processName: String?
    var aliases: [String] = []
    var label: String = "unlabeled"
    var duration: TimeInterval = 60
    var interval: TimeInterval = 2
    var depth: Int = 3
    var maxNodesPerWindow: Int = 250
    var includeAudioLogs: Bool = true
    var promptAccessibility: Bool = false
    var outputURL: URL?
}

let knownAudioAliases: [String: [String]] = [
    "us.zoom.xos": ["zoom.us", "Zoom", "aomhost"],
    "com.microsoft.teams": ["Microsoft Teams"],
    "com.microsoft.teams2": ["MSTeams", "Microsoft Teams ModuleHost", "Microsoft Teams WebView Helper"],
    "com.cisco.webex.webex": ["Webex"],
    "com.tencent.meeting": ["TencentMeeting", "wemeet", "com.tencent.meeting"],
    "com.electron.lark.iron": ["Feishu", "Lark", "Lark Helper", "com.electron.lark.iron"],
    "com.tencent.xinWeChat": ["WeChat", "微信"]
]

func usage() -> String {
    """
    用法：
      swift Tools/Diagnostics/collect_meeting_signals.swift --bundle us.zoom.xos --process zoom.us --label zoom-main --duration 30

    参数：
      --bundle <bundle-id>        目标 app 的 bundle identifier，例如 us.zoom.xos
      --process <name>           用于匹配音频日志的进程/app 名称
      --alias <name[,name]>      额外进程别名，用于过滤音频日志
      --label <name>             当前测试场景标签，会写入每条事件
      --duration <seconds>       采集时长，默认 60 秒
      --interval <seconds>       AX 采样间隔，默认 2 秒
      --depth <n>                AX 子节点遍历深度，默认 3
      --max-nodes <n>            每个窗口最多采集的 AX 节点数，默认 250
      --out <path>               JSONL 输出路径，默认 /private/tmp/meetingsonar-signals-<timestamp>.jsonl
      --no-audio                 不启动 /usr/bin/log stream，只采集进程和 AX 信号
      --prompt-accessibility     如缺少权限，请求 macOS 显示 Accessibility 授权提示
      --help                     显示帮助
    """
}

func parseArgs(_ args: [String]) throws -> Config {
    var config = Config()
    var index = 0

    func requireValue(for option: String) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < args.count else {
            throw DiagnosticError.invalidArguments("Missing value for \(option)")
        }
        index = valueIndex
        return args[valueIndex]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--bundle":
            config.bundleID = try requireValue(for: arg)
        case "--process":
            config.processName = try requireValue(for: arg)
        case "--alias":
            let raw = try requireValue(for: arg)
            config.aliases.append(contentsOf: raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        case "--label":
            config.label = try requireValue(for: arg)
        case "--duration":
            guard let value = TimeInterval(try requireValue(for: arg)), value > 0 else {
                throw DiagnosticError.invalidArguments("Invalid --duration")
            }
            config.duration = value
        case "--interval":
            guard let value = TimeInterval(try requireValue(for: arg)), value > 0 else {
                throw DiagnosticError.invalidArguments("Invalid --interval")
            }
            config.interval = value
        case "--depth":
            guard let value = Int(try requireValue(for: arg)), value >= 0 else {
                throw DiagnosticError.invalidArguments("Invalid --depth")
            }
            config.depth = value
        case "--max-nodes":
            guard let value = Int(try requireValue(for: arg)), value > 0 else {
                throw DiagnosticError.invalidArguments("Invalid --max-nodes")
            }
            config.maxNodesPerWindow = value
        case "--out":
            config.outputURL = URL(fileURLWithPath: try requireValue(for: arg))
        case "--no-audio":
            config.includeAudioLogs = false
        case "--prompt-accessibility":
            config.promptAccessibility = true
        case "--help", "-h":
            print(usage())
            exit(0)
        default:
            throw DiagnosticError.invalidArguments("Unknown argument: \(arg)")
        }
        index += 1
    }

    guard config.bundleID != nil || config.processName != nil else {
        throw DiagnosticError.invalidArguments("Provide at least --bundle or --process")
    }

    return config
}

enum DiagnosticError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case outputFile(String)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .outputFile(let message):
            return "Output file error: \(message)"
        }
    }
}

final class JSONLWriter {
    private let handle: FileHandle
    private let lock = NSLock()

    init(url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw DiagnosticError.outputFile("Cannot open \(url.path)")
        }
        self.handle = handle
    }

    func write(_ event: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }

        do {
            var normalized = event
            normalized["timestamp"] = normalized["timestamp"] ?? isoTimestamp()
            let data = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
            handle.write(data)
            handle.write(Data("\n".utf8))
        } catch {
            fputs("Failed to encode event: \(error)\n", stderr)
        }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle.close()
    }
}

func isoTimestamp(_ date: Date = Date()) -> String {
    ISO8601DateFormatter().string(from: date)
}

func defaultOutputURL() -> URL {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    let filename = "meetingsonar-signals-\(formatter.string(from: Date())).jsonl"
    return URL(fileURLWithPath: "/private/tmp").appendingPathComponent(filename)
}

func accessibilityTrusted(prompt: Bool) -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func matchingApps(config: Config) -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter { app in
        let bundleMatches = config.bundleID.map { app.bundleIdentifier == $0 } ?? false
        let nameMatches = config.processName.map { processName in
            app.localizedName == processName ||
                app.bundleURL?.deletingPathExtension().lastPathComponent == processName
        } ?? false
        return bundleMatches || nameMatches
    }
}

func appSnapshot(_ app: NSRunningApplication) -> [String: Any] {
    [
        "bundleIdentifier": app.bundleIdentifier ?? "",
        "localizedName": app.localizedName ?? "",
        "pid": app.processIdentifier,
        "isActive": app.isActive,
        "isHidden": app.isHidden,
        "activationPolicy": String(describing: app.activationPolicy),
        "bundleURL": app.bundleURL?.path ?? ""
    ]
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
    var ref: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard result == .success, let value = ref else { return nil }

    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
    var ref: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard result == .success, let value = ref else { return nil }
    return value as? Bool
}

func arrayAttribute(_ element: AXUIElement, _ attribute: CFString) -> [AXUIElement] {
    var ref: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute, &ref)
    guard result == .success, let array = ref as? [AXUIElement] else { return [] }
    return array
}

func actionNames(_ element: AXUIElement) -> [String] {
    var ref: CFArray?
    let result = AXUIElementCopyActionNames(element, &ref)
    guard result == .success, let actions = ref as? [String] else { return [] }
    return actions
}

func elementInfo(_ element: AXUIElement, depth: Int) -> [String: Any] {
    var info: [String: Any] = ["depth": depth]

    let attributes: [(String, CFString)] = [
        ("role", kAXRoleAttribute as CFString),
        ("subrole", kAXSubroleAttribute as CFString),
        ("title", kAXTitleAttribute as CFString),
        ("description", kAXDescriptionAttribute as CFString),
        ("value", kAXValueAttribute as CFString),
        ("help", kAXHelpAttribute as CFString),
        ("identifier", "AXIdentifier" as CFString)
    ]

    for (key, attribute) in attributes {
        if let value = stringAttribute(element, attribute), !value.isEmpty {
            info[key] = value
        }
    }

    if let enabled = boolAttribute(element, kAXEnabledAttribute as CFString) {
        info["enabled"] = enabled
    }

    let actions = actionNames(element)
    if !actions.isEmpty {
        info["actions"] = actions
    }

    return info
}

func shouldIncludeElement(_ info: [String: Any]) -> Bool {
    let textKeys = ["title", "description", "value", "help", "identifier"]
    if textKeys.contains(where: { (info[$0] as? String)?.isEmpty == false }) {
        return true
    }

    guard let role = info["role"] as? String else { return false }
    return [
        "AXButton",
        "AXCheckBox",
        "AXMenuButton",
        "AXPopUpButton",
        "AXRadioButton",
        "AXStaticText",
        "AXTextField",
        "AXWindow",
        "AXSheet",
        "AXDialog"
    ].contains(role)
}

func collectAXNodes(from element: AXUIElement, remainingDepth: Int, currentDepth: Int, maxNodes: Int, count: inout Int) -> [[String: Any]] {
    guard count < maxNodes else { return [] }

    let info = elementInfo(element, depth: currentDepth)
    count += 1

    var nodes: [[String: Any]] = []
    if shouldIncludeElement(info) {
        nodes.append(info)
    }

    guard remainingDepth > 0, count < maxNodes else { return nodes }
    let children = arrayAttribute(element, kAXChildrenAttribute as CFString)
    for child in children {
        nodes.append(contentsOf: collectAXNodes(
            from: child,
            remainingDepth: remainingDepth - 1,
            currentDepth: currentDepth + 1,
            maxNodes: maxNodes,
            count: &count
        ))
        if count >= maxNodes { break }
    }
    return nodes
}

func axSnapshot(for app: NSRunningApplication, depth: Int, maxNodesPerWindow: Int) -> [String: Any] {
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    let windows = arrayAttribute(appElement, kAXWindowsAttribute as CFString)
    var windowSnapshots: [[String: Any]] = []

    for (index, window) in windows.enumerated() {
        var count = 0
        var snapshot = elementInfo(window, depth: 0)
        snapshot["index"] = index
        snapshot["nodeCountLimit"] = maxNodesPerWindow
        snapshot["nodes"] = collectAXNodes(
            from: window,
            remainingDepth: depth,
            currentDepth: 0,
            maxNodes: maxNodesPerWindow,
            count: &count
        )
        snapshot["visitedNodeCount"] = count
        windowSnapshots.append(snapshot)
    }

    return [
        "windowCount": windows.count,
        "windows": windowSnapshots
    ]
}

func targetAudioTerms(config: Config) -> [String] {
    var terms = Set<String>()
    if let processName = config.processName {
        terms.insert(processName)
    }
    if let bundleID = config.bundleID {
        for alias in knownAudioAliases[bundleID] ?? [] {
            terms.insert(alias)
        }
    }
    for alias in config.aliases {
        terms.insert(alias)
    }
    return terms.sorted { $0.count > $1.count }
}

func parseAudioLine(_ line: String, terms: [String]) -> [String: Any]? {
    guard line.contains("setPlayState") else { return nil }

    let matchedTerm = terms.first { line.localizedCaseInsensitiveContains($0) }
    if !terms.isEmpty, matchedTerm == nil {
        return nil
    }

    var active: Bool?
    var pattern = "unknown"

    if let range = line.range(of: "IOState: [") {
        let after = line[range.upperBound...]
        let first = after.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        if let inputLevel = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)) {
            active = inputLevel > 0
            pattern = "IOState"
        }
    } else if line.contains("setPlayState Started") && line.contains("Input") && !line.contains("Input/Output") {
        active = true
        pattern = "Started Input"
    } else if line.contains("setPlayState Stopped") && line.contains("Input") {
        active = false
        pattern = "Stopped Input"
    }

    var event: [String: Any] = [
        "type": "audio_log",
        "pattern": pattern,
        "line": line
    ]
    if let active {
        event["inputActive"] = active
    }
    if let matchedTerm {
        event["matchedTerm"] = matchedTerm
    }
    return event
}

final class AudioLogMonitor {
    private let process = Process()
    private let pipe = Pipe()
    private var buffer = ""
    private let terms: [String]
    private let writer: JSONLWriter

    init(terms: [String], writer: JSONLWriter) {
        self.terms = terms
        self.writer = writer
    }

    func start() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style",
            "compact",
            "--predicate",
            "message CONTAINS 'setPlayState'"
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            self.consume(chunk)
        }

        do {
            try process.run()
            writer.write([
                "type": "audio_monitor_started",
                "pid": process.processIdentifier,
                "filterTerms": terms
            ])
        } catch {
            writer.write([
                "type": "audio_monitor_failed",
                "error": error.localizedDescription
            ])
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        writer.write(["type": "audio_monitor_stopped"])
    }

    private func consume(_ chunk: String) {
        buffer += chunk
        let parts = buffer.components(separatedBy: .newlines)
        buffer = parts.last ?? ""

        for line in parts.dropLast() {
            guard let event = parseAudioLine(line, terms: terms) else { continue }
            writer.write(event)
        }
    }
}

func run(config: Config) throws {
    let outputURL = config.outputURL ?? defaultOutputURL()
    let writer = try JSONLWriter(url: outputURL)
    defer {
        writer.close()
    }

    let axTrusted = accessibilityTrusted(prompt: config.promptAccessibility)
    let audioTerms = targetAudioTerms(config: config)

    writer.write([
        "type": "session_start",
        "label": config.label,
        "bundleID": config.bundleID ?? "",
        "processName": config.processName ?? "",
        "aliases": config.aliases,
        "duration": config.duration,
        "interval": config.interval,
        "depth": config.depth,
        "maxNodesPerWindow": config.maxNodesPerWindow,
        "includeAudioLogs": config.includeAudioLogs,
        "accessibilityTrusted": axTrusted,
        "audioFilterTerms": audioTerms,
        "outputPath": outputURL.path
    ])

    print("MeetingSonar signal capture started")
    print("Label: \(config.label)")
    print("Output: \(outputURL.path)")
    print("Accessibility trusted: \(axTrusted)")
    if !axTrusted {
        print("AX window/control details will be limited. Re-run with --prompt-accessibility if needed.")
    }

    let audioMonitor: AudioLogMonitor?
    if config.includeAudioLogs {
        audioMonitor = AudioLogMonitor(terms: audioTerms, writer: writer)
        audioMonitor?.start()
    } else {
        audioMonitor = nil
    }

    let endTime = Date().addingTimeInterval(config.duration)
    var sampleIndex = 0
    while Date() < endTime {
        autoreleasepool {
            let apps = matchingApps(config: config)
            var appEvents: [[String: Any]] = []

            for app in apps {
                var appEvent: [String: Any] = appSnapshot(app)
                if axTrusted {
                    appEvent["ax"] = axSnapshot(
                        for: app,
                        depth: config.depth,
                        maxNodesPerWindow: config.maxNodesPerWindow
                    )
                }
                appEvents.append(appEvent)
            }

            writer.write([
                "type": "sample",
                "label": config.label,
                "sampleIndex": sampleIndex,
                "matchingAppCount": apps.count,
                "apps": appEvents
            ])
            sampleIndex += 1
        }

        Thread.sleep(forTimeInterval: config.interval)
    }

    audioMonitor?.stop()
    writer.write([
        "type": "session_end",
        "label": config.label,
        "sampleCount": sampleIndex,
        "outputPath": outputURL.path
    ])

    print("MeetingSonar signal capture finished")
    print("Output: \(outputURL.path)")
}

do {
    let config = try parseArgs(Array(CommandLine.arguments.dropFirst()))
    try run(config: config)
} catch {
    fputs("\(error)\n\n\(usage())\n", stderr)
    exit(2)
}
