#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Convert lwarp/pandoc footnote markup and Quick Quiz answers to native
# EPUB 3 footnotes (epub:type="noteref"/"footnote" with backlinks).
# Phase 1 converts plain numeric footnotes; Phase 2 converts Quick Quiz
# [Answer] links and Appendix E answers, tagging the latter with class
# "quiz-answer" so the stylesheet can keep them out of in-page footnote
# areas. All counts are asserted before writing any files.

use strict;
use warnings;

die "Usage: $0 <xhtml-file> [...]\n" unless @ARGV;

my (%html, %dirty, $answers_file);
for my $path (@ARGV) {
    open(my $fh, '<', $path) or die "$0: cannot read $path: $!\n";
    local $/;
    $html{$path} = <$fh>;
    close($fh);
}

# Phase 1: plain numeric footnotes.
for my $path (@ARGV) {
    my %is_body;
    $is_body{$1} = 1 while $html{$path} =~ m{<p[^>]*>\s*<sup>(\d+)</sup>}g;
    next unless %is_body;

    my ($bodies, $refs, %ref_seen) = (0, 0);
    $html{$path} =~ s{
        <p([^>]*)>\s*<sup>(\d+)</sup>\s*(?:&(nbsp|\#160|\#xA0);|\x{c2}\x{a0}|\x{a0})?\s*(.*?)</p>
    }{
        my ($attrs, $n, $text) = ($1, $2, $4);
        exists $is_body{$n} ? do {
            $bodies++;
            qq{<aside id="footnote-$n" epub:type="footnote" role="doc-footnote"><p$attrs>} .
            qq{<a href="#noteref-$n" epub:type="backlink" role="doc-backlink" aria-label="Back to note reference $n">$n.</a> } .
            qq{$text</p></aside>};
        } : $&;
    }gexs;

    $html{$path} =~ s{<sup>(\d+)</sup>}{
        my $n = $1;
        exists $is_body{$n} ? do {
            my $s = $ref_seen{$n}++;
            my $id = $s ? "noteref-$n-" . ($s + 1) : "noteref-$n";
            $refs++;
            qq{<a id="$id" epub:type="noteref" role="doc-noteref" href="#footnote-$n"><sup>$n</sup></a>};
        } : $&;
    }gex;

    if ($bodies) {
        $dirty{$path} = 1;
        print "$path: footnotes $bodies bodies, $refs refs -> epub:type noteref/footnote\n";
    }
}

# Phase 2: Quick Quiz answers.
for my $path (@ARGV) {
    if ($html{$path} =~ m{<span id="QQA\.[^"]+"></span>} && $html{$path} =~ m{<p><strong>Answer:</strong>}) {
        die "$0: multiple quiz answers files ($answers_file, $path)\n" if defined $answers_file;
        $answers_file = $path;
    }
}
die "$0: no quiz answers file found\n" unless defined $answers_file;

my @nums = ($html{$answers_file} =~ m{<span id="QQA\.([^"]+)"></span>}g);
die "$0: no quiz answers in $answers_file\n" unless @nums;

my ($n_asides, $n_noterefs) = (0, 0);
$html{$answers_file} =~ s{
    <p><strong>Answer:</strong>(.*?)(?=<p><a\ href="[^"]*\#QQ\.[^"]*"><strong>Quick\ Quiz|</section>|\z)
}{
    my $rest = $1;
    my $n = $nums[$n_asides++] // die "$0: more answers than questions in $answers_file\n";
    die "$0: answer $n leaks a question marker\n" if $rest =~ m{id="QQA\.};
    my $nback = ($rest =~ s{(<a\ href="[^"]*\#QQE\.[^"]*")>}{$1 epub:type="backlink" role="doc-backlink">}g);
    die "$0: answer $n has $nback end-links (want 1)\n" unless $nback == 1;
    qq{<aside class="quiz-answer" id="QQA.$n" epub:type="footnote" role="doc-footnote"><p><strong>Answer:</strong>$rest</aside>};
}gexs;

die "$0: paired $n_asides answers with " . scalar(@nums) . " questions\n" unless $n_asides == @nums;
my $nspans = ($html{$answers_file} =~ s{<span id="QQA\.[^"]+"></span>}{}g);
die "$0: $nspans answer spans, want $n_asides\n" unless $nspans == $n_asides;
$dirty{$answers_file} = 1;
print "$answers_file: quiz answers $n_asides bodies -> epub:type footnote\n";

for my $path (@ARGV) {
    next if $path eq $answers_file;
    my $n = ($html{$path} =~ s{
        <a\ (href="[^"]*\#QQA\.[^"]*")><strong>\[Answer\]</strong></a>
    }{<a $1 epub:type="noteref" role="doc-noteref"><strong>[Answer]</strong></a>}gx);
    next unless $n;
    $dirty{$path} = 1;
    $n_noterefs += $n;
    print "$path: quiz noterefs $n\n";
}
die "$0: $n_noterefs references, want $n_asides answers\n" unless $n_noterefs == $n_asides;

for my $path (@ARGV) {
    next unless $dirty{$path};
    open(my $oh, '>', $path) or die "$0: cannot write $path: $!\n";
    print $oh $html{$path};
    close($oh) or die "$0: cannot write $path: $!\n";
}
print "quiz total: $n_asides answers, $n_noterefs references\n";
