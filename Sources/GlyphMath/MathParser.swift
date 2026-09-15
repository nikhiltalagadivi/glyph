import Foundation

/// A recursive-descent parser over folded tokens.
///
/// Precedence, loosest to tightest:
///   relation → additive → multiplicative (incl. implicit juxtaposition)
///   → unary → postfix (`^`, `_`, `!`, "squared") → primary
///
/// Word-form operators deliberately bind looser than their symbolic twins:
/// "two to the power of n plus one" is `2^{n+1}` while `2^n + 1` is not.
struct MathParser {

    enum ParseError: Error { case unexpected, unfinished, empty }

    private let lexemes: [MathLexeme]
    private var index = 0
    /// Structural richness — used to reject prose that happens to parse.
    private(set) var score = 0
    /// Inside an integral body a bare `dx` terminates the integrand.
    private var integrandDepth = 0
    /// Inside an operator's limits, "of" belongs to the operator, not to `f of x`.
    private var boundDepth = 0

    init(_ lexemes: [MathLexeme]) {
        self.lexemes = lexemes
    }

    // MARK: Entry point

    /// Parses the whole token list; throws unless every token is consumed.
    static func parse(_ lexemes: [MathLexeme]) throws -> (node: MathNode, score: Int) {
        guard !lexemes.isEmpty else { throw ParseError.empty }
        for lexeme in lexemes {
            if case .unknown = lexeme.token { throw ParseError.unexpected }
        }
        var parser = MathParser(lexemes)
        let node = try parser.parseRelation()
        guard parser.index == lexemes.count else { throw ParseError.unfinished }
        return (node, parser.score)
    }

    // MARK: Cursor

    private var current: MathToken? { index < lexemes.count ? lexemes[index].token : nil }

    private mutating func advance() { index += 1 }

    private mutating func consume(_ keyword: MathKeyword) -> Bool {
        if case .keyword(keyword)? = current { advance(); return true }
        return false
    }

    // MARK: Grammar

    private mutating func parseRelation() throws -> MathNode {
        var node = try parseAdditive()
        while case .relation(let op)? = current {
            advance()
            let rhs = try parseAdditive()
            node = .binary(op: op, lhs: node, rhs: rhs)
            score += 2
        }
        if case .keyword(.fromTheRight)? = current {
            advance()
            node = attachSideLimit(node, sign: "+")
        } else if case .keyword(.fromTheLeft)? = current {
            advance()
            node = attachSideLimit(node, sign: "-")
        }
        return node
    }

    private mutating func parseAdditive() throws -> MathNode {
        var node = try parseMultiplicative()
        while case .additive(let op)? = current {
            advance()
            let rhs = try parseMultiplicative()
            node = .binary(op: op, lhs: node, rhs: rhs)
            score += 2
        }
        return node
    }

    private mutating func parseMultiplicative() throws -> MathNode {
        var node = try parseUnary()
        var factors: [MathNode] = []

        while let token = current {
            if case .multiplicative(let kind, let binding) = token {
                if !factors.isEmpty { node = collapse(&factors, into: node) }
                advance()
                let rhs = binding == .loose ? try parseJuxtaposedRun() : try parseUnary()
                score += 2
                switch kind {
                case .fraction: node = .frac(node, rhs)
                case .choose:   node = .atom("\\binom{\(node.latex)}{\(rhs.latex)}")
                case .cdot:     node = .binary(op: "\\cdot", lhs: node, rhs: rhs)
                case .cross:    node = .binary(op: "\\times", lhs: node, rhs: rhs)
                case .div:      node = .binary(op: "\\div", lhs: node, rhs: rhs)
                }
                continue
            }

            // "f of x" is function application, not juxtaposition.
            if case .keyword(.of) = token, boundDepth == 0, node.isSingleLetter {
                advance()
                let argument = try parsePostfix()
                node = .juxt([node, .group(open: "(", close: ")", argument)])
                score += 2
                continue
            }

            guard canStartPrimary(token) else { break }
            // Inside an integral, `dx` closes the integrand rather than multiplying it.
            if integrandDepth > 0, case .differential = token { break }
            // A lone bar is a divider (`P(A|B)`), not the start of an absolute value.
            if case .open("|") = token, !hasMatchingBar { break }

            let next = try parseUnary()
            if factors.isEmpty { factors.append(node) }
            factors.append(next)
            score += 1
        }

        if !factors.isEmpty { node = collapse(&factors, into: node) }
        return node
    }

