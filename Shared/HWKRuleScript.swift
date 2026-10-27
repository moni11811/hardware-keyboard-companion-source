import Foundation
import CoreFoundation

/// Custom text-rule engine: a small, governed mini-VM.
///
/// A custom rule (the open-ended kind the user authors in plain language, e.g.
/// "show ? on sentences that start with a wh-question") compiles to an
/// `HWKRuleScript` — a tiny program with variables, conditionals, loops, string
/// and regex operations, and `emit` actions. The runtime interprets it
/// deterministically under a `HWKRuleBudget` resource governor that bounds steps,
/// loop iterations, string length, variables, and emits.
///
/// The governor is the whole point: it lets us offer real programmability inside
/// the keyboard extension without an unbounded interpreter that would blow the
/// extension's memory/latency budget. Every run provably terminates and stays
/// within fixed limits; a rule that exceeds them aborts cleanly and emits nothing.
///
/// This file has no FoundationModels / on-device-model dependency, so it stays
/// extension-safe and fully unit-testable. Scripts are produced at config time
/// (parser / on-device model in the companion app, later phases) and run here.

// MARK: - Values

enum HWKRuleValue: Equatable, Codable {
    case null
    case string(String)
    case int(Int)
    case bool(Bool)

    var asString: String {
        switch self {
        case .null: return ""
        case .string(let s): return s
        case .int(let i): return String(i)
        case .bool(let b): return b ? "true" : "false"
        }
    }

    var asInt: Int {
        switch self {
        case .null: return 0
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
        case .int(let i): return i
        case .bool(let b): return b ? 1 : 0
        }
    }

    /// Truthiness: null / 0 / "" / false are false; everything else is true.
    var asBool: Bool {
        switch self {
        case .null: return false
        case .string(let s): return !s.isEmpty
        case .int(let i): return i != 0
        case .bool(let b): return b
        }
    }
}

// MARK: - Read-only context

/// The slice of the surrounding text a rule can read. The extension fills this
/// from the document proxy at a commit boundary; tests construct it directly.
struct HWKRuleContext: Equatable {
    var currentWord: String = ""
    var currentSentence: String = ""
    var textBeforeCursor: String = ""

    enum Key: String, Codable {
        case currentWord
        case currentSentence
        case textBeforeCursor
        case sentenceLength
    }

    func value(for key: Key) -> HWKRuleValue {
        switch key {
        case .currentWord: return .string(currentWord)
        case .currentSentence: return .string(currentSentence)
        case .textBeforeCursor: return .string(textBeforeCursor)
        case .sentenceLength: return .int(currentSentence.count)
        }
    }
}

// MARK: - Grammar

enum HWKRuleCompareOp: String, Codable { case eq, neq, lt, gt, lte, gte }
enum HWKRuleArithOp: String, Codable { case add, sub, mul, div, mod }

/// String / pattern operations. Arg counts: lower/upper/trim/length take 1;
/// contains/startsWith/endsWith/concat/matches take 2; replace takes 3
/// (string, pattern, template); capture takes 3 (string, pattern, group);
/// slice takes 3 (string, start, length).
enum HWKRuleStrOp: String, Codable {
    case lower, upper, trim, length
    case concat, contains, startsWith, endsWith
    case matches, replace, capture, slice
}

enum HWKRuleEmitKind: String, Codable { case suggest, insertAtCursor, replaceWord, appendSentence }

indirect enum HWKRuleExpr: Codable, Equatable {
    case lit(HWKRuleValue)
    case variable(String)
    case context(HWKRuleContext.Key)
    case not(HWKRuleExpr)
    case and(HWKRuleExpr, HWKRuleExpr)
    case or(HWKRuleExpr, HWKRuleExpr)
    case compare(HWKRuleCompareOp, HWKRuleExpr, HWKRuleExpr)
    case arith(HWKRuleArithOp, HWKRuleExpr, HWKRuleExpr)
    case str(HWKRuleStrOp, [HWKRuleExpr])
}

indirect enum HWKRuleStatement: Codable, Equatable {
    case assign(String, HWKRuleExpr)
    case ifElse(HWKRuleExpr, [HWKRuleStatement], [HWKRuleStatement])
    case whileLoop(HWKRuleExpr, [HWKRuleStatement])
    case emit(HWKRuleEmitKind, HWKRuleExpr)
    case stop
}

