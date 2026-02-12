# MeetingSonar v${VERSION} (Build ${BUILD})

**发布日期**: ${DATE}
**发布类型**: Internal（内部测试版）

---

## 发布说明

本次发布为内部测试版本 v0.9.5，用于验证新功能和修复内容。

### 修复内容

本次发布包含以下测试修复：

- AIProcessingCoordinator：修复初始化状态测试
- AudioCaptureService：修复错误描述关键词匹配
- PromptManager：修复系统模板删除保护逻辑
- MetadataManager：修复并发操作数据一致性问题
- StreamingSummaryViewModel：修复异步状态转换测试

**注意**：由于 Release 构建工具问题，本次发布使用 Debug 构建产物。

---

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Apple Silicon (arm64) 或 Intel (x86_64)

---

## 下载

暂无可下载链接。本次为内部测试版本。

---

**完整变更日志**：[CHANGELOG.md](../CHANGELOG.md)

---

**注意**：此版本为内部测试版本，不建议用于生产环境。
