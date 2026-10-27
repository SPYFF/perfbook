#!/usr/bin/env perl
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Index-based link repair and validation for the EPUB pipeline:
#   perl utilities/epub-links.pl reattach <xhtml-file> [...]
#   perl utilities/epub-links.pl check <html-file> [...]

use strict;
use warnings;
use File::Basename;

my $mode = shift @ARGV;
die "Usage: $0 reattach|check <file> [...]\n"
    unless defined $mode && $mode =~ /^(?:reattach|check)$/ && @ARGV;

my (%content, %ids_in, %owner);
for my $path (@ARGV) {
    open(my $fh, '<', $path) or die "$0: cannot read $path: $!\n";
    local $/;
    my $text = $content{$path} = <$fh>;
    close($fh);
    while ($text =~ m{(?:\sid="|LWRANCHOR:)([^"\s]+)}g) {
        $ids_in{$path}{$1} = 1;
        $owner{$1} //= $path;
    }
}

if ($mode eq 'reattach') {
    for my $path (@ARGV) {
        my $before = $content{$path};
        $content{$path} =~ s{href="#([^"]+)"}{
            ($ids_in{$path}{$1} || !exists $owner{$1})
                ? qq{href="#$1"}
                : 'href="' . basename($owner{$1}) . "#$1\"";
        }ge;
        next if $content{$path} eq $before;
        open(my $fh, '>', $path) or die "$0: cannot write $path: $!\n";
        print $fh $content{$path};
        close($fh) or die "$0: cannot write $path: $!\n";
    }
}

my (%checked, $bad);
for my $path (@ARGV) {
    my $dir = dirname($path);
    while ($content{$path} =~ m{href="([^"]+)"}g) {
        my $href = $1;
        next if $href =~ m{^[a-z][a-z0-9+.-]*:} || $href !~ m{^([^"#]*)#([^"]+)$};
        next if $checked{"$path\0$href"}++;
        my ($file, $frag) = ($1, $2);
        my $ok = length($file) ? $ids_in{"$dir/$file"}{$frag}
               : $mode eq 'check' ? exists $owner{$frag}
               : $ids_in{$path}{$frag};
        unless ($ok) {
            print STDERR "----- unresolved link: $path -> $href -----\n";
            $bad = 1;
        }
    }
}
exit($bad ? 1 : 0);
