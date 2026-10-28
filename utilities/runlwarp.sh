#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a reflowable EPUB (or browsable HTML) from perfbook-epub.tex.
# Usage: sh utilities/runlwarp.sh perfbook-epub [epub|html]
#
# Copyright (C) Fejes Ferenc, 2026
# Author: Fejes Ferenc <ferenc.fejes@ericsson.com>

: ${LATEX:=pdflatex}
: ${MAXPASS:=6}
: ${PANDOC:=pandoc}
base=`echo $1 | sed -e 's/\.tex$//'`
html=${base}_html
tmp=epub-tmp
mode=${2:-epub}
case "$mode" in
  epub|html) ;;
  *) echo "Unknown mode '$mode' (want epub|html)" >&2; exit 2 ;;
esac
title="Is Parallel Programming Hard, And, If So, What Can You Do About It?"
cover=cartoons/r-2014-Book-cover-front.png

tools="$LATEX bibtex lwarpmk pdftocairo unzip zip"
test "$mode" = epub && tools="$tools $PANDOC"
for t in $tools; do
	command -v "$t" > /dev/null 2>&1 ||
		{ echo "Required tool not found: $t (prerequisites: #15 in FAQ-BUILD.txt)"; exit 2; }
done
lwarp_version=`lwarpmk --version 2>/dev/null | sed -n 's/.*v\([0-9][0-9.]*\).*/\1/p'`
if test -z "$lwarp_version" || ! awk -v v="$lwarp_version" 'BEGIN { exit !(v >= 0.921) }'; then
	echo "lwarp >= 0.921 is required (found ${lwarp_version:-unknown})" >&2
	exit 2
fi

if test ! -r $html.html; then
	rm -f $html.aux $html.bbl $html.toc $html.lof $html.lot $html.out
fi

run_latex () {   # $1 = jobname, $2 = label, $3 = extra flags
	echo "$LATEX $3 for $1 # $2"
	$LATEX $3 -interaction=nonstopmode $1 > /dev/null 2>&1 < /dev/null || {
		echo "----- !!! LaTeX failed for $1 !!! -----"; exit 2; }
	test -r $1.log || { echo "----- no log produced for $1 -----"; exit 2; }
	if grep -q '^! ' $1.log ; then
		echo "----- !!! TeX error in $1.log !!! -----"; grep -A 6 '^! ' $1.log | head -60; exit 2
	fi
}

check () {   # $1 = label, $2 = expected, $3 = actual
	[ "$2" -eq "$3" ] || { echo "----- $1: expected $2, found $3 -----"; exit 1; }
}
check_positive () {
	check "$@"
	[ "$2" -gt 0 ] || { echo "----- $1: count is zero -----"; exit 1; }
}
wait_limages () {
	while find $base-images -name '*.pdf' -o -size 0 2>/dev/null | grep -q .; do sleep 0.1; done
}

# 1. Print pass: lwarp writes ${html}.tex and lwarpmk.conf.
run_latex $base "lwarp wrapper generation" -draftmode
test -r $html.tex || { echo "lwarp did not write $html.tex"; exit 2; }

# 2. HTML passes until cross-references and lwarp's image list stabilize.
i=0
draft=-draftmode
test -r $html.bbl && draft=
while :; do
	i=`expr $i + 1`
	[ $i -ge 3 ] && draft=
	run_latex $html "HTML pass $i" $draft
	if [ $i -eq 1 ]; then
		(if grep -q '\\bibdata' $html.aux; then
			bibtex $html > /dev/null &&
			sed -i 's/\bpage \([0-9]*\)–/pages \1--/g; s/\\href {{\([^}]*\)}}/\\href {\1}/g' $html.bbl
		fi) &
		bib_pid=$!
		(if test -r $html.acn; then
			makeglossaries $html > /dev/null 2>&1 ||
			{ test -r $html.ist && makeindex -s $html.ist -t $html.alg -o $html.acr $html.acn > /dev/null 2>&1; }
		fi) &
		gls_pid=$!
		wait $bib_pid || { echo "----- bibtex failed for $html -----"; exit 2; }
		wait $gls_pid || { echo "----- glossary generation failed for $html -----"; exit 2; }
	fi
	if grep -q 'Rerun to get\|Label(s) may have changed\|There were undefined' $html.log; then
		if [ $i -ge $MAXPASS ]; then echo "Still unstable after $MAXPASS passes, giving up."; exit 1; fi
		continue
	fi
	if tail -1 $base-images.txt 2>/dev/null | grep -q '|end|end|end|'; then break; fi
	if [ $i -ge $MAXPASS ]; then echo "Still unstable after $MAXPASS passes, giving up."; exit 1; fi
done
if grep -q 'LaTeX Warning: Reference\|LaTeX Warning: Citation' $html.log; then
	grep -A 2 'LaTeX Warning: Reference\|LaTeX Warning: Citation' $html.log | head -40
	echo "----- Undefined references/citations remain in $html.log -----"; exit 1
