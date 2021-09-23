#!/usr/bin/env bash

set -ex

# Redirect output to stderr.
exec 1>&2

GITHUB_TOKEN=$1
[ -n "$GITHUB_TOKEN" ]

TAG_PR_TOKEN=$2
[ -n "$TAG_PR_TOKEN" ]

pushd $(dirname $0) > /dev/null

git checkout main

version=$(git tag --sort=-creatordate | head -n1)
sed --in-place -r -e "s/set\\(AWS_CRT_CPP_VERSION \".+\"\\)/set(AWS_CRT_CPP_VERSION \"${version}\")/" CMakeLists.txt
echo "Updating AWS_CRT_CPP_VERSION default to ${version}"

if git diff --exit-code CMakeLists.txt > /dev/null; then
    echo "No version change"
else
    version_branch=AutoTag-${version}
    git checkout -b ${version_branch}

    git config --local user.email "aws-sdk-common-runtime@amazon.com"
    git config --local user.name "GitHub Actions"
    git add CMakeLists.txt
    git commit -m "Updated version to ${version}"

    echo $TAG_PR_TOKEN | gh auth login --with-token

    # awkward - we need to snip the old release message and then force overwrite the tag with the new commit but
    # preserving the old message
    # the release message seems to be best retrievable by grabbing the last lines of the release view from the
    # github cli
    release_line_count=$(gh release view ${version} | wc -l)
    let release_message_lines=release_line_count-7
    tag_message=$(gh release view ${version} | tail -n ${release_message_lines})
    #tag_message=$(git tag -l -n20 ${version} | sed -n "s/${version} \(.*\)/\1/p")
    echo "Old release message is: ${tag_message}"

    # push the commit
    git push -u "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/awslabs/aws-crt-cpp.git" ${version_branch}

    gh pr create --title "AutoTag PR for ${version}" --body "AutoTag PR for ${version}" --head ${version_branch}
    gh pr merge --admin --squash

    git fetch
    git checkout main
    git pull "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/awslabs/aws-crt-cpp.git" main

    # delete the old tag on github
    git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/awslabs/aws-crt-cpp.git" :refs/tags/${version}

    # create new tag on latest commit with old message
    git tag -f ${version} -m "${tag_message}"

    # push new tag to github
    git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/awslabs/aws-crt-cpp.git" --tags
fi

popd > /dev/null
