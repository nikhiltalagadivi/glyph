import Foundation

// MARK: - Canonical tokens

/// Multiplication flavours, kept apart because they render differently.
public enum MulOp: Sendable, Equatable {
    case cdot     // "times", "*", "·"
    case cross    // "cross", "×"
    case div      // "÷"
    case fraction // "over", "divided by", "/"
    case choose   // "n choose k"
}

/// How tightly a multiplicative operator grabs its right operand.
///
/// Spoken operators take the whole implicit product — "Delta y over Delta x" is one
/// fraction. Typed operators take a single factor, so `4/3 pi r^3` keeps `\pi r^3`
/// outside the fraction, exactly as it would in LaTeX.
public enum MulBinding: Sendable, Equatable { case tight, loose }

public enum MathKeyword: Sendable, Equatable {
    case from, to, of, asWord, withRespectTo, sub, quantity, filler
    case fromTheRight, fromTheLeft
}

/// A token after phrase folding: everything the parser understands.
public indirect enum MathToken: Sendable, Equatable {
    case number(String)
    /// A renderable atom — a variable (`x`), a symbol (`\pi`), a set (`\mathbb{R}`).
    case identifier(String)
    /// A named operator such as `\sin`, rendered upright and taking an argument.
    case function(String)
    /// `=`, `\leq`, `\to`, `\in`, …
    case relation(String)
    /// `+`, `-`, `\pm`, `\mp`
    case additive(String)
    case multiplicative(MulOp, MulBinding)
    case caret
    case underscore
    /// The spoken "to the power of", which binds looser than `^`.
    case powerWord
    /// "square root of" / "cube root of" / "nth root of"
    case root(index: String?)
    /// Applies to whatever precedes it: `squared`, `!`, `'`, `inverse`, …
    case postfix(PostfixOp)
    case open(String)
    case close(String)
    /// A `|…|` or `‖…‖` delimiter pair introduced by words rather than symbols.
    case absWord
    case normWord
    case bigOperator(String)   // \int \sum \prod \oint \bigcup …
    case limitOp(String)       // \lim \limsup \liminf
    case derivative(order: Int, partial: Bool)
    /// The `x` of a `dx`.
    case differential(String)
    case keyword(MathKeyword)
    case comma
    /// Anything the lexicon does not know. Its presence rejects the whole phrase.
    case unknown(String)
}

public enum PostfixOp: Sendable, Equatable {
    /// A literal superscript, from typed characters like `²` or `⁻`.
    case explicit(String)
    case square          // "squared"
    case cube            // "cubed"
    case factorial       // "!" / "factorial"
    case prime           // "'" / "prime"
    case doublePrime
    case inverse         // "inverse"
    case transpose       // "transpose"
    case conjugate       // "conjugate"
    case percent
    case degrees
}

/// A canonical token plus the source range it was folded from.
public struct MathLexeme: Sendable, Equatable {
    public let token: MathToken
    public let range: NSRange
}

// MARK: - Lexicon

public enum MathLexicon {

    // MARK: Greek

    /// Greek letters that have a distinct capital glyph in TeX.
    static let capitalGreek: Set<String> = [
        "gamma", "delta", "theta", "lambda", "xi", "pi", "sigma", "upsilon", "phi", "psi", "omega"
    ]

    // MARK: Functions

