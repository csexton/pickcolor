#!/bin/sh
# pickcolor copies the picked color to the clipboard itself. Cancelling with
# Esc exits 1, which isn't an error worth showing in LaunchBar.
"$(dirname "$0")/pickcolor" >/dev/null || true
