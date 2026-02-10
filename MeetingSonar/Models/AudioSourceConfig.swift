//
//  AudioSourceConfig.swift
//  MeetingSonar
//
//  Audio source configuration for recording scenarios.
//  v1.0 - Recording Scenario Optimization
//

import Foundation

/// 音频源配置
/// 用于定义录音时包含的音频源
struct AudioSourceConfig: Codable, Equatable, Sendable {
    /// 是否包含系统音频
    /// - 当为 true 时，RecordingService 会启动 AudioCaptureService 采集系统音频
    /// - 当为 false 时，仅录制麦克风或不录制任何音频
    var includeSystemAudio: Bool

    /// 是否包含麦克风
    /// - 当为 true 时，RecordingService 会启动 MicrophoneService 采集麦克风
    /// - 当为 false 时，仅录制系统音频或不录制任何音频
    var includeMicrophone: Bool

    /// 默认配置：全部开启
    /// 用于自动检测录音场景，确保会议中双方声音都被录制
    static let `default` = AudioSourceConfig(
        includeSystemAudio: true,
        includeMicrophone: true
    )

    /// 仅系统音频
    /// 用于手动录音场景，适合录制视频/音乐而无需环境音
    static let systemOnly = AudioSourceConfig(
        includeSystemAudio: true,
        includeMicrophone: false
    )

    /// 仅麦克风
    /// 用于纯语音备忘录场景
    static let microphoneOnly = AudioSourceConfig(
        includeSystemAudio: false,
        includeMicrophone: true
    )

    /// 检查是否有任何音频源
    /// 用于验证配置有效性，防止用户禁用所有音频源导致录制空文件
    var hasAnySource: Bool {
        includeSystemAudio || includeMicrophone
    }

    /// 验证配置有效性
    /// - Returns: 如果至少有一个音频源则返回 true
    func isValid() -> Bool {
        hasAnySource
    }
}

// MARK: - UserDefaults 支持

extension AudioSourceConfig {
    /// 从 UserDefaults 读取配置
    /// - Parameters:
    ///   - key: 存储的键名
    ///   - defaults: UserDefaults 实例，默认为标准实例
    /// - Returns: 解码后的配置，如果失败返回 nil
    static func fromDefaults(key: String, defaults: UserDefaults = .standard) -> AudioSourceConfig? {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AudioSourceConfig.self, from: data) else {
            return nil
        }
        return config
    }

    /// 保存到 UserDefaults
    /// - Parameters:
    ///   - key: 存储的键名
    ///   - defaults: UserDefaults 实例，默认为标准实例
    func save(toDefaults key: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: key)
        }
    }
}
