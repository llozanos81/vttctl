#!/usr/bin/env bash
# usage:
# ./prestage.sh "TIMED_DOWNLOAD_URL"
DEST="FoundryVTT"
VERSION=$(echo "$1" | grep -oP "(?<=releases\/)\d+\.\d+")
TARGET="${DEST}/${VERSION}"


#rm -rf .env ${TARGET}
FILE=$(basename "$1" | awk -F\? {'print $1'})
wget -O downloads/$FILE $1
echo "Extracting $FILE to ${TARGET}/ ..."
unzip -qq -o downloads/$FILE -d ${TARGET}/
VER=$(cat ${TARGET}/resources/app/package.json | jq -r '"\(.release.generation).\(.release.build)"')
cp ${DEST}/docker-entrypoint.sh ${TARGET}
#echo "VERSION=$VER" > .env
echo "done!"