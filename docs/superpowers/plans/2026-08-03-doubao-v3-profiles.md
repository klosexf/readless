# 豆包 V3 / V1 独立配置实施计划

> **For implementation:** Execute the tasks in order. Use test-first changes, keep commits task-scoped, and do not record API Keys, Access Tokens, source text, clipboard text, or raw service responses in test fixtures, preferences, diagnostics, or commits.

**目标：** 为 Readless 增加豆包 V3 单向 WebSocket 合成，同时继续支持现有 V1。设置中由用户手动选择 V3（推荐）或 V1（兼容）；两套非敏感配置与凭据独立保存，且绝不自动回退。

**架构：** `Core/` 持有接口版本、非敏感 profile、凭据槽位、校验、迁移选择和 V3 可测试协议编解码。`System/` 只负责 Keychain、WebSocket 收发、音频聚合与播放。设置和引导通过 `ReadlessActions` 使用活动 profile；运行时通过配置枚举精确挑选 V1 或 V3 Provider。旧 `voice-service-configuration-v1` 和旧 Keychain `doubao` 只作为 V1 的兼容读取来源，永不被自动删除。

**技术栈：** Swift 6、SwiftUI、Foundation `URLSessionWebSocketTask`、Security Keychain Services、AVFoundation、XCTest、macOS 15。

---

## 文件地图

- 修改 `readless/Core/VoiceServiceModels.swift`：V1/V3 profile、活动版本、凭据槽位与验证。
- 修改 `readless/Core/VoiceServiceStore.swift`：profile 读取/选择契约与活动 profile 就绪性。
- 修改 `readless/Core/CloudSpeechRequests.swift`：V3 单向 WebSocket 请求与响应 packet codec、稳定错误映射。
- 修改 `readless/System/VoiceServiceSettingsStore.swift` 和 `KeychainCredentialStore.swift`：版本化的 profile 数据与旧 V1 凭据兼容读取。
- 新建 `readless/System/DoubaoV3SpeechProvider.swift`，并修改 V1 Provider、`CloudSpeechEngine.swift`：只按活动 profile 请求。
- 修改 `readless/AppActions.swift`、`AppDelegate.swift`、`MainWindowView.swift`、`PreviewFixtures.swift`：手动版本选择、独立字段、保存与试播。
- 修改 `Package.swift`，并更新 `Tests/ReadlessCoreTests/VoiceServiceModelsTests.swift`、`VoiceServiceStoreTests.swift`、`CloudSpeechRequestTests.swift`、`VoiceServiceSettingsLayoutTests.swift`。
- 完成后更新本地忽略的 `progress.md`（不纳入提交）。

## Task 1：用类型表达 V1/V3 profile 与独立凭据槽位

**Files:**

- Modify: `readless/Core/VoiceServiceModels.swift`
- Modify: `readless/Core/VoiceServiceStore.swift`
- Modify: `Tests/ReadlessCoreTests/VoiceServiceModelsTests.swift`
- Modify: `Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift`

- [ ] **Step 1: 先写失败测试。**

  在模型测试中增加 V3 resource ID、speaker 必填，以及 V1/V3 使用不同凭据槽位的断言；保留原 `.doubao(appID:cluster:voiceType:)` 的 V1 校验测试。

  ```swift
  func testDoubaoV3RequiresResourceIDBeforeSpeaker() {
      let value = VoiceServiceConfiguration.doubaoV3(
          resourceID: "", speaker: ""
      )
      XCTAssertEqual(value.validationError, .resourceIDRequired)
  }

  func testDoubaoVersionsUseSeparateCredentialSlots() {
      XCTAssertEqual(
          VoiceServiceConfiguration.doubao(
              appID: "id", cluster: "volcano_tts", voiceType: "voice"
          ).credentialSlot,
          .doubaoV1
      )
      XCTAssertEqual(
          VoiceServiceConfiguration.doubaoV3(
              resourceID: "seed-tts-2.0", speaker: "voice"
          ).credentialSlot,
          .doubaoV3
      )
  }
  ```

