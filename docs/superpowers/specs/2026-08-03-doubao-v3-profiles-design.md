# 豆包 V3 与 V1 独立配置设计

## 目标

为 Readless 的豆包语音增加 V3 单向 WebSocket 支持，同时保留已有 V1 接入。设置页由用户明确选择 V3（默认、推荐）或 V1（兼容），应用只使用被选中的版本，不执行静默降级。

## 非目标

- 不更改 OpenAI-compatible Provider。
- 不接入声音复刻、混音、双向流式或长文本异步合成。
- 不保存选区、剪贴板正文、音频数据或原始云端响应。
- 不删除已保存的 V1 配置与凭据。

## 配置模型与存储

豆包配置由独立的 profile 集合保存，并记录当前启用的接口版本。

- `V3` profile：`resourceID`（默认 `seed-tts-2.0`）和 `speaker`；API Key 仅存入 Keychain 的 `doubao-v3` 项。
- `V1` profile：现有 `appID`、`cluster`、`voiceType`；Access Token 仅存入 Keychain 的 `doubao-v1` 项。
- 已有 `VoiceServiceConfiguration.doubao` 与其旧 Keychain `doubao` 项视为 V1 数据：首次读取 V1 时兼容读取旧凭据；保存 V1 后使用新 `doubao-v1` 项。旧项不自动删除。
- profile 集合与当前版本使用新的、版本化 UserDefaults 键保存；其中不包含 API Key 或 Access Token。

任一时刻只有一个 profile 为活动 profile。`StoredVoiceServiceReadiness`、设置页试播和 `CloudSpeechEngine` 都只读取该 profile 及其对应 Keychain 凭据。

## 设置与引导界面

豆包表单顶部增加“接口版本”选择：

- **V3（推荐）**：显示 API Key、资源 ID 与音色 ID；资源 ID 默认 `seed-tts-2.0`，可修改以匹配控制台购买的资源与音色。
- **V1（兼容）**：显示原有 App ID、Access Token、Cluster 与音色 ID。

切换版本只切换编辑的 profile；已经输入或保存的另一 profile 保持不变。每一版本独立显示“凭据已保存”。保存、试播和首次引导始终使用当前版本。V3 未配置时不能用 V1 代替试播；V1 未配置时也不能用 V3 代替。

## Provider 与错误处理

保留 V1 Provider 的二进制协议实现，并新增 V3 单向 WebSocket Provider，连接：

`wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream`

V3 通过 API Key、资源 ID与每请求 UUID 进行鉴权和请求标识；请求使用当前 profile 的音色和固定 MP3 输出。Provider 将 V3 成功音频帧聚合为 `Data`，交给既有 `CloudSpeechEngine` 播放。V3 的鉴权、配额、超时、网络和协议错误继续映射到现有 `ReadingError` 分类，不暴露密钥或原始响应。

## 测试与验证

- Core 测试覆盖 V3 profile 校验、V1 旧配置/凭据兼容、切换 profile 不覆盖另一版本、活动 profile 就绪性。
- V3 编码/解码测试使用固定的无敏感 fixture，验证 endpoint、鉴权头、资源 ID、音色、帧解析与错误映射。
- 完整 `swift test` 和 Xcode Debug 构建必须通过。
- 真实 V3 测试由用户以自有 API Key 执行：保存 V3、固定内置试播、辅助功能授权与一次真实选区朗读；确认 V1 profile 未被覆盖。

## 风险与回滚

V3 的资源 ID 必须与所购买套餐和音色匹配；不匹配会显示已分类的服务端错误，不会自动切换到 V1。实现以独立 Provider 和 versioned storage 隔离，回滚时可仅回退 V3 相关提交，同时保留已有 V1 运行路径。