struct HWKRuleScript: Codable, Equatable {
    var statements: [HWKRuleStatement]

    init(_ statements: [HWKRuleStatement]) {
        self.statements = statements
    }
}

enum HWKRuleScriptCodeError: Error, Equatable {
    case invalidTopLevel
    case invalidStatement
    case invalidExpression
    case invalidContext
}

enum HWKRuleScriptCodeCodec {
    static func editableSourceCode(_ sourceCode: String?, script: HWKRuleScript) -> String {
        guard let sourceCode,
              !sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return render(script)
        }

        let trimmed = sourceCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            return render(script)
        }
        return sourceCode
    }

    static func render(_ script: HWKRuleScript) -> String {
        if let recipe = renderWordSuggestionRecipe(script) {
            return recipe
        }
        return renderReadableScript(script)
    }

    static func parse(_ source: String) throws -> HWKRuleScript {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recipe = try? parseWordSuggestionRecipe(trimmed) {
            return recipe
        }
        return try parseJSON(source)
    }

    private static func renderJSON(_ script: HWKRuleScript) -> String {
        let object = script.statements.map(renderStatement)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    private static func parseJSON(_ source: String) throws -> HWKRuleScript {
        guard let data = source.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw HWKRuleScriptCodeError.invalidTopLevel
        }
        return HWKRuleScript(try object.map(parseStatement))
    }

    private static func renderWordSuggestionRecipe(_ script: HWKRuleScript) -> String? {
        guard script.statements.count == 1,
              case .ifElse(let condition, let thenStatements, let elseStatements) = script.statements[0],
              elseStatements.isEmpty,
              thenStatements.count == 1,
              case .emit(.suggest, .lit(.string(let suggestion))) = thenStatements[0],
              let word = lowercaseTrimmedCurrentWordMatch(in: condition) else {
            return nil
        }

        return """
        Rule recipe
        When the current word is "\(escapedRecipeString(word))" (ignore spaces and capitalization).
        Then show "\(escapedRecipeString(suggestion))" as a suggestion.
        Otherwise do nothing.
        """
    }

    private static func parseWordSuggestionRecipe(_ source: String) throws -> HWKRuleScript {
        let lines = source
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.first?.localizedCaseInsensitiveContains("rule recipe") == true,
              let whenLine = lines.first(where: { $0.lowercased().hasPrefix("when the current word is ") }),
              let thenLine = lines.first(where: {
                let lowercased = $0.lowercased()
                return lowercased.hasPrefix("then show ") || lowercased.hasPrefix("then suggest ")
              }),
              let word = firstQuotedString(in: whenLine),
              let suggestion = firstQuotedString(in: thenLine) else {
            throw HWKRuleScriptCodeError.invalidTopLevel
        }

        return HWKRuleScript([
            .ifElse(
                .compare(
                    .eq,
                    .str(.lower, [.str(.trim, [.context(.currentWord)])]),
                    .lit(.string(word.lowercased()))
                ),
                [.emit(.suggest, .lit(.string(suggestion)))],
                []
            )
        ])
    }

    private static func renderReadableScript(_ script: HWKRuleScript) -> String {
        var lines = ["Rule recipe"]
        for statement in script.statements {
            appendReadableStatement(statement, to: &lines, indent: "")
        }
        return lines.joined(separator: "\n")
    }

    private static func appendReadableStatement(_ statement: HWKRuleStatement, to lines: inout [String], indent: String) {
        switch statement {
        case .assign(let name, let expression):
            lines.append("\(indent)Remember \"\(escapedRecipeString(name))\" as \(renderReadableExpression(expression)).")
        case .ifElse(let condition, let thenStatements, let elseStatements):
            lines.append("\(indent)If \(renderReadableExpression(condition)):")
            lines.append("\(indent)Then:")
            if thenStatements.isEmpty {
                lines.append("\(indent)- Do nothing.")
            } else {
                for statement in thenStatements {
                    appendReadableStatement(statement, to: &lines, indent: indent + "- ")
                }
            }
            if !elseStatements.isEmpty {
                lines.append("\(indent)Otherwise:")
                for statement in elseStatements {
                    appendReadableStatement(statement, to: &lines, indent: indent + "- ")
                }
            }
        case .whileLoop(let condition, let statements):
            lines.append("\(indent)Repeat while \(renderReadableExpression(condition)):")
            for statement in statements {
                appendReadableStatement(statement, to: &lines, indent: indent + "- ")
            }
        case .emit(let kind, let expression):
            lines.append("\(indent)\(readableEmitVerb(kind)) \(renderReadableExpression(expression)).")
        case .stop:
            lines.append("\(indent)Stop running this rule.")
        }
    }

    private static func renderReadableExpression(_ expression: HWKRuleExpr) -> String {
        switch expression {
        case .lit(let value):
            return renderReadableValue(value)
        case .variable(let name):
            return "the remembered value \"\(escapedRecipeString(name))\""
        case .context(let key):
            return readableContext(key)
        case .not(let expression):
            return "not \(renderReadableExpression(expression))"
        case .and(let lhs, let rhs):
            return "\(renderReadableExpression(lhs)) and \(renderReadableExpression(rhs))"
        case .or(let lhs, let rhs):
            return "\(renderReadableExpression(lhs)) or \(renderReadableExpression(rhs))"
        case .compare(let op, let lhs, let rhs):
            return "\(renderReadableExpression(lhs)) \(readableCompare(op)) \(renderReadableExpression(rhs))"
        case .arith(let op, let lhs, let rhs):
            return "\(renderReadableExpression(lhs)) \(readableArith(op)) \(renderReadableExpression(rhs))"
        case .str(let op, let args):
            return renderReadableStringOperation(op, args: args)
        }
    }

    private static func renderReadableValue(_ value: HWKRuleValue) -> String {
        switch value {
        case .null:
            return "nothing"
        case .string(let string):
            return "\"\(escapedRecipeString(string))\""
        case .int(let int):
            return String(int)
        case .bool(let bool):
            return bool ? "true" : "false"
        }
    }

    private static func renderReadableStringOperation(_ op: HWKRuleStrOp, args: [HWKRuleExpr]) -> String {
        let rendered = args.map(renderReadableExpression)
        switch op {
        case .lower:
            return "\(rendered.first ?? "text"), ignoring capitalization"
        case .upper:
            return "\(rendered.first ?? "text"), all uppercase"
        case .trim:
            return "\(rendered.first ?? "text"), without extra spaces"
        case .length:
            return "the length of \(rendered.first ?? "text")"
        case .concat:
            return rendered.joined(separator: " plus ")
        case .contains:
            return "\(rendered.first ?? "text") contains \(rendered.dropFirst().first ?? "text")"
        case .startsWith:
            return "\(rendered.first ?? "text") starts with \(rendered.dropFirst().first ?? "text")"
        case .endsWith:
            return "\(rendered.first ?? "text") ends with \(rendered.dropFirst().first ?? "text")"
        case .matches:
            return "\(rendered.first ?? "text") matches pattern \(rendered.dropFirst().first ?? "pattern")"
        case .replace:
            return "\(rendered.first ?? "text") with \(rendered.dropFirst().first ?? "pattern") changed to \(rendered.dropFirst(2).first ?? "replacement")"
        case .capture:
            return "the captured part of \(rendered.first ?? "text")"
        case .slice:
            return "part of \(rendered.first ?? "text")"
        }
    }

    private static func readableEmitVerb(_ kind: HWKRuleEmitKind) -> String {
        switch kind {
        case .suggest:
            return "Show suggestion"
        case .insertAtCursor:
            return "Insert"
        case .replaceWord:
            return "Replace the current word with"
        case .appendSentence:
            return "Append to the sentence"
        }
    }

    private static func readableContext(_ key: HWKRuleContext.Key) -> String {
        switch key {
        case .currentWord:
            return "the current word"
        case .currentSentence:
            return "the current sentence"
        case .textBeforeCursor:
            return "the text before the cursor"
        case .sentenceLength:
            return "the sentence length"
        }
    }

    private static func readableCompare(_ op: HWKRuleCompareOp) -> String {
        switch op {
        case .eq: return "is"
        case .neq: return "is not"
        case .lt: return "is less than"
        case .gt: return "is greater than"
        case .lte: return "is at most"
        case .gte: return "is at least"
        }
    }

    private static func readableArith(_ op: HWKRuleArithOp) -> String {
        switch op {
        case .add: return "plus"
        case .sub: return "minus"
        case .mul: return "times"
        case .div: return "divided by"
        case .mod: return "modulo"
        }
    }

    private static func lowercaseTrimmedCurrentWordMatch(in expression: HWKRuleExpr) -> String? {
        guard case .compare(.eq, let lhs, let rhs) = expression else { return nil }
        if isLowercaseTrimmedCurrentWord(lhs), case .lit(.string(let word)) = rhs {
            return word
        }
        if isLowercaseTrimmedCurrentWord(rhs), case .lit(.string(let word)) = lhs {
            return word
        }
        return nil
    }

    private static func isLowercaseTrimmedCurrentWord(_ expression: HWKRuleExpr) -> Bool {
        guard case .str(.lower, let lowerArgs) = expression,
              lowerArgs.count == 1,
              case .str(.trim, let trimArgs) = lowerArgs[0],
              trimArgs.count == 1,
              case .context(.currentWord) = trimArgs[0] else {
            return false
        }
        return true
    }

    private static func escapedRecipeString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func firstQuotedString(in line: String) -> String? {
        var output = ""
        var isEscaped = false
        var isInsideQuote = false
        for character in line {
            if isEscaped {
                output.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                if isInsideQuote {
                    return output
                }
                isInsideQuote = true
                continue
            }
            if isInsideQuote {
                output.append(character)
            }
        }
        return nil
    }

    private static func renderStatement(_ statement: HWKRuleStatement) -> Any {
        switch statement {
        case .assign(let name, let expression):
            return ["set": name, "to": renderExpression(expression)]
        case .ifElse(let condition, let thenStatements, let elseStatements):
            return [
                "if": renderExpression(condition),
                "then": thenStatements.map(renderStatement),
                "else": elseStatements.map(renderStatement)
            ]
        case .whileLoop(let condition, let statements):
            return ["while": renderExpression(condition), "do": statements.map(renderStatement)]
        case .emit(let kind, let expression):
            return [kind.rawValue: renderExpression(expression)]
        case .stop:
            return ["stop": true]
        }
    }

    private static func renderExpression(_ expression: HWKRuleExpr) -> Any {
        switch expression {
        case .lit(let value):
            return renderValue(value)
        case .variable(let name):
            return ["var": name]
        case .context(let key):
            return ["context": key.rawValue]
        case .not(let expression):
            return ["not": renderExpression(expression)]
        case .and(let lhs, let rhs):
            return ["and": [renderExpression(lhs), renderExpression(rhs)]]
        case .or(let lhs, let rhs):
            return ["or": [renderExpression(lhs), renderExpression(rhs)]]
        case .compare(let op, let lhs, let rhs):
            return [op.rawValue: [renderExpression(lhs), renderExpression(rhs)]]
        case .arith(let op, let lhs, let rhs):
            return [op.rawValue: [renderExpression(lhs), renderExpression(rhs)]]
        case .str(let op, let args):
            return [op.rawValue: renderedArgs(for: op, args: args)]
        }
    }

    private static func renderValue(_ value: HWKRuleValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .string(let string): return string
        case .int(let int): return int
        case .bool(let bool): return bool
        }
    }

    private static func renderedArgs(for op: HWKRuleStrOp, args: [HWKRuleExpr]) -> Any {
        if [.lower, .upper, .trim, .length].contains(op), args.count == 1 {
            return renderExpression(args[0])
        }
        return args.map(renderExpression)
    }

    private static func parseStatement(_ object: Any) throws -> HWKRuleStatement {
        guard let dict = object as? [String: Any] else {
            throw HWKRuleScriptCodeError.invalidStatement
        }
        if let name = dict["set"] as? String,
           let expression = dict["to"] {
            return .assign(name, try parseExpression(expression))
        }
        if let condition = dict["if"],
           let thenObjects = dict["then"] as? [Any] {
            return .ifElse(
                try parseExpression(condition),
                try thenObjects.map(parseStatement),
                try (dict["else"] as? [Any] ?? []).map(parseStatement)
            )
        }
        if let condition = dict["while"],
           let body = dict["do"] as? [Any] {
            return .whileLoop(try parseExpression(condition), try body.map(parseStatement))
        }
        for kind in [HWKRuleEmitKind.suggest, .insertAtCursor, .replaceWord, .appendSentence] {
            if let expression = dict[kind.rawValue] {
                return .emit(kind, try parseExpression(expression))
            }
        }
        if dict["stop"] as? Bool == true {
            return .stop
        }
        throw HWKRuleScriptCodeError.invalidStatement
    }

    private static func parseExpression(_ object: Any) throws -> HWKRuleExpr {
        if object is NSNull {
            return .lit(.null)
        }
        if let string = object as? String {
            return .lit(.string(string))
        }
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .lit(.bool(number.boolValue))
            }
            return .lit(.int(number.intValue))
        }
        guard let dict = object as? [String: Any], dict.count == 1,
              let key = dict.keys.first,
              let value = dict[key] else {
            throw HWKRuleScriptCodeError.invalidExpression
        }

        if key == "var", let name = value as? String {
            return .variable(name)
        }
        if key == "context", let raw = value as? String,
           let contextKey = HWKRuleContext.Key(rawValue: raw) {
            return .context(contextKey)
        }
        if key == "not" {
            return .not(try parseExpression(value))
        }
        if key == "and" || key == "or" {
            let pair = try parseExpressionPair(value)
            return key == "and" ? .and(pair.0, pair.1) : .or(pair.0, pair.1)
        }
        if let op = HWKRuleCompareOp(rawValue: key) {
            let pair = try parseExpressionPair(value)
            return .compare(op, pair.0, pair.1)
        }
        if let op = HWKRuleArithOp(rawValue: key) {
            let pair = try parseExpressionPair(value)
            return .arith(op, pair.0, pair.1)
        }
        if let op = HWKRuleStrOp(rawValue: key) {
            return .str(op, try parseStringArgs(op: op, object: value))
        }
        throw HWKRuleScriptCodeError.invalidExpression
    }

    private static func parseExpressionPair(_ object: Any) throws -> (HWKRuleExpr, HWKRuleExpr) {
        guard let array = object as? [Any], array.count == 2 else {
            throw HWKRuleScriptCodeError.invalidExpression
        }
        return (try parseExpression(array[0]), try parseExpression(array[1]))
    }

    private static func parseStringArgs(op: HWKRuleStrOp, object: Any) throws -> [HWKRuleExpr] {
        if [.lower, .upper, .trim, .length].contains(op) {
            return [try parseExpression(object)]
        }
        guard let array = object as? [Any] else {
            throw HWKRuleScriptCodeError.invalidExpression
        }
        return try array.map(parseExpression)
    }
}

