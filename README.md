# cmd-replay

Record terminal demos without typing them by hand. `cmd-replay.sh` plays a list of
shell commands back in your terminal with a timed pause and a screen clear before
each one, so every take of a README GIF looks the same.

```bash
./cmd-replay.sh scripts/demo.script
```

## Requirements

- `bash` 4+ (5+ for `--pace`). Git Bash on Windows works.
- A screen recorder, e.g. ScreenToGif on Windows or `vhs` if you want the GIF
  rendered from source.

## Quickstart

Write the commands you want on screen into a script file, one per line:

```bash
ls -1
@sleep 1
git status --short
@sleep 2
```

Then start your recorder and run it:

```bash
./cmd-replay.sh scripts/demo.script            # 2s pause between steps
./cmd-replay.sh -p 2.5 -w 45 scripts/demo.script   # slower, typed out
./cmd-replay.sh --pace 3 scripts/demo2.script  # ~3s per step, no guessing
./cmd-replay.sh -C scripts/demo3.script        # keep scrollback, don't clear
```

Each line is `eval`'d in the replay shell, so `cd` and `export` carry over
between steps (and `exit` ends the replay). Samples live in `scripts/`.

## Options

| Flag | Meaning |
| --- | --- |
| `SCRIPT` | File of commands, one per line (`-` or omitted reads stdin) |
| `-p, --pause SEC` | Wait after each command (default `2`) |
| `--pace SEC` | Per-step time budget instead: wait only for the time the command itself did not use |
| `-w, --type MS` | Type each command out at `MS` milliseconds per character |
| `-C, --no-clear` | Keep scrollback instead of clearing before each step |
| `-e, --stop-on-error` | Stop at the first non-zero exit |
| `-h, --help` | Usage and script syntax |

No pause is added after the final command, so end the script with `@sleep N` if
the last screen should linger.

## Script directives

| Directive | Effect |
| --- | --- |
| `# comment` | Skipped, like blank lines |
| `@sleep SEC` | Wait `SEC` extra seconds, leaving the screen as it is |
| `@delay SEC` | Wait `SEC` after printing the command line but before running it, so an instant command still looks slow |
| `@pause SEC` | Replace the pause after the command above it, so one slow step does not force you to retune `-p` |
| `@start_output` / `@end_output` | Print literal output instead of running the command above |

`-p` is a fixed pause. `--pace SEC` is the alternative: give each step a budget
and it only waits for the time the command did not use, so `npm install` gets no
dead air while `git status` gets time to be read.

### Staged output

For demos that should not touch the network, follow a command with an output
block. The command is shown but **not executed**, and the block is printed
literally, blank lines and whitespace included. An empty block prints nothing.

```text
exa search "example" -n 1
@start_output
Title: Example result
URL: https://example.com
@end_output
@pause 4
```

`@end_output` must be on its own line and blocks cannot be nested. Directives
inside a block are printed as text rather than applied.

## Chaining every knob

`scripts/mashup.sh` emits one long replay that uses every directive, with a
multiplier per knob (`-s` for `@sleep`, `-d` for `@delay`, `-P` for pauses) so
the pacing scales without editing numbers:

```bash
./scripts/mashup.sh                  # base speeds
./scripts/mashup.sh -s 2 -d .5 -P .5 # @sleep x2, @delay/pause x0.5
./scripts/mashup.sh -n -s 3          # print the scaled script without running
```

It is a generator, so run it directly; anything it does not recognise is passed
through to `cmd-replay.sh`.

## Recording a GIF

1. Size the terminal once (a 814x496 window records to a ~340 KB GIF here) and
   leave it alone between takes.
2. Start the recorder, then run `./cmd-replay.sh ...`. The line that launched the
   replay is cleared away too, so the first frame is just your prompt.
3. Stop the recorder once the last screen has been held for `@sleep N`.

Compress before committing. `gifsicle -O3 --careful` only merges identical
frames and rewrites diffs, so it is lossless and typically cuts 80-90% off a
terminal recording:

```bash
gifsicle -O3 --careful demo.gif -o demo.min.gif
```

Confirm nothing changed by comparing per-frame hashes of both files:

```bash
for f in demo.gif demo.min.gif; do
  ffmpeg -v error -i "$f" -f framemd5 - | awk '!/^#/{print $NF}' | uniq > "$f.md5"
done
diff demo.gif.md5 demo.min.gif.md5 && echo "identical"
```

`uniq` collapses the duplicate frames gifsicle folded into delays. If the diff is
empty, playback is pixel-identical. Avoid `--lossy` or `--colors N` on terminal
recordings: they shrink further but text starts going soft.

## Matching your own prompt

The prompt drawn before each command is assembled from the `p_*` strings and
`col_*` colours at the top of `cmd-replay.sh`. Change the values, not the escape
codes, to match your shell.
