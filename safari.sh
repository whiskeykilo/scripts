#!/bin/sh
# Add Touch Icons to Safari's cache

# Theory of operation is that the domain from the URL of each bookmark is MD5 hashed and used as the filename of a PNG stored in $DIR
# The URL is the domain and subdomain, with no protocol, or path. So for example "app.slack.com" or "discordapp.com".
# Yes this means that multiple sites might collide, and seems to be a weakness of Safari's scheme.
# So this script searches Bookmarks.plist to find the bookmark in question, grabs the URL, hashes it, and copies the new icon named $DIR/${HASH}.png
# Usage: Create PNG files named the same as a bookmarks you want to add. So to add a Touch Icon for a bookmark called Gmail, create a PNG called Gmail.png. Run this script in the directory with the PNGs.

DIR="$HOME/Library/Safari/Touch Icons Cache/Images"
CS="cache_settings"
DB="$DIR/../TouchIconCacheSettings.db"

# If no argument is provided then assume the icons are in the current directory
# ICONDIR=$1
# if [ $# -eq 0 ]
# then
# 	ICONDIR=`pwd`
# fi

ICONDIR="/Users/$USER/Library/Mobile Documents/com~apple~CloudDocs/Documents/Safari"

for png in "$ICONDIR"/*.png
do 
	BASENAME=`basename "${png%.png}"`

	# We use an XPath to find the URL because you can't reliably parse XML with regular expressions
	XPATH="//dict[dict/string='$BASENAME']/key[text()='URLString']/following-sibling::string[1]/text()"

	# Use plutil to convert the binary Bookmarks plist into raw XML, and xmllint to parse it
	URL=$(plutil -convert xml1 -o - "$HOME/Library/Safari/Bookmarks.plist" | xmllint --xpath "$XPATH" -)

	# Strip out the protocol and everything after the first forward slash
	URL=`echo $URL | sed -e "s/http[s]*:\/\///g" -e "s/\/.*//g"`

	# md5 hash the URL and make it upper case
	HASH="$(md5 -q -s $URL | tr '[a-z]' '[A-Z]')"
	
	echo "`basename "$png"` ($URL) -> ${HASH}.png"
	cp -f "$png" "$DIR/${HASH}.png"
done

sqlite3 "$DB" "UPDATE $CS SET icon_is_in_cache=1, download_status_flags=1, transparency_analysis_result=1";