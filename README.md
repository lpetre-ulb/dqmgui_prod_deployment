# [Legacy] DQMGUI Deployment

[![Build DQMGUI Installation Package](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml/badge.svg)](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml)

This repository contains all the requirements for deploying the [Legacy] [DQMGUI](https://github.com/cms-DQM/dqmgui_prod) on a Red Hat Enterprise Linux 8 machine, with Python3.8 for the needs of moving DQM production to new machines.

It aims to replace the existing one (`Deploy`), found in [`dmwm/deployment`](https://github.com/dmwm/deployment/tree/master/Deploy), which only targets OS up to SLC7. The main difference is that the `Deploy` script relies on pre-built libraries and executables, found on `cmsrep.cern.ch`, while the method we implement in this repository depends on two steps:

1. Download all the external resources needed (e.g. python packages from PyPI, github repositories) and compress them. This is done automatically with GitHub actions, and you can download a package ready to install [here](https://github.com/cms-DQM/dqmgui_prod_deployment/actions/workflows/build_installation_package.yaml).
2. Copy the archives to the P5 machine and extract, then build from source (hence takes longer to deploy).

> [!WARNING]
> This deployment script should *not* be run as a sudo user.

Complete instructions and more information can be found on the [Wiki](https://github.com/cms-DQM/dqmgui_prod_deployment/wiki).
