#!/bin/bash
#
# Script intended for installing [legacy] DQMGUI on online HLT machines (dqmsrv-...).
# It tries to imitate the behavior of the Deploy script without installing external RPMs.
#
# The installation depends on the steps defined in the installation_steps array.
# They are executed in sequence and can be skipped with the appropriate flag.
#
# Only targeting RHEL8 + Python3.8 for now(!)
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
EUID_USER_DQM=40454

# Main directory we're installing into.
INSTALLATION_DIR=/data/srv

# Where ROOT will be installed
ROOT_INSTALLATION_DIR=$INSTALLATION_DIR/root

# This scipt's directory
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Get constants from config file
# This is needed to name some directories whose name is
# based on the version of the package (DMWM and DQMGUI).
source $SCRIPT_DIR/config.sh

# Preliminary checks to do before installing the GUI
preliminary_checks() {
    # Make sure we don't have superuser privileges
    if [[ $EUID -eq 0 ]]; then
        echo "This script should not be run with superuser privileges!" 1>&2
        exit 1
    fi

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

    # Stop GUI if already running
    if [ -f $INSTALLATION_DIR/$DMWM_GIT_TAG/config/dqmgui/manage ]; then
        $INSTALLATION_DIR/$DMWM_GIT_TAG/config/dqmgui/manage stop 'I did read documentation'
    fi

    # Delete installation (config & sw, does not delete state)
    if [ -d $INSTALLATION_DIR/$DMWM_GIT_TAG ]; then
        echo "WARNING: $INSTALLATION_DIR/$DMWM_GIT_TAG exists, deleting contents"
        rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/*
    fi

}

# Check for needed OS-wide dependencies
check_dependencies() {
    pkgs_installed=1
    declare -a required_packages=(patch unzip bzip2 libglvnd-opengl libX11-devel libXext-devel libXft-devel
        libXpm-devel mesa-libGLU mesa-libGLU-devel perl-Env perl-Switch
        perl-Thread-Queue glibc-headers libidn libXcursor
        libXi libXinerama libXrandr perl perl-Digest-MD5 tcsh zsh epel-release
        libcurl-devel python38 python38-devel boost-python3-devel protobuf-devel jemalloc-devel
        pcre-devel boost-devel lzo-devel cmake xz-devel openssl-devel
        libjpeg-turbo-devel libpng-devel gcc-c++ gcc binutils gcc-gfortran mesa-libGL-devel mesa-libGLU-devel
        glew-devel ftgl-devel fftw-devel cfitsio-devel graphviz-devel libuuid-devel avahi-compat-libdns_sd-devel
        openldap-devel python3-numpy libxml2-devel gsl-devel readline-devel R-devel R-Rcpp-devel R-RInside-devel
        xrootd-client)

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

# Remove existing DQMGUI cronjobs
clean_crontab() {
    # Filter cronjobs starting in $INSTALLATION_DIR/current/dqmgui and
    # replace crontabs
    crontab -l 2>/dev/null | grep -v "$INSTALLATION_DIR/current/config/dqmgui" | grep -vE "$INSTALLATION_DIR/current.+logrotate.conf" | crontab -
}

# Install DQMGUI cronjobs
install_crontab() {
    _create_logrotate_conf

    (
        crontab -l # Get existing crontabs
        echo "17 2 * * * $INSTALLATION_DIR/current/config/dqmgui/daily"
        echo "@reboot $INSTALLATION_DIR/current/config/dqmgui/manage sysboot"
        echo "0 3 * * * logrotate $INSTALLATION_DIR/current/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/logrotate.conf --state $INSTALLATION_DIR/state/logrotate.state"
    ) | crontab -
}

# TODO: Clean acrontabs for Offline GUI
clean_acrontab() {
    : # Not implemented yet
}

# TODO: Install acrontabs for Offline GUI
install_acrontab() {
    : # Not implemented yet
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
        # State dirs
        dirname="$INSTALLATION_DIR/state/dqmgui/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
        # Log dirs
        dirname="$INSTALLATION_DIR/logs/dqmgui/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
    done

    # Dirs to create under DMWM_GIT_TAG dir
    declare -a necessary_dirs=("config" "sw" "apps.sw")
    for subdir in "${necessary_dirs[@]}"; do
        dirname="$INSTALLATION_DIR/$DMWM_GIT_TAG/$subdir"
        echo "DEBUG: Creating subdirectory $dirname"
        mkdir -p "$dirname"
    done

    if [ ! -L "$INSTALLATION_DIR/$DMWM_GIT_TAG/apps" ]; then
        echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG/apps.sw <-- $INSTALLATION_DIR/$DMWM_GIT_TAG/apps"
        ln -s "$INSTALLATION_DIR/$DMWM_GIT_TAG/apps.sw" "$INSTALLATION_DIR/$DMWM_GIT_TAG/apps"
    fi

    # Create a "current" link to the DMWM version we're using, like how it was done
    # in the older scripts.
    if [ -L $INSTALLATION_DIR/current ]; then
        rm $INSTALLATION_DIR/current
    fi
    echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG <-- $INSTALLATION_DIR/current"
    ln -s "$INSTALLATION_DIR/$DMWM_GIT_TAG" "$INSTALLATION_DIR/current"

    # Directories for external source and lib files (e.g. classlib)
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src"
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib"

    # DQMGUI dirs
    echo "DEBUG: Creating subdirectory $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG"
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG"

}

install_rotoglup() {
    ROTOGLUP_TMP_DIR=/tmp/rotoglup
    mkdir -p $ROTOGLUP_TMP_DIR
    tar -xzf "$SCRIPT_DIR/rotoglup/rotoglup.tar.gz" -C /tmp

    cd $ROTOGLUP_TMP_DIR
    #patch -p1 < $SCRIPT_DIR/rotoglup/patches/01.patch
    patch -p1 <"$SCRIPT_DIR/rotoglup/patches/02.patch"
    mv $ROTOGLUP_TMP_DIR/rtgu $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/rtgu
    cd $INSTALLATION_DIR/
    rm -rf $ROTOGLUP_TMP_DIR
}

# Compilation step for classlib
compile_classlib() {
    cd "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3"

    #INCLUDE_DIRS="$INCLUDE_DIRS:/usr/include/lzo" make -j `nproc`
    make -j "$(nproc)" CXXFLAGS="-Wno-error=extra -ansi -pedantic -W -Wall -Wno-long-long -Werror"

    # Move the compiled library in the libs dir
    mv "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3/.libs/libclasslib.so" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libclasslib.so"

}

# Classlib is needed both as a shared object and for its header files for DQMGUI compilation.
install_classlib() {
    # Temporary directory to extract to
    CLASSLIB_TMP_DIR=/tmp/classlib-3.1.3
    mkdir -p $CLASSLIB_TMP_DIR
    tar -xf "$SCRIPT_DIR/classlib/classlib-3.1.3.tar.bz2" -C /tmp

    # Apply code patches I found on cmsdist. The 7th one is ours, and has some extra needed fixes.
    cd $CLASSLIB_TMP_DIR
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

    if [ -d "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3" ]; then
        rm -rf "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3"
    fi

    # Move the classlib files inside the installation dir, needed for compiling the GUI
    mv "$CLASSLIB_TMP_DIR" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/"

    # Make a link so that DQMGUI compilation can find the classlib headers easily
    ln -s "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib-3.1.3/classlib" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/classlib"

    rm -rf $CLASSLIB_TMP_DIR
}

install_boost_gil() {
    mkdir -p $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/
    tar -xzf "$SCRIPT_DIR/boost_gil/boost_gil.tar.gz" -C /tmp
    mv /tmp/boost_gil/include/boost "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost"
}

install_gil_numeric() {
    NUMERIC_TMP_DIR=/tmp/numeric
    tar -xzf "$SCRIPT_DIR/numeric/numeric.tar.gz" -C /tmp
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost/gil/extension/"
    mv "$NUMERIC_TMP_DIR" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/boost/gil/extension/numeric"
}

install_dmwm() {
    # Temporary directory to clone DMWM deployment scripts into
    DMWM_TMP_DIR=/tmp/dmwm
    mkdir -p $DMWM_TMP_DIR
    tar -xzf "$SCRIPT_DIR/dmwm/dmwm.tar.gz" -C /tmp
    # Move dqmgui-related scripts from DMWM to the config folder
    mv "$DMWM_TMP_DIR/dqmgui" "$INSTALLATION_DIR/$DMWM_GIT_TAG/config/"

    rm -rf $DMWM_TMP_DIR
}

# Create a configuration file for logrotate to manage...(surprise!) rotating logs.
_create_logrotate_conf() {
    echo "# DQMGUI logrotate configuration file
# Automagically generated, please do not edit.

# Make daily compressed rotations in the same directory, keep up to
# 1 year of logs. Dooes not remove the rotated logs, instead copies the
# contents and truncates them to 0.
$INSTALLATION_DIR/logs/dqmgui/*/*.log {
    daily
    compress
    copytruncate
    rotate 365
    maxage 365
    noolddir
    nomail
    dateext
}
" >"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/logrotate.conf"
}

