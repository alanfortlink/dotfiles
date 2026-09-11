# chat-view

Makes the pi transcript read like a chat: your messages are right-aligned,
shrink-to-fit bubbles (theme `userMessageBg`) under a `You` label; the
assistant's replies sit on the left under a `● pi · <model>` label with an
accent bar down the side. The label shows once per turn; later text chunks of
the same turn (between tool calls) keep only the bar.

Display-only. Composes with compact-view in either load order. Tunables are
the constants at the top of `index.ts` (names, bar glyph, width caps, colors).

## Test

Same jiti one-liner as compact-view's README, run from this directory.
