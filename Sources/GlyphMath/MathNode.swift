import Foundation

/// The parsed shape of an expression. Rendering is a pure function of this tree,
/// which keeps precedence and bracketing decisions in one place.
public indirect enum MathNode: Sendable, Equatable {
    /// A single already-LaTeX unit: `x`, `2`, `\pi`, `\mathbb{R}`.
    case atom(String)
    /// Implicit multiplication: `\pi r^{2}`.
    case juxt([MathNode])
    /// An infix operator or relation.
    case binary(op: String, lhs: MathNode, rhs: MathNode)
    case frac(MathNode, MathNode)
    case power(base: MathNode, exponent: MathNode)
    case subscripted(base: MathNode, index: MathNode)
    case root(index: MathNode?, radicand: MathNode)
    case group(open: String, close: String, MathNode)
    case function(name: String, sub: MathNode?, sup: MathNode?, argument: MathNode?)
    case bigOperator(name: String, sub: MathNode?, sup: MathNode?, body: MathNode?, differential: String?)
    case prefix(op: String, MathNode)
    case suffix(MathNode, op: String)
    case sequence([MathNode])

    // MARK: Rendering

    public var latex: String { render() }

    private func render() -> String {
        switch self {
        case .atom(let value):
            return value

        case .juxt(let parts):
            var out = ""
            for part in parts {
                let piece = part.render()
                if !out.isEmpty, Self.needsSeparator(between: out, and: piece), !part.attachesDirectly {
                    out += " "
                }
                out += piece
            }
            return out

        case .binary(let op, let lhs, let rhs):
            return "\(lhs.render()) \(op) \(rhs.render())"

        case .frac(let numerator, let denominator):
            return "\\frac{\(numerator.unbracketed.render())}{\(denominator.unbracketed.render())}"

        case .power(let base, let exponent):
            return base.renderAsBase() + "^" + Self.braced(exponent.unbracketed.render())

        case .subscripted(let base, let index):
            return base.renderAsBase() + "_" + Self.braced(index.unbracketed.render())

        case .root(let index, let radicand):
            if let index {
                return "\\sqrt[\(index.render())]{\(radicand.unbracketed.render())}"
            }
            return "\\sqrt{\(radicand.unbracketed.render())}"

        case .group(let open, let close, let inner):
            let body = inner.render()
            if inner.isTall || open == "|" || open == "\\|" {
                return "\\left\(open) \(body) \\right\(close)"
            }
            return "\(open)\(body)\(close)"

        case .function(let name, let sub, let sup, let argument):
            var out = name
            if let sub { out += "_" + Self.braced(sub.render()) }
            if let sup { out += "^" + Self.braced(sup.render()) }
            if let argument {
                out += argument.attachesDirectly ? argument.render() : " " + argument.render()
            }
            return out

        case .bigOperator(let name, let sub, let sup, let body, let differential):
            var out = name
            if let sub { out += "_" + Self.braced(sub.render()) }
            if let sup { out += "^" + Self.braced(sup.render()) }
            if let body { out += " " + body.render() }
            if let differential { out += " \\, d\(differential)" }
            return out

        case .prefix(let op, let operand):
            return op + operand.render()

        case .suffix(let operand, let op):
            return operand.renderAsBase() + op

        case .sequence(let items):
            return items.map { $0.render() }.joined(separator: ", ")
        }
    }

    /// Superscripts and subscripts must not stack ambiguously (`x^2^3` is invalid TeX).
    private func renderAsBase() -> String {
        if case .power = self { return "{\(render())}" }
        return render()
    }

    /// `f(x)` reads better than `f (x)`; everything else gets a separating space.
    private var attachesDirectly: Bool {
        if case .group(let open, _, _) = self { return open == "(" || open == "[" }
        return false
    }

    /// Tall content needs `\left…\right` so the delimiters grow with it.
    private var isTall: Bool {
        switch self {
        case .frac, .root, .bigOperator:
            return true
        case .juxt(let parts):
            return parts.contains { $0.isTall }
        case .binary(_, let lhs, let rhs):
            return lhs.isTall || rhs.isTall
        case .power(let base, _), .subscripted(let base, _):
            return base.isTall
        case .prefix(_, let operand), .suffix(let operand, _):
            return operand.isTall
        case .sequence(let items):
            return items.contains { $0.isTall }
        case .group, .atom, .function:
            return false
        }
    }

    /// Braces are only needed when the argument is more than one character wide.
    private static func braced(_ body: String) -> String {
        body.count == 1 ? body : "{\(body)}"
    }

    /// `\frac{}{}`, `\sqrt{}` and `^{}` already group their arguments, so a
    /// user-typed bracket pair inside one is noise: `sqrt(x^2+1)` → `\sqrt{x^2+1}`.
    private var unbracketed: MathNode {
        if case .group(let open, _, let inner) = self, open == "(" { return inner }
        return self
    }

    /// A space is only required where a LaTeX command would otherwise absorb the next
    /// letters: `\pi r` must keep its space, while `3x` and `mv^2` read better without.
    private static func needsSeparator(between left: String, and right: String) -> Bool {
        guard let firstRight = right.unicodeScalars.first else { return false }
        guard let lastLeft = left.last, lastLeft.isLetter else { return false }
        // `x \exists y` reads better than `x\exists y`, and both are valid.
        if firstRight == "\\" { return true }
        // Does `left` end in an unbraced LaTeX command such as `\pi` or `\Delta`?
        var sawLetters = false
        for character in left.reversed() {
            if character.isLetter { sawLetters = true; continue }
            return character == "\\" && sawLetters
                && (CharacterSet.letters.contains(firstRight) || firstRight == "\\")
        }
        return false
    }
}