- [ ] **Step 2: 验证 RED。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter 'VoiceServiceModelsTests|VoiceServiceStoreTests'
  ```

  预期：测试无法编译，因为 V3 case、credential slot 与 profile API 尚不存在。

- [ ] **Step 3: 添加最小 Core 模型与 Store 契约。**

  在 `VoiceServiceConfiguration` 增加非敏感 case：

  ```swift
  case doubao(appID: String, cluster: String, voiceType: String) // V1，保留原 Codable 形态
  case doubaoV3(resourceID: String, speaker: String)
  case openAICompatible(baseURL: String, model: String, voice: String)
  ```

  新增 `DoubaoAPIVersion: String, Codable, CaseIterable, Sendable`（`.v3`、`.v1`）和 `VoiceCredentialSlot`（`.doubaoLegacy`、`.doubaoV1`、`.doubaoV3`、`.openAICompatible`）。让 `.doubao` 映射 `.doubaoV1`，`.doubaoV3` 映射 `.doubaoV3`；保持两者的 `provider == .doubao`，因此 OpenAI-compatible 与待扩展 provider 的行为不变。

  新增 `resourceIDRequired` 并在 `userMessage` 中显示“请填写资源 ID。”；V3 speaker 继续使用既有 `.voiceRequired`。增加非敏感的 `VoiceServiceProfiles`：保存 `activeProvider`、`activeDoubaoVersion`、`doubaoV1`、`doubaoV3` 和 `openAICompatible`，并以 `activeConfiguration` 只返回活动 provider 对应 profile。

  将凭据协议改为按槽位工作：

  ```swift
  func hasCredential(for slot: VoiceCredentialSlot) -> Bool
  func credential(for slot: VoiceCredentialSlot) throws -> String?
  func saveCredential(_ credential: String, for slot: VoiceCredentialSlot) throws
  ```

  `StoredVoiceServiceReadiness` 只检查 `settings.configuration` 的 `credentialSlot`。为方便调用方，`VoiceServiceConfigurationStoring` 增加 `profiles`、`selectDoubaoVersion(_:)`、`save(configuration:)`；配置 store 的实现仍负责决定活跃 profile。

- [ ] **Step 4: 验证 GREEN。**

  重跑 Step 2。再新增断言：切换 V3/V1 时所选 profile 改变，但未选 profile 的值和其凭据槽位不被改变。

- [ ] **Step 5: 提交。**

  ```bash
  git add readless/Core/VoiceServiceModels.swift readless/Core/VoiceServiceStore.swift Tests/ReadlessCoreTests/VoiceServiceModelsTests.swift Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift
  git commit -m "feat: model separate doubao v1 and v3 profiles"
  ```

## Task 2：迁移安全存储，兼容读取旧 V1 数据

**Files:**

- Modify: `readless/System/VoiceServiceSettingsStore.swift`
- Modify: `readless/System/KeychainCredentialStore.swift`
- Modify: `Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift`

- [ ] **Step 1: 先写迁移和隔离测试。**

  使用独立 suite 的 `UserDefaults` fake/test instance 验证：无新 profile key 时，旧 `voice-service-configuration-v1` 的 `.doubao` 被当成 V1 活动 profile；保存 V3 不覆盖 V1；切回 V1 能读取原 profile。使用 credential fake 断言 V1 先读取 `.doubaoV1`，若为空才读取 `.doubaoLegacy`；V3 绝不能读取 legacy 项。

  ```swift
  func testLegacyDoubaoConfigurationLoadsAsV1Profile() throws {
      // 将不含 secret 的旧 .doubao 编码写入 legacy key。
      XCTAssertEqual(store.profiles.activeDoubaoVersion, .v1)
      XCTAssertEqual(store.configuration, legacyConfiguration)
  }
  ```

- [ ] **Step 2: 验证 RED。**

  运行 Task 1 的过滤测试；预期迁移 API/行为失败。

- [ ] **Step 3: 实现版本化 preferences 和 Keychain 迁移策略。**

  `VoiceServiceSettingsStore` 新增 `voice-service-profiles-v2` 键。读取时优先解码 `VoiceServiceProfiles`；没有该键时读取旧 key，将 `.doubao` 映射为 V1 活动 profile、`.openAICompatible` 映射为兼容接口活动 profile。不要在读取阶段删除或重写旧键；下一次成功 `save(configuration:)` 时写入 v2 profile 集合。

  `KeychainCredentialStore` 通过 account 使用 `.doubaoV1.rawValue`、`.doubaoV3.rawValue`、`.openAICompatible.rawValue`。当且仅当读取 V1 且 `.doubaoV1` 未找到时，再读取旧 `.doubaoLegacy`（实际 account 仍是历史 `doubao`）；保存 V1 只写 `.doubaoV1`，保存 V3 只写 `.doubaoV3`。不调用对 legacy account 的删除。`removeCredential` 仅删除传入的现代 slot。

  所有 `SecItemCopyMatching`、更新/写入失败仍抛通用 Keychain error；不得将 credential 放进错误内容、日志或 `UserDefaults`。

- [ ] **Step 4: 验证 GREEN 与 app 编译。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-v3-derived build CODE_SIGNING_ALLOWED=NO
  ```

  预期：Core 测试全绿，macOS 工程包含 Keychain 代码且可编译。

