#import "/content/blog.typ": *
#show: main.with(
  title: "Statements in Pratt parsing",
  desc: "A small note pointing to material on parsing statements using Pratt",
  date: "2026-04-16",
  tags: (
    "parsing",
    "pratt",
  ),
  show-outline: false,
)

Pratt is pretty good to parse expression-oriented languages, but any serious
programming language you stumble upon is going to invariably require some form
of statements (e.g. definitions, imports, ...). Thus mastering how to parse
statements using Pratt is essential to use it in serious projects.

However I have nothing new to add to this topic. This blog post is more of a
note pointing to historical material with maybe a couple of comments on
top. You'll need to follow through the linked articles to actually learn the
technique.

A 2007 article from Douglas Crockford already showed how to parse statements
using Pratt.#footnote[https://crockford.com/javascript/tdop/tdop.html] The idea
was to create a new category for statements. Pratt starts with:

- Nud for null denotation.
- Led for left denotation.

So Crockford added:

- Std for statement denotation.

6 years later Crockford changed the term
to#footnote[https://www.youtube.com/watch?t=1171&v=Nlqv6NtBXcA]:

- Fud for first null denotation.

This extension doesn't actually touch anything in the Pratt algorithm so the
parser will stay as is -- looking only at nuds and leds. What actually changes
is a particular nud that you most likely already have in your grammar: the nud
for the opening brace is going to query the fud table before invoking
Pratt. This way it'll query keywords that only happen at the start of -- for the
lack of a better word -- sentences.

To illustrate the idea I'll just copy'n'paste a single code snippet from
Crockford's site#footnote[https://crockford.com/javascript/tdop/tdop.html] (but
please do check his site as he goes into more detail on the issue):

```javascript
// taken from https://crockford.com/javascript/tdop/tdop.html
var statement = function () {
    var n = token, v;
    if (n.std) {
        advance();
        scope.reserve(n);
        return n.std();
    }
    v = expression(0);
    if (!v.assignment && v.id !== "(") {
        v.error("Bad expression statement.");
    }
    advance(";");
    return v;
};

var statements = function () {
    var a = [], s;
    while (true) {
        if (token.id === "}" || token.id === "(end)") {
            break;
        }
        s = statement();
        if (s) {
            a.push(s);
        }
    }
    return a.length === 0 ? null : a.length === 1 ? a[0] : a;
};

prefix("function", function () {
    var a = [];
    new_scope();
    if (token.arity === "name") {
        scope.define(token);
        this.name = token.value;
        advance();
    }
    advance("(");
    if (token.id !== ")") {
        while (true) {
            if (token.arity !== "name") {
                token.error("Expected a parameter name.");
            }
            scope.define(token);
            a.push(token);
            advance();
            if (token.id !== ",") {
                break;
            }
            advance(",");
        }
    }
    this.first = a;
    advance(")");
    advance("{");
    this.second = statements();
    advance("}");
    this.arity = "function";
    scope.pop();
    return this;
});
```

If you prefer C++ code to illustrate the idea, here's a simplified version of a
parser that I've written in C++ to parse Rust-like syntax in a language that
I've been developing since last year:

```cpp
// parse_lbrace is the nud for "{" (code::lbrace)
std::shared_ptr<ast::Expr> parse_lbrace(
    ParsingContext& context, reader tok, reader& r)
{
    [[maybe_unused]] ParsingContext::ScopeGuard scope_guard{context};

    std::vector<std::shared_ptr<ast::Expr>> exprs;
    bool value_is_void = true;
    while (r.code() != rbrace) {
        // parse_statement() is the one querying/dispatching on fuds
        if (parse_statement(context, r, exprs)) {
            continue;
        }

        exprs.emplace_back(parse_expr(context, r, parse_until_end));
        if (!r.eat<code::semicolon>()) {
            value_is_void = false;
            break;
        }
    }
    if (r.code() != token::rbrace) {
        throw unexpected_token{r, /*expected=*/"}"};
    }
    r.next();
    return ast::make_expr<ast::Block>(
        tok.line(), tok.column(), std::move(exprs), value_is_void);
}

bool parse_statement(
    ParsingContext& context, reader& r,
    std::vector<std::shared_ptr<ast::Expr>>& out)
{
    if (at_or_zero(fud_table, r.code())) {
        auto tok = r;
        r.next();
        auto stmt = fud_table[tok.code()](context, tok, r);
        out.emplace_back(stmt);
        return true;
    } else {
        return false;
    }
}
```

