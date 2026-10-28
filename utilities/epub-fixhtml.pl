#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Apply packaging-level lwarp-HTML-to-EPUB fixups to each chapter file,
# or post-Pandoc XHTML/SVG figure normalization with --post:
#   perl utilities/epub-fixhtml.pl <outdir> <in.html> [...]
#   perl utilities/epub-fixhtml.pl --post <package-dir>

use strict;
use warnings;
use File::Basename;
use File::Spec;

if (@ARGV == 2 && $ARGV[0] eq '--post') {
    my $pkg = $ARGV[1];
    my @xhtmls = glob("$pkg/EPUB/text/*.xhtml");
    my (%rot90, %fig_svg, %aspect);

    for my $xf (@xhtmls) {
        open(my $fh, '<', $xf) or die "$0: cannot read $xf: $!\n";
        local $/;
        my $x = <$fh>;
        close($fh);

        # Unwrap CSS -90deg rotated image spans (e.g. Figure 14.3) and mark SVG for rotation.
        $x =~ s{<span\s+style="[^"]*transform:rotate\(-90deg\)[^"]*">\s*(<img\b[^>]*\bsrc="\.\./media/([^"]+)"[^>]*>)\s*</span>}{
            $rot90{$2} = 1;
            $1
        }gse;

        # Normalize \begin{picture} figures (e.g. Figure C.2) to inlineimage.
        $x =~ s{(<figure\b[^>]*\bclass="figure\b[^>]*>(?:(?!</figure>).)*?)(<img\b[^>]*\bclass=")lateximage("[^>]*\balt="\(picture\)"[^>]*>)}{
            my ($pre, $a, $b) = ($1, $2, $3);
            $b =~ s/\bstyle=""/style="width:60%;"/;
            "$pre${a}inlineimage$b"
        }gse;

        while ($x =~ m{<img\b[^>]*\bsrc="\.\./media/([^"]+\.svg)"[^>]*\bclass="inlineimage"}g) {
            $fig_svg{$1} = 1;
        }

        open(my $oh, '>', $xf) or die "$0: cannot write $xf: $!\n";
        print $oh $x;
        close($oh) or die "$0: cannot write $xf: $!\n";
    }

    for my $sf (glob("$pkg/EPUB/media/*.svg")) {
        my $name = basename($sf);
        open(my $fh, '<', $sf) or die "$0: cannot read $sf: $!\n";
        local $/;
        my $svg = <$fh>;
        close($fh);
        my $orig = $svg;

        # Rotate SVGs that were wrapped in \rotatebox{90} so all readers render them upright.
        if ($rot90{$name}) {
            $svg =~ s{(<svg\b[^>]*?\swidth=")([0-9.]+)(pt"\s+height=")([0-9.]+)(pt"\s+viewBox="0 0 )([0-9.]+)\s+([0-9.]+)("[^>]*>)(.*)(</svg>)}{
                my ($p1, $w, $p2, $h, $p3, $vw, $vh, $p4, $body, $p5) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);
                "$p1$h$p2$w$p3$vh $vw$p4\n<g transform=\"translate(0,$vw) rotate(-90)\">$body</g>\n$p5"
            }se;
        }

        # Add viewBox="0 0 W H" to Inkscape SVGs that only declare numeric width/height,
        # and normalize figure SVG intrinsic dimensions to 800pt wide for crengine (KOReader).
        $svg =~ s{<svg\b([^>]*)>}{
            my $attrs = $1;
            my ($w, $wu) = $attrs =~ /\bwidth="([0-9.]+)(pt|px)?"/;
            my ($h, $hu) = $attrs =~ /\bheight="([0-9.]+)(pt|px)?"/;
            if (defined $w && defined $h && $w > 0 && $h > 0) {
                if ($attrs !~ /\bviewBox="/) {
                    $attrs .= qq( viewBox="0 0 $w $h");
                }
                $aspect{$name} = $h / $w;
                if ($fig_svg{$name}) {
                    my $tw = 800;
                    my $th = int($tw * $h / $w + 0.5);
                    $attrs =~ s/\bwidth="[0-9.]+(?:pt|px)?"/width="${tw}pt"/;
                    $attrs =~ s/\bheight="[0-9.]+(?:pt|px)?"/height="${th}pt"/;
                }
            }
            "<svg$attrs>"
        }se;

        if ($svg ne $orig) {
            open(my $oh, '>', $sf) or die "$0: cannot write $sf: $!\n";
            print $oh $svg;
            close($oh) or die "$0: cannot write $sf: $!\n";
        }
    }

    # Cap tall portrait figures so their rendered height never exceeds ~65% of column width.
    for my $xf (@xhtmls) {
        open(my $fh, '<', $xf) or die "$0: cannot read $xf: $!\n";
        local $/;
        my $x = <$fh>;
        close($fh);
        my $orig = $x;

        $x =~ s{(<img\b[^>]*\bsrc="\.\./media/([^"]+)"[^>]*\bclass="inlineimage"[^>]*\bstyle=")\s*width:(\d+)%;\s*(")}{
            my ($pre, $name, $pct, $post) = ($1, $2, $3, $4);
            my $r = $aspect{$name} // 1;
            if ($r > 1.15) {
                my $cap = int(65 / $r + 0.5);
                $cap = 25 if $cap < 25;
                $pct = $cap if $pct > $cap;
            }
            "${pre}width:${pct}%;$post"
        }gse;

        if ($x ne $orig) {
            open(my $oh, '>', $xf) or die "$0: cannot write $xf: $!\n";
            print $oh $x;
            close($oh) or die "$0: cannot write $xf: $!\n";
        }
    }
    exit 0;
}

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

    # 5. Merge consecutive fancyvrb blocks in multi-snippet listings, then wrap
    #    <pre> contents in <code> for Pandoc and protect line anchors.
    $html =~ s{(<pre\s+class="verbatim">.*?\n)</pre>\s*</div>\s*<div\s+class="fancyvrb">\s*<pre\s+class="verbatim">\n?(.*?)(?=</pre>)}{
        my ($p1, $p2) = ($1, $2);
        $p2 =~ s/^(  \d+) (?=\S)/$1   /gm;
        "$p1$p2"
    }gse;
    $html =~ s{(<pre\b[^>]*>)(.*?)(</pre>)}{
        my ($o, $b, $c) = ($1, $2, $3);
        $b =~ s{<(?!(?:/?(?:a|span|kbd|em|i|b|sub|sup)\b))([^>]*)>}{&lt;$1&gt;}g;
        "$o<code>$b</code>$c"
    }gse;
    $html =~ s{<(?:span|a) id="(ln:[^"]+)"></(?:span|a)>}{my $x = $1; $x =~ s/\s+|[?#]/-/g; $x =~ s/\\$//; qq(<a id="$x"></a>LWRANCHOR:$x)}ge;

    # 6. Drop empty headings/bottomrule rows, hoist \cellcolor onto <td>, and
    #    convert epigraph divs to <figure class="epigraph">.
    $html =~ s{<h[1-6][^>]*>\s*</h[1-6]>}{}g;
    $html =~ s{<tr\s+class="tbrule"\s+aria-hidden="true">\s*(?:<td[^>]*>\s*</td>\s*)*</tr>}{}gs;
    $html =~ s{<td\b([^>]*)>(.*?)</td>}{
        my ($attrs, $body) = ($1, $2);
        if ($body =~ s{<div\s+class="cellcolor"\s+style="background:\s*(#[0-9A-Fa-f]+)\s*"\s*>(.*?)</div>}{$2}s) {
            my $col = uc($1);
            if ($col eq '#FFFFFF') {
                $attrs =~ s/\s*\bstyle="background:\s*#E5E5E5\s*;?\s*"//i;
            } else {
                $attrs =~ s/\bstyle="([^"]*)"/style="$1; background:$col"/
                    or $attrs .= qq( style="background:$col");
                $body = '&#160;' if $body !~ /\S/;
            }
        }
        "<td$attrs>$body</td>"
    }gse;
    $html =~ s{<div\s+class="epigraph">\s*<div\s+class="qitem">\s*<p>(.*?)</p>\s*<div\s+class="epigraphsource">\s*<p>(.*?)</p>\s*</div>\s*</div>\s*</div>}
              {<figure class="epigraph">\n<p>$1</p>\n<figcaption>$2</figcaption>\n</figure>}gs;

    # 7. Convert lwarp caption divs into <figcaption> (or <span class="figurecaption">
    #    for multi-caption figures) so Pandoc (-f html-native_divs) preserves them.
    $html =~ s{(<figure\b[^>]*\bclass="(?:figure|table|listing)\b[^>]*>)(.*?)(</figure>)}{
        my ($open, $body, $close) = ($1, $2, $3);
        my $ncap = () = $body =~ /<div\s+class="figurecaption">/g;
        my $otag = ($ncap == 1) ? '<figcaption>' : '<p><span class="figurecaption">';
        my $ctag = ($ncap == 1) ? '</figcaption>' : '</span></p>';
        $body =~ s|<div\s+class="figurecaption">\s*(.*?)\s*</div>((?:\s*<a\s+id="[^"]*"></a>)*)|$otag$1$2$ctag|gs;
        "$open$body$close"
    }gse;

    my $out = File::Spec->catfile($outdir, basename($in));
    open(my $oh, '>', $out) or die "$0: cannot write $out: $!\n";
    print $oh $html;
    close($oh) or die "$0: cannot write $out: $!\n";
}
