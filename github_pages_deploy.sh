#!/bin/bash
#
# Deploy the PDF, HTML, EPUB files of an Underscore book (source)
# into another Git repository (target)
#
set -e

#if [[ "${TRAVIS_PULL_REQUEST}" == "false" ]]; then

# Configuration
# 1. Location of the book to deploy:
export SRC_DIR=~/underscoreio/essential-slick

# 2. The key for writing into the other repository:
export KEY_FILENAME=essential_slick_deploy.enc

# 3. Folder inside target of where to place the artifacts:
export $TARGET_PATH=books/essential-slick/
# End of configuration

echo "Starting deploy to github pages"
echo -e "Host github.com\n\tStrictHostKeyChecking no\nIdentityFile ~/.ssh/deploy.key\n" >> ~/.ssh/config
openssl aes-256-cbc -k "$SERVER_KEY" -in $KEY_FILENAME -d -a -out deploy.key
cp deploy.key ~/.ssh/
chmod 600 ~/.ssh/deploy.key

git config --global user.email "hello@underscore.io"
git config --global user.name "Travis Build"

export TARGET_DIR=/tmp/dist
mkdir $TARGET_DIR
cd $TARGET_DIR
git clone git@github.com:underscoreio/books.git

cp $SRC_DIR/dist/*.pdf $TARGET_PATH
cp $SRC_DIR/dist/*.html $TARGET_PATH
cp $SRC_DIR/dist/*.epub $TARGET_PATH

git add $TARGET_PATH
git commit -m "auto commit via travis $TRAVIS_JOB_NUMBER $TRAVIS_COMMIT [ci skip]"
git push git@github.com:underscoreio/books.git master:master

rm -rf $TARGET_DIR
#fi
