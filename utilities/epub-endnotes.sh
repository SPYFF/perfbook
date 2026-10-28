#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Derive an EPUB with plain linked endnotes from the popup-footnote EPUB
# built by utilities/runlwarp.sh (see utilities/epub-endnotes.pl).
# Usage: sh utilities/epub-endnotes.sh perfbook.epub perfbook-endnotes.epub

in=$1
out=$2
tmp=epub-tmp/endnotes
test -r "$in" && test -n "$out" || { echo "Usage: $0 <in.epub> <out.epub>" >&2; exit 2; }
for t in perl unzip zip; do
	command -v "$t" > /dev/null 2>&1 ||
		{ echo "Required tool not found: $t (prerequisites: #15 in FAQ-BUILD.txt)"; exit 2; }
done

rm -rf $tmp
mkdir -p $tmp || exit 2
trap 'rm -rf $tmp' EXIT
package=$tmp/package
unzip -q "$in" -d $package || exit 2
perl utilities/epub-endnotes.pl $package/EPUB/text/*.xhtml || exit 1
perl utilities/epub-links.pl check $package/EPUB/text/*.xhtml || exit 1

# Give this variant its own identifier so that reading systems keep
# separate positions and annotations for the two EPUBs.
old=`sed -n 's/.*<dc:identifier[^>]*>\(urn:uuid:[^<]*\)<.*/\1/p' $package/EPUB/content.opf`
test -n "$old" || { echo "----- no urn:uuid identifier in content.opf -----"; exit 1; }
new=urn:uuid:`OLD="$old" perl -MDigest::MD5=md5 -e 'my @b = unpack "C16", md5("$ENV{OLD} endnotes");
	$b[6] = $b[6] & 0x0f | 0x30; $b[8] = $b[8] & 0x3f | 0x80;
	printf "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", @b'`
OLD="$old" NEW="$new" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' $package/EPUB/content.opf $package/EPUB/toc.ncx || exit 2

cat >> $package/EPUB/styles/stylesheet1.css << 'EOF' || exit 2

/* Endnote variant (see utilities/epub-endnotes.pl). */
section.endnotes { margin-top: 2em; font-size: .9em; }
section.endnotes hr { width: 30%; margin: 0 0 1em 0; }
div.endnote p { margin: .5em 0; }
EOF

root=`pwd`
(
	cd $package || exit 2
	zip -X0 "$root/$tmp/out.epub" mimetype > /dev/null &&
	zip -Xr9D "$root/$tmp/out.epub" META-INF EPUB > /dev/null
) || exit 2
unzip -tq $tmp/out.epub > /dev/null || { echo "----- $tmp/out.epub is not a valid zip -----"; exit 1; }
if command -v epubcheck > /dev/null 2>&1; then
	epubcheck $tmp/out.epub || { echo "----- epubcheck failed -----"; exit 1; }
fi
mv -f $tmp/out.epub "$out" || exit 2
echo "$out built."
