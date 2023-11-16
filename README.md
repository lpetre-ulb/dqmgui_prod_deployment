# [Legacy] DQMGUI Deployment

[![Build DQMGUI Installation Package](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml/badge.svg)](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml)

This repository contains all the requirements for deploying the [Legacy] [DQMGUI](https://github.com/cms-DQM/dqmgui_prod) on a Red Hat Enterprise Linux 8 machine, with Python3.8 for the needs of moving DQM production to new machines.

It aims to replace the existing one (`Deploy`), found in [`dmwm/deployment`](https://github.com/dmwm/deployment/tree/master/Deploy), which only targets OS up to SLC7. The main difference is that the `Deploy` script relies on pre-built libraries and executables, found on `cmsrep.cern.ch`, while the method we implement in this repository depends on two steps:

1. Download all the external resources needed (e.g. python packages from PyPI, github repositories) and compress them. This is done automatically with GitHub actions, and you can download a package ready to install [here](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml).
2. Copy the archives to the P5 machine and extract, then build from source (hence takes longer to deploy).

> **Warning**
> This deployment script should *not* be run as a sudo user.

## Requirements

- RHEL8 (Tested with version 8.8)
- `sudo` permissions:
  - To install the system-wide packages (listed below).
- Python 3.8
- Several system packages, installed via `yum`:
  <details>
  <summary>Package list</summary>

  - unzip
  - bzip2
  - libglvnd-opengl
  - libX11-devel
  - libXext-devel
  - libXft-devel
  - libXpm-devel
  - mesa-libGLU
  - mesa-libGLU-devel
  - perl-Env
  - perl-Switch
  - perl-Thread-Queue
  - glibc-headers
  - libidn
  - libXcursor
  - libXi
  - libXinerama
  - libXrandr
  - perl
  - perl-Digest-MD5
  - tcsh
  - zsh
  - epel-release
  - libcurl-devel
  - python38
  - python38-devel
  - boost-python3-devel
  - protobuf-devel
  - jemalloc-devel
  - pcre-devel
  - boost-devel
  - lzo-devel
  - cmake
  - xz-devel
  - openssl-devel
  - libjpeg-turbo-devel
  - libpng-devel
  - gcc-c++
  - gcc
  - binutils
  - gcc-gfortran
  - mesa-libGL-devel
  - mesa-libGLU-devel
  - glew-devel
  - ftgl-devel
  - fftw-devel
  - cfitsio-devel
  - graphviz-devel
  - libuuid-devel
  - avahi-compat-libdns_sd-devel
  - openldap-devel
  - python3-numpy
  - libxml2-devel
  - gsl-devel
  - readline-devel
  - R-devel
  - R-Rcpp-devel
  - R-RInside-devel
  - xrootd-client
  </details>

## Deploying [Legacy] DQMGUI

This procedure has been tested on a RHEL8 Openstack VM. Instructions below are primarily for a personal VM.

0.

  a. Download the latest build artifact and copy it to the machine you want to install it to:

  ```bash
  curl -L https://github.com/cms-DQM/dqmgui_prod_deployment/releases/download/latest/dqmgui_installation_package.tar.gz --output dqmgui_installation_package.tar.gz
  scp dqmgui_installation_package.tar.gz root@<VM machine>:/tmp/
  ```

  OR

  b. Download all the required files yourself:

  ```bash
  # This will create a dqmgui_installation_package.tar.gz in /tmp
  bash download_dependencies.sh && bash build_installation_package.sh
  scp /tmp/dqmgui_installation_package.tar.gz root@<VM machine>:/tmp/
  ```

1. Connect to the VM and install the system packages:

  ```bash
  sudo yum install -y patch unzip bzip2 libglvnd-opengl libX11-devel libXext-devel libXft-devel libXpm-devel mesa-libGLU mesa-libGLU-devel perl-Env perl-Switch perl-Thread-Queue glibc-headers libidn libXcursor libXi libXinerama libXrandr perl perl-Digest-MD5 tcsh zsh epel-release libcurl-devel python38 python38-devel boost-python3-devel protobuf-devel jemalloc-devel pcre-devel boost-devel lzo-devel cmake xz-devel openssl-devel libjpeg-turbo-devel libpng-devel gcc-c++ gcc binutils gcc-gfortran mesa-libGL-devel mesa-libGLU-devel glew-devel ftgl-devel fftw-devel cfitsio-devel graphviz-devel libuuid-devel avahi-compat-libdns_sd-devel openldap-devel python3-numpy libxml2-devel gsl-devel readline-devel R-devel R-Rcpp-devel R-RInside-devel xrootd-client
  ```

2. Add a non-privileged user, create and give access to necessary directories and switch to it:

  ```bash
  adduser dqm

  # Installation directory
  sudo mkdir -p /data/srv
  sudo chown -R dqm /data/srv

  # Data directory
  sudo mkdir -p /dqmdata/dqm
  sudo chown -R dqm /dqmdata

  # Installation package
  sudo chown dqm /tmp/dqmgui_installation_package.tar.gz

  sudo su dqm
  ```

3. Start the deployment (`dev` flavor):

  ```bash
  cd ~
  tar -xf dqmgui_installation_package.tar.gz -C dqmgui_deployment

  # Start the deployment script, it will take some time to finish
  bash /home/dqm/dqmgui_deployment/deploy_dqmgui.sh

  # Start all the services
  /data/srv/current/config/dqmgui/manage -f dev start "I did read documentation"
  ```

4. Open firewall ports (if needed):

  ```bash
  firewall-cmd --list-all-zones
  firewall-cmd --zone=public --add-port=8030/tcp # online
  firewall-cmd --zone=public --add-port=8060/tcp # dev
  firewall-cmd --zone=public --add-port=8070/tcp # online/dev
  firewall-cmd --zone=public --add-port=8080/tcp # offline
  firewall-cmd --zone=public --add-port=8081/tcp # relval
  ```

## Deployment command-line arguments

This script uses some internal variables to specify options such as the main installation directory, or the git tags/refs to use when cloning repositories. It's not recommended that you edit those, as most of them are hand-picked so that the project compiles (we're mostly referring to the git refs).

However, if needed, you can override them by passing them as arguments to the script in the form of `<variable name>=<value` (e.g. `bash deploy_dqmgui.sh INSTALLATION_DIR="~/dqmgui"`).

Below is a list of the values that you will most probably need to change to customize your installation.

| Variable name | Description |Default value |
|---------------|-------------|--------------|
| `INSTALLATION_DIR` | The directory to install the GUI into. It should be writable by the user running the script | `/data/srv` |

### [Debug] Selectively run parts of the installation script

The script is split into steps (see the `installation_steps` array declared in the `deploy_dqmgui.sh` script), which can all be toggled off or on by arguments when running the script.

The flags are named by concatenating `do_` with the name of the step, so, for example, `do_check_dependencies` or `do_install_rotoglup`.

The are all set to `1` by default, and you can override them when running the script as follows:

```bash
bash deploy_dqmgui.sh do_preliminary_checks=0 do_check_dependencies=0
```

A useful combination that can be used when you've already installed and built all steps once, but you only want to re-compile the DQMGUI part for testing:

```bash
bash deploy_dqmgui.sh do_preliminary_checks=0 do_check_dependencies=0 do_create_directories=1 do_install_boost_gil=0 do_install_gil_numeric=0 do_install_rotoglup=0 do_install_classlib=0 do_compile_classlib=0 do_install_dmwm=0 do_install_root=0 do_compile_root=0 do_install_dqmgui=0 do_compile_dqmgui=1 do_install_yui=0 do_install_extjs=0 do_install_d3=0 do_install_jsroot=0
```

## Download script

The installation package is created by running `download_dependencies.sh`. This is done automatically by github actions (see `.github/workflows/build_installation_package` in this repository). The versions of the packages downloaded are specified in `config.sh`.

## Notes

- We're not using the RHEL8 `root` package, due to the fact that they are built for python3.6, hence we need to build it with python3.8.
