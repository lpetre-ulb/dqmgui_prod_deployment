#!/bin/bash
#
# Script intended for installing [legacy] DQMGUI on online HLT machines (dqmsrv-...).
# It tries to imitate the behavior of the Deploy script without installing external RPMs.
#
# It clones DQMGUI, dmwm/deployment code and classlib, creates a virtual env...TODO
#
# Only targeting RHEL8 + Python3.6 for now(!)
#
# If the target (installation+dmqm tag) directory exists (e.g. /data/srv/$DMWM_GIT_TAG), it will
# be *DELETED* by the script, before re-installing. The "state" dir is left alone.
#
# Required system packages: See check_dependencies().
#
# Contact: cms-dqm-coreteam@cern.ch

# Stop at any non-zero return and display all commands.
set -ex

### Constants

# The EUID of the authorized user to run the script.
EUID_USER_DQM=1000

# Default architecture. It doesn't really play a role now.
# ARCHITECTURE=el8_amd64_gcc11

# Main directory we're installing into.
INSTALLATION_DIR=/data/srv

# This scipt's directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Tag to use for getting the layouts and manage/deploy scripts
# See: https://github.com/dmwm/deployment/tags
#DMWM_GIT_TAG=HG2307b
#DMWM_GIT_URL=https://github.com/dmwm/deployment
DMWM_GIT_TAG=debug
DMWM_GIT_URL=https://github.com/nothingface0/cms_dmwm_deployment

# DQMGUI tag to use, see https://github.com/cms-DQM/dqmgui_prod/tags
#DQMGUI_GIT_TAG=9.8.0
DQMGUI_GIT_TAG=python3_backup
DQMGUI_GIT_URL=https://github.com/cms-DQM/dqmgui_prod

# Boost.GIL configuration
BOOST_GIL_GIT_URL=https://github.com/boostorg/gil

# At most 1.67 for boost/gil/extension/io/jpeg_io.hpp
BOOST_GIL_GIT_TAG=boost-1.66.0

# OLD rotoglup code. Commit was found with lots of pain, so that the patch
# applies: https://github.com/cms-sw/cmsdist/blob/comp_gcc630/dqmgui-rtgu.patch
ROTOGLUP_GIT_TAG=d8ce23aecd0b1fb7d45c9bedb615abdab27a5494
ROTOGLUP_GIT_URL=https://github.com/rotoglup/rotoglup-scratchpad

# Yahoo!(TM) UI
YUI_GIT_URL=https://github.com/yui/yui2
YUI_GIT_TAG=master

# Extjs
EXTJS_GIT_URL=https://github.com/probonogeek/extjs
EXTJS_GIT_TAG=3.1.1

# D3
D3_GIT_URL=https://github.com/d3/d3
D3_GIT_TAG=v2.7.4

# JSROOT
JSROOT_GIT_URL=https://github.com/root-project/jsroot
JSROOT_GIT_TAG=5.1.0

