#!/bin/sh
# Double-click to build Jarvis and put it in Applications.
if cd "$(dirname "$0")" && scripts/install.sh; then
  printf '\nYou can close this window.\n'
else
  printf '\nThe install stopped before it finished (see the red text above). Fix that, then run this again.\n'
  exit 1
fi
