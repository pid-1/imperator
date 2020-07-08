# imperator.sh

Automates most of my weekly system maintenance/administration condensed into a
single utility, allowing me to easily add/remove tasks.

### on `eval`

Yes, I am using `eval`.

For this particular application, I find the use to be acceptable. The input
should only be your own, intentionally entered into the config file.

Limited measures have been taken to stop people from inadvertantly taking
silly actions. `$` and ````` are stripped from the input. I considered
allowing all characters, which could facilitate expanding `$HOME` for example,
but decided against it.

### on colors

Most terminals set `.color0` (black) to the terminal's background color. My
background has its own (darker) value, so `.color0` is visible. This may not be
the case for you. Color defs are at the top (line 37).