# Preliminary checks to do before installing the GUI
preliminary_checks() {
    # Make sure only the dqm user can run our script
    if [[ $EUID -ne $EUID_USER_DQM ]]; then
        echo "This script must be run as dqm" 1>&2
        exit 1
    fi

    # Make sure you can only run the script on the DQM servers
    case $HOSTNAME in
    dqmsrv-c2a06-07-01 | dqmsrv-c2a06-08-01 | dpapagia-dev-vm*)
        echo "Valid DQM GUI server: $HOSTNAME"
        ;;
    *)
        echo "This script must be run on a GUI server" 1>&2
        exit 1
        ;;
    esac

    if [[ -d $INSTALLATION_DIR/$DMWM_GIT_TAG ]]; then
        echo "WARNING: $INSTALLATION_DIR/$DMWM_GIT_TAG exists, deleting contents"
        rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/*
    fi

}

# Check for needed OS-wide dependencies
check_dependencies() {
    pkgs_installed=1
    declare -a required_packages=(bzip2 libglvnd-opengl libX11-devel libXext-devel libXft-devel
        libXpm-devel mesa-libGLU mesa-libGLU-devel perl-Env perl-Switch
        perl-Thread-Queue glibc-headers libidn libXcursor
        libXi libXinerama libXrandr perl perl-Digest-MD5 tcsh zsh root python3-root epel-release
        python3-pip libcurl-devel python36-devel boost-python3-devel protobuf-devel jemalloc-devel
        pcre-devel boost-devel lzo-devel cmake xz-devel python3-sphinx openssl-devel
        libjpeg-turbo-devel libpng-devel)

    # Instead of doing a 'yum list' per package, it may be faster to just
    # ask all of them at once, and dump to file. Then grep the file.
    echo -n "Getting system packages..."
    tmp_yum_list=/tmp/yum_list.txt
    eval "yum list ${required_packages[*]}" >$tmp_yum_list
    echo "Done"

    # Parse up to "Available Packages", which we don't care about.
    parse_up_to_line=$(grep -n "Available" $tmp_yum_list | cut -d ':' -f 1)
    parse_up_to_line=$((parse_up_to_line - 1))

    # Look for the package in the installed packages
    for package in "${required_packages[@]}"; do
        (head -$parse_up_to_line $tmp_yum_list | grep "$package") || pkgs_installed=0
        if [ $pkgs_installed -eq 0 ]; then
            break
        fi
    done

    rm $tmp_yum_list
    if [ $pkgs_installed -eq 0 ]; then
        echo "ERROR: Package $package missing please run: 'sudo yum install ${required_packages[@]}'"
        exit 1
    else
        echo "INFO: All required packages are installed"
    fi

}

# Create necessary directories for installation
create_directories() {
    # Dirs to create under INSTALLATION_DIR
    declare -a necessary_dirs=("logs" "state" "enabled" "$DMWM_GIT_TAG")
    for subdir in "${necessary_dirs[@]}"; do
        dirname="$INSTALLATION_DIR/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
    done
    mkdir -p $INSTALLATION_DIR/logs/dqmgui

    # Create subdirs for state/dqmgui
    mkdir -p $INSTALLATION_DIR/state/dqmgui
    declare -a necessary_dirs=("backup" "dev" "offline" "online" "relval")
    for subdir in "${necessary_dirs[@]}"; do
        dirname="$INSTALLATION_DIR/state/dqmgui/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
        dirname="$INSTALLATION_DIR/logs/dqmgui/$subdir"
    done

    # Dirs to create under DMWM_GIT_TAG dir
    declare -a necessary_dirs=("config" "sw" "apps.sw")
    for subdir in "${necessary_dirs[@]}"; do
        dirname="$INSTALLATION_DIR/$DMWM_GIT_TAG/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
    done

    if [ ! -L $INSTALLATION_DIR/$DMWM_GIT_TAG/apps ]; then
        echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG/apps.sw <-- $INSTALLATION_DIR/$DMWM_GIT_TAG/apps"
        ln -s $INSTALLATION_DIR/$DMWM_GIT_TAG/apps.sw $INSTALLATION_DIR/$DMWM_GIT_TAG/apps
    fi

    # Create a "current" link to the DMWM version we're using, like how it was done
    # in the older scripts.
    if [ -L $INSTALLATION_DIR/current ]; then
        rm $INSTALLATION_DIR/current
    fi
    echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG <-- $INSTALLATION_DIR/current"
    ln -s $INSTALLATION_DIR/$DMWM_GIT_TAG $INSTALLATION_DIR/current

    # Directories for external source and lib files (e.g. classlib)
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib

    # DQMGUI dirs
    echo "DEBUG: Creating subdirectory $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG"
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG

}

# Helper function to clone a repo and checkout to specific tag
# Takes the following positional arguments:
# - URL of the repo,
# - A reference (tag, branch, commit) to checkout to and
# - The directory to clone the code to.
_clone_from_git() {
    cd $INSTALLATION_DIR/
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

    # Shallow clone
    git clone "$url" "$dir" --depth 1

    # Checkout to ref
    cd "$dir"
    # Shallow clone misses remote branches, so
    # fix that.
    git remote set-branches origin '*'
    git fetch --all --tags
    git fetch --depth=1
    # DIRTY HACK
    git checkout "$ref" || (git fetch --all --depth=50 && git checkout "$ref")
    cd $INSTALLATION_DIR/
}

install_rotoglup() {
    ROTOGLUP_TMP_DIR=/tmp/rotoglup
    _clone_from_git $ROTOGLUP_GIT_URL $ROTOGLUP_GIT_TAG $ROTOGLUP_TMP_DIR

    cd $ROTOGLUP_TMP_DIR
    #patch -p1 < $SCRIPT_DIR/rotoglup/patches/01.patch
    patch -p1 <"$SCRIPT_DIR/rotoglup/patches/02.patch"
    mv $ROTOGLUP_TMP_DIR/rtgu $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/rtgu
    cd $INSTALLATION_DIR/
    rm -rf $ROTOGLUP_TMP_DIR
}

# Compilation step for classlib
compile_classlib() {
    cd $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3

    #INCLUDE_DIRS="$INCLUDE_DIRS:/usr/include/lzo" make -j `nproc`
    make -j "$(nproc)" CXXFLAGS="-Wno-error=extra -ansi -pedantic -W -Wall -Wno-long-long -Werror"

    # Move the compiled library in the libs dir
    mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3/.libs/libclasslib.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libclasslib.so

}

# Classlib is needed both as a shared object and for its header files for DQMGUI compilation.
install_classlib() {
    # Temporary directory to extract to
    CLASSLIB_TMP_DIR=/tmp/classlib
    mkdir -p $CLASSLIB_TMP_DIR
    tar -xf "$SCRIPT_DIR/classlib/classlib-3.1.3.tar.bz2" -C $CLASSLIB_TMP_DIR

    # Apply code patches I found on cmsdist. The 7th one is ours, and has some extra needed fixes.
    cd $CLASSLIB_TMP_DIR/classlib-3.1.3
    for i in 1 2 3 4 5 6 7 8; do
        patch -p1 <"$SCRIPT_DIR/classlib/patches/0${i}.patch"
    done

    # Run cmake to generate makefiles and others
    cmake .

    ./configure

    # More stuff I found on cmsdist
    perl -p -i -e '
      s{-llzo2}{}g;
        !/^\S+: / && s{\S+LZO((C|Dec)ompressor|Constants|Error)\S+}{}g' \
        $CLASSLIB_TMP_DIR/classlib-3.1.3/Makefile

    if [ -d $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3 ]; then
        rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3
    fi

    # Move the classlib files inside the installation dir, needed for compiling the GUI
    mv $CLASSLIB_TMP_DIR/classlib-3.1.3 $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/

    # Make a link so that DQMGUI compilation can find the classlib headers easily
    ln -s $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3/classlib $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib

    rm -rf $CLASSLIB_TMP_DIR
}

install_boost_gil() {
    BOOST_GIL_TMP_DIR=/tmp/boost_gil
    _clone_from_git $BOOST_GIL_GIT_URL $BOOST_GIL_GIT_TAG $BOOST_GIL_TMP_DIR
    mv $BOOST_GIL_TMP_DIR/include/boost $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost
    rm -rf $BOOST_GIL_TMP_DIR
}

install_gil_numeric() {
    NUMERIC_TMP_DIR=/tmp/numeric
    mkdir -p $NUMERIC_TMP_DIR
    tar -xf "$SCRIPT_DIR/numeric/numeric.tar.gz" -C $NUMERIC_TMP_DIR
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost/gil/extension/
    mv $NUMERIC_TMP_DIR/numeric $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost/gil/extension/numeric
    rm -rf $NUMERIC_TMP_DIR
}

install_dmwm() {
    # Temporary directory to clone DMWM deployment scripts into
    DMWM_TMP_DIR=/tmp/deployment
    _clone_from_git $DMWM_GIT_URL $DMWM_GIT_TAG $DMWM_TMP_DIR

    # Move dqmgui-related scripts from DMWM to the config folder
    mv $DMWM_TMP_DIR/dqmgui $INSTALLATION_DIR/$DMWM_GIT_TAG/config/

    rm -rf $DMWM_TMP_DIR
}

# env.sh and init.sh file creation. They're needed by other scripts (e.g. manage).
_create_env_and_init_sh() {
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/

    # init.sh contents. This is sourced by env.sh
    echo "export PATH=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/bin:$PATH
export PYTHONPATH=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib/python${PYTHON_VERSION}/site-packages:$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib64/python${PYTHON_VERSION}/site-packages
.  $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/activate
" >$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/init.sh

    # env.sh contents. This is sourced by the manage script
    echo ". $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/init.sh
export YUI_ROOT=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/yui
export EXTJS_ROOT=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/extjs
export D3_ROOT=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/d3
export ROOTJS_ROOT=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/jsroot
export MONITOR_ROOT=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv
export DQMGUI_VERSION='$DQMGUI_GIT_TAG';
# For pointing to the custom built libraries
export LD_PRELOAD=\"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/libDQMGUI.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libclasslib.so\"
export LD_LIBRARY_PATH="$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/:$LD_LIBRARY_PATH"
" >$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/env.sh
}

# Crete the Python3 virtual environment for the GUI
_create_python_venv() {
    python_exe=$(which python3)

    python_venv_dir=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv
    mkdir -p "$python_venv_dir"
    eval "$python_exe" -m pip install --upgrade pip --user
    eval "$python_exe" -m pip install virtualenv --user
    echo -n "INFO: Creating virtual environment at $python_venv_dir"
    virtualenv $python_venv_dir

    # Now use the new venv's python
    python_venv_exe=$python_venv_dir/bin/python
    cd $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/
    eval $python_venv_exe -m pip install -r $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/requirements.txt

    echo "Done"
    # Needed for specifying the PYTHONPATH later
    export PYTHON_VERSION=$($python_exe --version | cut -d ' ' -f 2 | cut -d '.' -f 1,2)
    export PYTHON_LIB_DIR_NAME=lib/python$PYTHON_VERSION/site-packages

}

# External requirements for building the GUI
# Must be run after the venv is created
_create_makefile_ext() {
    echo "INCLUDE_DIRS = . $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp /usr/include/root /usr/include/libpng16 /usr/include/jemalloc $(python3-config --includes | sed -e 's/-I//g') $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src /usr/include/google/protobuf /usr/include/boost

LIBRARY_DIRS = . /usr/lib64/root $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib /usr/lib /usr/lib64 $(python3-config --ldflags | sed -e 's/-L//g' | sed -e '[[:space:]]-l[a-zA-Z0-9\.]+')  $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/ $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/
" >$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/makefile.ext

}

# Compile and setup all the required stuff that DQMGUI needs.
# Custom libraries, binaries, links to other libraries...
# Then runs the actual compilation, which is the part that takes the longest
# in this script.
compile_dqmgui() {
    cd $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/
    # Links to python libraries so that the build command can find them
    if [ ! -L $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libboost_python.so ]; then
        ln -s /usr/lib64/libboost_python3.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libboost_python.so
    fi

    if [ ! -L "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libpython${PYTHON_VERSION}.so" ]; then
        ln -s /usr/lib64/libpython3.so "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libpython${PYTHON_VERSION}.so"
    fi

    # The actual build command. Uses the makefile in the DQMGUI's repo.
    PYTHONPATH="$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib/python${PYTHON_VERSION}/site-packages:$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib64/python${PYTHON_VERSION}/site-packages" CPLUS_INCLUDE_PATH="$(python3-config --includes | sed -e 's/-I//g')" $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/python $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/setup.py -v build_system -s DQM -d

    # Stuff that I found being done in the dqmgui spec file. I kind of blindy copy paste it
    # here because reasons.
    $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/python $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/setup.py -v install_system -s DQM

    # Move executables to expected place
    for exe in DQMCollector visDQMIndex visDQMRender; do
        mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/$exe $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/bin/$exe
    done

    # Move libs to expected place
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/
    mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/libDQMGUI.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/libDQMGUI.so

    # Move the custom Boost.Python interface library to libs.
    mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/Accelerator.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/build/lib/Monitoring/DQM/Accelerator.so
}

# Installation procedure of the DQMGUI repository.
# Based on recipe I found here: https://github.com/cms-sw/cmsdist/blob/comp_gcc630/dqmgui.spec
# The resulting directory structure and compiled binaries is a mess, but that's the best
# we can do right now, considering the existing mess.
install_dqmgui() {
    # Temporary directory to clone GUI into
    DQMGUI_TMP_DIR=/tmp/128
    _clone_from_git $DQMGUI_GIT_URL $DQMGUI_GIT_TAG $DQMGUI_TMP_DIR

    # Move dqmgui source and bin files to appropriate directory
    if [ -d $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG ]; then
        rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG
    fi
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128

    mv $DQMGUI_TMP_DIR $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG

    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/data
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/
    if [ -d $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates ]; then
        rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates
    fi

    mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/templates $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates

    if [ ! -L $INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui ]; then
        echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG <-- $INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui"
        ln -s $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG $INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui
    fi

    # Create python venv for all python "binaries" and webserver
    _create_python_venv

    # Create files needed by manage script for env variables
    _create_env_and_init_sh

    # Dynamic parametrization of the makefile, i.e. paths required
    # during the compilation procedure.
    _create_makefile_ext
}

install_yui() {
    YUI_TMP_DIR=/tmp/yui
    _clone_from_git $YUI_GIT_URL $YUI_GIT_TAG $YUI_TMP_DIR
    mv $YUI_TMP_DIR $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/yui
}

install_extjs() {
    EXTJS_TMP_DIR=/tmp/extjs
    _clone_from_git $EXTJS_GIT_URL $EXTJS_GIT_TAG $EXTJS_TMP_DIR
    mv $EXTJS_TMP_DIR $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/extjs
}

install_d3() {
    D3_TMP_DIR=/tmp/d3
    _clone_from_git $D3_GIT_URL $D3_GIT_TAG $D3_TMP_DIR
    mv $D3_TMP_DIR $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/d3
}

install_jsroot() {
    JSROOT_TMP_DIR=/tmp/jsroot
    _clone_from_git $JSROOT_GIT_URL $JSROOT_GIT_TAG $JSROOT_TMP_DIR
    mv $JSROOT_TMP_DIR $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/jsroot
}

### Main script ###

# Declare each step of the installation procedure here. Steps
# will be executed sequentially.
declare -a installation_steps=(preliminary_checks
    check_dependencies
    create_directories
    install_boost_gil
    install_gil_numeric
    install_rotoglup
    install_classlib
    compile_classlib
    install_dmwm
    install_dqmgui
    compile_dqmgui
    install_yui
    install_extjs
    install_d3
    install_jsroot)

# Create dynamic flags to selectively disable/enable steps of the installation
# Those flags are named "do_" with the name of the function, e.g. "do_install_yui" for
# the "install_yui" step and "do_check_dependencies" for "check_dependencies".
# We set those flags to 1 by default.
for step in "${installation_steps[@]}"; do
    eval "do_${step}=1"
done

# Parse command line arguments -- use <key>=<value> to override the flags mentioned above.
# e.g. do_install_yui=0
for ARGUMENT in "$@"; do
    KEY=$(echo "$ARGUMENT" | cut -f1 -d=)
    KEY_LENGTH=${#KEY}
    VALUE="${ARGUMENT:$KEY_LENGTH+1}"
    eval "$KEY=$VALUE"
done

# Go to the installation directory
cd $INSTALLATION_DIR/

# The actual installation procedure.
# For each step, check if the appropriate flag is enabled.
for step in "${installation_steps[@]}"; do

    installation_step_flag_name=do_$step
    if [ "${!installation_step_flag_name}" -ne 0 ]; then
        echo "Installation step: $step"
        # Run the actual function
        eval "$step"
    else
        echo "Skipping step: $step"
    fi

done

echo "INFO: Complete!"
