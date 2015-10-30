#!/bin/bash

# Exit on error, unitialized variables, and show commands 
set -eux

# Remember current working directory
OLDPWD=$PWD
TEMPDIR=$(mktemp -d)
cleanup() {
  ls -lha $TEMPDIR/log/
  # Shutdown auth_server process if it is still running
  killall auth_server
  rm -rf $TEMPDIR
  cd $OLDPWD
}

trap "cleanup" EXIT

# Build the auth_server
cd ../
go build

LOGDIR=$TEMPDIR/log
mkdir -p $LOGDIR
./auth_server -v 5 -log_dir=$LOGDIR test/config/testconfig.yml &

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
  
  
  set -x
  respCode=$(curl -sk --output /dev/null --write-out '%{http_code}' -H "$authHeader" "$URL")
  set +x
  if [ "$respCode" != "$expectedResponseCode" ]; then
    echo "TEST FAILED: $msg" 1>&2
    echo " - Expected $expectedResponseCode and got \"$respCode\" with authHeader=\"$authHeader\" and URL=\"$URL\"" 1>&2
    cat $LOGDIR/auth_server.INFO
    exit 2
  else
    echo "TEST PASSED: $msg" 1>&2
#    echo " - Expected $expectedResponseCode and got \"$respCode\" with authHeader=\"$authHeader\" and URL=\"$URL\"" 1>&2
  fi  
}

adminAuthHeader="Authorization: Basic $(echo -n "admin:badmin" | base64)"
testAuthHeader="Authorization: Basic $(echo -n "test:123" | base64)"
test1AuthHeader="Authorization: Basic $(echo -n "test1:123" | base64)"
test2AuthHeader="Authorization: Basic $(echo -n "test2:123" | base64)"

baseUrl="https://localhost:5001/auth?service=registry.docker.io&scope=repository:"

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
testAuth "200" "" "$b{aseUrl}randomuser/hello-world:pull" 'Anonymous users can pull "hello-world". (2)'

# Access is denied by default.
testAuth "200" "$test1AuthHeader" "$baseUrl&scope=repository:randomuser/randomrepo:push" 'Access is denied by default.'


