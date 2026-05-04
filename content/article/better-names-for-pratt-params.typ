#import "/typ/templates/blog.typ": *
#show: main.with(
  title: "Better names for Pratt parameters",
  desc: "A few suggestions to more clearly name the parameters of your Pratt implementation",
  date: "2026-05-04",
  tags: (
    "parsing",
    "pratt",
    "rhombus",
  ),
  show-outline: false,
)

One thing that confuses me about Pratt implementations in general is the
arbitrary use of the terms left and right. It's fair to recognize that the whole
issue solved by operator-precedence parsing is whether a given
term/subexpression binds to left or right:

```
A ♠ B ♦ C
```

In the example above, does B bind to ♠ or ♦? We must compare their binding
powers to know. However, in Pratt, algorithms are recursive and whether a term
is left or right depends on the point of view (how deep are you in the
callstack?). So... I always found confusing to understand Pratt from this
exposition:

```rhombus
fun expression(rbp = 0):
    let mutable t = token
    advance()
    let mutable left = t.nud()
    while rbp < token.lbp():
        t := token
        advance()
        left := t.led(left)
    left
```

Over the months using Pratt, I found it was clearer to me to rename the
parameters to:

```rhombus
fun expression(caller_binding_power = 0):
    let mutable t = token
    advance()
    let mutable expr = t.nud()
    while caller_binding_power < token.led_binding_power():
        t := token
        advance()
        expr := t.led(expr)
    expr
```

However the semantic action for a led can retain the name _left_ for its last
parameter:

```rhombus
class Multiplication():
    extends Token
    override led_binding_power():
        20
    override led(left):
        left * expression(led_binding_power())
```

After using Pratt extensively for a language that I've been developing since
last year, _nud_ & _led_ were terms that never damaged me. Nud & led are the
terms that beginners in the Pratt school usually complain about, but introducing
new terms for new concepts help to shape your mental model to use the new
framework. They put you in the proper state of mind to reason about the problem,
and that matters for enabling you to tackle harder problems with more ease. If
we were to replace “led” by “binary operator” (as usually done by beginners),
it'd hide the fact that leds are also used for postfix operators (and some
mistfix ones), and it'd actually preclude you from understating Pratt's
power. The changes that I suggest above don't suffer from this problem.
