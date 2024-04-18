#!/bin/zsh

# set -ex

cd "$(dirname "$0")"
cd "$(realpath "$PWD")"

cd "$PWD/GCDWebUploader/GCDWebUploader"
outfile="$PWD/GCDWebUploader_bundle.m"

echo "#import <Foundation/Foundation.h>" > "$outfile"
# echo "//file of $PWD" >> "$outfile"
echo 'extern NSDictionary *GCDWebUploader_bundle_content(void);' >> "$outfile"
echo 'NSDictionary *GCDWebUploader_bundle_content(void) { return @{' >> "$outfile"
find 'GCDWebUploader.bundle' -type f | while read line; do
    b64=`base64 "$line"`
    cat <<EOF >> "$outfile"
    @"$line":@"$b64",
EOF
done

echo '};}'>>"$outfile"

exit
