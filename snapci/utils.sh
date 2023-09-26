 #!/usr/bin/env bash

function escape_sashes() {
  echo "$1" | sed 's/\//\\\//g'
}

function post_comment() {
    comment_msg=${1:-}
    if [ -z "$comment_msg" ]; then
        echo "Comment message must be set"
        exist 1
    fi

    git_sha=$(git rev-parse --short HEAD) || exit 1
    echo "Posting Github comment on $git_sha..."

    repo_name=$(git config --get remote.origin.url | awk -F"[\.\/]" '{ print $4}') || exit 1
    curl -s -H "Authorization: token ${GITHUB_APIKEY}" -H "Content-Type: application/json" \
        -X POST -d "{\"body\": \"${comment_msg}\"}" \
        https://github.sc-corp.net/api/v3/repos/Snapchat/${repo_name}/issues/${pull_number}/comments
}

function deploy() {
    dev_suffix=$1
    tmp_dir=$(mktemp -d)
    current_dir=$(pwd)
    archive_path="${tmp_dir}/rules_swift.tar.gz"

    echo "Creating archive ${archive_path}"
    pushd "${tmp_dir}"
    tar -C "${current_dir}" --exclude="./.*/*" -cvzf rules_swift.tar.gz .
    popd

    echo "Getting commit SHA"
    git_sha=$(git rev-parse --short HEAD) || exit 1

    GCS_DIR_NAME="snapengine-maven-publish${dev_suffix}/bazel-releases/rules/rules_swift/${BUILD_NUMBER}-${git_sha}/rules_swift.tar.gz"
    GCS_URL="gs://${GCS_DIR_NAME}"
    HTTP_URL="https://storage.googleapis.com/${GCS_DIR_NAME}"

    echo "Uploading rules_swift to GCS..."
    gsutil cp "${archive_path}" "$GCS_URL"

    echo "Getting shasum of the binary"
    sha256=$(shasum -a 256 "${archive_path}" | awk '{print $1}')
    quoted_sha="\\\"${sha256}\\\""

    echo "Posting PR Comment..."
    escaped_url=$(escape_sashes "${HTTP_URL}")
    quoted_url="\\\"${escaped_url}\\\""
    comment="Rules published:\r\n    sha256 = ${quoted_sha},\r\n    url = ${quoted_url}"

    post_comment "${comment}"
}
