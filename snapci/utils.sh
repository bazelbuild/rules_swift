 #!/usr/bin/env bash

function escape_sashes() {
  echo "$1" | sed 's/\//\\\//g'
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

    # Build number is a Jenkins thing, in SnapCI; we will use the date_PIPLINE_ID
    # so the values are incremental
    BUILD_NUMBER=${BUILD_NUMBER:-}
    if [ -z "$BUILD_NUMBER" ]; then
        BUILD_NUMBER=$(date +"%Y%m%d%H%M%S")_${CI_PIPELINE_ID}
    fi

    GCS_DIR_NAME="snapengine-maven-publish${dev_suffix}/bazel-releases/rules/rules_swift/${BUILD_NUMBER}-${git_sha}/rules_swift.tar.gz"
    GCS_URL="gs://${GCS_DIR_NAME}"
    HTTP_URL="https://storage.googleapis.com/${GCS_DIR_NAME}"

    echo "Uploading rules_swift to GCS..."
    gsutil cp "${archive_path}" "$GCS_URL"

    echo "Getting shasum of the binary"
    sha256=$(shasum -a 256 "${archive_path}" | awk '{print $1}')

    echo "Posting PR Comment..."
    if [ -z "$CI_PULL_REQUEST" ]; then
        echo "No PR provided (CI_PULL_REQUEST), skipping publishing message to PR"
        exit 0
    fi
    snapci gh prs comments create <<END_GITHUB_COMMENT
Swift Rules ${dev_suffix} published:
\`\`\`
http_archive(
    name = "build_bazel_rules_swift",
    sha256 = "${sha256}",
    url = "${HTTP_URL}",
)
\`\`\`
END_GITHUB_COMMENT
}
