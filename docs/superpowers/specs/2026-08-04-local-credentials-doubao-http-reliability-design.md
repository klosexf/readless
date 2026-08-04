# Readless 本地凭据与豆包朗读可靠性修复设计

**日期：** 2026-08-04

## 目标

解决两个相互关联的用户问题：语音服务保存被 macOS 钥匙串阻断，以及选中文字后按全局快捷键无法开始朗读。同时修正豆包 V3 将握手、鉴权和资源配置失败统一显示为“网络错误”的问题。

## 已确认的根因

当前运行的是 Xcode DerivedData 中的最新调试构建。登录钥匙串里存在 `doubao-v3` 旧条目，但应用保存新凭据时仍返回持久化失败；语音配置因此没有写入 `UserDefaults`。`ReadingCoordinator.handleReadShortcut()` 在读取前台选区之前先调用 `StoredVoiceServiceReadiness`，所以缺少可用的“配置 + 凭据”组合时，快捷键链路会提前退出。

豆包 V3 当前通过 `URLSessionWebSocketTask` 调用单向流式 WebSocket。该实现把除超时之外的传输错误全部映射成 `voiceServiceNetworkUnavailable`，无法区分 WebSocket 握手拒绝、凭据无效和资源配置不匹配。Readless 会等完整音频收齐后才播放，并未利用 WebSocket 的逐块播放能力，因此使用官方 HTTP Chunked 接口更简单，也更容易读取服务端状态。

## 方案选择

采用以下组合方案：

1. 不再在运行时访问 macOS 钥匙串。API Key 保存到 Readless 的 Application Support 目录。
2. 豆包 V3 改用官方 `POST /api/v3/tts/unidirectional` HTTP Chunked 接口。
3. 保持现有选区读取和全局快捷键架构；修复凭据就绪的上游状态后，快捷键继续进入既有选区读取链路。

未采用的方案：

- 继续修复旧钥匙串条目的 ACL：仍受调试签名、历史条目和 macOS 授权状态影响，不能消除本次反复出现的环境依赖。
- 只在内存保存凭据：每次启动都需要重新输入，不符合“保存”按钮的用户预期。
- 把凭据写入 `UserDefaults`：实现简单，但会和普通界面偏好混在同一个 plist 中，权限和数据边界不够清楚。

## 本地凭据存储

新增 `LocalCredentialStore` 实现现有 `VoiceServiceCredentialStoring` 协议。默认位置为用户 Application Support 目录下 Readless 专属子目录中的 JSON 文件。文件内容按 `VoiceCredentialSlot.rawValue` 保存各服务商凭据。

存储行为：

- 目录创建后设置为仅当前用户可访问（POSIX `0700`）。
- 凭据文件采用原子写入，写入后设置为仅当前用户读写（POSIX `0600`）。
- 文件不存在时返回“没有凭据”，不视为错误。
- JSON 无法解析、目录创建失败或写入失败时抛出持久化错误。
- 删除最后一个凭据后仍保留合法的空 JSON 对象，避免特殊删除分支。
- 不从旧钥匙串自动迁移，避免再次触发钥匙串授权或失败。用户需重新输入一次 API Key。

`AppDelegate`、`CloudSpeechEngine`、`StoredVoiceServiceReadiness` 和界面通过既有协议使用同一个 `LocalCredentialStore` 实例。旧 `KeychainCredentialStore` 从运行时和 Swift Package 测试目标中移除。

设置页文案改为明确说明：凭据仅保存于这台 Mac 的 Readless 应用数据中，不使用 macOS 钥匙串，也不经过 Readless 服务器。保存失败文案不再提钥匙串。

## 豆包 V3 HTTP 数据流

`DoubaoV3RequestBuilder` 生成 HTTP `POST` 请求：

- URL：`https://openspeech.bytedance.com/api/v3/tts/unidirectional`
- 请求头：`X-Api-Key`、`X-Api-Resource-Id`、`X-Api-Request-Id`、`Content-Type: application/json`
- JSON 请求体：`req_params.text`、`req_params.speaker` 和 `req_params.audio_params`
- 音频格式保持 `mp3`，采样率保持 `24000`，语速继续使用当前 `[-50, 100]` 映射。