fi

# 3. Render math SVGs (backgrounded by lwarpmk) while splitting HTML chapters.
find $base-images -name '*.pdf' -o -size 0 -delete 2>/dev/null
lwarpmk limages   -p $base > $tmp-limages.log   2>&1 || { tail -20 $tmp-limages.log;   exit 2; }
lwarpmk pdftohtml -p $base > $tmp-pdftohtml.log 2>&1 || { tail -20 $tmp-pdftohtml.log; exit 2; }

if [ "$mode" = html ]; then
	wait_limages
	echo "HTML ready: $html.html (split chapters ${base}-*.html, images ${base}-images/)."
	exit 0
fi

# 4. Book order + per-chapter HTML fixups.
rm -rf $tmp; mkdir $tmp
order=`grep -o '<!--|Start file|[^|]*|' $html.html | cut -d'|' -f3 | awk '!seen[$0]++'`
perl utilities/epub-fixhtml.pl $tmp $order || exit 2
files=`echo "$order" | sed -e "s|^|$tmp/|"`
wait_limages

# 5. Package with Pandoc, then apply post-Pandoc XHTML repairs and repack once.
$PANDOC -f html-native_divs --shift-heading-level-by=-2 \
	--split-level=1 --toc --toc-depth=3 \
	--metadata title="$title" --metadata author="Paul E. McKenney" --metadata lang=en-US \
	--epub-cover-image=$cover --resource-path=epub-figs:. \
	-o $base.epub $files || exit 2

package=$tmp/package
rm -rf "$package"
unzip -q $base.epub -d "$package" || exit 2
perl -pi -e 's/LWRANCHOR:([^\s<\\\\]+)/<span id="$1"><\/span>/g' "$package"/EPUB/text/*.xhtml || exit 2
perl utilities/epub-fixhtml.pl --post "$package" || exit 2
check "listing preservation" "`grep -rho '<pre' $tmp/*.html | wc -l`" "`grep -rho '<pre' "$package"/EPUB/text/*.xhtml | wc -l`"
check "line-anchor preservation" "`grep -rho 'LWRANCHOR:ln:' $tmp/*.html | wc -l`" "`grep -rho 'id="ln:' "$package"/EPUB/text/*.xhtml | wc -l`"
check_positive "display equation formatting" "`grep -rho 'class=\"displaymathnumbered\"' $tmp/*.html | wc -l`" "`grep -rho '<table class=\"displaymath\">' "$package"/EPUB/text/*.xhtml | wc -l`"

perl utilities/epub-footnotes.pl "$package"/EPUB/text/*.xhtml || exit 2
expected_fn=`perl -0777 -ne '$n += () = /<p[^>]*>\s*<sup>\d+<\/sup>/g; END { print $n+0 }' $tmp/*.html`
check "footnote preservation" "$expected_fn" "`grep -rho '<aside[^>]*id="footnote-' "$package"/EPUB/text/*.xhtml | wc -l`"
expected_qq=`grep -rho 'id="QQA\.' $tmp/*.html | wc -l`
check_positive "quiz answer preservation" "$expected_qq" "`grep -rho 'id="QQA\.' "$package"/EPUB/text/*.xhtml | wc -l`"
check "quiz answers on asides" "$expected_qq" "`grep -rho '<aside[^>]*id="QQA\.' "$package"/EPUB/text/*.xhtml | wc -l`"

epub_css="$package/EPUB/styles/stylesheet1.css"
test -r "$epub_css" || { echo "----- missing packaged stylesheet -----"; exit 1; }
cat >> "$epub_css" << 'EOF' || exit 2

/* Chapter/section epigraphs (see reflow.ltx): right-flushed narrow box
   with ruled small-caps attribution, like the print edition. */
