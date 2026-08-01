# 云端语音与首次引导设计规格

**日期：** 2026-08-01
**状态：** 已确认

## 目标

把 Readless 从系统语音原型升级为用户自带凭证的云端听读工具。首期真实支持豆包（火山引擎）和 OpenAI-compatible TTS，同时交付可扩展的服务商目录、按字段可恢复的错误提示，以及引导用户完成首次成功朗读的四步流程。

## 非目标

- 不接入 OpenAI 或阿里百炼的真实请求；它们在目录中显示为“即将支持”。
- 不保存选区、剪贴板内容、合成音频或朗读历史。
- 不引入账号、服务端代理、遥测、缓存、媒体键或跨重启续听。
- 不改变辅助功能读取范围、Carbon 全局快捷键机制、工程签名或 Sandbox 配置。

## 用户流程

首次启动或尚未完成配置时，显示独立引导窗口：

1. **服务商配置**：用户选择豆包或 OpenAI-compatible。豆包要求 App ID、Access Token、Cluster、voice type；兼容接口要求 Base URL、API Key、Model、Voice。OpenAI 与阿里百炼显示为不可选择的“即将支持”。
2. **播放测试句**：仅向所选服务商发送内置、固定的测试句。请求成功并开始播放后才允许进入下一步；任何失败留在本步并标出可恢复原因。
3. **辅助功能权限**：解释只会在用户按快捷键时读取当前选区。用户点击后调用现有权限请求；授权前不能继续。
4. **快捷键练习**：显示默认快捷键和练习说明。用户完成一次成功朗读后写入“已完成引导”状态并关闭窗口。

正常运行时，若服务尚未配置或配置失效，用户按快捷键不读取选区、不发送任何内容，改为打开引导的配置步骤。

## 架构

```text
SwiftUI settings / onboarding
          ↓ actions + published state
VoiceServiceStore + KeychainCredentialStore
          ↓ VoiceServiceConfiguration (no secret)
ReadingCoordinator → CloudSpeechEngine → SpeechProvider
                                      ├─ DoubaoSpeechProvider
                                      └─ OpenAICompatibleSpeechProvider
```

- `VoiceServiceConfiguration` 只含服务商种类、端点、模型、音色与非秘密标识；保存到 `UserDefaults`。
- `KeychainCredentialStore` 以稳定 service/account 名称保存 API Key、Access Token；普通配置、错误信息、日志和测试 fixture 均不得包含秘密。
- `SpeechProvider` 接收已清洗文本和短期凭证，在请求结束后丢弃凭证。首版豆包 provider 使用官方仍可用的 V1 单向流式 WebSocket，并与未来 V3 实现隔离；兼容 provider 使用 `POST /v1/audio/speech`，请求体为 `input`、`model`、`voice`，并接收音频响应。
- `CloudSpeechEngine` 管理下载/流入的音频与本地播放回调，继续满足现有 `SpeechEngine` 的开始、进度、结束、失败、暂停、继续与停止合同。
- OpenAI 与阿里 provider 类型只占位在 `SpeechProviderKind`，不创建请求实现，不允许保存或验证其配置。

## 错误与恢复

新增的用户可见错误必须映射到下列稳定类别，且不回显服务商原始响应、凭证、选区或剪贴板内容。

| 类别 | 触发 | 用户操作 |
| --- | --- | --- |
| `voiceServiceNotConfigured` | 没有有效配置或 Keychain 凭证 | 打开配置步骤 |
| `voiceServiceNetworkUnavailable` | 网络、DNS、连接失败 | 重试 |
| `voiceServiceCredentialInvalid` | 401/403 或豆包鉴权失败 | 打开并聚焦凭证字段 |
| `voiceServiceQuotaExceeded` | 额度耗尽的明确状态 | 打开服务商控制台链接（若配置提供） |
| `voiceServiceTimedOut` | 超过定义的请求/首包等待时间 | 重试 |
| `voiceServiceResponseInvalid` | 协议响应无法解析或音频不可播放 | 重试或检查配置 |

测试句与真实朗读使用同一错误映射。重试必须重新构造请求，不能复用可能已失效的授权或音频 URL。

## 隐私与持久化

- 所有密钥仅写入 macOS Keychain；UI 只显示“已保存”，不回显秘密。
- 只有用户发起测试句或朗读后，文本才发送给其选择的服务商；应用没有自有服务器。
- 首启完成状态和非敏感配置使用版本化 `UserDefaults` 键；迁移将从无配置安全地开始，不读取未知旧值。
- 选择、剪贴板与音频只保留在活动会话内存，停止、失败或完成后释放。

## 验收与测试

- 核心测试先验证配置验证、Keychain 抽象、错误映射、未配置快捷键不读取选区，以及引导四步的前进守卫。
- Provider 请求使用注入的 HTTP/WebSocket transport 测试 URL、headers 和 JSON，不使用真实凭证或真实网络。
- 完整 App 构建后手测：首次配置、测试句成功/失败、拒绝/授予辅助功能、一次真实选区朗读，以及设置页变更后重新测试。
- 若本机无法取得完整 Xcode 或真实凭证，记录为未完成验证，不宣称服务商实测通过。

## 风险与回滚

- 豆包 V1 接口已标记为不推荐，且 V3 的公开帧规范在本次开发环境中不可解析；实现把编码/解码限制在 provider 内，便于独立升级到 V3。
- 用户自建兼容端点对音频格式和错误 body 的支持不一致；首期只承诺 OpenAI Speech API 形状，不对任意非兼容实现作兼容保证。
- 回滚时可撤销本功能提交；未配置用户继续使用原有系统语音路径，已写入的非敏感配置可忽略，Keychain 项不自动删除。
