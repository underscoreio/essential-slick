set -e

#if [[ "${TRAVIS_PULL_REQUEST}" == "false" ]]; then
  echo -e "Host github.com\n\tStrictHostKeyChecking no\nIdentityFile ~/.ssh/deploy.key\n" >> ~/.ssh/config
  openssl aes-256-cbc -k "$SERVER_KEY" -in essential_slick_deploy_key.enc -d -a -out deploy.key
  cp deploy.key ~/.ssh/
  chmod 600 ~/.ssh/deploy.key
  
  git config --global user.email "richard@dallaway.com"
  git config --global user.name "Richard Dallaway"
 
  mkdir tmp
  cd tmp
  git clone git@github.com:underscoreio/books.git

  cp ../dist/*.pdf books/essential-slick/
  cp ../dist/*.html books/essential-slick/
  cp ../dist/*.epub books/essential-slick/

  git add books/essential-slick
  git commit -m "auto commit Essential Slick via travis $TRAVIS_JOB_NUMBER $TRAVIS_COMMIT [ci skip]"
  git push git@github.com:underscoreio/books.git master:master
#fi
