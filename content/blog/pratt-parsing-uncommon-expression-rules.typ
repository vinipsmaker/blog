#import "/content/blog.typ": *
#show: main.with(
  title: "Pratt parsing uncommon expression rules",
  desc: "A Pratt parsing tutorial on how to parse partially ordered operator precedence and implicit binary operators",
  date: "2026-04-05",
  tags: (
    "parsing",
    "pratt",
    "rhombus",
  ),
  show-outline: false,
)

==== Introduction

Pratt parsing is a powerful parsing technique to parse programming
languages. It's as much of an organizational pattern for the parser code as it's
the driving algorithm to combine the grammar rules. The core algorithm can be as
small as 14 lines even in verbose languages such as C++ (code slightly adapted
from a compiler that I'm writing):

```cpp
std::shared_ptr<ast::Expr> parse_expr(
    ParsingContext& context, reader& r, unsigned caller_binding_power)
{
    auto tok = r;
    if (!at_or_zero(nud_table, tok.code())) {
        throw expected_expr{tok};
    }
    r.next();
    auto expr = nud_table[tok.code()](context, tok, r);
    auto led_binding_power = at_or_zero(token::binding_power, r.code());
    while (caller_binding_power < led_binding_power) {
        tok = r;
        r.next();
        expr = led_table[tok.code()](context, tok, r, expr);
        led_binding_power = at_or_zero(token::binding_power, r.code());
    }
    return expr;
}
```

It can get even cleaner when targeting high-level languages such as JavaScript:

```javascript
// code taken from
// https://crockford.com/javascript/tdop/tdop.html
var expression = function (rbp) {
    var t = token;
    advance();
    var left = t.nud();
    while (rbp < token.lbp) {
        t = token;
        advance();
        left = t.led(left);
    }
    return left;
}
```

The small size of the algorithm and a clean separation of responsibilities make
it a great candidate for small extensions that allow it to target even larger
classes of languages. The link mentioned above already introduces a small
extension to parse statement-oriented languages, and builds upon that to parse a
small subset of JavaScript. It goes as far as to teach you how to build a
keyword-free language where the first use of a word within a function body will
determine whether a word is a keyword or a name free to use for user variables.

That just shows how extensively malleable Pratt parsing is. You can even augment
the parsing rules as it parses the text. For an interpreted language, that means
the text read so far may define how to parse the text yet to come. For compiled
languages, if enough attention is given, you may even design a language whose
user-provided parsing rules are only found later in the text. The use of such
extra rules are known as macros around Lisp communities, and they're far more
powerful than more popular macro technologies such as C preprocessor
macros. Some Racket developers have already been exploring Pratt to add a more
conventional syntax to Lisp languages for over a decade.

Since last year I've been acquiring more and more of a Pratt parsing mindset as
I'm developing my own macro language for the C++ ABI, but in this article I'll
be focusing on two extensions for Pratt parsing that I still haven't seen
documented in the wild:

- Partial precedence ordering for operator precedence.
- Juxtaposition as an implicit operator.

==== The structure of the code samples

I'll use the language Rhombus for all code samples as that's a high-level
dynamic language where lexer definitions won't waste a lot of space. Rhombus
isn't actually a language focused on lexing or parsing, but the language is
extensible and the lexer library from the package `rhombus-parser-lib` makes use
of this extensibility to create a concise eDSL to define lexers. Below there's a
Pratt parser/evaluator for a basic arithmetic language:

```rhombus
#lang rhombus

import:
    parser/lex open

class Token(~nud: nud_impl = #false,
            ~led: led_impl = #false,
            ~lbp = 0):
    nonfinal
    method nud(): nud_impl(this)
    method led(lhs): led_impl(this, lhs)
    method prefix(): pratt(30)
    method rhs(): pratt(this.lbp)

class RParen(): extends Token

def lex:
    lexer
    | "+": Token(
        ~nud: (_.prefix()),
        ~led: fun(t, lhs): lhs + t.rhs(),
        ~lbp: 10)
    | "-": Token(
        ~nud: (-_.prefix()),
        ~led: fun(t, lhs): lhs - t.rhs(),
        ~lbp: 10)
    | "*": Token(
        ~led: fun(t, lhs): lhs * t.rhs(),
        ~lbp: 20)
    | "/": Token(
        ~led: fun(t, lhs): lhs / t.rhs(),
        ~lbp: 20)
    | digit+: Token(~nud: fun(_): String.to_int(lexeme))
    | " "+: lex(input_port)
    | "(": Token(
        ~nud: fun(_):
                  let ret = pratt()
                  guard token is_a RParen
                  | error("expected closing parens")
                  advance()
                  ret)
    | ")": RParen()
    | ~eof: Token()

def input = Port.Input.open_string("4 * (3 - 3) / 2 + -10")
def mutable token = lex(input)
fun advance(): token := lex(input)

fun pratt(rbp = 0):
    let mutable t = token
    advance()
    let mutable expr = t.nud()
    for (_ in 0..):
        break_when: rbp >= token.lbp
        t := token
        advance()
        expr := t.led(expr)
    expr

println(pratt())
```

Do notice that's my first time using Rhombus. I never used a language with such
a weird syntax. Even so I just gave it a shot and it worked out in the end. If
you feel intimated, remember that you're only reading it (I was the one who had
to write in it). Try to get past the weirdness and do the leap of faith as
well. I can assure you that the end result is good teaching material on Pratt
parsing.

