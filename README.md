# pickcolor

A command-line color picker for macOS. Run it and the system zoom loupe appears. Click any pixel and its color is copied to the clipboard and printed to stdout. Press Esc to cancel.

```sh
make            # build ./pickcolor
make install    # install to /usr/local/bin (override with PREFIX=~ or BINDIR=...)

pickcolor              # B896DB  (sRGB hex, the default)
pickcolor -f css       # #B896DB
pickcolor -f rgb       # rgb(184, 150, 219)
pickcolor -f hsl       # hsl(270, 49%, 72%)
pickcolor --display    # display-native values (Digital Color Meter "Display native")
color=$(pickcolor)     # use it in scripts
```

Exit codes: `0` means a color was picked, `1` means it was cancelled, `2` means a bad argument.

While you hover, a label next to the loupe shows the value (in the chosen format) and a swatch for the pixel under the cursor. Reading the screen this way needs **Screen Recording** permission for whatever launches `pickcolor` (Terminal, LaunchBar, …). The first run asks for it. Without it you still get the loupe and the clicked color, just no live label.

**LaunchBar:** create a Shell Script action, or put a script in `~/Library/Application Support/LaunchBar/Actions`, that runs `/usr/local/bin/pickcolor`.
