# 通用表格朗读 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将明确为 Tab 加换行结构的选区或剪贴板表格自动转换为稳定的逐行通用朗读稿。

**Architecture:** 在既有的 `DefaultTextSanitizer` 内先保留并检查原始 Tab/换行结构。仅当首行可作列标题、至少一行数据、每行至少两列且列数一致时，格式化为“概况、列标题、逐行字段、结束提示”；否则复用既有段落清洗。因为 `ReadingCoordinator` 的选区和剪贴板路径都依赖同一个清洗器，格式化结果会自然进入既有指纹、分句与语音流程。

**Tech Stack:** Swift 6、Foundation、XCTest、SwiftPM、macOS Xcode project。

---

## 文件结构

- 修改：`readless/Core/TextSanitizer.swift` — 在现有纯文本清洗边界加入严格的 Tab 表格识别及通用朗读稿生成，保留原普通段落逻辑。
- 修改：`Tests/ReadlessCoreTests/TextSanitizerTests.swift` — 使用 XCTest 覆盖识别、格式化、清洗与安全降级。
- 修改：`progress.md` — 记录实际修改范围及过滤测试、全量 SwiftPM 测试、Xcode 构建和手测证据。

不修改 `Package.swift`、AppKit/SwiftUI、系统适配器、权限、UserDefaults 或快捷键生命周期。

### Task 1: 为标准表格和单元格清洗写失败测试

**Files:**
- Modify: `Tests/ReadlessCoreTests/TextSanitizerTests.swift`

- [ ] **Step 1: 添加标准表格格式化测试**

在 `TextSanitizerTests` 中添加：

```swift
func testFormatsTabDelimitedTableAsGenericRows() throws {
    XCTAssertEqual(
        try sanitizer.sanitize(
            "项目\t第一遍\t第二遍\n字数\t905\t910\n例子\t0\t0"
        ),
        """
        这是一个 3 列、2 行的表格。
        
        列标题依次是：项目、第一遍、第二遍。
        
        第 1 行。项目：字数；第一遍：905；第二遍：910。
        
        第 2 行。项目：例子；第一遍：0；第二遍：0。
        
        表格朗读结束。
        """
    )
}
```

- [ ] **Step 2: 添加空白单元格、空标题和 URL 单元格测试**

在同一测试类中添加：

```swift
func testFormatsEmptyAndURLOnlyCellsWithoutLosingColumnPosition() throws {
    XCTAssertEqual(
        try sanitizer.sanitize(
            "\t状态\t备注\n任务 A\t \thttps://example.com/a"
        ),
        """
        这是一个 3 列、1 行的表格。
        
        列标题依次是：第 1 列、状态、备注。
        
        第 1 行。第 1 列：任务 A；状态：空白；备注：空白。
        
        表格朗读结束。
        """
    )
}
```

- [ ] **Step 3: 运行新增测试，确认它们因尚未实现而失败**

Run:

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter TextSanitizerTests/testFormatsTabDelimitedTableAsGenericRows
```

Expected: FAIL；实际返回值仍是被压平的普通文本，尚未包含“这是一个 3 列、2 行的表格”。

### Task 2: 实现最小的严格表格识别和朗读稿生成

**Files:**
- Modify: `readless/Core/TextSanitizer.swift`

- [ ] **Step 1: 在 `sanitize(_:)` 标准化行尾后优先尝试表格格式化**

将行尾归一化提取为 `normalizedLineEndings(_:)`，并在普通段落标记逻辑前加入：

```swift
let lineEndingNormalized = normalizedLineEndings(text)
if let formattedTable = formatTableIfPossible(lineEndingNormalized) {
    return formattedTable
}
return try sanitizeProse(lineEndingNormalized)
```

把现有主体移入 `sanitizeProse(_:)`，它继续在空结果时抛出 `.emptySelection`。普通文本不得调用表格格式化后的分支。

- [ ] **Step 2: 添加严格解析函数**

在 `DefaultTextSanitizer` 中实现：

```swift
private func formatTableIfPossible(_ text: String) -> String? {
    let lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        .reversed()
        .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        .reversed()

    guard lines.count >= 2 else { return nil }
    let rows = lines.map { $0.components(separatedBy: "\t") }
    guard let columnCount = rows.first?.count,
          columnCount >= 2,
          rows.allSatisfy({ $0.count == columnCount }) else {
        return nil
    }
    return makeGenericTableReading(rows: rows)
}
```

The actual implementation may use a small local `trimmedLines` variable instead of the chained `drop` expression, but must preserve empty cells between adjacent Tab characters and must decline any internal blank row because its column count is not valid.

- [ ] **Step 3: 添加单元格与朗读稿辅助函数**

Implement `makeGenericTableReading(rows:)` and `cleanTableCell(_:)` with these exact output rules:

```swift
private func cleanTableCell(_ value: String) -> String {
    (try? sanitizeProse(value)) ?? "空白"
}