The following line would be a huge PITA in any other language, but here is just
a single line:

```rhombus
| " "+: lex(input_port)
```

It recursively (hopefully doing tail call optimization) calls the lexer again to
skip over insignificant whitespace. That's unimportant for teaching Pratt
parsing, and accordingly it only contributes to a single lone quiet line in our
code. Many of such smalls details contribute it to being a good language for
teaching Pratt parsing. The guys behind this lexer library knew what they were
doing.

The lexer is directly returning objects for the class that I created for use in
the Pratt parser. So the lexer became the nud table, and the led table, and the
binding power table. You can directly correlate a token and its semantic
action. Even the more advanced semantic actions such as the nud for lparen have
concise code that express the whole intent in just a glance. You aren't chasing
through abstractions jumping from here to there and back again just to make
sense of what's happening. This is peak abstraction for a Pratt parsing
tutorial.

==== Partial precedence ordering for operator precedence

Folks behind Carbonlang were inspired by Hasse diagrams to define a partial
order for the precedence between the operators.
#footnote[https://github.com/carbon-language/carbon-lang/pull/555] Their design
instructs the parser to error on expressions such as `a + b << c` where the
order between operators isn't defined forcing the user to explicitly resolve
such cases by parentheses-grouping.

It was this single unsuspecting rule that motivated me to learn new parsing
techniques. It was my desire to be able to parse such grammar rules that
eventually drove me to the road that got me into Pratt parsing. I didn't know
how to parse such rule with my skills on PEG parsing. Pratt parsing also doesn't
give an answer here, but at least it's easy to extend the algorithm to handle
such cases.

In fact, there are several ways to extend Pratt parsing to handle this rule. The
approach that I'm going to present is an approach that I'd use if I were coding
in C++. I'm only using Rhombus here because it's a high-level language and
allows us to focus on the algorithms. However on implementations that are
designed to be fast, I wouldn't be using the class `Token` that I used here. I'd
waste time just thinking about the design of dispatch tables for nuds and
leds. I'd waste time just thinking about lexers that convert tokens into enums
and are cheap. I'd waste time on such trivial details that are unimportant to
teach Pratt. However now I'll take a turn back and present the extension for
Carbon operators that I'd use in C++.

The key observation here is that the group that a Carbon operator belongs to is
a property of the expression (as written), not a property of the value returned
by the expression. Therefore we need a new class to represent expressions:

```rhombus
class Expression(value, group = 0)
```

Then we modify the leds to check the groups:

```rhombus
| "+": Token(
    ~led: fun(t, lhs):
              guard lhs.group == 0 || lhs.group == 1
              | error("parentheses-grouping required")
              let rhs = t.rhs()
              guard rhs.group == 0 || rhs.group == 1
              | error("parentheses-grouping required")
              Expression(lhs.value + rhs.value, 1),
    ~lbp: 90)
| "<<": Token(
    ~led: fun(t, lhs):
              guard lhs.group == 0 || lhs.group == 2
              | error("parentheses-grouping required")
              let rhs = t.rhs()
              guard rhs.group == 0 || rhs.group == 2
              | error("parentheses-grouping required")
              Expression(lhs.value * math.expt(2, rhs.value), 2),
    ~lbp: 80)
```

And use the nud for parentheses to reset the group back to zero:

```rhombus
| "(": Token(
    ~nud: fun(_):
              let ret = Expression(pratt().value, 0)
              guard token is_a RParen
              | error("expected closing parens")
              advance()
              ret)
```

Done. We just implemented Carbon's P0555. Easy peasy.

==== Juxtaposition as an implicit operator

In programming languages, the operator for multiplication is usually denoted by
`*`. However, mathematicians and physicists traditionally do not use the
operator `*`. Instead they use simple juxtaposition to indicate multiplication:

```
x y
```

The popularity of juxtaposition as an implicit binary operator also reached the
field of programming, but only in a specific case: regexes. The regex `A`
matches the letter `A`. The regex `B` matches the letter `B`. The regex `AB`
matches the letter `A` followed by the letter `B`.

Some might hate regex overuse and avoid its usage altogether, but some of their
notable problems have solutions, and there are folks working on
them#footnote[Check YSH's eggexes for an example:
https://oils.pub/release/latest/doc/eggex.html]. The thing is...  even these
improvements to good'n'old regexes make use of juxtaposition as an implicit
operator. Rhombus even reserved the symbol `#%juxtapose` to expose this idiom.

Then comes the question: how to parse juxtaposition as an implicit binary
operator using Pratt?

```rhombus
fun pratt(rbp = 0):
    let mutable t = token
    advance()
    let mutable expr = t.nud()
    for (_ in 0..):
        for (_ in 0..):
            break_when: token.led_impl || !token.nud_impl
            t := token
            advance()
            expr := expr * t.nud()
        break_when: rbp >= token.lbp
        t := token
        advance()
        expr := t.led(expr)
    expr
```

Easy again. This time the trick was to use 1-token of lookahead to check:

- The next token isn't a binary operator (it isn't a led).
- The next token is a nud.

So we just interpret the juxtaposition as a multiplication implicitly before
proceeding to the led loop.
