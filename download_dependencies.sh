#!/bin/bash

# Script that downloads all online dependencies for [Legacy] DQMGUI
# in order to install them at P5, where there is no access to neither GitHub,
# nor PyPI. This script is to be called whenever those packages are to be recreated, e.g
# new PyPI packages version, new DQMGUI repo version, new DMQM/deployment version.
#
# For every element in the repos_to_download array, the equivalent repo and tag/ref are
# cloned and compressed under a directory of the same name.
# All PyPI packages (see requirements.txt) are compressed together, under pip/.
#
# To change any of the package versions, edit config.sh
#
# Dependency: libcurl4-gnutls-dev for curl-config

set -ex

# This scipt's directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Get constants from config file
source "$SCRIPT_DIR/config.sh"

# Helper function to clone a repo and checkout to specific tag
# Takes the following positional arguments:
# - URL of the repo,
# - A reference (tag, branch, commit) to checkout to and
# - The directory to clone the code to.
_clone_from_git() {
    # repo url
    url=$1

    # Which branch/tag to checkout to
    ref=$2

    # The path to the directory to clone to
    dir=$3

    # If tmp dir exists, remove it
    if [[ -d $dir ]]; then
        rm -rf "$dir"
    fi
    # Try to checkout to ref directly, else just get a shallow clone and try to find the ref there
    git clone --depth 1 --branch "$ref" "$url" "$dir" || (
        (git clone --depth 1 "$url" "$dir" &&
            cd "$dir" &&
            git remote set-branches origin '*' &&
            git fetch --all --tags &&
            git checkout "$ref" &&
            cd -) || (
            cd "$dir" &&
                # If shallow clone fails, get last 100 commits
                git fetch --all --depth=100 &&
                git checkout "$ref" &&
                cd -
        )
    )

}

download_repo() {
    set -x
    repo=$1
    download_repo_flag_name=do_download_$repo
    if [ "${!download_repo_flag_name}" -eq 0 ]; then
        echo "INFO: Skipping downloading $repo"
        return
    fi

    echo "INFO: Downloading $repo"

    prefix="$(echo $repo | tr '[:lower:]' '[:upper:]')"
    git_url=${prefix}_GIT_URL
    git_tag=${prefix}_GIT_TAG
    if [ -z "${!git_url}" ] || [ -z "${!git_tag}" ]; then
        echo "WARNING: git url or tag not configured for repository $repo, skipping"
        return
    fi

    temp_dir=/tmp/$repo
    mkdir -p "$temp_dir"
    _clone_from_git "${!git_url}" "${!git_tag}" "$temp_dir"
    rm -rf "$temp_dir/.git" # Remove .git, it will slow things down
    mkdir -p "$SCRIPT_DIR/$repo"
    if [ -f "$SCRIPT_DIR/$repo/$repo.tar.gz" ]; then
        rm "$SCRIPT_DIR/$repo/$repo.tar.gz"
    fi
    tar -cf "$SCRIPT_DIR/$repo/$repo.tar.gz" --directory=/tmp "$repo" -I "pigz --best"
    rm -rf "$temp_dir"
}

download_python_packages() {
    python_exe=$1
    PIP_TEMP_DIR=/tmp/pip
    mkdir -p $PIP_TEMP_DIR
    mkdir -p "$SCRIPT_DIR/pypi"
    eval "$python_exe -m pip download -r requirements.txt --destination-directory $PIP_TEMP_DIR"
    tar -cf "$SCRIPT_DIR/pypi/pypi.tar.gz" --directory=/tmp pip -I "pigz --best"
    rm -rf $PIP_TEMP_DIR
}

# Check the version of a specific python executable
_check_python_version() {
    python_exe=$1
    python_version=$($python_exe -c 'import platform; print(platform.python_version())')
    python_version_major="$(echo $python_version | cut -d'.' -f1)"
    python_version_minor="$(echo $python_version | cut -d'.' -f2)"
    if [ "$python_version_major.$python_version_minor" != "$PYTHON_VERSION" ]; then
        return 1
    fi
    return 0
}

# Try to find a python version compatible with the one configured in config.sh
find_compatible_python_version() {
    required_python_version_major="$(echo $PYTHON_VERSION | cut -d'.' -f1)"
    required_python_version_minor="$(echo $PYTHON_VERSION | cut -d'.' -f2)"
    declare -a python_executables=(python3 "python${PYTHON_VERSION}" "python${required_python_version_major}${required_python_version_minor}")
    for python_executable in "${python_executables[@]}"; do
        if which "$python_executable" 2>&1 1>&/dev/null; then
            if _check_python_version $(which "$python_executable"); then
                echo $(which "$python_executable")
            fi
        fi
    done
    echo
}
### Main script

# Check for python version, just to be sure
python_exe=$(find_compatible_python_version)
if [ -z "$python_exe" ]; then
    echo "No python $PYTHON_VERSION was found on the system"
    exit 1
else
    echo "Using python $python_exe"
fi
# For GitHub repos, clone the source on a specific branch/tag/ref, then make a tar.
declare -a repos_to_download=(rotoglup boost_gil dmwm dqmgui yui extjs d3 jsroot root)

# Create dynamic flags to selectively disable/enable steps of the download procedure
# Those flags are named "do_download" with the name of the repo, e.g. "do_download_root" for
# the "root" repo.
# We set those flags to 1 by default.
for repo in "${repos_to_download[@]}"; do
    eval "do_download_${repo}=1"
done

# Parse command line arguments -- use <key>=<value> to override the flags mentioned above.
# e.g. DQMGUI_GIT_TAG=9.9.0
for ARGUMENT in "$@"; do
    KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
    KEY_LENGTH=${#KEY}
    VALUE="${ARGUMENT:$KEY_LENGTH+1}"
    eval "$KEY=$VALUE"
done

# Download all repos in parallel
for repo in "${repos_to_download[@]}"; do
    download_repo "$repo" &
done

download_python_packages "$python_exe"
wait
echo "INFO: Done!"
