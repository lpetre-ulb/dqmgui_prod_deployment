#!/bin/bash

# Configuration file, which is sourced by both download_dependencies.sh and deploy_dqmgui.sh
# Here we specify both the URLs and tags/branches/refs of the repositories that DQMGUI
# depends on.

# Target python version. This is important for downloading
# compatible packages for PyPI. Make sure it's the same
# with the python version that is running on the target machine.
PYTHON_VERSION=3.9

# Tag to use for getting the layouts and manage/deploy scripts
# See: https://github.com/dmwm/deployment/tags
#DMWM_GIT_URL=https://github.com/dmwm/deployment
DMWM_GIT_URL=https://github.com/nothingface0/cms_dmwm_deployment
#DMWM_GIT_TAG=debug
DMWM_GIT_TAG=85f9f02fc8c62cdbbad601039feb991f27f28d09

# DQMGUI tag to use, see https://github.com/cms-DQM/dqmgui_prod/tags
DQMGUI_GIT_URL=https://github.com/cms-DQM/dqmgui_prod
#DQMGUI_GIT_TAG=python3_backup
DQMGUI_GIT_TAG=ad780c5099f258d3e7b66d34f13f7a3212db527a

# Boost.GIL. At most version 1.67!! The API changed radically after that.
BOOST_GIL_GIT_URL=https://github.com/boostorg/gil
BOOST_GIL_GIT_TAG=boost-1.66.0

# OLD rotoglup code. Commit was found with lots of pain, so that the patch
# applies: https://github.com/cms-sw/cmsdist/blob/comp_gcc630/dqmgui-rtgu.patch
ROTOGLUP_GIT_URL=https://github.com/rotoglup/rotoglup-scratchpad
ROTOGLUP_GIT_TAG=d8ce23aecd0b1fb7d45c9bedb615abdab27a5494

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

# ROOT
ROOT_GIT_URL=https://github.com/root-project/root/
ROOT_GIT_TAG=v6-28-08