In this project of mine, I started with a mix of PEG parsers and Pratt to parse
statements, but soon after I just refactored my code to make use of Crockford's
approach. Fud tables are extensible in the same way that nud tables are so if
your language has macro support it may make more sense to organize your code
using fuds rather than hard-coded chains of if-elses that implement a PEG
parser. If your language doesn't have room for macros... well a single dispatch
table might be faster than the PEG parsers and you still should consider fuds.

If your language uses indentation instead of braces this technique may still
apply. Just change the lexer to emit tokens for every start/end of new
indentation levels. Then instead of changing the nud for open-brace, you change
the nud for indent-increase where you'll query and dispatch on the fud
table. Python is one popular language creating virtual tokens to keep track of
indentation levels with the tokens `INDENT` and
`DEDENT`.#footnote[https://docs.python.org/3/reference/lexical_analysis.html#indentation]
Guido van Rossum doesn't seem to see this lexer-parser's division of labour
unfavorably. Python migrated to PEG parsers way back in the version 3.9. One of
the features found in PEG parsers is that they don't require a separate lexer,
but Python still uses a separate lexer to this day.

#quote(attribution: [Guido van Rossum#footnote[https://medium.com/@gvanrossum_83706/building-a-peg-parser-d4869b5958fb]], block: true)[
Let’s start with the input side. Classic parsers use a separate tokenizer which
breaks the input (a text file or string) into a series of tokens, such as
keywords, identifiers (names), numbers and operators. PEG parsers (like other
modern parsers such as ANTLR) often unify tokenizing and parsing, but for my
project I chose to keep the separate tokenizer.

Tokenizing Python is complicated enough that I don’t want to reimplement it
using PEG’s formalism. For example, you have to keep track of indentation (this
requires a stack inside the tokenizer), and the handling of newlines in Python
is interesting (they are significant except inside matching brackets). The many
types of string quotes also cause some complexity. In short, I have no beef with
Python’s existing tokenizer, so I want to keep it.
]

However pay attention to not put too much work into the lexer. As Andy Chu from
oils-for-unix eloquently stated:

#quote(attribution: [Andy Chu#footnote[https://www.oilshell.org/blog/2017/12/17.html#lexing-versus-parsing]], block: true)[
+ Lexing and parsing are *fundamentally different*. Parsers are *recursive*
  because languages are recursive. Lexers are not recursive. In other words,
  programming languages inherently have both lexical structure and grammatical
  structure.

+ It's more *efficient* to do the easy thing with the fast algorithm (lexing)
  and the hard thing with the slow algorithm (parsing).
]

Another interesting case to mention is
Rhombus#footnote[https://rhombus-lang.org/], a parentheses-less Lisp built on
top of Racket that uses Pratt for expressions. The language has a parsing
algorithm that groups some structures before finally deferring some parsing work
to Pratt. The algorithm started in a previous experiment as _enforestation
parsing_.#footnote[https://dl.acm.org/doi/abs/10.1145/2371401.2371420] Quite
frankly I get lost every time I try to understand this algorithm. I just don't
know what's going on. Feel free to pursue how they adapted Pratt here, but be
warned that you'll be on your own. I won't help you on this one. The only hint
that I'll give you is that hygienic macro support in Lisp can be way more
complex than in a language with traditional syntax and maybe this detail played
a part on how they approached the problem (Rhombus runs on top of Racket and
attempts to bridge both ecosystems as to not create isolated islands of
abstractions).