- [ ] **Step 5: 提交。**

  ```bash
  git add readless/System/VoiceServiceSettingsStore.swift readless/System/KeychainCredentialStore.swift Tests/ReadlessCoreTests/VoiceServiceStoreTests.swift
  git commit -m "feat: persist isolated doubao voice profiles"
  ```

## Task 3：实现并测试 V3 单向 WebSocket 协议 codec

**Files:**

- Modify: `readless/Core/CloudSpeechRequests.swift`
- Modify: `Package.swift`
- Modify: `Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift`

- [ ] **Step 1: 固化官方 V3 contract 并写失败测试。**

  以火山引擎当前 V3 单向 WebSocket 文档为唯一协议依据，锁定 endpoint `wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream`、API Key、Resource ID、每次请求 UUID、当前 speaker、MP3 输出和速率字段。将字段只写入不含真实凭据的 unit test：

  ```swift
  func testDoubaoV3RequestUsesSelectedResourceAndSpeaker() throws {
      let request = try DoubaoV3RequestBuilder.make(
          configuration: .doubaoV3(
              resourceID: "seed-tts-2.0", speaker: "test-speaker"
          ),
          apiKey: "unit-test-key",
          text: "测试",
          rate: 1
      )

      XCTAssertEqual(request.url?.absoluteString,
          "wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "unit-test-key")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Resource-Id"), "seed-tts-2.0")
  }
  ```

  另为文档规定的音频 frame、末尾 frame 和错误 frame 创建固定十六进制 fixture，测试音频累计、结束判定及错误消息到 `ReadingError` 的映射；fixture 不含用户文本、真实 request ID、API Key 或服务端原文。