// MARK: - Governor

struct HWKRuleBudget {
    var maxSteps = 2_000
    var maxLoopIterations = 500
    var maxStringLength = 2_000
    var maxVariables = 64
    var maxEmits = 32
    var maxPatternLength = 400

    static let `default` = HWKRuleBudget()
}

// MARK: - Output

enum HWKRuleEmit: Equatable {
    case suggest(String)
    case insertAtCursor(String)
    case replaceWord(String)
    case appendSentence(String)

    /// The text payload, regardless of emit kind.
    var text: String {
        switch self {
        case .suggest(let s), .insertAtCursor(let s), .replaceWord(let s), .appendSentence(let s):
            return s
        }
    }
}

struct HWKRuleRunResult: Equatable {
    var emits: [HWKRuleEmit] = []
    var aborted = false
    var abortReason: String?
    var variables: [String: HWKRuleValue] = [:]
}

// MARK: - Interpreter

/// Deterministic, governed interpreter. Construct via `run(...)`. On any budget
/// breach it aborts and returns no emits (a half-applied program must never reach
/// the user's text); an explicit `.stop` keeps the emits produced so far.
final class HWKRuleScriptInterpreter {
    private let context: HWKRuleContext
    private let budget: HWKRuleBudget
    private var vars: [String: HWKRuleValue]
    private var steps = 0
    private var emits: [HWKRuleEmit] = []

