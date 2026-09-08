import Foundation

/// The behavioural specification of the translator, in one place.
///
/// `expectations` pins the exact LaTeX for phrases that must translate.
/// `rejections` pins prose that must never be turned into an equation — the
/// false-positive side is the one users actually notice, so it is tested just as hard.
public enum MathCorpus {

    // MARK: Must translate, exactly like this

    public static let expectations: [(phrase: String, latex: String)] = [
        // Spoken algebra
        ("pi r squared", "\\pi r^2"),
        ("x squared plus y squared equals z squared", "x^2 + y^2 = z^2"),
        ("a squared plus b squared equals c squared", "a^2 + b^2 = c^2"),
        ("y equals m x plus b", "y = mx + b"),
        ("two x plus three", "2x + 3"),
        ("x is 5", "x = 5"),
        ("theta squared over 2", "\\frac{\\theta^2}{2}"),
        ("3 over 4", "\\frac{3}{4}"),
        ("one half m v squared", "\\frac{1}{2}mv^2"),
        ("alpha times beta", "\\alpha \\cdot \\beta"),
        ("a plus or minus b", "a \\pm b"),
        ("2 pi r", "2\\pi r"),
        ("n factorial", "n!"),
        ("5 factorial equals 120", "5! = 120"),
        ("n choose k", "\\binom{n}{k}"),
        ("5 percent", "5\\%"),
        ("90 degrees", "90^{\\circ}"),
        ("A inverse", "A^{-1}"),
        ("sigma squared", "\\sigma^2"),
        ("alpha beta gamma", "\\alpha \\beta \\gamma"),

        // Typed shorthand
        ("x^2 + 3x - 5 = 0", "x^2 + 3x - 5 = 0"),
        ("f(x) = x^2 + 3x - 5", "f(x) = x^2 + 3x - 5"),
        ("E = mc^2", "E = mc^2"),
        ("dy/dx = 2x", "\\frac{dy}{dx} = 2x"),
        ("d/dx", "\\frac{d}{dx}"),
        ("1/2 m v squared", "\\frac{1}{2}mv^2"),
        ("v = 4/3 pi r^3", "v = \\frac{4}{3}\\pi r^3"),
        ("10^-6", "10^{-6}"),
        ("x_1 + x_2", "x_1 + x_2"),
        ("a_n = a_1 + (n-1)d", "a_n = a_1 + (n - 1)d"),
        ("(x + 1)(x - 1)", "(x + 1)(x - 1)"),
        ("sqrt(x^2 + y^2)", "\\sqrt{x^2 + y^2}"),
        ("e^{-x^2}", "e^{-x^2}"),
        ("x <= 5", "x \\leq 5"),
        ("y != 0", "y \\neq 0"),
        ("3 <= x <= 7", "3 \\leq x \\leq 7"),
        ("|x - 3| < 5", "\\left| x - 3 \\right| < 5"),
        ("P(A|B)", "P(A \\mid B)"),
        ("P(A) = 1/2", "P(A) = \\frac{1}{2}"),
        ("log_2 x", "\\log_2 x"),
        ("x = (-b +- sqrt(b^2 - 4ac)) / (2a)", "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}"),
        ("T = 2 pi sqrt(L/g)", "T = 2\\pi \\sqrt{\\frac{L}{g}}"),
        ("int_0^1 x dx", "\\int_0^1 x \\, dx"),
        ("sum_{n=1}^{inf} 1/n^2", "\\sum_{n = 1}^{\\infty} \\frac{1}{n^2}"),
        ("lim_{x -> 0} sin x / x", "\\lim_{x \\to 0} \\frac{\\sin x}{x}"),

        // Calculus in words
        ("the integral of x dx", "\\int x \\, dx"),
        ("the integral from 0 to 1 of x squared dx", "\\int_0^1 x^2 \\, dx"),
        ("the sum from n equals 1 to infinity of 1 over n squared",
         "\\sum_{n = 1}^{\\infty} \\frac{1}{n^2}"),
        ("the sum from i equals 1 to n of i", "\\sum_{i = 1}^n i"),
        ("the product from k equals 1 to n of k", "\\prod_{k = 1}^n k"),
        ("the limit as x approaches 0 of sin x over x", "\\lim_{x \\to 0} \\frac{\\sin x}{x}"),
        ("the limit as n goes to infinity of 1 over n", "\\lim_{n \\to \\infty} \\frac{1}{n}"),
        ("the limit of f as x approaches a", "\\lim_{x \\to a} f"),
        ("lim x to 0", "\\lim_{x \\to 0}"),
        ("the derivative of y with respect to x", "\\frac{dy}{dx}"),
        ("the second derivative of y with respect to x", "\\frac{d^{2}y}{dx^{2}}"),
        ("the partial derivative of f with respect to x", "\\frac{\\partial f}{\\partial x}"),
        ("the second partial derivative of u with respect to t",
         "\\frac{\\partial^{2} u}{\\partial t^{2}}"),
        ("Delta y over Delta x", "\\frac{\\Delta y}{\\Delta x}"),
        ("delta x approaches 0", "\\delta x \\to 0"),
        ("x approaches 0 from the left", "x \\to 0^-"),
        ("the limit as h approaches 0 from the right of f", "\\lim_{h \\to 0^+} f"),

        // Roots, powers, functions
        ("the square root of 2", "\\sqrt{2}"),
        ("the square root of x squared plus y squared", "\\sqrt{x^2 + y^2}"),
        ("the cube root of 27", "\\sqrt[3]{27}"),
        ("the nth root of x", "\\sqrt[n]{x}"),
        ("e to the power of i pi plus 1 equals 0", "e^{i \\pi} + 1 = 0"),
        ("2 to the power of n", "2^n"),
        ("10 to the power of 6", "10^6"),
        ("sin squared theta plus cos squared theta equals 1",
         "\\sin^2 \\theta + \\cos^2 \\theta = 1"),
        ("sec squared x", "\\sec^2 x"),
        ("log base 2 of x", "\\log_2 x"),
        ("the determinant of A", "\\det A"),
        ("f of x equals x squared", "f(x) = x^2"),
        ("g of t", "g(t)"),
        ("f'(x) = 2x + 5", "f^{\\prime}(x) = 2x + 5"),
        ("sin(2x) = 2 sin x cos x", "\\sin(2x) = 2\\sin x \\cos x"),

        // Sets, logic, relations
        ("A union B", "A \\cup B"),
        ("A is a subset of B", "A \\subseteq B"),
        ("x is an element of the reals", "x \\in \\mathbb{R}"),
        ("for all x there exists y", "\\forall x \\exists y"),
        ("x tends to infinity", "x \\to \\infty"),
        ("f(x) approx x", "f(x) \\approx x"),
        ("the norm of v", "\\left\\| v \\right\\|"),
        ("nabla cross F", "\\nabla \\times F"),
        ("x mod 3", "x \\;\\mathrm{mod}\\; 3"),

        // Unicode input
        ("α + β = γ", "\\alpha + \\beta = \\gamma"),
        ("x ≤ 5", "x \\leq 5"),
        ("∫ x dx", "\\int x \\, dx"),
        ("π r²", "\\pi r^2")
    ]

    /// Every phrase that must translate, for bulk checks.
    public static var translatable: [String] { expectations.map(\.phrase) }

    // MARK: Must never translate

    public static let rejections: [String] = [
        // Ordinary prose
        "the cat sat on the mat",
        "hello world",
        "I went to the store",
        "this is a test of the system",
        "we can see that the value increases",
        "let me think about this",
        "so the answer is 42",
        "meet me at 5",
        "chapter 2 section 3",
        "I think that is fine",
        "we are going to the park",
        "it is over there",
        "put it in the box",
        "she said that x marks the spot",
        "the quick brown fox jumps",
        "please review the attached document",

        // Prose that reuses mathematical vocabulary
        "the sum of money",
        "he is at least as tall",
        "a lot of times",
        "to be or not to be",
        "over the hill",
        "the limit of my patience",
        "pi day is in march",
        "log in to the system",
        "min and max values",
        "the product manager",
        "an integral part of life",
        "the derivative works of the author",
        "a matter of degrees",
        "in the limit case",

        // Too little structure to be worth rendering
        "x",
        "42",
        "pi",
        "",
        "   ",
        "sin",
        "the"
    ]
}
