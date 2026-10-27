import UIKit

protocol HWKTextMutationTarget: AnyObject {
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }

    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
    func setMarkedText(_ markedText: String, selectedRange: NSRange)
    func unmarkText()
}

struct HWKPasteInsertionPlan {
    static let maximumCharacterCount = 4_096
    static let chunkCharacterCount = 512

    let text: String
    let chunks: [String]

    init(text sourceText: String) {
        let boundedText = String(sourceText.prefix(Self.maximumCharacterCount))
        text = boundedText

        var plannedChunks = [String]()
        var index = boundedText.startIndex
        while index < boundedText.endIndex {
            let nextIndex = boundedText.index(
                index,
                offsetBy: Self.chunkCharacterCount,
                limitedBy: boundedText.endIndex
            ) ?? boundedText.endIndex
            plannedChunks.append(String(boundedText[index..<nextIndex]))
            index = nextIndex
        }
        chunks = plannedChunks
    }
}

final class HWKTextDocumentProxyMutationTarget: HWKTextMutationTarget {
    private let proxy: UITextDocumentProxy

    init(proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    var documentContextAfterInput: String? {
        proxy.documentContextAfterInput
    }

    var selectedText: String? {
        proxy.selectedText
    }

    func insertText(_ text: String) {
        proxy.insertText(text)
    }

    func deleteBackward() {
        proxy.deleteBackward()
    }

    func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
    }

    func setMarkedText(_ markedText: String, selectedRange: NSRange) {
        proxy.setMarkedText(markedText, selectedRange: selectedRange)
    }

    func unmarkText() {
        proxy.unmarkText()
    }
}

struct HWKTextMutationApplier {
    static let maximumDeleteBatchCount = 32
    static let boundedDeleteBatchCount = maximumDeleteBatchCount
    private let complexScriptPlanner = HWKComplexScriptPlanner()

    func apply(_ outcome: HWKInputOutcome, to target: HWKTextMutationTarget) {
        for mutation in outcome.textMutations {
            apply(mutation, to: target)
        }
    }

    func apply(_ mutation: HWKTextMutation, to target: HWKTextMutationTarget) {
        switch mutation {
        case .insert(let text):
            target.insertText(text)
        case .deleteBackward(let count):
            deleteBackward(count: count, from: target)
        case .deleteForward(let count):
            deleteForward(count: count, from: target)
        case .moveCursor(let offset):
            target.adjustTextPosition(byCharacterOffset: offset)
        case .setMarkedText(let text):
            target.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        case .unmarkText:
            target.unmarkText()
        }
    }

    private func deleteBackward(count: Int, from target: HWKTextMutationTarget) {
        guard count > 0 else { return }

        if let selectedText = target.selectedText, !selectedText.isEmpty {
            target.deleteBackward()
            return
        }

        let boundedCount = min(count, Self.boundedDeleteBatchCount)
        for _ in 0..<boundedCount {
            target.deleteBackward()
        }
    }

    private func deleteForward(count: Int, from target: HWKTextMutationTarget) {
        guard count > 0 else { return }

        if let selectedText = target.selectedText, !selectedText.isEmpty {
            target.deleteBackward()
            return
        }

        let boundedCount = min(count, Self.boundedDeleteBatchCount)
        for _ in 0..<boundedCount {
            guard let afterInput = target.documentContextAfterInput, !afterInput.isEmpty else { break }
            let remainingAfterDelete = complexScriptPlanner.deleteForward(in: afterInput)
            let deletedCount = max(1, afterInput.utf16.count - remainingAfterDelete.utf16.count)
            target.adjustTextPosition(byCharacterOffset: deletedCount)
            target.deleteBackward()
        }
    }
}

final class HWKKeyboardEditHistory {
    private struct Entry {
        let undo: [HWKTextMutation]
        let redo: [HWKTextMutation]
    }

    private var undoStack = [Entry]()
    private var redoStack = [Entry]()
    private let limit: Int

    init(limit: Int = 80) {
        self.limit = limit
    }

    func recordInsert(_ text: String) {
        guard !text.isEmpty else { return }
        record(
            undo: [.deleteBackward(count: min(text.count, HWKTextMutationApplier.maximumDeleteBatchCount))],
            redo: [.insert(text)]
        )
    }

    func recordDeleteBackward(_ text: String) {
        guard !text.isEmpty else { return }
        record(
            undo: [.insert(text)],
            redo: [.deleteBackward(count: text.count)]
        )
    }

    func recordDeleteForward(_ text: String) {
        guard !text.isEmpty else { return }
        let replayCount = complexScriptReplayDeleteForwardCount(for: text)
        record(
            undo: [.insert(text), .moveCursor(offset: -replayCount)],
            redo: [.deleteForward(count: replayCount)]
        )
    }

    func undoMutations() -> [HWKTextMutation]? {
        guard let entry = undoStack.popLast() else { return nil }
        redoStack.append(entry)
        return entry.undo
    }

    func redoMutations() -> [HWKTextMutation]? {
        guard let entry = redoStack.popLast() else { return nil }
        undoStack.append(entry)
        return entry.redo
    }

    func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func record(undo: [HWKTextMutation], redo: [HWKTextMutation]) {
        undoStack.append(Entry(undo: undo, redo: redo))
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
    }

    private func complexScriptReplayDeleteForwardCount(for text: String) -> Int {
        let planner = HWKComplexScriptPlanner()
        var remainingText = text
        var count = 0

        while !remainingText.isEmpty {
            let nextText = planner.deleteForward(in: remainingText)
            guard nextText.count < remainingText.count else { break }
            remainingText = nextText
            count += 1
        }

        return count
    }
}
