#!/bin/bash

THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # directory of this script
PROGNAME=auth_server
OLDPWD=$PWD
LOGDIR=$(mktemp -d)
NUMERRORS=0
NUMTESTS=0

# Outputs everything to stderr with a UTC datetime prefixed in braces "[]"
log() {
  echo "[$(date -u)] $@" 1>&2
}

# Outputs everything to stderr
logtest() {
  echo "$@" 1>&2
}

# Prints a summary of passed and failed tests and shows where to find the logs.
# Then the server is stopped.
cleanup() {
  if [ "$NUMERRORS" != "0" ]; then
    log "$NUMERRORS of $NUMTESTS tests were failing!"
  else
    log "All $NUMTESTS tests were passing!"
  fi
  log "Logs are in $LOGDIR"
  log "Shutting down $PROGNAME"
  # Shutdown auth_server process if it is still running
  killall $PROGNAME
  cd $OLDPWD
}

# Fires an authorization requests to the auth_server to see if it is responding
# correctly. The inputs are:
#
# 1. Expected Result Code (e.g. "200", or "401")
# 2. The auth Header with which to authenticate, e.g. "Authorization: Basic $(echo -n "test:123" | base64)"
# 3. The URL to try, e.g. "https://localhost:5001/auth?service=registry.docker.io&scope=repository:somenamespace/somerepo,pull,push"
# 4. A message to describe the test.
testAuth() {
  expectedResponseCode=$1
  authHeader="$2"
  URL="$3"
  msg=$4

  NUMTESTS=$((NUMTESTS+1))

  respCode=$(curl -sk --output /dev/null --write-out '%{http_code}' -H "$authHeader" "$URL")
  if [ "$respCode" != "$expectedResponseCode" ]; then
    echo "TEST FAILED: $msg" 1>&2
    echo " - Expected $expectedResponseCode and got \"$respCode\" with authHeader=\"$authHeader\" and URL=\"$URL\"" 1>&2
    #cat $LOGDIR/$PROGNAME.* 1>&2
    NUMERRORS=$((NUMERRORS+1))
    #exit 2
  else
    logtest "TEST PASSED: $msg"
  fi
}