# env.sh and init.sh file creation. They're needed by other scripts (e.g. manage).
_create_env_and_init_sh() {
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/"

    # init.sh contents. This is sourced by env.sh
    echo "export PATH=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/bin:$PATH
export PYTHONPATH=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib/python${PYTHON_VERSION}/site-packages:$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib64/python${PYTHON_VERSION}/site-packages
.  $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/activate
" >"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/init.sh"

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
export LD_LIBRARY_PATH=\"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/:$LD_LIBRARY_PATH\"
source $ROOT_INSTALLATION_DIR/bin/thisroot.sh
" >"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/profile.d/env.sh"
}

# Crete the Python3 virtual environment for the GUI
_create_python_venv() {
    python_exe=$(which python3)

    python_venv_dir=$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv
    if [ -d "$python_venv_dir" ]; then
        rm -rf "$python_venv_dir"
    fi
    mkdir -p "$python_venv_dir"

    # Extract the downloaded python packages
    tar -xzf "$SCRIPT_DIR/pypi/pypi.tar.gz" -C /tmp
    echo -n "INFO: Creating virtual environment at $python_venv_dir"
    $python_exe -m venv "$python_venv_dir"

    # Now use the new venv's python
    python_venv_exe=$python_venv_dir/bin/python

    # Needed for specifying the PYTHONPATH later
    PYTHON_VERSION=$($python_exe --version | cut -d ' ' -f 2 | cut -d '.' -f 1,2)
    export PYTHON_VERSION

    PYTHON_LIB_DIR_NAME=lib/python$PYTHON_VERSION/site-packages
    export PYTHON_LIB_DIR_NAME

    # Install pip
    unzip -u /tmp/pip/pip*whl -d /tmp/pip/pip
    if [ -d "$python_venv_dir/$PYTHON_LIB_DIR_NAME/pip" ]; then
        rm -rf "$python_venv_dir/$PYTHON_LIB_DIR_NAME/pip"
    fi

    # pipipipi
    mv /tmp/pip/pip/pip "$python_venv_dir/$PYTHON_LIB_DIR_NAME/pip"
    rm -rf /tmp/pip/pip

    # Install wheels
    eval "${python_venv_exe} -m pip install --no-index --find-links /tmp/pip /tmp/pip/*"
    eval "${python_venv_exe} -m pip install $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128"

    cd "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/"
    rm -rf /tmp/pip
    echo "Done"
}

