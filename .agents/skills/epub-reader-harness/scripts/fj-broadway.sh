#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Inside the GNOME runtime sandbox: start a private GTK Broadway display
# (headless, loopback only) and run the given python3 script on it.
#   fj-broadway.sh <display-number> <broadway-http-port> <script.py> [args...]
# The Broadway viewer (http://127.0.0.1:<port>/) shows the live window in
# any browser, for a human peeking at a background session.
n=$1; port=$2; shift 2
sock=$XDG_RUNTIME_DIR/broadway$n.socket
rm -f "$sock"	# a stale socket from a killed session blocks startup
gtk4-broadwayd -a 127.0.0.1 -p "$port" ":$n" &
bw=$!
trap 'kill $bw 2> /dev/null; rm -f "$sock"' EXIT INT TERM
i=0
while [ ! -S "$sock" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
GDK_BACKEND=broadway BROADWAY_DISPLAY=:$n python3 "$@"
