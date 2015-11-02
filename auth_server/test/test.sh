#!/bin/bash

# Exit on error and unitialized variables
set -eu

# Remember current working directory
PROGNAME=auth_server
OLDPWD=$PWD
LOGDIR=$(mktemp -d)
NUMERRORS=0
NUMTESTS=0

log() {
  echo "[$(date -u)] $@" 1>&2
}
logtest() {
  echo "$@" 1>&2
}

cleanup() {
  if [ "$NUMERRORS" != "0" ]; then
    log "$NUMERRORS of $NUMTESTS tests were failing!"
  else
    log "All tests were passing!"
  fi
  log "Logs are in $LOGDIR"
  log "Shutting down $PROGNAME"
  # Shutdown auth_server process if it is still running
  killall auth_server
  cd $OLDPWD
}

trap "cleanup" EXIT

# Build the auth_server
log "Building $PROGNAME"
cd ../
go build

log "Starting $PROGNAME"
./$PROGNAME -v 5 -log_dir=$LOGDIR test/config/testconfig.yml &

# Wait for server to start
# TODO: (kwk) optimize with loop waiting on port
sleep 2

# Fire some authorization requests to the auth_server to see if it is responding
# correctly.
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

adminAuthHeader="Authorization: Basic $(echo -n "admin:badmin" | base64)"
testAuthHeader="Authorization: Basic $(echo -n "test:123" | base64)"
test1AuthHeader="Authorization: Basic $(echo -n "test1:123" | base64)"
test2AuthHeader="Authorization: Basic $(echo -n "test2:123" | base64)"

baseUrl="https://localhost:5001/auth?service=registry.docker.io&scope=repository:"

log "Starting tests"

# Admin has full access to everything.
testAuth "200" "$adminAuthHeader" "${baseUrl}randomuser/randomrepo:pull,push" 'Admin has full access to everything.'

# User "test" has full access to test-* images but nothing else.
testAuth "200" "$testAuthHeader" "${baseUrl}test-randomuser/randomrepo:pull" 'User "test" has full access to test-* images but nothing else. (1)'
testAuth "200" "$testAuthHeader" "${baseUrl}randomuser/test-randomrepo:pull,push" 'User "test" has full access to test-* images but nothing else. (2)'
testAuth "401" "$testAuthHeader" "${baseUrl}randomuser/randomrepo:push" 'User "test" has full access to test-* images but nothing else. (3)'
testAuth "401" "$testAuthHeader" "${baseUrl}randomuser/randomrepo:pull" 'User "test" has full access to test-* images but nothing else. (4)'

# All logged in users can pull all images.
testAuth "200" "$test1AuthHeader" "${baseUrl}randomuser/randomrepo:pull" 'All logged in users can pull all images.'

# All logged in users can push all images that are in a namespace beginning with their name
testAuth "200" "$test1AuthHeader" "${baseUrl}test1/randomrepo:push" 'All logged in users can push all images that are in a namespace beginning with their name (1)'
testAuth "200" "$test1AuthHeader" "${baseUrl}test1-with-suffix/randomrepo:push" 'All logged in users can push all images that are in a namespace beginning with their name (2)'

# Anonymous users can pull "hello-world".
testAuth "200" "" "${baseUrl}hello-world:pull" 'Anonymous users can pull "hello-world". (1)'
testAuth "200" "" "${baseUrl}randomuser/hello-world:pull" 'Anonymous users can pull "hello-world". (2)'

# Access is denied by default.
testAuth "200" "$test1AuthHeader" "${baseUrl}randomuser/randomrepo:push" 'Access is denied by default.'