    private struct Abort: Error { let reason: String }
    private struct StopSignal: Error {}

    private init(context: HWKRuleContext, budget: HWKRuleBudget, initialVariables: [String: HWKRuleValue]) {
        self.context = context
        self.budget = budget
        self.vars = initialVariables
    }

    /// Run a script. `initialVariables` carries persistent (e.g. sentence- or
    /// document-scoped) state forward across commits; the result's `variables`
    /// is the updated state to feed into the next run.
    static func run(
        _ script: HWKRuleScript,
        context: HWKRuleContext,
        budget: HWKRuleBudget = .default,
        initialVariables: [String: HWKRuleValue] = [:]
    ) -> HWKRuleRunResult {
        let interpreter = HWKRuleScriptInterpreter(
            context: context,
            budget: budget,
            initialVariables: initialVariables
        )
        return interpreter.execute(script)
    }

    private func execute(_ script: HWKRuleScript) -> HWKRuleRunResult {
        do {
            try run(script.statements)
            return HWKRuleRunResult(emits: emits, aborted: false, abortReason: nil, variables: vars)
        } catch let abort as Abort {
            return HWKRuleRunResult(emits: [], aborted: true, abortReason: abort.reason, variables: vars)
        } catch is StopSignal {
            return HWKRuleRunResult(emits: emits, aborted: false, abortReason: nil, variables: vars)
        } catch {
            return HWKRuleRunResult(emits: [], aborted: true, abortReason: "\(error)", variables: vars)
        }
    }

