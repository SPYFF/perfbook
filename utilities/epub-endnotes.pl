#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Turn the EPUB 3 popup footnotes produced by utilities/epub-footnotes.pl
# into plain hyperlinked notes, for reading systems that lack popup
# footnote support or that typeset footnotes at the bottom of the page:
#   - footnote asides become <div class="endnote"> blocks collected at the
#     end of their chapter file, still linked to and from their references;
#   - Quick Quiz answer asides become <div class="quiz-answer"> blocks in
#     place, so Appendix E reads like the print edition;
#   - epub:type/role footnote semantics are dropped from links.
# All conversions are asserted before writing any files.
#   perl utilities/epub-endnotes.pl <xhtml-file> [...]

use strict;
use warnings;

die "Usage: $0 <xhtml-file> [...]\n" unless @ARGV;

my (%out, $n_notes, $n_quiz);
for my $path (@ARGV) {
    open(my $fh, '<', $path) or die "$0: cannot read $path: $!\n";
    local $/;
    my $html = <$fh>;
    close($fh);
    my $orig = $html;

    # Footnote asides hold a single paragraph and never nest, so the first
    # </aside> closes each one.  Extract them before touching quiz answers,
    # which may contain footnotes.
    my @notes;
    $html =~ s{<aside\ id="(footnote-[^"]+)"\ epub:type="footnote"\ role="doc-footnote">(.*?)</aside>\n?}{
        push @notes, qq{<div class="endnote" id="$1">$2</div>};
        '';
    }gsex;
    if (@notes) {
        my $block = qq{<section class="endnotes">\n<hr />\n} . join("\n", @notes) . "\n</section>\n";
        $html =~ s{</body>}{$block</body>} or die "$0: $path: no </body>\n";
    }

    my $nq = ($html =~ s{<aside\ class="quiz-answer"\ id="([^"]+)"\ epub:type="footnote"\ role="doc-footnote">}
                        {<div class="quiz-answer" id="$1">}gx);
    my $nclose = ($html =~ s{</aside>}{</div>}g);
    die "$0: $path: $nq quiz answers but $nclose </aside> tags\n" unless $nq == $nclose;
    die "$0: $path: unconverted <aside> remains\n" if $html =~ /<aside\b/;

    $html =~ s{\s+epub:type="(?:noteref|backlink)"}{}g;
    $html =~ s{\s+role="doc-(?:noteref|backlink)"}{}g;
    die "$0: $path: footnote semantics remain\n"
        if $html =~ /epub:type="(?:noteref|footnote|backlink)"|role="doc-(?:noteref|footnote|backlink)"/;

    $n_notes += @notes;
    $n_quiz += $nq;
    $out{$path} = $html unless $html eq $orig;
}
die "$0: no footnotes converted\n" unless $n_notes;
die "$0: no quiz answers converted\n" unless $n_quiz;

for my $path (sort keys %out) {
    open(my $oh, '>', $path) or die "$0: cannot write $path: $!\n";
    print $oh $out{$path};
    close($oh) or die "$0: cannot write $path: $!\n";
}
print "endnotes: $n_notes footnotes moved to chapter ends, $n_quiz quiz answers inlined\n";