    /// A run of juxtaposed factors with no infix operator, e.g. the `\Delta x` of
    /// "Delta y over Delta x". Used as the right operand of `over`, `times` and `/`
    /// so those bind the whole implicit product rather than a single symbol.
    private mutating func parseJuxtaposedRun() throws -> MathNode {
        var node = try parseUnary()
        var factors: [MathNode] = []
        while let token = current, canStartPrimary(token) {
            if integrandDepth > 0, case .differential = token { break }
            if case .open("|") = token, !hasMatchingBar { break }
            let next = try parseUnary()
            if factors.isEmpty { factors.append(node) }
            factors.append(next)
            score += 1
        }
        if !factors.isEmpty { node = collapse(&factors, into: node) }
        return node
    }

    private func collapse(_ factors: inout [MathNode], into node: MathNode) -> MathNode {
        guard !factors.isEmpty else { return node }
        let result = MathNode.juxt(factors)
        factors.removeAll(keepingCapacity: true)
        return result
    }

    private mutating func parseUnary() throws -> MathNode {
        if case .additive(let op)? = current, op == "-" || op == "+" || op == "\\pm" || op == "\\mp" {
            advance()
            let operand = try parseUnary()
            return .prefix(op: op, operand)
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> MathNode {
        var node = try parsePrimary()

        loop: while let token = current {
            switch token {
            case .postfix(let op):
                advance()
                node = apply(op, to: node)
                score += 2

            case .caret:
                advance()
                node = .power(base: node, exponent: try parseTightArgument())
                score += 2

            case .underscore, .keyword(.sub):
                advance()
                node = .subscripted(base: node, index: try parseTightArgument())
                score += 2

            case .powerWord:
                advance()
                // The spoken form takes the whole following product: "e to the power of i pi".
                node = .power(base: node, exponent: try parseMultiplicative())
                score += 2

            default:
                break loop
            }
        }
        return node
    }

    private mutating func apply(_ op: PostfixOp, to node: MathNode) -> MathNode {
        switch op {
        case .explicit(let value): return .power(base: node, exponent: .atom(value))
        case .square:      return .power(base: node, exponent: .atom("2"))
        case .cube:        return .power(base: node, exponent: .atom("3"))
        case .factorial:   return .suffix(node, op: "!")
        case .prime:       return .power(base: node, exponent: .atom("\\prime"))
        case .doublePrime: return .power(base: node, exponent: .atom("\\prime\\prime"))
        case .inverse:     return .power(base: node, exponent: .atom("-1"))
        case .transpose:   return .power(base: node, exponent: .atom("T"))
        case .conjugate:   return .power(base: node, exponent: .atom("*"))
        case .percent:     return .suffix(node, op: "\\%")
        case .degrees:     return .power(base: node, exponent: .atom("\\circ"))
        }
    }

    /// The operand of `^` or `_`: a brace group, a parenthesised group whose
    /// brackets are dropped, or a single tight factor.
    private mutating func parseTightArgument() throws -> MathNode {
        switch current {
        case .open(let open)?:
            advance()
            let inner = try parseRelation()
            try expectClose(matching: open)
            return inner
        case .additive(let op)? where op == "-" || op == "+":
            advance()
            return .prefix(op: op, try parseTightArgument())
        default:
            return try parsePrimary()
        }
    }

    private mutating func expectClose(matching open: String) throws {
        guard case .close? = current else { throw ParseError.unexpected }
        advance()
    }

    // MARK: Primaries

    private mutating func parsePrimary() throws -> MathNode {
        guard let token = current else { throw ParseError.unexpected }

        switch token {
        case .number(let value):
            advance()
            return .atom(value)

        case .identifier(let value):
            advance()
            if value.hasPrefix("\\") { score += 1 }
            return .atom(value)

        case .differential(let variable):
            advance()
            return .atom("d\(variable)")

        case .function(let name):
            advance()
            return try parseFunction(named: name)

        case .open(let open):
            advance()
            if open == "|" { return try parseBars(open: open) }
            let inner = try parseSeparated()
            try expectClose(matching: open)
            score += 1
            return .group(open: open, close: closing(for: open), inner)

        case .absWord:
            advance()
            _ = consume(.of)
            score += 2
            return .group(open: "|", close: "|", try parseMultiplicative())

        case .normWord:
            advance()
            _ = consume(.of)
            score += 2
            return .group(open: "\\|", close: "\\|", try parseMultiplicative())

        case .root(let degree):
            advance()
            _ = consume(.of)
            score += 3
            let radicand: MathNode
            if case .open? = current {
                // Explicit brackets delimit the radicand exactly: `sqrt(2) + 1`.
                radicand = try parsePostfix()
            } else {
                // Spoken form covers the whole sum: "root of x squared plus y squared".
                radicand = try parseAdditive()
            }
            return .root(index: degree.map { .atom($0) }, radicand: radicand)

        case .bigOperator(let name):
            advance()
            return try parseBigOperator(named: name)

        case .limitOp(let name):
            advance()
            return try parseLimit(named: name)

        case .derivative(let order, let partial):
            advance()
            return try parseDerivative(order: order, partial: partial)

        case .keyword(.quantity):
            advance()
            score += 1
            if case .open(let open)? = current {
                advance()
                let inner = try parseSeparated()
                try expectClose(matching: open)
                return .group(open: open, close: closing(for: open), inner)
            }
            return .group(open: "(", close: ")", try parseAdditive())

        default:
            throw ParseError.unexpected
        }
    }

    /// `f(x, y)` — comma-separated arguments inside one bracket pair.
    private mutating func parseSeparated() throws -> MathNode {
        var items = [try parseRelation()]
        while let token = current {
            if case .comma = token {
                advance()
                items.append(try parseRelation())
                continue
            }
            // `P(A|B)` — inside brackets a bar separates rather than delimits.
            if case .open("|") = token, index + 1 < lexemes.count, !isClosingNext, !hasMatchingBar {
                advance()
                let rhs = try parseRelation()
                items[items.count - 1] = .binary(op: "\\mid", lhs: items[items.count - 1], rhs: rhs)
                score += 1
                continue
            }
            break
        }
        return items.count == 1 ? items[0] : .sequence(items)
    }

    /// True when the token after a bar closes the enclosing bracket, meaning the bar
    /// was the right half of an absolute value rather than a divider.
    private var isClosingNext: Bool {
        guard index + 1 < lexemes.count else { return false }
        if case .close = lexemes[index + 1].token { return true }
        return false
    }

    /// Looks past the bar at `index` for its partner at the same bracket depth.
    /// `|x| + 1` has one; the bar in `P(A|B)` does not and is a `\mid` divider.
    private var hasMatchingBar: Bool {
        var depth = 0
        var cursor = index + 1
        while cursor < lexemes.count {
            switch lexemes[cursor].token {
            case .open("|") where depth == 0:
                return true
            case .open:
                depth += 1
            case .close:
                if depth == 0 { return false }
                depth -= 1
            default:
                break
            }
            cursor += 1
        }
        return false
    }

    private mutating func parseBars(open: String) throws -> MathNode {
        guard hasMatchingBar else { throw ParseError.unexpected }
        let inner = try parseRelation()
        guard case .open("|")? = current else { throw ParseError.unexpected }
        advance()
        score += 2
        return .group(open: "|", close: "|", inner)
    }

    private mutating func parseFunction(named name: String) throws -> MathNode {
        var sub: MathNode?
        var sup: MathNode?

        // `\log_2 x`, `\sin^2 x`, "sine squared of theta"
        if case .underscore? = current { advance(); sub = try parseTightArgument() }
        else if case .keyword(.sub)? = current { advance(); sub = try parseTightArgument() }
        if case .caret? = current { advance(); sup = try parseTightArgument() }
        if case .postfix(let op)? = current, op == .square || op == .cube || op == .inverse {
            advance()
            sup = .atom(op == .square ? "2" : op == .cube ? "3" : "-1")
        }
        _ = consume(.of)

        var argument: MathNode?
        if let token = current, canStartPrimary(token) {
            if integrandDepth > 0, case .differential = token {
                argument = nil
            } else {
                argument = try parsePostfix()
            }
        }
        if argument != nil || sub != nil || sup != nil { score += 2 }
        return .function(name: name, sub: sub, sup: sup, argument: argument)
    }

    private mutating func parseBigOperator(named name: String) throws -> MathNode {
        score += 4
        var sub: MathNode?
        var sup: MathNode?

        if case .underscore? = current { advance(); sub = try parseTightArgument() }
        if case .caret? = current { advance(); sup = try parseTightArgument() }

        if sub == nil, consume(.from) {
            sub = try parseBoundExpression()
            if consume(.to) { sup = try parseBoundExpression() }
        } else if sub == nil, consume(.to) {
            sup = try parseBoundExpression()
        }

        _ = consume(.of)

        let isIntegral = name.contains("int")
        if isIntegral { integrandDepth += 1 }
        defer { if isIntegral { integrandDepth -= 1 } }

        var body: MathNode?
        if let token = current, canStartPrimary(token) || isUnaryStart(token) {
            if isIntegral, case .differential = token {
                body = nil
            } else {
                body = try parseAdditive()
            }
        }

        var differential: String?
        if isIntegral, case .differential(let variable)? = current {
            advance()
            differential = variable
        }

        return .bigOperator(name: name, sub: sub, sup: sup, body: body, differential: differential)
    }

    /// The `n = 1` of "from n equals 1", or the `\infty` of "to infinity".
    private mutating func parseBoundExpression() throws -> MathNode {
        boundDepth += 1
        defer { boundDepth -= 1 }
        var node = try parseAdditive()
        while case .relation(let op)? = current, op == "=" || op == "\\to" || op == "\\in" {
            advance()
            let rhs = try parseAdditive()
            node = .binary(op: op, lhs: node, rhs: rhs)
        }
        // "x approaches 0 from the right" → x \to 0^{+}
        if case .keyword(.fromTheRight)? = current {
            advance()
            node = attachSideLimit(node, sign: "+")
        } else if case .keyword(.fromTheLeft)? = current {
            advance()
            node = attachSideLimit(node, sign: "-")
        }
        return node
    }

    private func attachSideLimit(_ node: MathNode, sign: String) -> MathNode {
        guard case .binary(let op, let lhs, let rhs) = node else {
            return .power(base: node, exponent: .atom(sign))
        }
        return .binary(op: op, lhs: lhs, rhs: .power(base: rhs, exponent: .atom(sign)))
    }

    private mutating func parseLimit(named name: String) throws -> MathNode {
        score += 4
        var sub: MathNode?

        if case .underscore? = current {
            advance()
            sub = try parseTightArgument()
        } else if consume(.asWord) {
            sub = try parseBoundExpression()
        } else if consume(.of) {
            // "the limit of f as x approaches a" — body first, condition after.
            let body = try parseAdditive()
            if consume(.asWord) { sub = try parseBoundExpression() }
            return .bigOperator(name: name, sub: sub, sup: nil, body: body, differential: nil)
        }

        _ = consume(.of)
        var body: MathNode?
        if let token = current, canStartPrimary(token) || isUnaryStart(token) {
            body = try parseAdditive()
        }
        if sub == nil, consume(.asWord) { sub = try parseBoundExpression() }
        // "lim x to 0": what looked like the body is really the limit condition.
        if sub == nil, let body, consume(.to) {
            let target = try parseBoundExpression()
            return .bigOperator(
                name: name,
                sub: .binary(op: "\\to", lhs: body, rhs: target),
                sup: nil,
                body: nil,
                differential: nil
            )
        }
        return .bigOperator(name: name, sub: sub, sup: nil, body: body, differential: nil)
    }

    private mutating func parseDerivative(order: Int, partial: Bool) throws -> MathNode {
        score += 4
        _ = consume(.of)
        let target = try parseMultiplicative()

        guard consume(.withRespectTo) else { throw ParseError.unexpected }
        let variable = try parsePostfix()

        let d = partial ? "\\partial" : "d"
        // `\partial` is a command, so it needs a space before the variable it acts on.
        let gap = partial ? " " : ""
        let orderSuffix = order > 1 ? "^{\(order)}" : ""
        let denominator = MathNode.atom("\(d)\(gap)\(variable.latex)\(orderSuffix)")

        if target.isSimpleAtom {
            return .frac(.atom("\(d)\(orderSuffix)\(gap)\(target.latex)"), denominator)
        }
        return .juxt([
            .frac(.atom("\(d)\(orderSuffix)"), denominator),
            .group(open: "(", close: ")", target)
        ])
    }

    // MARK: Token classification

    private func canStartPrimary(_ token: MathToken) -> Bool {
        switch token {
        case .number, .identifier, .function, .open, .absWord, .normWord,
             .root, .bigOperator, .limitOp, .derivative, .differential:
            return true
        case .keyword(.quantity):
            return true
        default:
            return false
        }
    }

    private func isUnaryStart(_ token: MathToken) -> Bool {
        if case .additive = token { return true }
        return false
    }

    private func closing(for open: String) -> String {
        switch open {
        case "(": return ")"
        case "[": return "]"
        case "\\{": return "\\}"
        case "|": return "|"
        case "\\|": return "\\|"
        default: return ")"
        }
    }
}

private extension MathNode {
    /// A single symbol, so `\frac{dy}{dx}` is preferred over `\frac{d}{dx}(y)`.
    var isSimpleAtom: Bool {
        if case .atom(let value) = self {
            return value.count == 1 || value.hasPrefix("\\")
        }
        return false
    }

    /// Only a bare variable takes an argument via "of": `f of x`, never `1 of x`.
    var isSingleLetter: Bool {
        if case .atom(let value) = self, value.count == 1, let c = value.first {
            return c.isLetter
        }
        return false
    }
}