    private func tick() throws {
        steps += 1
        if steps > budget.maxSteps { throw Abort(reason: "step budget exceeded") }
    }

    private func run(_ statements: [HWKRuleStatement]) throws {
        for statement in statements { try exec(statement) }
    }

    private func exec(_ statement: HWKRuleStatement) throws {
        try tick()
        switch statement {
        case .assign(let name, let expr):
            let value = try capped(eval(expr))
            if vars[name] == nil && vars.count >= budget.maxVariables {
                throw Abort(reason: "variable limit")
            }
            vars[name] = value

        case .ifElse(let cond, let thenBranch, let elseBranch):
            if try eval(cond).asBool {
                try run(thenBranch)
            } else {
                try run(elseBranch)
            }

        case .whileLoop(let cond, let body):
            var iterations = 0
            while try eval(cond).asBool {
                iterations += 1
                if iterations > budget.maxLoopIterations {
                    throw Abort(reason: "loop iteration limit")
                }
                try run(body)
            }

        case .emit(let kind, let expr):
            let text = String(try capped(eval(expr)).asString.prefix(budget.maxStringLength))
            switch kind {
            case .suggest: emits.append(.suggest(text))
            case .insertAtCursor: emits.append(.insertAtCursor(text))
            case .replaceWord: emits.append(.replaceWord(text))
            case .appendSentence: emits.append(.appendSentence(text))
            }
            if emits.count > budget.maxEmits { throw Abort(reason: "emit limit") }

        case .stop:
            throw StopSignal()
        }
    }