# External requirements for building the GUI
# Must be run after the venv is created
_create_makefile_ext() {
    echo "INCLUDE_DIRS = . $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp /usr/include/libpng16 /usr/include/jemalloc $(root-config --incdir) $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src /usr/include/google/protobuf /usr/include/boost $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/root

LIBRARY_DIRS = . $ROOT_INSTALLATION_DIR/lib $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib /usr/lib /usr/lib64 $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/ $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/
" >"$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/etc/makefile.ext"
}

# Compile and setup all the required stuff that DQMGUI needs.
# Custom libraries, binaries, links to other libraries...
# Then runs the actual compilation, which is the part that takes the longest
# in this script.
compile_dqmgui() {
    cd "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/"
    # Links to python libraries so that the build command can find them
    if [ ! -L "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libboost_python.so" ]; then
        ln -s /usr/lib64/libboost_python3.so "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libboost_python.so"
    fi

    if [ ! -L "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libpython${PYTHON_VERSION}.so" ]; then
        ln -s /usr/lib64/libpython3.so "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/lib/libpython${PYTHON_VERSION}.so"
    fi

    # python3-config is not always in a predictable place
    python_config_cmd=$(which python3-config) || python_config_cmd=$(find /usr/bin -name "python3*-config" | head -1)

    if [ -z "$python_config_cmd" ]; then
        echo "ERROR: Could not find python3-config"
        exit 1
    fi
    # The actual build command. Uses the makefile in the DQMGUI's repo.
    source "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/activate"
    PYTHONPATH="$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib/python${PYTHON_VERSION}/site-packages:$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/lib64/python${PYTHON_VERSION}/site-packages" CPLUS_INCLUDE_PATH="$(${python_config_cmd} --includes | sed -e 's/-I//g')" $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/python $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/setup.py -v build_system -s DQM -d

    # Stuff that I found being done in the dqmgui spec file. I kind of blindy copy paste it
    # here because reasons.
    $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/bin/python $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/setup.py -v install_system -s DQM

    # Move executables to expected place
    for exe in DQMCollector visDQMIndex visDQMRender; do
        mv "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/$exe" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/bin/$exe"
    done

    # Move libs to expected place
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/"
    mv "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/libDQMGUI.so" $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/lib/libDQMGUI.so

    # Move the custom Boost.Python interface library to libs.
    mv $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/cpp/Accelerator.so $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/build/lib/Monitoring/DQM/Accelerator.so

    # Compiles layouts etc.
    $INSTALLATION_DIR/current/config/dqmgui/manage compile
}

