#!/bin/bash

# This script sets up a new Ubuntu machine to be able to run the bash scripts
# in this repo. Inspiration was taken from here:
# https://hackmd.io/@yisun/BkT0RS87q

# Script should be run like so
# ./machine_initialization.sh <ptau_size> <branch>
# ./machine_initialization.sh 25 main

############################################
############## ERROR HANDLING ##############
############################################

# http://stackoverflow.com/questions/35800082/ddg#35800451
set -eE

# call like `graceful_exit <exit_code>`
function graceful_exit {
    printf "\n####### EXITING... #######\n"
    DEFAULT_EXIT_CODE=0
    exit ${1:-$DEFAULT_EXIT_CODE} # use first param or default to 0
}

# Print line number & message of error and exit gracefully
# call like `err_report $LINENO $ERR_MSG`
function err_report {
    ret=$? # previous command exit value
    printf "\n####### A COMMAND FAILED ON LINE $1 #######\n\n"
    echo "Error message: ${@:2}"
    graceful_exit "$ret"
}

# can change this in the functions below to get nicer error messages
# make sure to set back to "UNKNOWN" at end of function scope
ERR_MSG="UNKNOWN"

# global error catcher
trap 'err_report $LINENO $ERR_MSG' ERR

############################################
################ VARIABLES #################
############################################

DEFAULT_PTAU_SIZE=18
PTAU_SIZE=${1:-$DEFAULT_PTAU_SIZE}

DEFAULT_BRANCH="main"
BRANCH=${2:-$DEFAULT_BRANCH}

############################################
####### APT SOFTWARE INSTALLATION ##########
############################################

ERR_MSG="Initial setup failed"

sudo apt update && sudo apt upgrade -y

sudo apt install -y nodejs build-essential gcc pkg-config libssl-dev libgmp-dev libsodium-dev nasm nlohmann-json3-dev cmake m4

############################################
############### CLOUDWATCH #################
############################################

# Setup memory metrics for CloudWatch
# https://stackoverflow.com/questions/42317062/how-to-monitor-ec2-instances-by-memory

ERR_MSG="CloudWatch setup failed"

sudo wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
echo '{"metrics":{"metrics_collected":{"mem":{"measurement":["mem_used_percent"],"metrics_collection_interval":30}}}}' | sudo tee -a /opt/aws/amazon-cloudwatch-agent/bin/config.json > /dev/null
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s

############################################
############## SYSTEM CONFIG ###############
############################################

# Increase kernel memory map per process, and persist after reboot
# https://www.kernel.org/doc/Documentation/sysctl/vm.txt
sudo sysctl -w vm.max_map_count=655300
sudo sh -c 'echo "vm.max_map_count=655300" >>/etc/sysctl.conf'

# Increase swap memory, and persist after reboot
# https://serverfault.com/questions/967852/swapfile-mount-etc-fstab-swap-swap-or-none-swap
sudo fallocate -l 400G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile whatever swap sw 0 0' | sudo tee -a /etc/fstab

############################################
##### CUSTOM SOFTWARE INSTALLATION #########
############################################

# PNPM
ERR_MSG="PNPM setup failed"
curl -fsSL https://get.pnpm.io/install.sh | sh -
source /home/ubuntu/.bashrc
pnpm add npx -g

# Rust
ERR_MSG="Rust setup failed"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Circom
ERR_MSG="Circom setup failed"
git clone https://github.com/iden3/circom.git
cd circom
cargo build --release
cargo install --path circom
cd -

# Patched node
ERR_MSG="Node setup failed"
git clone https://github.com/nodejs/node.git
cd node
git checkout 8beef5eeb82425b13d447b50beafb04ece7f91b1
./configure
make -j16
NODE_PATH=$HOME/node/out/Release/node
cd -

# Rapidsnark
git clone git@github.com:iden3/rapidsnark.git
cd rapidsnark
pnpm i
git submodule init
git submodule update
npx task createFieldSources
npx task buildProver
RAPIDSNARK_PATH=$HOME/rapidsnark/build/prover
cd -

# Setup repo
ERR_MSG="Repo setup failed"
git clone https://github.com/silversixpence-crypto/zk-proof-of-assets
cd zk-proof-of-assets
wget https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_"$PTAU_SIZE".ptau
git switch -c "$BRANCH" origin/"$BRANCH"
pnpm i
git submodule init
git submodule update


