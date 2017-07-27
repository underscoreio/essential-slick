#!/bin/bash
#
# Inject analytics into html document.
#
set -e

if [[ "${TRAVIS_PULL_REQUEST}" == "false" &&
     "${TRAVIS_BRANCH}" == "master"
]]; then
# Configuration
# 1. The key for writing into the other repository:
ANALYTICS_LINK='<link rel="import" href="../../analytics.html">'
SRC_DIR=`pwd` # e.g., /home/travis/build/underscoreio/essential-slick
SRC_FILE="$SRC_DIR/dist/*.html"
# End of configuration
echo "Inject google analytics code into html document"
LN=$(echo `grep -n '</head>'  $SRC_FILE` | awk -F: '{print $1}')
sed -i "$LN i $ANALYTICS_LINK" $SRC_FILE
fi
