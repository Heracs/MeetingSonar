import Foundation

// MARK: - Summary Result

/// LLM 生成结果
struct SummaryResult {
    /// 生成的摘要文本
    let summary: String

    /// 输入 token 数
    let inputTokens: Int

    /// 输出 token 数
    let outputTokens: Int

    /// 生成时间（秒）
    let generationTime: TimeInterval

    /// 每秒 token 数
    var tokensPerSecond: Double {
        guard generationTime > 0 else { return 0 }
        return Double(outputTokens) / generationTime
    }
}