# Installation procedure of the DQMGUI repository.
# Based on recipe I found here: https://github.com/cms-sw/cmsdist/blob/comp_gcc630/dqmgui.spec
# The resulting directory structure and compiled binaries is a mess, but that's the best
# we can do right now, considering the existing mess.
install_dqmgui() {
    # Activate ROOT, we need it to be available so that we can run root-config later
    source "$INSTALLATION_DIR/root/bin/thisroot.sh"

    # Temporary directory to clone GUI into
    DQMGUI_TMP_DIR=/tmp/dqmgui
    tar -xzf "$SCRIPT_DIR/dqmgui/dqmgui.tar.gz" -C /tmp

    # Move dqmgui source and bin files to appropriate directory
    if [ -d "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG" ]; then
        rm -rf "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG"
    fi
    mkdir -p "$DQMGUI_TMP_DIR" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/"
    mv $DQMGUI_TMP_DIR "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128"

    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/data"

    if [ ! -L "$INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui" ]; then
        echo "DEBUG: Creating link $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG <-- $INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui"
        ln -s "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG" "$INSTALLATION_DIR/$DMWM_GIT_TAG/apps/dqmgui"
    fi

    # Create python venv for all python "binaries" and webserver
    _create_python_venv

    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/" # Needed for DQMGUI templates
    if [ -d "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates" ]; then
        rm -rf "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates"
    fi

    mv "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/cms/dqmgui/$DQMGUI_GIT_TAG/128/src/templates" "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/venv/data/templates"

    # Create files needed by manage script for env variables
    _create_env_and_init_sh

    # Dynamic parametrization of the makefile, i.e. paths required
    # during the compilation procedure.
    _create_makefile_ext

    # TODO: find more info on blacklist.txt file
}

# Javascript library
install_yui() {
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/yui"
    tar -xzf "$SCRIPT_DIR/yui/yui.tar.gz" -C "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external"
}

# Javascript library
install_extjs() {
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/extjs"
    tar -xzf "$SCRIPT_DIR/extjs/extjs.tar.gz" -C "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external"
}

# Javascript library
install_d3() {
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/d3"
    tar -xzf "$SCRIPT_DIR/d3/d3.tar.gz" -C "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external"
}

# Javascript library
install_jsroot() {
    mkdir -p "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/jsroot"
    tar -xzf "$SCRIPT_DIR/jsroot/jsroot.tar.gz" -C "$INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external"
}

# Extract the ROOT tar to a tmp folder for compilation
install_root() {
    tar -xzf "$SCRIPT_DIR/root/root.tar.gz" -C /tmp
    #if [ -d $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/root ]; then
    #	rm -rf $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/root
    #fi
    #
    #cp -r /tmp/root $INSTALLATION_DIR/$DMWM_GIT_TAG/sw/external/src/root
}

compile_root() {
    ROOT_TMP_DIR=/tmp/root
    ROOT_TMP_BUILD_DIR=/tmp/root_build
    if [ ! -d $ROOT_TMP_DIR ]; then
        echo "ERROR: ROOT source was not found in $ROOT_TMP_DIR"
        exit 1
    fi

    if source "$ROOT_INSTALLATION_DIR/bin/thisroot.sh"; then
        echo "INFO: ROOT installation found, not re-compiling ROOT"
        return
    fi
    mkdir -p $ROOT_TMP_BUILD_DIR
    cd $ROOT_TMP_BUILD_DIR
    cmake -DCMAKE_INSTALL_PREFIX=$ROOT_INSTALLATION_DIR $ROOT_TMP_DIR -DPython3_ROOT_DIR=$(which python3) -Dtesting=OFF -Dbuiltin_gtest=OFF
    cmake --build . --target install -j $(nproc)
    cd $INSTALLATION_DIR
    rm -rf $ROOT_TMP_DIR $ROOT_TMP_BUILD_DIR
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
    install_root
    compile_root
    install_dqmgui
    compile_dqmgui
    install_yui
    install_extjs
    install_d3
    install_jsroot
    clean_crontab
    install_crontab
    clean_acrontab
    install_acrontab)

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