`DoubaoV3SpeechProvider` 使用 `URLSessionDataTask` 获取完整 HTTP 响应。响应解析器按行解码 JSON Chunk，将所有非空 `data` Base64 音频块按顺序拼接。解析规则：

- HTTP 401/403 映射为凭据无效，408/504 映射为超时，429 映射为额度不足。
- 其他非 2xx 状态结合响应 JSON 的 `code` 和 `message` 映射；无法识别时显示服务返回异常，而不是误报网络断开。
- 2xx 响应中出现服务错误码时，使用同一错误映射。
- 只有至少获得一个合法音频块才返回成功；空响应、非法 JSON 或非法 Base64 返回服务响应异常。
- `URLError.timedOut` 映射为超时；其他真实传输错误映射为网络不可用。

应用当前在音频完整下载后才创建 `AVAudioPlayer`，因此从 WebSocket 改为 HTTP 不改变用户可见的播放时序。

## 快捷键链路

全局选区快捷键仍由 `GlobalHotKeyController` 调用 `ReadingCoordinator.handleReadShortcut()`。修复后：

1. 保存配置和 API Key 成功。
2. `StoredVoiceServiceReadiness` 从本地凭据文件确认当前配置对应的槽位存在。
3. 按 `⌥R` 后继续检查辅助功能权限。
4. 从前台应用读取当前选区、清洗文本并调用豆包 HTTP 语音合成。

不新增自动读取剪贴板的回退，避免在用户未明确触发时读取剪贴板。若辅助功能权限缺失或目标应用不支持选区，继续使用现有的具体错误提示。

## 错误处理与隐私

- API Key 不打印、不写日志、不进入测试快照。
- 诊断信息只包含持久化阶段、HTTP 状态、豆包错误码和服务消息分类，不包含凭据或朗读原文。
- 本地文件方案弱于钥匙串：拥有当前 macOS 用户文件访问权的进程可能读取该文件。界面文案明确“仅保存于本机应用数据”，不宣称加密。
- Readless 不增加中转服务器；选中文字仍直接发送给用户配置的豆包服务。

## 测试与验收

自动化测试：

- 本地凭据可按槽位保存、读取、覆盖和删除。
- 新文件和目录权限分别为 `0600` 与 `0700`。
- 缺失文件返回空凭据；损坏 JSON 返回持久化错误。
- 豆包 V3 请求使用官方 HTTP URL、请求方法、请求头和 JSON 字段。
- 多个响应音频块按顺序拼接；空数据、非法 Base64 和服务错误正确分类。
- 就绪检查在配置和本地凭据齐全时通过，缺任一项时失败。
- 选区快捷键在就绪时调用选区读取和语音引擎，未就绪时不会读取选区。

构建与本机验收：

1. 运行全部 Swift Package 测试和现有 Node 回归测试。
2. 运行 Xcode Debug 构建。
3. 终止旧 Readless 进程并启动本次新构建。
4. 在设置页重新输入 API Key，保存后确认没有钥匙串错误且“凭据已保存”状态正确。
5. 播放内置测试句，确认豆包返回音频并实际开始播放。
6. 在 TextEdit 或 Safari 选中文字后按 `⌥R`，确认进入准备、播放状态；再次按键确认暂停/继续。
7. 退出并重新启动 Readless，确认配置和凭据仍可用。

真实豆包调用和系统选区读取依赖用户当前的 API Key、网络及辅助功能授权。若自动化环境无法判断扬声器是否出声，以应用进入 `playing` 状态、音频播放器成功启动和用户听觉确认为最终标准。

## 回滚

本次修改集中在凭据存储实现、豆包 V3 请求/响应实现、设置文案和对应测试。回滚这些提交即可恢复旧钥匙串与 WebSocket 路径；本地凭据文件不会影响旧版本读取钥匙串。
