#!/usr/bin/env bash
# For use in Docker 

# fetch a recent SBT to use:
mkdir -p ~/bin
curl -Ls https://git.io/sbt > ~/bin/sbt 
chmod 0755 ~/bin/sbt

export JAVA_OPTS="-Xmx3g -XX:+TieredCompilation -XX:ReservedCodeCacheSize=256m -XX:+UseNUMA -XX:+UseParallelGC -XX:+CMSClassUnloadingEnabled"

~/bin/sbt "$@"