figure.epigraph { margin: 1.5em 0 1.5em auto; max-width: 27em; font-size: .85em; text-align: left; }
figure.epigraph p { margin: 0; padding: .25ex 0; text-indent: 0; }
figure.epigraph figcaption { text-align: right; border-top: 1px solid #A0A0A0; font-variant: small-caps; font-size: .92em; margin-top: .5ex; }

/* Figures: center all images and captions, cap width at 85%, and keep
   captions attached to their images across page breaks. */
figure.figure { text-align: center; margin: 1.2em auto; page-break-inside: avoid; break-inside: avoid; }
figure.figure p { margin: 0 0 .4em 0; text-indent: 0; text-align: center; }
figure.figure img.inlineimage { display: inline-block; margin: 0 auto; max-width: 85%; height: auto; }

/* Listings and tables: use smaller relative font sizes to minimize line
   wraps while scaling with the reader's user-configured font size, and
   avoid scroll boxes (WebKit-based readers like Foliate paint only the
   first page of an overflow:auto box split across pages). */
figure.listing, figure.table { margin: 1em 0; }
figure.figure figcaption, figure.figure span.figurecaption,
figure.listing figcaption, figure.listing span.figurecaption,
figure.table figcaption, figure.table span.figurecaption {
  display: block; text-align: center; font-size: .9em; margin: .35em 0;
  page-break-before: avoid; break-before: avoid;
}
figure.listing.ruled { border-top: 1px solid #A0A0A0; border-bottom: 1px solid #A0A0A0; padding: .35em 0; }
figure.listing pre { margin: .35em 0; }
figure.listing table td { font-family: Menlo, Monaco, 'Lucida Console', Consolas, monospace; }
pre, table { overflow: visible; line-height: 1.25; }
pre { font-size: .75em; }
pre code { font-size: 100%; overflow-wrap: anywhere; }
kbd { font-family: Menlo, Monaco, 'Lucida Console', Consolas, monospace; font-size: 85%; }
table { display: table; width: 100%; font-size: .8em; }
th, td { overflow-wrap: break-word; padding: .2em .35em; text-align: left; }
td.tdc, td.tdcenter { text-align: center; }
td.tdr, td.tdright { text-align: right; }
tr.hline td, tr.tbrule td { border-top: 1px solid #808080; }
tbody tr.tbrule:first-child td { border-top: none; }
td.tdrule, td.tdrulel, td.tdruler, td.tdrulelr { border-top: 1px solid #A0A0A0; }
td.tvertbarl { border-left: 1px solid #808080; }
td.tvertbarr { border-right: 1px solid #808080; }
td.tvertbarldouble { border-left: 3px double #808080; }
td.tvertbarrdouble { border-right: 3px double #808080; }
th p, td p { margin: 0; text-align: inherit; line-height: inherit; }

/* Numbered display equations: center math expression and flush equation
   number to the right margin while scaling math with the body font. */
table.displaymath { width: 100%; margin: .8em 0; border: none; border-collapse: collapse; font-size: 1em; page-break-inside: avoid; break-inside: avoid; }
table.displaymath tbody, table.displaymath tr, table.displaymath td { border: none; padding: 0; vertical-align: middle; }
table.displaymath td.eqpad { width: 12%; }
table.displaymath td.eqbody { width: 76%; text-align: center; }
table.displaymath td.eqbody img.lateximage { max-width: 100%; height: auto; vertical-align: middle; }
table.displaymath td.eqnum { width: 12%; text-align: right; white-space: nowrap; }

/* KOReader: never typeset Quick Quiz answers as in-page footnotes (they
   would spoil the answer below the question); tap-to-popup still works
   because detection uses the epub:type/role attributes. */
aside.quiz-answer { -cr-hint: none !important; }
EOF
check_positive "epigraph preservation" "`grep -rho '<figure class="epigraph"' $tmp/*.html | wc -l`" "`grep -rho '<figure class="epigraph"' "$package"/EPUB/text/*.xhtml | wc -l`"

perl utilities/epub-links.pl reattach "$package"/EPUB/text/*.xhtml || exit 1
post=$base-post.epub
root=`pwd`
rm -f "$post"
(
	cd "$package" || exit 2
	zip -X0 "$root/$post" mimetype >/dev/null &&
	zip -Xr9D "$root/$post" META-INF EPUB >/dev/null
) || exit 2
mv -f "$post" $base.epub || exit 2

# 6. Validation gates.
unzip -tq $base.epub > /dev/null || { echo "$base.epub is not a valid zip"; exit 1; }
check "unresolved references in HTML" 0 "`cat $tmp/*.html | grep -o 'href="#??"' | wc -l`"
outside=`perl -0777 -ne 'while (/<a\s[^>]*?href="([^"#][^"]*)"/g) { print "$1\n" unless $1 =~ m{^(?:https?|ftp|git|mailto):} }' $tmp/*.html`
[ -z "$outside" ] || {
	echo "$outside" | sort | uniq -c | head -20
	echo "----- links to files outside the EPUB remain in HTML, see $tmp/ -----"; exit 1
}
n=`perl -0777 -ne 'while (m{<pre[^>]*>(?:<code>)?(.*?)</pre>}sg) { my @l = grep { /\S/ } split /\n/, $1; $n++ if @l > 1 && $l[0] !~ /^\s*[A-Z]?\d+\s/ && $l[1] =~ /^\s*[A-Z]?1\s*(?:<a id="[^"]*"><\/a>(?:LWRANCHOR:\S+)?\s*)?$/ } END { print $n+0 }' $tmp/*.html`
check "listing first line numbers" 0 "$n"
perl utilities/epub-links.pl check $tmp/*.html || exit 1
check "page-number phrases" 0 "`cat $tmp/*.html | grep -c 'page\(&nbsp;\| \)for'`"
if command -v epubcheck > /dev/null 2>&1; then
	epubcheck $base.epub || { echo "----- epubcheck failed -----"; exit 1; }
fi
test -s $base.epub || { echo "----- no EPUB candidate produced -----"; exit 1; }
mv -f $base.epub perfbook.epub || { echo "----- failed to publish EPUB -----"; exit 1; }
echo "perfbook.epub built ($i HTML passes)."