    /// Named operators SwiftMath renders natively as `\name`.
    static let nativeFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth",
        "log", "lg", "ln", "exp", "arg", "ker", "dim", "hom", "deg",
        "det", "gcd", "min", "max", "sup", "inf", "Pr"
    ]

    /// Named operators SwiftMath has no command for; rendered upright via `\mathrm`.
    static let romanFunctions: Set<String> = [
        "sech", "csch", "arcsinh", "arccosh", "arctanh", "arccot", "arcsec", "arccsc",
        "sgn", "sign", "tr", "rank", "lcm", "erf", "cis", "adj", "curl", "grad", "proj",
        "var", "cov", "corr", "diag", "span", "supp", "res", "ord", "lub", "glb"
    ]

    /// Spoken spellings that resolve to a function name.
    static let functionAliases: [String: String] = [
        "sine": "sin", "cosine": "cos", "tangent": "tan",
        "cotangent": "cot", "secant": "sec", "cosecant": "csc",
        "logarithm": "log", "natural log": "ln", "natural logarithm": "ln",
        "determinant": "det", "trace": "tr", "signum": "sgn",
        "maximum": "max", "minimum": "min",
        "supremum": "sup", "infimum": "inf",
        "dimension": "dim", "kernel": "ker", "rank": "rank",
        "expected value": "E", "variance": "var", "covariance": "cov",
        "probability": "P", "gradient": "grad", "divergence": "div"
    ]

    // MARK: Single-word symbols

    static let constants: [String: String] = [
        "infinity": "\\infty", "infty": "\\infty", "inf": "\\infty",
        "empty set": "\\emptyset", "emptyset": "\\emptyset", "varnothing": "\\emptyset",
        "nabla": "\\nabla", "del": "\\nabla", "partial": "\\partial",
        "hbar": "\\hbar", "ell": "\\ell", "aleph": "\\aleph",
        "reals": "\\mathbb{R}", "real numbers": "\\mathbb{R}", "the reals": "\\mathbb{R}",
        "integers": "\\mathbb{Z}", "the integers": "\\mathbb{Z}",
        "naturals": "\\mathbb{N}", "natural numbers": "\\mathbb{N}",
        "rationals": "\\mathbb{Q}", "rational numbers": "\\mathbb{Q}",
        "complex numbers": "\\mathbb{C}", "the complex numbers": "\\mathbb{C}",
        "dots": "\\ldots", "ellipsis": "\\ldots", "and so on": "\\ldots"
    ]

    // MARK: Multi-word phrase table

    /// Word sequences folded into a single token, matched longest-first.
    /// Everything here is lowercase and space-separated.
    static let phrases: [String: MathToken] = {
        var p: [String: MathToken] = [:]

        // Relations
        let relations: [String: String] = [
            "equals": "=", "equal to": "=", "is equal to": "=", "equal": "=",
            "is": "=", "are": "=", "gives": "=", "yields": "=",
            "not equal to": "\\neq", "is not equal to": "\\neq", "does not equal": "\\neq",
            "less than": "<", "is less than": "<",
            "greater than": ">", "is greater than": ">",
            "less than or equal to": "\\leq", "at most": "\\leq", "no more than": "\\leq",
            "greater than or equal to": "\\geq", "at least": "\\geq", "no less than": "\\geq",
            "much less than": "\\ll", "much greater than": "\\gg",
            "approximately": "\\approx", "approximately equal to": "\\approx",
            "is approximately": "\\approx", "is approximately equal to": "\\approx",
            "approx": "\\approx",
            "proportional to": "\\propto", "is proportional to": "\\propto",
            "congruent to": "\\equiv", "is congruent to": "\\equiv",
            "identically equal to": "\\equiv", "equivalent to": "\\equiv",
            "similar to": "\\sim", "asymptotic to": "\\asymp",
            "approaches": "\\to", "approaching": "\\to", "tends to": "\\to",
            "goes to": "\\to", "maps to": "\\mapsto", "converges to": "\\to",
            "implies": "\\Rightarrow", "if and only if": "\\iff", "iff": "\\iff",
            "element of": "\\in", "an element of": "\\in",
            "is an element of": "\\in", "belongs to": "\\in", "is in": "\\in",
            "not in": "\\notin", "is not in": "\\notin", "not an element of": "\\notin",
            "subset of": "\\subseteq", "is a subset of": "\\subseteq",
            "a subset of": "\\subseteq", "subseteq": "\\subseteq",
            "proper subset of": "\\subset",
            "superset of": "\\supseteq", "is a superset of": "\\supseteq",
            "divides": "\\mid", "parallel to": "\\parallel", "is parallel to": "\\parallel",
            "perpendicular to": "\\perp", "is perpendicular to": "\\perp",
            "orthogonal to": "\\perp", "modulo": "\\;\\mathrm{mod}\\;", "mod": "\\;\\mathrm{mod}\\;"
        ]
        for (k, v) in relations { p[k] = .relation(v) }

        // Additive
        p["plus"] = .additive("+")
        p["minus"] = .additive("-")
        p["plus or minus"] = .additive("\\pm")
        p["minus or plus"] = .additive("\\mp")

        // Multiplicative
        for k in ["times", "multiplied by", "dot"] { p[k] = .multiplicative(.cdot, .loose) }
        for k in ["cross", "cross product with"] { p[k] = .multiplicative(.cross, .loose) }
        for k in ["over", "divided by"] { p[k] = .multiplicative(.fraction, .loose) }
        for k in ["choose"] { p[k] = .multiplicative(.choose, .loose) }

        // Set operations behave like binary operators.
        p["union"] = .relation("\\cup")
        p["intersect"] = .relation("\\cap")
        p["intersection"] = .relation("\\cap")
        p["intersected with"] = .relation("\\cap")
        p["setminus"] = .relation("\\setminus")
        p["set minus"] = .relation("\\setminus")

        // Powers
        for k in ["to the power of", "raised to the power of", "raised to the power",
                  "to the power", "to the exponent"] {
            p[k] = .powerWord
        }
        p["squared"] = .postfix(.square)
        p["cubed"] = .postfix(.cube)
        p["factorial"] = .postfix(.factorial)
        p["prime"] = .postfix(.prime)
        p["double prime"] = .postfix(.doublePrime)
        p["inverse"] = .postfix(.inverse)
        p["inverted"] = .postfix(.inverse)
        p["transpose"] = .postfix(.transpose)
        p["transposed"] = .postfix(.transpose)
        p["conjugate"] = .postfix(.conjugate)
        p["percent"] = .postfix(.percent)
        p["degrees"] = .postfix(.degrees)
        p["degree"] = .postfix(.degrees)

        // Roots
        for k in ["square root of", "the square root of", "square root", "sqrt of", "sqrt",
                  "root of"] {
            p[k] = .root(index: nil)
        }
        for k in ["cube root of", "the cube root of", "cube root", "cbrt"] {
            p[k] = .root(index: "3")
        }
        p["fourth root of"] = .root(index: "4")
        p["nth root of"] = .root(index: "n")

        // Magnitudes
        for k in ["absolute value of", "the absolute value of", "absolute value",
                  "modulus of", "the modulus of", "magnitude of", "the magnitude of"] {
            p[k] = .absWord
        }
        for k in ["norm of", "the norm of", "the length of"] { p[k] = .normWord }

        // Big operators
        for k in ["integral", "the integral", "an integral", "integral of", "the integral of"] {
            p[k] = .bigOperator("\\int")
        }
        // SwiftMath has no \\iint, so compose one from two tight integrals.
        p["double integral"] = .bigOperator("\\int\\!\\!\\int")
        p["the double integral"] = .bigOperator("\\int\\!\\!\\int")
        p["iint"] = .bigOperator("\\int\\!\\!\\int")
        // Typed shorthand for the big operators.
        p["int"] = .bigOperator("\\int")
        p["oint"] = .bigOperator("\\oint")
        p["prod"] = .bigOperator("\\prod")
        p["contour integral"] = .bigOperator("\\oint")
        p["line integral"] = .bigOperator("\\oint")
        for k in ["sum", "the sum", "summation", "the summation", "sum of", "the sum of"] {
            p[k] = .bigOperator("\\sum")
        }
        for k in ["product", "the product", "the product of", "product of"] {
            p[k] = .bigOperator("\\prod")
        }
        p["union over"] = .bigOperator("\\bigcup")
        p["intersection over"] = .bigOperator("\\bigcap")

        // Limits
        for k in ["limit", "the limit", "lim", "limit of", "the limit of"] {
            p[k] = .limitOp("\\lim")
        }
        p["limit superior"] = .limitOp("\\limsup")
        p["limsup"] = .limitOp("\\limsup")
        p["limit inferior"] = .limitOp("\\liminf")
        p["liminf"] = .limitOp("\\liminf")

        // Derivatives
        for k in ["derivative of", "the derivative of", "derivative", "the derivative"] {
            p[k] = .derivative(order: 1, partial: false)
        }
        for k in ["second derivative of", "the second derivative of", "second derivative"] {
            p[k] = .derivative(order: 2, partial: false)
        }
        for k in ["third derivative of", "the third derivative of"] {
            p[k] = .derivative(order: 3, partial: false)
        }
        for k in ["partial derivative of", "the partial derivative of", "partial derivative"] {
            p[k] = .derivative(order: 1, partial: true)
        }
        for k in ["second partial derivative of", "the second partial derivative of"] {
            p[k] = .derivative(order: 2, partial: true)
        }

        // Quantifiers
        p["for all"] = .identifier("\\forall")
        p["for every"] = .identifier("\\forall")
        p["for each"] = .identifier("\\forall")
        p["there exists"] = .identifier("\\exists")
        p["there is"] = .identifier("\\exists")
        p["exists"] = .identifier("\\exists")

        // Structural keywords
        p["from"] = .keyword(.from)
        p["to"] = .keyword(.to)
        p["of"] = .keyword(.of)
        p["as"] = .keyword(.asWord)
        p["with respect to"] = .keyword(.withRespectTo)
        p["wrt"] = .keyword(.withRespectTo)
        p["sub"] = .keyword(.sub)
        p["base"] = .keyword(.sub)
        p["subscript"] = .keyword(.sub)
        p["underscore"] = .keyword(.sub)
        p["superscript"] = .keyword(.filler)
        for k in ["the quantity", "quantity", "the expression"] { p[k] = .keyword(.quantity) }
        p["the"] = .keyword(.filler)
        for k in ["from the right", "from above"] { p[k] = .keyword(.fromTheRight) }
        for k in ["from the left", "from below"] { p[k] = .keyword(.fromTheLeft) }

        // Fraction phrasings
        p["one half"] = .number("1/2")   // resolved into a real fraction by the parser
        p["a half"] = .number("1/2")
        p["one third"] = .number("1/3")
        p["two thirds"] = .number("2/3")
        p["one quarter"] = .number("1/4")
        p["one fourth"] = .number("1/4")
        p["three quarters"] = .number("3/4")

        // Number words, so "two x plus three" works.
        let numberWords = ["zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
                           "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
                           "ten": "10", "eleven": "11", "twelve": "12", "twenty": "20",
                           "fifty": "50", "hundred": "100", "thousand": "1000"]
        for (k, v) in numberWords { p[k] = .number(v) }

        // Constants and named sets
        for (k, v) in constants { p[k] = .identifier(v) }

        // Greek (lowercase spelling → lowercase letter)
        for name in ["alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta",
                     "theta", "vartheta", "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron",
                     "pi", "varpi", "rho", "varrho", "sigma", "varsigma", "tau", "upsilon",
                     "phi", "varphi", "chi", "psi", "omega"] {
            p[name] = .identifier("\\" + name)
        }

        // Function names and aliases
        for name in nativeFunctions { p[name.lowercased()] = .function("\\" + name) }
        for name in romanFunctions { p[name] = .function("\\mathrm{\(name)}") }
        for (alias, target) in functionAliases {
            if nativeFunctions.contains(target) {
                p[alias] = .function("\\" + target)
            } else if romanFunctions.contains(target) {
                p[alias] = .function("\\mathrm{\(target)}")
            } else {
                p[alias] = .function("\\mathrm{\(target)}")
            }
        }
        // "div" as a word is ambiguous; keep it as the divergence operator only.
        p["div"] = .function("\\mathrm{div}")
        // Typed shorthand: "inf" almost always means infinity, not the infimum.
        p["inf"] = .identifier("\\infty")

        return p
    }()

    /// Longest phrase length (in words) present in `phrases`, used to bound lookahead.
    static let maxPhraseWords: Int = {
        phrases.keys.reduce(1) { max($0, $1.split(separator: " ").count) }
    }()

    // MARK: Symbols

    static let symbolTokens: [String: MathToken] = [
        "+": .additive("+"), "-": .additive("-"), "\u{2212}": .additive("-"),
        "\u{00B1}": .additive("\\pm"), "+-": .additive("\\pm"), "-+": .additive("\\mp"),
        "\u{2213}": .additive("\\mp"),
        "*": .multiplicative(.cdot, .tight), "\u{00B7}": .multiplicative(.cdot, .tight),
        "\u{22C5}": .multiplicative(.cdot, .tight),
        "\u{00D7}": .multiplicative(.cross, .tight), "\u{00F7}": .multiplicative(.div, .tight),
        "/": .multiplicative(.fraction, .tight),
        "^": .caret, "**": .caret, "_": .underscore,
        "=": .relation("="), "==": .relation("="),
        "<": .relation("<"), ">": .relation(">"),
        "<=": .relation("\\leq"), ">=": .relation("\\geq"),
        "\u{2264}": .relation("\\leq"), "\u{2265}": .relation("\\geq"),
        "!=": .relation("\\neq"), "~=": .relation("\\approx"),
        "\u{2260}": .relation("\\neq"), "\u{2248}": .relation("\\approx"),
        "\u{2261}": .relation("\\equiv"), "\u{221D}": .relation("\\propto"),
        "->": .relation("\\to"), "\u{2192}": .relation("\\to"),
        "=>": .relation("\\Rightarrow"), "\u{21D2}": .relation("\\Rightarrow"),
        "<=>": .relation("\\iff"), "\u{21D4}": .relation("\\iff"),
        "<->": .relation("\\leftrightarrow"),
        "\u{2208}": .relation("\\in"), "\u{2209}": .relation("\\notin"),
        "\u{2282}": .relation("\\subset"), "\u{2286}": .relation("\\subseteq"),
        "\u{222A}": .relation("\\cup"), "\u{2229}": .relation("\\cap"),
        "(": .open("("), ")": .close(")"),
        "[": .open("["), "]": .close("]"),
        "{": .open("\\{"), "}": .close("\\}"),
        "|": .open("|"),
        ",": .comma,
        "!": .postfix(.factorial), "'": .postfix(.prime), "\u{2032}": .postfix(.prime),
        "\u{2033}": .postfix(.doublePrime), "%": .postfix(.percent),
        "\u{00B0}": .postfix(.degrees),
        "\u{03C0}": .identifier("\\pi"), "\u{221E}": .identifier("\\infty"),
        "\u{2202}": .identifier("\\partial"), "\u{2207}": .identifier("\\nabla"),
        "\u{2200}": .identifier("\\forall"), "\u{2203}": .identifier("\\exists"),
        "\u{2205}": .identifier("\\emptyset"), "\u{22A5}": .relation("\\perp"),
        "\u{2225}": .relation("\\parallel"), "\u{2220}": .identifier("\\angle"),
        "\u{2211}": .bigOperator("\\sum"), "\u{220F}": .bigOperator("\\prod"),
        "\u{222B}": .bigOperator("\\int"), "\u{222E}": .bigOperator("\\oint"),
        "\u{221A}": .root(index: nil),
        "\u{2026}": .identifier("\\ldots"), "...": .identifier("\\ldots"),
        "\u{2218}": .multiplicative(.cdot, .tight),
        // Typed superscripts: "r²" is exactly "r squared".
        "\u{00B2}": .postfix(.square), "\u{00B3}": .postfix(.cube),
        "\u{00B9}": .postfix(.explicit("1")), "\u{2070}": .postfix(.explicit("0")),
        "\u{2074}": .postfix(.explicit("4")), "\u{2075}": .postfix(.explicit("5")),
        "\u{2076}": .postfix(.explicit("6")), "\u{2077}": .postfix(.explicit("7")),
        "\u{2078}": .postfix(.explicit("8")), "\u{2079}": .postfix(.explicit("9")),
        "\u{207F}": .postfix(.explicit("n")),
        "\u{00BD}": .identifier("\\frac{1}{2}"), "\u{00BC}": .identifier("\\frac{1}{4}"),
        "\u{00BE}": .identifier("\\frac{3}{4}"), "\u{2153}": .identifier("\\frac{1}{3}")
    ]

    /// Greek letters typed directly, e.g. `α`.
    static let unicodeGreek: [Unicode.Scalar: String] = {
        var table: [Unicode.Scalar: String] = [:]
        let lower: [(Unicode.Scalar, String)] = [
            ("\u{03B1}", "alpha"), ("\u{03B2}", "beta"), ("\u{03B3}", "gamma"),
            ("\u{03B4}", "delta"), ("\u{03B5}", "epsilon"), ("\u{03B6}", "zeta"),
            ("\u{03B7}", "eta"), ("\u{03B8}", "theta"), ("\u{03B9}", "iota"),
            ("\u{03BA}", "kappa"), ("\u{03BB}", "lambda"), ("\u{03BC}", "mu"),
            ("\u{03BD}", "nu"), ("\u{03BE}", "xi"), ("\u{03C1}", "rho"),
            ("\u{03C3}", "sigma"), ("\u{03C4}", "tau"), ("\u{03C5}", "upsilon"),
            ("\u{03C6}", "phi"), ("\u{03C7}", "chi"), ("\u{03C8}", "psi"),
            ("\u{03C9}", "omega")
        ]
        for (scalar, name) in lower { table[scalar] = "\\" + name }
        let upper: [(Unicode.Scalar, String)] = [
            ("\u{0393}", "Gamma"), ("\u{0394}", "Delta"), ("\u{0398}", "Theta"),
            ("\u{039B}", "Lambda"), ("\u{039E}", "Xi"), ("\u{03A0}", "Pi"),
            ("\u{03A3}", "Sigma"), ("\u{03A6}", "Phi"), ("\u{03A8}", "Psi"),
            ("\u{03A9}", "Omega")
        ]
        for (scalar, name) in upper { table[scalar] = "\\" + name }
        return table
    }()

    // MARK: Differentials

    /// `dx`-style tokens. Kept as an explicit whitelist so common English words
    /// ("do", "de", "day") are never mistaken for a differential.
    static let differentialSuffixes: Set<String> = [
        "x", "y", "z", "t", "s", "r", "u", "v", "w", "n", "m", "p", "q", "k", "l",
        "theta", "phi", "psi", "rho", "mu", "nu", "lambda", "sigma", "tau", "omega",
        "alpha", "beta", "gamma", "xi", "eta"
    ]
    static let differentialUppercaseSuffixes: Set<String> = ["A", "V", "S", "R", "T", "P", "Q"]

    /// Returns the differential's variable (already LaTeX-rendered) for a word like `dx`.
    static func differentialVariable(for word: String) -> String? {
        guard word.count >= 2, word.first == "d" else { return nil }
        let rest = String(word.dropFirst())
        if rest.count == 1, let c = rest.first, c.isUppercase,
           differentialUppercaseSuffixes.contains(rest) {
            return rest
        }
        let lowerRest = rest.lowercased()
        guard differentialSuffixes.contains(lowerRest) else { return nil }
        if lowerRest.count == 1 { return rest }
        return "\\" + lowerRest
    }

    // MARK: Classification helpers

    /// Words that make a phrase worth handing to the language model even when the
    /// deterministic parser gives up.
    public static let strongHints: Set<String> = [
        "integral", "integrate", "integrating", "sum", "summation", "product",
        "limit", "derivative", "differentiate", "differentiating", "gradient",
        "matrix", "determinant", "eigenvalue", "eigenvector", "vector",
        "sqrt", "squared", "cubed", "factorial", "infinity", "pi", "theta",
        "sigma", "lambda", "delta", "alpha", "beta", "gamma", "omega", "mu",
        "equals", "plus", "minus", "times", "over", "divided", "power",
        "sin", "cos", "tan", "log", "ln", "exp", "partial", "binomial",
        "probability", "expectation", "variance", "convolution", "fourier",
        "laplace", "transform", "modulo", "factorise", "factorize", "solve",
        "expand", "simplify", "evaluate", "approaches"
    ]
}
