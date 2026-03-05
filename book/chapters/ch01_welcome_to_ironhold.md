# Chapter 01: Welcome to Ironhold

By sunrise, the slate board outside Shaft Three is already full. A foreman has chalked the night yield. A novice runepriest has marked two seals as unstable. Someone else has written, in larger letters than necessary, "do not light the west lattice until inspected." Ironhold calls this an ordinary morning.

Ordinary mornings need systems more than heroes. That is where `Runewarden` begins: a ledger that grows, chapter by chapter, into the nervous system of a dwarven city that would prefer not to explode.

For now, none of that matters. A first chapter needs one thing: a program that runs.

Make a file:

```text
book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
```

Put this in it:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID
```

Run it:

```bash
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
```

You should see three lines. That is enough to establish the basic loop: edit, run, observe. We will not leave that loop for the rest of the book.

The second thing to learn is that Cairn is postfix and stack-based. The value comes first. The operator comes after it. You can feel this in one line:

```cairn
2 3 ADD
```

The interpreter reads left to right. It pushes `2`, then `3`, then `ADD` pops both, adds them, and pushes the result back. When the program ends, remaining values on the stack are printed.

We can fold this into our chapter file:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID

2 3 ADD "sample_load={}" FMT SAID
```

Now we are doing two kinds of work. We emit lines to humans with `SAID`. We compute values on the stack and format them with `FMT`. This pair shows up everywhere in practical Cairn code.

To make the output react to input, we can read command-line arguments through `ARGV`. If the caller gives one argument, we will treat it as the shift scribe. Otherwise we default to `apprentice`.

```cairn
ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "apprentice"
END
LET scribe

scribe "scribe={}" FMT SAID
```

This is our first conditional that matters. A chapter one program is still allowed to branch as long as the branch stays obvious. If arguments exist, pick the first one. If not, use a stable fallback. No magic.

If you are new to stack languages, read this block once as stack motion, not as "syntax." Assume the command was run with no extra arguments.

`ARGV` pushes the argument list. With no extras, that list is `[]`.

`LEN` pops that list and pushes its length, so the stack now holds `0`.

`0 GT` compares the two numbers on top of the stack. In this case it asks whether `0 > 0`, which is `FALSE`.

`IF ... ELSE ... END` now consumes that boolean and runs the `ELSE` branch, pushing `"apprentice"`.

`LET scribe` pops `"apprentice"` and binds it to the name `scribe`.

The stack is empty again, but the environment now contains `scribe = "apprentice"`.

Run the same logic with `dorin` as one argument and only two moments change. `ARGV` starts as `["dorin"]`, so `LEN` produces `1`, and `1 0 GT` is `TRUE`. The `IF` branch runs, `ARGV HEAD` pushes `"dorin"`, and `LET scribe` binds that value instead.

This is the core habit for reading Cairn: watch what each word removes, what it leaves behind, and when a value moves from stack to name.

Put everything together:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID

2 3 ADD "sample_load={}" FMT SAID

ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "apprentice"
END
LET scribe

scribe "scribe={}" FMT SAID
```

Run it both ways:

```bash
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn dorin
```

You should see `scribe=apprentice` in the first run and `scribe=dorin` in the second.

Nothing here is grand. That is exactly the point. We now have the first stone in place: a real program in a real project directory, with input, output, arithmetic, formatting, and a controlled fallback.

In the next chapter we will slow down and look directly at stack movement. If you do not learn to see the stack, you can still write Cairn, but you will write it with tension. We want the opposite. We want the calm feeling that comes when every value has a known place and every operator has a known effect.
