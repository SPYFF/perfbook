#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Write a KOReader settings.reader.lua for a throwaway harness profile.
#   ko-settings.py <out.lua> [key=value ...]
# Values are Lua literals (true, 18, "x", {a=1}); a dotted key sets one
# field of a table setting, e.g. style_tweaks.footnote-inpage_epub=nil
# (nil removes it).  The defaults give a deterministic profile: no
# quickstart, no statistics plugin, footnote popups on, KOReader's default
# global style tweaks.

import re
import sys

# Table settings are dicts of field -> Lua literal; scalars are literals.
DEFAULTS = {
    'quickstart_shown_version': '999999999',
    'footnote_link_in_popup': 'true',
    'plugins_disabled': {'statistics': 'true'},
    'style_tweaks': {'footnote-inpage_epub': 'true', 'footnote-inpage_fb2': 'true',
                     'inpage_footnote_font-size_smaller': 'true'},
    'color_rendering': 'true',
}


def key(k):
    return k if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) else '["%s"]' % k


def literal(v):
    if isinstance(v, dict):
        return '{' + ', '.join('%s = %s' % (key(f), x) for f, x in v.items() if x != 'nil') + '}'
    return v


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: ko-settings.py <out.lua> [key=value ...]')
    settings = {k: (dict(v) if isinstance(v, dict) else v) for k, v in DEFAULTS.items()}
    for a in sys.argv[2:]:
        if '=' not in a:
            sys.exit('ko-settings.py: expected key=value, got %r' % a)
        k, v = a.split('=', 1)
        if '.' in k:
            t, f = k.split('.', 1)
            cur = settings.setdefault(t, {})
            if not isinstance(cur, dict):
                sys.exit('ko-settings.py: %s is not a table setting' % t)
            cur[f] = v
        else:
            settings[k] = v
    with open(sys.argv[1], 'w') as fh:
        fh.write('-- harness profile, written by ko-settings.py\nreturn {\n')
        for k, v in settings.items():
            if v != 'nil':
                fh.write('    %s = %s,\n' % (key(k), literal(v)))
        fh.write('}\n')


main()
