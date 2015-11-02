#!/bin/bash

# Exit on error and unitialized variables
set -eu

TESTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # directory of this script

# Load in functions shared by multiple tests
source $TESTDIR/common.sh
trap "cleanup" EXIT

# Build the auth_server or reuse an existing artifact
cd $TESTDIR/..
if [ ! -e "$PROGNAME" ]; then
  log "Building $PROGNAME"
  go build
else
  log "Found already existing $PROGNAME (skipping build)."
fi

WAITFORSTARTUP=2
log "Starting $PROGNAME and waiting $WAITFORSTARTUP seconds to finish"
./$PROGNAME -v 1 -log_dir=$LOGDIR test/config/testconfig.yml &
# TODO: (kwk) optimize with loop waiting on port
sleep $WAITFORSTARTUP

# Configure Basic auth authorization headers
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