private func makeGenericTableReading(rows: [[String]]) -> String {
    let headings = rows[0].enumerated().map { index, value in
        let cleaned = cleanTableCell(value)
        return cleaned == "空白" ? "第 \(index + 1) 列" : cleaned
    }
    let body = rows.dropFirst().enumerated().map { rowIndex, row in
        let fields = zip(headings, row).map { heading, value in
            "\(heading)：\(cleanTableCell(value))"
        }
        return "第 \(rowIndex + 1) 行。\(fields.joined(separator: "；"))。"
    }
    return ([
        "这是一个 \(headings.count) 列、\(body.count) 行的表格。",
        "列标题依次是：\(headings.joined(separator: "、"))。"
    ] + body + ["表格朗读结束。"])
        .joined(separator: "\n\n")
}
```

`sanitizeProse(_:)` continues to remove standalone URL lines. Empty data cells and URL-only cells therefore remain audible as “空白”; an empty header becomes “第 N 列”.

- [ ] **Step 4: 运行 Task 1 的两条测试，确认通过**

Run:

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter TextSanitizerTests/testFormatsTabDelimitedTableAsGenericRows
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter TextSanitizerTests/testFormatsEmptyAndURLOnlyCellsWithoutLosingColumnPosition
```

Expected: both PASS.

- [ ] **Step 5: Commit the focused implementation**

```bash
cd readless && git add readless/Core/TextSanitizer.swift Tests/ReadlessCoreTests/TextSanitizerTests.swift
cd readless && git commit -m "feat: add generic table reading"
```

### Task 3: 为不可靠输入添加降级测试

**Files:**
- Modify: `Tests/ReadlessCoreTests/TextSanitizerTests.swift`

- [ ] **Step 1: 添加列数不一致时不识别为表格的测试**

```swift
func testDoesNotFormatRowsWithInconsistentColumnCountsAsTable() throws {
    XCTAssertEqual(
        try sanitizer.sanitize("名称\t状态\n任务 A"),
        "名称 状态 任务 A"
    )
}
```

- [ ] **Step 2: 添加单行 Tab 文本和无 Tab 多段文本的降级测试**

```swift
func testDoesNotFormatSingleTabDelimitedLineAsTable() throws {
    XCTAssertEqual(
        try sanitizer.sanitize("名称\t状态"),
        "名称 状态"
    )
}

func testPreservesExistingParagraphBehaviorForNonTableText() throws {
    XCTAssertEqual(
        try sanitizer.sanitize("第一段\n\n第二段"),
        "第一段\n\n第二段"
    )
}
```

- [ ] **Step 3: 运行这些测试，确认初始实现没有将它们误判为表格**

Run:

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter TextSanitizerTests
```

Expected: PASS；三条降级场景均不含“这是一个”。

- [ ] **Step 4: 若测试失败，只收紧 `formatTableIfPossible(_:)` 的 guard 条件**

Required behavior:

```swift
guard lines.count >= 2,
      let columnCount = rows.first?.count,
      columnCount >= 2,
      rows.allSatisfy({ $0.count == columnCount }) else {
    return nil
}
```

Do not add heuristic detection for spaces, pipes, visual widths, business keywords, HTML, or accessibility tree attributes.

- [ ] **Step 5: Re-run `TextSanitizerTests` and commit the tests**

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test --filter TextSanitizerTests
cd readless && git add Tests/ReadlessCoreTests/TextSanitizerTests.swift readless/Core/TextSanitizer.swift
cd readless && git commit -m "test: cover generic table fallback"
```

### Task 4: 完成项目级验证和进度记录

**Files:**
- Modify: `progress.md`

- [ ] **Step 1: 运行全量 Core 测试**

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/readless-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/readless-swiftpm-module-cache xcrun swift test
```

Expected: all tests PASS with 0 failures. If the command is blocked by environment/toolchain state, record the exact command and real failure in `progress.md`; do not claim it passed.

- [ ] **Step 2: 构建完整 macOS App**

```bash
cd readless && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project readless.xcodeproj -scheme readless -configuration Debug -derivedDataPath /tmp/readless-generic-table-derived build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 手测两个入口，不记录任何实际选区或剪贴板正文**

Use a temporary non-sensitive two-column sample table. First select it in a supported application and trigger the selection shortcut; then copy it and use the explicit clipboard action. In both cases, confirm the utterance begins with the column/row count, names the headings for every row, and ends with “表格朗读结束”。Then trigger ordinary paragraph reading and confirm no table introduction is spoken.

- [ ] **Step 4: 更新进度记录并检查最终差异**

Append to `progress.md`: task, L2 assessment, changed Core/test files, exact verification commands and outcomes, whether each real UI check was performed or blocked, remaining limitation that non-Tab tables fall back safely, and rollback commit hash. Then run:

```bash
cd readless && git diff --check
cd readless && git status --short
```

Expected: no `git diff --check` output; status contains only intended current-task changes before the documentation commit.

- [ ] **Step 5: Commit progress evidence**

```bash
cd readless && git add progress.md
cd readless && git commit -m "docs: record table reading verification"
```