- [ ] **Step 2: 验证 RED。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter CloudSpeechRequestTests
  ```

  预期：V3 builder 和 packet decoder 未定义而失败。

- [ ] **Step 3: 实现可测试的 V3 request/packet helpers。**

  在 `Core/CloudSpeechRequests.swift` 增加 `DoubaoV3RequestBuilder`，它只接受 `.doubaoV3`、经过验证的非敏感 profile 与调用方提供的 API Key；填充 `X-Api-Key`、`X-Api-Resource-Id`、当前请求 UUID，15 秒超时，并生成官方定义的单向请求 packet/JSON payload。它必须拒绝 V1 或不完整 profile，返回现有 `CloudSpeechRequestError.incompatibleConfiguration`。

  使用独立 `DoubaoV3PacketDecoder` 解析官方 V3 header、sequence、音频 payload 与 error payload。decoder 只输出 `.audio(Data, isFinal:)`、`.error(ReadingError)` 或 `.ignore`，不保留原 packet。保持 V1 packet 写入/读取代码在 `DoubaoSpeechProvider` 原处，避免协议耦合；`CloudSpeechErrorMapper` 继续将鉴权/配额/超时/服务端协议错误归类到既有错误类型。

- [ ] **Step 4: 验证 GREEN。**

  重跑 Step 2，再跑完整 `swift test`。确认 `Package.swift` 将更改后的 Core 文件继续显式列为 source。

- [ ] **Step 5: 提交。**

  ```bash
  git add Package.swift readless/Core/CloudSpeechRequests.swift Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift
  git commit -m "feat: encode doubao v3 speech requests"
  ```

## Task 4：接入 V3 Provider，并严格按活动 profile 路由

**Files:**

- Create: `readless/System/DoubaoV3SpeechProvider.swift`
- Modify: `readless/System/DoubaoSpeechProvider.swift`
- Modify: `readless/System/OpenAICompatibleSpeechProvider.swift`
- Modify: `readless/System/CloudSpeechEngine.swift`

- [ ] **Step 1: 先为路由决策添加 Core 层测试。**

  在 `CloudSpeechRequestTests` 或新建小型 Core test 中验证：`.doubao` 选择 V1 策略，`.doubaoV3` 选择 V3 策略，`.openAICompatible` 不受影响；任何 profile 都不会触发跨版本重试。测试不建立网络连接。

- [ ] **Step 2: 验证 RED。**

  跑对应过滤测试，预期因路由 helper 不存在而失败。

- [ ] **Step 3: 添加 V3 transport。**

  新建 `DoubaoV3SpeechProvider: CloudAudioProviding`。它从活动配置读取 `.doubaoV3`，只用 `.doubaoV3` Keychain credential slot，调用 Task 3 builder 后创建单次 `URLSessionWebSocketTask`。每次仅保持一次 synthesis 的 request、task、累计 MP3 `Data` 与 completion；每收到一个 binary frame 使用 decoder，音频 append，final frame 才 `finish(.success(audioData))`。连接/发送/接收超时映射 `.voiceServiceTimedOut`，无连接映射 `.voiceServiceNetworkUnavailable`，协议错误映射 `.voiceServiceResponseInvalid`，认证与配额遵循 mapper。`cancel()` 取消 task、清空音频和 completion。

  修改 V1 `DoubaoSpeechProvider`：只接受 `.doubao` 和 `.doubaoV1` credential slot；不得再通过 `.doubao` provider kind 访问共用 token。兼容读由 Keychain store 已封装，不写入 Provider。

  修改 `CloudSpeechEngine` 根据配置 case（而不是泛化 `provider == .doubao`）构造 V1 或 V3 Provider。保持 OpenAI-compatible Provider 使用自己的 `.openAICompatible` credential slot；对没有活动 profile 的情况仍抛 `.voiceServiceNotConfigured`。没有 catch-and-retry 路径，V3 失败不会实例化 V1 Provider。

- [ ] **Step 4: 验证 GREEN。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-v3-derived build CODE_SIGNING_ALLOWED=NO
  ```

  预期：所有 `System/` provider 都由 Xcode 编译；随后运行完整 `swift test`，Core 协议和配置测试全绿。

- [ ] **Step 5: 提交。**

  ```bash
  git add readless/System/DoubaoV3SpeechProvider.swift readless/System/DoubaoSpeechProvider.swift readless/System/OpenAICompatibleSpeechProvider.swift readless/System/CloudSpeechEngine.swift Tests/ReadlessCoreTests/CloudSpeechRequestTests.swift
  git commit -m "feat: route speech through selected doubao api version"
  ```

## Task 5：设置与引导提供手动 V3/V1 选择

**Files:**

- Modify: `readless/AppActions.swift`
- Modify: `readless/AppDelegate.swift`
- Modify: `readless/MainWindowView.swift`
- Modify: `readless/PreviewFixtures.swift`
- Modify: `readless/OnboardingView.swift`（仅在需要反映新 action 或 profile 状态时）
- Modify: `Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift`

- [ ] **Step 1: 先更新布局契约测试。**

  新增源文件测试，要求豆包区域先出现“接口版本”选择；V3 依次显示 API Key、资源 ID、音色 ID，V1 保持 App ID、Access Token、Cluster、音色；两套凭据状态按版本独立。继续保留 OpenAI-compatible 的 Base URL → API Key → 模型排序断言。

