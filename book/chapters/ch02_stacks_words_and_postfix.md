# Chapter 02: Stacks Words And Postfix

The foreman in North Deep keeps two ledgers. One is for numbers. The other is for mistakes. The first grows every shift. The second grows whenever someone forgets what is on top of a stack.

If Chapter 1 proved that Cairn runs, Chapter 2 is where we learn to run Cairn without guessing.

In postfix code, each word does one thing to the stack. It either pushes a value, or it consumes values and pushes a result. You can read a line as a series of tiny before/after transformations.

Take this expression:

```cairn
12 3 MUL
```

Read it left to right:
`12` pushes `12`. `3` pushes `3`. `MUL` pops both and pushes `36`. The final stack contains `36`.

We can make this concrete inside `Runewarden`. Create:

```text
book/code/runewarden/chapters/ch02_stacks_words_and_postfix/main.crn
```

with:

```cairn
"Runewarden: stack drill begins." SAID

12 3 MUL LET ore_load
ore_load "ore_load={}" FMT SAID

ore_load 5 ADD LET reinforced_load
reinforced_load "reinforced_load={}" FMT SAID

reinforced_load DUP ADD LET twin_total
twin_total "twin_total={}" FMT SAID

"green" "north-deep" "shaft={} status={}" FMT SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch02_stacks_words_and_postfix/main.crn
```

The first three numeric lines are a stack drill in slow motion.

`12 3 MUL LET ore_load` leaves no temporary values behind. `MUL` produces one value. `LET` consumes that value into a name. The stack is clear again.

`ore_load 5 ADD LET reinforced_load` does the same shape with a named value plus a literal.

`reinforced_load DUP ADD LET twin_total` adds one new operator. `DUP` copies the top value so `ADD` can consume two numbers. In plain terms, it doubles the current load.

The last line is the first place beginners usually stumble:

```cairn
"north-deep" "green" "shaft={} status={}" FMT SAID
```

`FMT` expects the format string on top. The placeholder values sit under it. The first `{}` gets the top value under the format string, which is `"green"` in this line. That means this exact line prints the wrong sentence for our intent.

To produce `shaft=north-deep status=green`, push values from right to left:

```cairn
"green" "north-deep" "shaft={} status={}" FMT SAID
```

Now the top value under the format string is `"north-deep"`, which lands in the first `{}`.

This is the stack habit in practice. When output is wrong, do not panic and rewrite the whole line. Check consumption order. Most early bugs in Cairn are order bugs, not logic bugs.

Chapter 3 will introduce function boundaries and contracts, so these small stack transformations can be named, reused, and checked.
