#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Apply packaging-level lwarp-HTML-to-EPUB fixups to each chapter file:
#   perl utilities/epub-fixhtml.pl <outdir> <in.html> [...]

use strict;
use warnings;
use File::Basename;
use File::Spec;

die "Usage: $0 <outdir> <in.html> [...]\n" unless @ARGV >= 2;
my $outdir = shift @ARGV;

for my $in (@ARGV) {
    (my $id = basename($in)) =~ s/\.html$//;
    open(my $fh, '<', $in) or die "$0: cannot read $in: $!\n";
    local $/;
    my $html = <$fh>;
    close($fh);

    my @lines = split(/\n/, $html, -1);
    for (@lines) {
        # 1. Convert split-file links to same-document fragments and add file anchor.
        s/href="perfbook-epub[^"#]*\.html#/href="#/g;
        s/href="(perfbook-epub[^"#]*)\.html"/href="#$1"/g;
        s|<body([^>]*)>|<body$1><a id="$id"></a>|;
        # 2. Replace spaces and URL punctuation in XML IDs and fragment hrefs.
        s{(id=")([^"]*)"}{my ($p, $x) = ($1, $2); $x =~ s/\s+|(?:%20)+|[?#]/-/g; "$p$x\""}ge;
        s{(href="#)([^"]*)"}{my ($p, $x) = ($1, $2); $x =~ s/\s+|[?#]/-/g; "$p$x\""}ge;
        # 3. Drop lwarp role="math"/"note" and external target attributes.
        s{\s+role="(?:math|note)"}{}g;
        s{\s*target="[^"]*"}{}g;
    }
    $html = join("\n", @lines);

    # 4. Rewrite lwarp inline-code spans as <code> for Pandoc.
    $html =~ s|<span\s*class="inlineprogramlisting"\s*>\s*</span>||g;
    $html =~ s|<span\s*class="inlineprogramlisting"\s*>\s*([^<]*[^<\s])\s*</span>|<code>$1</code>|g;

    # 5. Wrap <pre> contents in <code> for Pandoc and protect line anchors.
    $html =~ s{<pre([^>]*)>}{<pre$1><code>}g;
    $html =~ s{</pre>}{</code></pre>}g;
    $html =~ s{<(?:span|a) id="(ln:[^"]+)"></(?:span|a)>}{my $x = $1; $x =~ s/\s+|[?#]/-/g; $x =~ s/\\$//; qq(<a id="$x"></a>LWRANCHOR:$x)}ge;

    # 6. Drop empty headings and convert epigraph divs to <figure class="epigraph">.
    $html =~ s{<h[1-6][^>]*>\s*</h[1-6]>}{}g;
    $html =~ s{<div\s+class="epigraph">\s*<div\s+class="qitem">\s*<p>(.*?)</p>\s*<div\s+class="epigraphsource">\s*<p>(.*?)</p>\s*</div>\s*</div>\s*</div>}
              {<figure class="epigraph">\n<p>$1</p>\n<figcaption>$2</figcaption>\n</figure>}gs;

    my $out = File::Spec->catfile($outdir, basename($in));
    open(my $oh, '>', $out) or die "$0: cannot write $out: $!\n";
    print $oh $html;
    close($oh) or die "$0: cannot write $out: $!\n";
}
