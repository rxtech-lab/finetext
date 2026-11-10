import Foundation

/// Renders the Jinja-style subset used by cloud preset templates.
/// Mirrors website/src/lib/preset-template.ts; both run website/src/lib/preset-template-cases.json.
/// See website/presets/README.md for the syntax.
enum PresetTemplate {
  struct Failure: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
  }

  static func render(_ source: String, context: [String: TemplateValue]) throws -> String {
    var parser = Parser(raws: try lex(Array(source)))
    return try Renderer(context: .object(context)).render(parser.parseAll())
  }

  // MARK: Lexing

  private enum RawKind { case text, output, tag, comment }
  private struct Raw {
    var kind: RawKind
    var body: String
    var trimLeft = false
    var trimRight = false
  }

  private static func lex(_ chars: [Character]) throws -> [Raw] {
    var raws: [Raw] = []
    var text = ""
    var i = 0
    while i < chars.count {
      let next = i + 1 < chars.count ? chars[i + 1] : nil
      guard chars[i] == "{", let marker = next, marker == "{" || marker == "%" || marker == "#" else {
        text.append(chars[i])
        i += 1
        continue
      }
      if !text.isEmpty { raws.append(Raw(kind: .text, body: text)); text = "" }
      let close: Character = marker == "{" ? "}" : marker
      var end = i + 2
      while end + 1 < chars.count, !(chars[end] == close && chars[end + 1] == "}") { end += 1 }
      guard end + 1 < chars.count else { throw Failure(message: "Unclosed \"{\(marker)\" at offset \(i)") }
      var body = String(chars[(i + 2)..<end])
      let trimLeft = body.hasPrefix("-")
      if trimLeft { body.removeFirst() }
      let trimRight = body.hasSuffix("-")
      if trimRight { body.removeLast() }
      let kind: RawKind = marker == "{" ? .output : marker == "%" ? .tag : .comment
      raws.append(Raw(kind: kind, body: body.trimmingCharacters(in: .whitespacesAndNewlines), trimLeft: trimLeft, trimRight: trimRight))
      i = end + 2
    }
    if !text.isEmpty { raws.append(Raw(kind: .text, body: text)) }

    // Whitespace control, then trim_blocks/lstrip_blocks for block tags and comments.
    for n in raws.indices where raws[n].kind != .text {
      let isBlock = raws[n].kind != .output
      if n > 0, raws[n - 1].kind == .text {
        if raws[n].trimLeft {
          raws[n - 1].body = String(raws[n - 1].body.reversed().drop(while: \.isWhitespace).reversed())
        } else if isBlock {
          raws[n - 1].body = stripIndentation(raws[n - 1].body)
        }
      }
      if n + 1 < raws.count, raws[n + 1].kind == .text {
        if raws[n].trimRight {
          raws[n + 1].body = String(raws[n + 1].body.drop(while: \.isWhitespace))
        } else if isBlock, let first = raws[n + 1].body.first, first == "\n" || first == "\r\n" {
          raws[n + 1].body.removeFirst()
        }
      }
    }
    return raws.filter { $0.kind != .comment }
  }

  /// Drops spaces and tabs before a block tag when they are all that precedes it on its line.
  private static func stripIndentation(_ text: String) -> String {
    var trimmed = text
    while let last = trimmed.last, last == " " || last == "\t" { trimmed.removeLast() }
    return trimmed.isEmpty || trimmed.last!.isNewline ? trimmed : text
  }

  // MARK: Expressions

  fileprivate indirect enum Expr {
    case literal(TemplateValue)
    case path([String])
    case not(Expr)
    case binary(String, Expr, Expr)
    case filter(String, Expr, [Expr])
  }

  fileprivate indirect enum Node {
    case text(String)
    case output(Expr)
    case conditional([(condition: Expr?, body: [Node])])
  }

  static let filters: Set<String> = ["upper", "lower", "capitalize", "title", "trim", "length", "default", "replace"]

  private enum Token: Equatable {
    case string(String), number(Double), identifier(String), op(String)
  }

  private static func tokenize(_ source: String) throws -> [Token] {
    let chars = Array(source)
    var tokens: [Token] = []
    var i = 0
    func isIdentifierStart(_ c: Character) -> Bool { c == "_" || (c.isASCII && c.isLetter) }
    func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    while i < chars.count {
      let c = chars[i]
      if c.isWhitespace { i += 1; continue }
      if c == "\"" || c == "'" {
        var value = ""
        i += 1
        while i < chars.count, chars[i] != c {
          if chars[i] == "\\", i + 1 < chars.count {
            let escaped = chars[i + 1]
            value.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
            i += 2
          } else {
            value.append(chars[i])
            i += 1
          }
        }
        guard i < chars.count else { throw Failure(message: "Unterminated string in \"\(source)\"") }
        i += 1
        tokens.append(.string(value))
      } else if isDigit(c) {
        var end = i
        while end < chars.count, isDigit(chars[end]) { end += 1 }
        if end + 1 < chars.count, chars[end] == ".", isDigit(chars[end + 1]) {
          end += 1
          while end < chars.count, isDigit(chars[end]) { end += 1 }
        }
        tokens.append(.number(Double(String(chars[i..<end]))!))
        i = end
      } else if isIdentifierStart(c) {
        var end = i
        while end < chars.count, isIdentifierStart(chars[end]) || isDigit(chars[end]) { end += 1 }
        tokens.append(.identifier(String(chars[i..<end])))
        i = end
      } else if i + 1 < chars.count, ["==", "!=", "<=", ">="].contains(String(chars[i...(i + 1)])) {
        tokens.append(.op(String(chars[i...(i + 1)])))
        i += 2
      } else if "<>|().,".contains(c) {
        tokens.append(.op(String(c)))
        i += 1
      } else {
        throw Failure(message: "Unexpected \"\(c)\" in \"\(source)\"")
      }
    }
    return tokens
  }

  private struct ExpressionParser {
    let source: String
    let tokens: [Token]
    var p = 0

    init(_ source: String) throws {
      self.source = source
      tokens = try PresetTemplate.tokenize(source)
      guard !tokens.isEmpty else { throw Failure(message: "Empty expression") }
    }

    private var peek: Token? { p < tokens.count ? tokens[p] : nil }
    private func isOp(_ value: String) -> Bool { peek == .op(value) }
    private func isWord(_ value: String) -> Bool { peek == .identifier(value) }
    private mutating func expect(_ value: String) throws {
      guard isOp(value) else { throw Failure(message: "Expected \"\(value)\" in \"\(source)\"") }
      p += 1
    }

    mutating func parse() throws -> Expr {
      let expr = try or()
      guard p == tokens.count else { throw Failure(message: "Unexpected token in \"\(source)\"") }
      return expr
    }

    private mutating func or() throws -> Expr {
      var left = try and()
      while isWord("or") { p += 1; left = .binary("or", left, try and()) }
      return left
    }

    private mutating func and() throws -> Expr {
      var left = try not()
      while isWord("and") { p += 1; left = .binary("and", left, try not()) }
      return left
    }

    private mutating func not() throws -> Expr {
      if isWord("not") { p += 1; return .not(try not()) }
      return try compare()
    }

    private mutating func compare() throws -> Expr {
      let left = try filtered()
      switch peek {
      case .op(let op) where ["==", "!=", "<", "<=", ">", ">="].contains(op):
        p += 1
        return .binary(op, left, try filtered())
      case .identifier("in"):
        p += 1
        return .binary("in", left, try filtered())
      default:
        return left
      }
    }

    private mutating func filtered() throws -> Expr {
      var expr = try primary()
      while isOp("|") {
        p += 1
        guard case .identifier(let name) = peek else { throw Failure(message: "Expected a filter name in \"\(source)\"") }
        guard PresetTemplate.filters.contains(name) else { throw Failure(message: "Unknown filter \"\(name)\"") }
        p += 1
        var arguments: [Expr] = []
        if isOp("(") {
          p += 1
          if !isOp(")") {
            arguments.append(try or())
            while isOp(",") { p += 1; arguments.append(try or()) }
          }
          try expect(")")
        }
        expr = .filter(name, expr, arguments)
      }
      return expr
    }

    private mutating func primary() throws -> Expr {
      guard let token = peek else { throw Failure(message: "Unexpected end of \"\(source)\"") }
      p += 1
      switch token {
      case .string(let value): return .literal(.string(value))
      case .number(let value): return .literal(.number(value))
      case .op("("):
        let expr = try or()
        try expect(")")
        return expr
      case .identifier(let name):
        switch name {
        case "true", "True": return .literal(.bool(true))
        case "false", "False": return .literal(.bool(false))
        case "none", "None": return .literal(.null)
        default:
          var parts = [name]
          while isOp(".") {
            p += 1
            guard case .identifier(let part) = peek else { throw Failure(message: "Expected a name after \".\" in \"\(source)\"") }
            parts.append(part)
            p += 1
          }
          return .path(parts)
        }
      case .op(let op):
        throw Failure(message: "Unexpected \"\(op)\" in \"\(source)\"")
      }
    }
  }

  // MARK: Parsing

  private struct Parser {
    let raws: [Raw]
    var p = 0

    init(raws: [Raw]) { self.raws = raws }

    mutating func parseAll() throws -> [Node] {
      let (body, end) = try block(until: [])
      guard end == nil, p == raws.count else { throw Failure(message: "Unexpected \"{% \(raws[p].body) %}\"") }
      return body
    }

    private func word(_ body: String) -> String { String(body.prefix { !$0.isWhitespace }) }

    private mutating func block(until terminators: Set<String>) throws -> ([Node], String?) {
      var body: [Node] = []
      while p < raws.count {
        let raw = raws[p]
        switch raw.kind {
        case .text:
          if !raw.body.isEmpty { body.append(.text(raw.body)) }
          p += 1
        case .output:
          var parser = try ExpressionParser(raw.body)
          body.append(.output(try parser.parse()))
          p += 1
        case .tag, .comment:
          let tag = word(raw.body)
          if terminators.contains(tag) { return (body, tag) }
          guard tag == "if" else { throw Failure(message: "Unknown or unexpected tag \"{% \(raw.body) %}\"") }
          p += 1
          var branches: [(condition: Expr?, body: [Node])] = []
          var parser = try ExpressionParser(String(raw.body.dropFirst(2)))
          var condition: Expr? = try parser.parse()
          while true {
            let (inner, end) = try block(until: ["elif", "else", "endif"])
            branches.append((condition, inner))
            guard let end else { throw Failure(message: "Missing {% endif %} for \"{% \(raw.body) %}\"") }
            let tagBody = raws[p].body
            p += 1
            if end == "endif" { break }
            guard branches.last!.condition != nil else { throw Failure(message: "{% else %} must be the last branch") }
            if end == "elif" {
              var elif = try ExpressionParser(String(tagBody.dropFirst(4)))
              condition = try elif.parse()
            } else {
              condition = nil
            }
          }
          body.append(.conditional(branches))
        }
      }
      return (body, nil)
    }
  }

  // MARK: Rendering

  private struct Renderer {
    let context: TemplateValue

    func render(_ nodes: [Node]) throws -> String {
      var out = ""
      for node in nodes {
        switch node {
        case .text(let text): out += text
        case .output(let expr): out += try evaluate(expr).text
        case .conditional(let branches):
          if let branch = try branches.first(where: { try $0.condition.map { try evaluate($0).isTruthy } ?? true }) {
            out += try render(branch.body)
          }
        }
      }
      return out
    }

    func evaluate(_ expr: Expr) throws -> TemplateValue {
      switch expr {
      case .literal(let value): return value
      case .path(let parts):
        var value: TemplateValue = context
        for part in parts {
          guard case .object(let object) = value, let child = object[part] else { return .null }
          value = child
        }
        return value
      case .not(let inner): return .bool(!(try evaluate(inner).isTruthy))
      case .binary(let op, let lhs, let rhs):
        let left = try evaluate(lhs)
        if op == "and" { return left.isTruthy ? try evaluate(rhs) : left }
        if op == "or" { return left.isTruthy ? left : try evaluate(rhs) }
        let right = try evaluate(rhs)
        switch (op, left, right) {
        case ("==", _, _): return .bool(left == right)
        case ("!=", _, _): return .bool(left != right)
        case ("in", _, .string(let haystack)): return .bool(haystack.contains(left.text))
        case ("in", _, .object(let object)): return .bool(object[left.text] != nil)
        case ("in", _, _): return .bool(false)
        case (_, .number(let a), .number(let b)): return .bool(Self.compare(op, a, b))
        case (_, .string(let a), .string(let b)): return .bool(Self.compare(op, a, b))
        default: return .bool(false)
        }
      case .filter(let name, let inner, let argumentExprs):
        let value = try evaluate(inner)
        let arguments = try argumentExprs.map(evaluate)
        let text = value.text
        switch name {
        case "upper": return .string(text.uppercased())
        case "lower": return .string(text.lowercased())
        case "capitalize": return .string(text.prefix(1).uppercased() + text.dropFirst().lowercased())
        case "title": return .string(Self.titleCase(text.lowercased()))
        case "trim": return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "length":
          if case .object(let object) = value { return .number(Double(object.count)) }
          return .number(Double(text.count))
        case "default": return value.isMissing || value == .string("") ? (arguments.first ?? .null) : value
        case "replace":
          guard arguments.count == 2, !arguments[0].text.isEmpty else { return .string(text) }
          return .string(text.replacingOccurrences(of: arguments[0].text, with: arguments[1].text))
        default: throw Failure(message: "Unknown filter \"\(name)\"")
        }
      }
    }

    static func compare<T: Comparable>(_ op: String, _ a: T, _ b: T) -> Bool {
      switch op {
      case "<": a < b
      case "<=": a <= b
      case ">": a > b
      default: a >= b
      }
    }

    static func titleCase(_ text: String) -> String {
      var out = ""
      var previous: Character?
      for c in text {
        let boundary = previous.map { !($0.isASCII && ($0.isLetter || $0.isNumber)) && $0 != "'" } ?? true
        out += boundary && c.isASCII && c.isLowercase ? c.uppercased() : String(c)
        previous = c
      }
      return out
    }
  }
}

/// A value available to preset templates.
enum TemplateValue: Equatable, Sendable, Decodable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  case object([String: TemplateValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else { self = .object(try container.decode([String: TemplateValue].self)) }
  }

  var isMissing: Bool { self == .null }

  var isTruthy: Bool {
    switch self {
    case .null: false
    case .bool(let value): value
    case .number(let value): value != 0
    case .string(let value): !value.isEmpty
    case .object(let value): !value.isEmpty
    }
  }

  var text: String {
    switch self {
    case .null, .object: ""
    case .bool(let value): value ? "True" : "False"
    case .string(let value): value
    case .number(let value):
      value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
  }
}