    private func capped(_ value: HWKRuleValue) throws -> HWKRuleValue {
        if case .string(let s) = value, s.count > budget.maxStringLength {
            throw Abort(reason: "string length limit")
        }
        return value
    }

    private func eval(_ expr: HWKRuleExpr) throws -> HWKRuleValue {
        try tick()
        switch expr {
        case .lit(let value):
            return value
        case .variable(let name):
            return vars[name] ?? .null
        case .context(let key):
            return context.value(for: key)
        case .not(let inner):
            return .bool(!(try eval(inner).asBool))
        case .and(let lhs, let rhs):
            return .bool((try eval(lhs).asBool) ? (try eval(rhs).asBool) : false)
        case .or(let lhs, let rhs):
            return .bool((try eval(lhs).asBool) ? true : (try eval(rhs).asBool))
        case .compare(let op, let lhs, let rhs):
            return .bool(compare(op, try eval(lhs), try eval(rhs)))
        case .arith(let op, let lhs, let rhs):
            return try arith(op, try eval(lhs), try eval(rhs))
        case .str(let op, let args):
            return try strOp(op, args)
        }
    }

    private func valueEqual(_ a: HWKRuleValue, _ b: HWKRuleValue) -> Bool {
        switch (a, b) {
        case (.int, .int): return a.asInt == b.asInt
        case (.bool, .bool): return a.asBool == b.asBool
        default: return a.asString == b.asString
        }
    }

