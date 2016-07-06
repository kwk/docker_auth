#!/bin/bash

# Outputs everything to stderr with a UTC datetime prefixed in braces "[]"
log() {
  echo "[$(date -u)] $@" 1>&2
}

# Outputs everything to stderr
logtest() {
  echo -e "$@" 1>&2
}

# Prints a summary of passed and failed tests and shows where to find the logs.
# Then the server is stopped.
cleanup() {
  EXITCODE=0
  if [ "$NUMERRORS" != "0" ]; then
    log "$NUMERRORS of $NUMTESTS tests were failing:"
    echo "" 1>&2
    echo "----------------------------------------------------------------" 1>&2
    cat $FAILEDTESTS 1>&2
    echo "----------------------------------------------------------------" 1>&2
    echo "" 1>&2
    EXITCODE=1
  else
    log "All $NUMTESTS tests were passing!"
  fi
  log "Logs are in $LOGDIR"
  log "Shutting down $PROGNAME"
  # Shutdown auth_server process if it is still running
  killall $PROGNAME
  cd $OLDPWD
  exit $EXITCODE
}

# Encode to Base64-URL without padding.
function base64UrlEncode {
  echo -n "$1" | openssl enc -a -A | tr -d '=' | tr '/+' '_-'
}

# Decode from Base64-URL without padding.
function base64UrlDecode {
  _l=$((${#1} % 4))
  if [ $_l -eq 2 ]; then _s="$1"'=='
  elif [ $_l -eq 3 ]; then _s="$1"'='
  else _s="$1" ; fi
  echo "$_s" | tr '_-' '/+' | openssl enc -d -a -A
}


# Sets up some paths and variables and builds or reuses the auth_server artifact.
# The first argument must be the path to the config file to be used by the
# auth_server.
setuptest() {
  if [ "$#" != "1" ]; then
    log "You must specify a config file for the auth_server."
    exit 2
  fi

  trap "cleanup" EXIT
  THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # directory of this script
  PROGNAME=auth_server
  OLDPWD=$PWD
  LOGDIR=$(mktemp -d)
  NUMERRORS=0
  NUMTESTS=0
  FAILEDTESTS=$LOGDIR/failed_tests.txt
  CONFIGFILE=$1
  PUBKEYFILE=$LOGDIR/pubkey.pem

  log "Extract public key from certificate once"
  openssl x509 -pubkey -noout -in $TESTDIR/certs/auth.crt  > $PUBKEYFILE

  # If the ENV_NOCOLOR environment variable is set, don't output colorful reports.
  set +u
  if [ -z "$ENV_NOCOLOR" ]; then
    COLOR_ERROR='\033[0;31m' # Red
    COLOR_SUCCESS='\033[0;32m' # Green
    COLOR_NONE='\033[0m' # No Color
  else
    COLOR_ERROR=''
    COLOR_SUCCESS=''
    COLOR_NONE='' # No Color
  fi
  set -u

  # Build the auth_server or reuse an existing artifact
  cd $TESTDIR/..
  if [ ! -e "$PROGNAME" ]; then
    log "Building $PROGNAME"
    go build
  else
    log "Found already existing $PROGNAME (skipping build)."
  fi
}

# Starts the auth_server and fires an authorization requests to it to see if it
# is responding correctly. Then, the server is shutdown.
#
# The inputs are:
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
  LOGFILE=$LOGDIR/$PROGNAME.log.$NUMTESTS
  OUTFILE=$LOGDIR/$PROGNAME.out.$NUMTESTS

  # Start the auth server
  ./$PROGNAME -v 5 -alsologtostderr=true $CONFIGFILE > $LOGFILE 2>&1 & #-log_dir=$LOGDIR
  sleep 2

  FAILED=0

  respCode=$(curl -sk --output "$OUTFILE" --write-out '%{http_code}' -H "$authHeader" "$URL")
  if [ "$respCode" != "$expectedResponseCode" ]; then
    FAILED=1
  else
    # Analyse the token we received

    TOKEN=$(cat $OUTFILE | jq ".token" | tr -d '"')
    HEADER=$(base64UrlDecode $(echo $TOKEN | cut -d '.' -f 1))
    PAYLOAD=$(base64UrlDecode $(echo $TOKEN | tr -d '"' | cut -d '.' -f 2))
    SIGNATURE=$(base64UrlDecode $(echo $TOKEN | tr -d '"' | cut -d '.' -f 3))

    # Verify the signature
    # TODO (kwk) Either implement in bash or switch to Go and docker/libtrust instead
  fi

  if [ "$FAILED" == "1" ]; then
    echo -e "${COLOR_ERROR}TEST FAILED: $msg${COLOR_NONE}" | tee --append $FAILEDTESTS 1>&2
    echo -e " - Expected $expectedResponseCode and got \"$respCode\" with authHeader=\"$authHeader\" and URL=\"$URL\"" 1>&2
    echo -e "-------------------------   LOG   ------------------------------" 1>&2
    cat $LOGFILE
    echo -e "----------------------------------------------------------------" 1>&2
    #cat $LOGDIR/$PROGNAME.* 1>&2
    NUMERRORS=$((NUMERRORS+1))
    #exit 2
  else
    logtest "${COLOR_SUCCESS}TEST PASSED: $msg${COLOR_NONE}"
  fi

  killall $PROGNAME
}