- [ ] **Step 2: 验证 RED。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter VoiceServiceSettingsLayoutTests
  ```

  预期：新布局 contract 尚未满足。

- [ ] **Step 3: 扩展 action 与 AppDelegate 保存逻辑。**

  让 `ReadlessActions` 向 editor 提供当前 `profiles`、活动 Doubao version、按 `VoiceCredentialSlot` 查询状态，以及 `selectDoubaoVersion`。`AppDelegate.saveVoiceService` 从 configuration 派生 slot：空输入时只读取同一 slot 的现有凭据；非空输入只写同一 slot；校验通过后保存对应 profile 并把它设为活动。V1 读取旧 secret 的兼容仅发生在 `KeychainCredentialStore`，AppDelegate 不复制 legacy secret。保存 V3 与保存 V1 都可以推进现有 onboarding 的配置步骤；只在当前 profile 凭据存在时启用测试按钮。

- [ ] **Step 4: 改造 `VoiceServiceEditor`。**

  在豆包 provider 下添加 `Picker("接口版本")`，tag 使用 `DoubaoAPIVersion.v3` / `.v1`，初始默认 V3。切换 picker 时：从 `profiles` 装入所选 profile 的字段、清空未保存输入、刷新其独立的 `hasSavedCredential`，并通过 action 记录活动版本；不得清空或覆盖另一版本的字段与凭据。

  V3 表单使用以下顺序和默认值：`API Key`、`资源 ID`（`seed-tts-2.0`）、`音色 ID`。V1 保持：`App ID`、`Access Token`、`Cluster`、`音色`。通过 configuration case 生成提交值。V3 未配置时，试播按钮禁用；切到 V1 后仅根据 V1 profile 决定状态，反之亦然。文案明确“V3（推荐）”与“V1（兼容）”，且不承诺自动降级。

- [ ] **Step 5: 验证 GREEN。**

  运行布局过滤测试、完整 `swift test` 与完整 Xcode Debug build。用 Xcode Preview 或实际 app 手动检查：

  1. 第一次打开豆包显示 V3、资源 ID 为 `seed-tts-2.0`；
  2. 输入未保存的 V3 值后切到 V1 再回来，V3 草稿仍存在；
  3. 保存两套 profile 后切换不会覆盖另一套，且各自显示自己的“凭据已保存”；
  4. V3 没有凭据时，不能借用 V1 进行试播。

- [ ] **Step 6: 提交。**

  ```bash
  git add readless/AppActions.swift readless/AppDelegate.swift readless/MainWindowView.swift readless/PreviewFixtures.swift readless/OnboardingView.swift Tests/ReadlessCoreTests/VoiceServiceSettingsLayoutTests.swift
  git commit -m "feat: select doubao v3 or v1 in settings"
  ```

## Task 6：端到端验证、交接与合并准备

**Files:**

- Modify: `progress.md`（本地忽略，不提交）

- [ ] **Step 1: 执行干净的自动化验证。**

  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-v3-derived build CODE_SIGNING_ALLOWED=NO
  git diff --check
  git status --short
  ```

  预期：测试与 Debug build 成功、无 whitespace error；仅 `progress.md` 可作为忽略的本地变更。

- [ ] **Step 2: 进行用户凭据的手动验收。**

  在用户自己的火山引擎帐号中配置 V3 API Key、资源 ID 和与之匹配的 2.0 音色，保存后播放内置测试句，再进行一次已授权应用中的真实选区朗读。切换到已保存 V1 进行相同试播，确认两个 profile 均可独立使用。记录通过/失败类别，绝不记录凭据、文本或原始响应。

- [ ] **Step 3: 更新本地进度并进行最终审查。**

  在 `progress.md` 记录完成内容、执行的测试命令和结果；不加入 Git。检查 `git log --oneline main..HEAD` 只含本功能 commits 和设计/计划文档。合并前特别检查 `readless/MainWindowView.swift`：主工作区存在用户的未提交改动，合并时必须保留它并人工处理重叠区域，不能通过 reset/checkout 丢弃。

- [ ] **Step 4: 交付。**

  报告分支、自动化验证结果、需要用户完成的真实 V3 验收步骤、以及 V1/V3 均无自动 fallback 的产品行为；然后按用户指定方式合并。