    private func compare(_ op: HWKRuleCompareOp, _ a: HWKRuleValue, _ b: HWKRuleValue) -> Bool {
        switch op {
        case .eq: return valueEqual(a, b)
        case .neq: return !valueEqual(a, b)
        case .lt: return a.asInt < b.asInt
        case .gt: return a.asInt > b.asInt
        case .lte: return a.asInt <= b.asInt
        case .gte: return a.asInt >= b.asInt
        }
    }

    private func arith(_ op: HWKRuleArithOp, _ a: HWKRuleValue, _ b: HWKRuleValue) throws -> HWKRuleValue {
        if op == .add {
            if case .string = a { return try capped(.string(a.asString + b.asString)) }
            if case .string = b { return try capped(.string(a.asString + b.asString)) }
        }
        let x = a.asInt
        let y = b.asInt
        switch op {
        case .add: return .int(x &+ y)
        case .sub: return .int(x &- y)
        case .mul:
            let (result, overflow) = x.multipliedReportingOverflow(by: y)
            if overflow { throw Abort(reason: "integer overflow") }
            return .int(result)
        case .div:
            guard y != 0 else { return .int(0) }
            guard !(x == .min && y == -1) else { throw Abort(reason: "integer overflow") }
            return .int(x / y)
        case .mod:
            guard y != 0 else { return .int(0) }
            guard !(x == .min && y == -1) else { throw Abort(reason: "integer overflow") }
            return .int(x % y)
        }
    }

    private func strOp(_ op: HWKRuleStrOp, _ args: [HWKRuleExpr]) throws -> HWKRuleValue {
        func arg(_ index: Int) throws -> HWKRuleValue {
            index < args.count ? try eval(args[index]) : .null
        }
        switch op {
        case .lower:
            return .string(try arg(0).asString.lowercased())
        case .upper:
            return .string(try arg(0).asString.uppercased())
        case .trim:
            return .string(try arg(0).asString.trimmingCharacters(in: .whitespacesAndNewlines))
        case .length:
            return .int(try arg(0).asString.count)
        case .concat:
            return try capped(.string((try arg(0).asString) + (try arg(1).asString)))
        case .contains:
            let needle = try arg(1).asString
            return .bool(needle.isEmpty ? true : (try arg(0).asString).contains(needle))
        case .startsWith:
            return .bool((try arg(0).asString).hasPrefix(try arg(1).asString))
        case .endsWith:
            return .bool((try arg(0).asString).hasSuffix(try arg(1).asString))
        case .matches:
            return .bool(regexMatches(try arg(0).asString, pattern: try arg(1).asString))
        case .replace:
            return try capped(.string(regexReplace(try arg(0).asString, pattern: try arg(1).asString, template: try arg(2).asString)))
        case .capture:
            return .string(regexCapture(try arg(0).asString, pattern: try arg(1).asString, group: try arg(2).asInt))
        case .slice:
            return .string(slice(try arg(0).asString, start: try arg(1).asInt, length: try arg(2).asInt))
        }
    }

    // MARK: Bounded regex helpers

    private func compiledRegex(_ pattern: String) -> NSRegularExpression? {
        guard pattern.count <= budget.maxPatternLength else { return nil }
        return try? NSRegularExpression(pattern: pattern)
    }

    private func boundedInput(_ string: String) -> String {
        String(string.prefix(budget.maxStringLength))
    }

    private func regexMatches(_ string: String, pattern: String) -> Bool {
        let input = boundedInput(string)
        guard let regex = compiledRegex(pattern) else { return false }
        let range = NSRange(input.startIndex..., in: input)
        return regex.firstMatch(in: input, options: [], range: range) != nil
    }

    private func regexReplace(_ string: String, pattern: String, template: String) -> String {
        let input = boundedInput(string)
        guard let regex = compiledRegex(pattern) else { return string }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }

    private func regexCapture(_ string: String, pattern: String, group: Int) -> String {
        let input = boundedInput(string)
        guard group >= 0, let regex = compiledRegex(pattern) else { return "" }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range),
              group < match.numberOfRanges,
              let captured = Range(match.range(at: group), in: input) else {
            return ""
        }
        return String(input[captured])
    }

    private func slice(_ string: String, start: Int, length: Int) -> String {
        guard length > 0 else { return "" }
        let characters = Array(string)
        guard !characters.isEmpty else { return "" }
        let lower = min(max(start, 0), characters.count)
        let upper = min(lower + length, characters.count)
        guard lower < upper else { return "" }
        return String(characters[lower..<upper])
    }
}

// MARK: - Stored rule + multi-rule engine

/// A persistable custom rule: a script plus the metadata the UI and runtime need.
/// Stored in the App Group and synced like other preferences (Codable).
struct HWKCustomTextRule: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var sourceText: String
    var sourceCode: String
    var enabled: Bool
    var trigger: Trigger
    var presentation: Presentation
    var script: HWKRuleScript

    /// When the rule is evaluated. Triggers bound how often scripts run.
    enum Trigger: String, Codable, Equatable {
        case onWordCommit
        case onSentenceEnd
        case onManualInvoke
    }

    /// How emits reach the user. `suggest` never mutates text on its own.
    enum Presentation: String, Codable, Equatable {
        case suggest
        case autoApply
    }

    init(
        id: UUID = UUID(),
        name: String,
        sourceText: String = "",
        sourceCode: String? = nil,
        enabled: Bool = true,
        trigger: Trigger = .onWordCommit,
        presentation: Presentation = .suggest,
        script: HWKRuleScript
    ) {
        self.id = id
        self.name = name
        self.sourceText = sourceText
        self.sourceCode = HWKRuleScriptCodeCodec.editableSourceCode(sourceCode, script: script)
        self.enabled = enabled
        self.trigger = trigger
        self.presentation = presentation
        self.script = script
    }

    func replacingSourceCode(_ sourceCode: String, script: HWKRuleScript) -> HWKCustomTextRule {
        HWKCustomTextRule(
            id: id,
            name: name,
            sourceText: sourceText,
            sourceCode: sourceCode,
            enabled: enabled,
            trigger: trigger,
            presentation: presentation,
            script: script
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sourceText
        case sourceCode
        case enabled
        case trigger
        case presentation
        case script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText) ?? ""
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        trigger = try container.decodeIfPresent(Trigger.self, forKey: .trigger) ?? .onWordCommit
        presentation = try container.decodeIfPresent(Presentation.self, forKey: .presentation) ?? .suggest
        script = try container.decode(HWKRuleScript.self, forKey: .script)
        sourceCode = HWKRuleScriptCodeCodec.editableSourceCode(
            try container.decodeIfPresent(String.self, forKey: .sourceCode),
            script: script
        )
    }
}

/// The combined result of evaluating all custom rules at one commit boundary.
struct HWKCustomTextRuleOutcome: Equatable {
    /// Text offered in the suggestion bar (never applied automatically).
    var suggestions: [String] = []
    /// Mutations from auto-apply rules, in rule order, for the caller to apply.
    var mutations: [HWKRuleEmit] = []

    var isEmpty: Bool { suggestions.isEmpty && mutations.isEmpty }
}

/// Evaluates the enabled custom rules for a given trigger, carrying per-rule
/// persistent state forward. Pure and bounded — safe to call on the commit path.
enum HWKCustomTextRuleEngine {
    /// - Parameter state: per-rule persistent variables, updated in place so the
    ///   caller can carry sentence/document-scoped state across commits.
    static func evaluate(
        rules: [HWKCustomTextRule],
        context: HWKRuleContext,
        trigger: HWKCustomTextRule.Trigger,
        isSecureTextEntry: Bool = false,
        budget: HWKRuleBudget = .default,
        state: inout [UUID: [String: HWKRuleValue]]
    ) -> HWKCustomTextRuleOutcome {
        var outcome = HWKCustomTextRuleOutcome()
        // Never run user logic over secure (password) fields.
        guard !isSecureTextEntry else { return outcome }

        for rule in rules where rule.enabled && rule.trigger == trigger {
            let prior = state[rule.id] ?? [:]
            let result = HWKRuleScriptInterpreter.run(
                rule.script,
                context: context,
                budget: budget,
                initialVariables: prior
            )
            state[rule.id] = result.variables
            guard !result.aborted else { continue }

            for emit in result.emits {
                switch rule.presentation {
                case .suggest:
                    // In suggest mode nothing mutates text; surface every emit as a suggestion.
                    outcome.suggestions.append(emit.text)
                case .autoApply:
                    if case .suggest = emit {
                        outcome.suggestions.append(emit.text)
                    } else {
                        outcome.mutations.append(emit)
                    }
                }
            }
        }
        return outcome
    }
}
