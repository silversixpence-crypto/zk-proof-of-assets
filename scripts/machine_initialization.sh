#!/usr/bin/env bash

# This script sets up a new Debian machine to be able to run the bash scripts
# in this repo. Inspiration was taken from here:
# https://hackmd.io/@yisun/BkT0RS87q

# Get the path to the directory this script is in.
INIT_SCRIPT_PATH="$(realpath "${BASH_SOURCE[-1]}")"
INIT_SCRIPT_DIRECTORY="$(dirname "$INIT_SCRIPT_PATH")"

############################################
########### ERROR HANDLING #################
############################################

# Inspiration taken from
# https://unix.stackexchange.com/questions/462156/how-do-i-find-the-line-number-in-bash-when-an-error-occured
# https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html

# Change this in sourcing script to get error messages.
ERR_MSG="UNKNOWN"

set -eE -o functrace

failure() {
    local lineno=$2
    local fn=$3
    local exitstatus=$4
    local cmd=$5
    local msg=$6
    local lineno_fns=${1% 0}
    if [[ "$lineno_fns" != "0" ]]; then
        lineno="${lineno} ${lineno_fns}"
    fi
    printf "\n####### ERROR #######\n\n"
    echo "  Failure in file:                    ${BASH_SOURCE[1]}"
    echo "  Function trace [line numbers]:      ${fn} [${lineno}]"
    echo "  Exit status:                        ${exitstatus}"
    echo "  Command that failed:                $cmd"
    echo "  Error message:                      $msg"
}
trap 'failure "${BASH_LINENO[*]}" "$LINENO" "${FUNCNAME[*]:-script}" "$?" "$BASH_COMMAND" "$ERR_MSG"' ERR

############################################
################ DEFAULTS ##################
############################################

DEFAULT_PTAU_SIZE=18
DEFAULT_SWAP_SIZE=400G

############################################
################ CLI FLAGS #################
############################################

# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash#21128172

CLOUDWATCH=false
SWAP=false
PTAU=false
REPO=false
VERBOSE=false

print_usage() {
    printf "
Setup various software required to used the zk-proof-of-asset repo.

USAGE:
    ./machine_initialization.sh [FLAGS] [OPTIONS]

FLAGS:

     -c            AWS CloudWatch memory metrics
                   See this for more info https://stackoverflow.com/questions/42317062/how-to-monitor-ec2-instances-by-memory

     -P            Download ptau file number $DEFAULT_PTAU_SIZE & put in $HOME/zk-proof-of-assets

     -S            Create a swap file with default size: $DEFAULT_SWAP_SIZE

     -v            Print commands that are run (set -x)

     -h            Help

OPTIONS:

     -b <BRANCH>   Checkout <BRANCH> in $HOME/zk-proof-of-assets

     -p <NUM>      Download ptau file <NUM> & put in $HOME/zk-proof-of-assets
                   See all ptau files here https://github.com/iden3/snarkjs?tab=readme-ov-file#7-prepare-phase-2

     -r <DIR>      Clone zk-proof-of-assets repo into <DIR>

     -s <SIZE>     Create swap file of size <SIZE> (recommended for large circuits)
"
}

while getopts 'cvhr:Ss:b:Pp:' flag; do
    case "${flag}" in
    c) CLOUDWATCH=true ;;
    s)
        SWAP=true
        SWAP_SIZE_INPUT="${OPTARG}"
        ;;
    S) SWAP=true ;;
    r)
        REPO=true
        REPO_PARENT_DIR="${OPTARG}"
        ;;
    b) BRANCH="${OPTARG}" ;;
    p)
        PTAU=true
        PTAU_SIZE_INPUT="${OPTARG}"
        ;;
    P) PTAU=true ;;
    v) VERBOSE=true ;;
    h)
        print_usage
        exit 1
        ;;
    *)
        print_usage
        exit 1
        ;;
    esac
done

SWAP_SIZE=${SWAP_SIZE_INPUT:-$DEFAULT_SWAP_SIZE}
PTAU_SIZE=${PTAU_SIZE_INPUT:-$DEFAULT_PTAU_SIZE}

if $VERBOSE; then
    # print commands before executing
    set -x
fi

############################################
####### APT SOFTWARE INSTALLATION ##########
############################################

ERR_MSG="Initial setup failed"

sudo apt update && sudo apt upgrade -y

sudo apt install -y build-essential gcc pkg-config libssl-dev libgmp-dev libsodium-dev nasm nlohmann-json3-dev cmake m4 curl wget git time patch parallel

# for pyenv
sudo apt install -y --no-install-recommends make zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev llvm libncurses5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

############################################
############### CLOUDWATCH #################
############################################

# Setup memory metrics for CloudWatch
# https://stackoverflow.com/questions/42317062/how-to-monitor-ec2-instances-by-memory

if $CLOUDWATCH; then
    ERR_MSG="CloudWatch setup failed"

    sudo wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
    echo '{"metrics":{"metrics_collected":{"mem":{"measurement":["mem_used_percent"],"metrics_collection_interval":30}}}}' | sudo tee -a /opt/aws/amazon-cloudwatch-agent/bin/config.json >/dev/null
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s
fi

############################################
############## SYSTEM CONFIG ###############
############################################

ERR_MSG="System config setup failed"

# Increase kernel memory map per process, and persist after reboot
# https://www.kernel.org/doc/Documentation/sysctl/vm.txt
# https://github.com/iden3/snarkjs/issues/397#issuecomment-1876700914
#
# NOTE this may not work if you are using a Docker container, and will give message (exit code 0)
# `sysctl: setting key "vm.max_map_count", ignoring: Read-only file system`
# https://stackoverflow.com/questions/23537560/docker-build-read-only-file-system
# 65530000 is enough for at least 256 signatures in a layer one circuit
sudo sysctl -w vm.max_map_count=6553000
# TODO do not add this if it has already been added
sudo sh -c 'echo "vm.max_map_count=6553000" >>/etc/sysctl.conf'

if $SWAP; then
    # Increase swap memory, and persist after reboot
    sudo fallocate -l $SWAP_SIZE /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    # https://serverfault.com/questions/967852/swapfile-mount-etc-fstab-swap-swap-or-none-swap
    echo '/swapfile whatever swap sw 0 0' | sudo tee -a /etc/fstab
fi

############################################
##### CUSTOM SOFTWARE INSTALLATION #########
############################################

# Rust
ERR_MSG="Rust setup failed"
cd "$HOME"
if [[ ! -f "$HOME/.cargo/env" ]]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs >>./rustup-init.sh
    chmod +x ./rustup-init.sh
    ./rustup-init.sh -y --no-modify-path
    rm -f ./rustup-init.sh
fi
source "$HOME/.cargo/env"

# Circom
ERR_MSG="Circom setup failed"
cd "$HOME"
if [[ ! -d "$HOME/circom" ]]; then
    git clone https://github.com/iden3/circom.git
    cd circom
    cargo build --release
    cargo install --path circom
fi

# Pyenv
ERR_MSG="Pyenv setup failed"
cd "$HOME"
if [[ ! -d "$HOME/pyenv" ]]; then git clone https://github.com/pyenv/pyenv.git; fi
export PATH="$HOME/pyenv/bin:$PATH"
eval "$(pyenv init -)"
if ! pyenv versions | grep "3\.10\."; then pyenv install 3.10; fi
pyenv global 3.10
if ! pyenv versions | grep "3\.6\."; then pyenv install 3.6; fi

# Patched node
ERR_MSG="Node setup failed"
cd "$HOME"
if [[ ! -f "$HOME/node/out/Release/node" ]]; then
    git clone https://github.com/nodejs/node.git
    cd node
    pyenv local 3.6
    git checkout 8beef5eeb82425b13d447b50beafb04ece7f91b1
    python configure.py
    make -j16
fi
export PATCHED_NODE_PATH=$HOME/node/out/Release/node

# NPM
ERR_MSG="NPM setup failed"
cd "$HOME"
if ! which npm; then
    if [[ ! -d "$HOME/.nvm" ]]; then
        wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
    fi
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # NOTE This sometimes fails with:
    # > Installing latest LTS version.
    # > Downloading and installing node v20.11.0...
    # > Binary download failed, trying source.
    #
    # In this case run this command manually:
    # `export NVM_DIR="$HOME/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" && nvm install --lts`.
    nvm install --lts
fi

# Rapidsnark (x86_64 architecture only)
ERR_MSG="Rapidsnark setup failed"
cd "$HOME"
if [[ ! -f "$HOME/rapidsnark/package/bin/prover" ]]; then
    git clone https://github.com/iden3/rapidsnark.git
    cd rapidsnark
    git submodule init
    git submodule update
    ./build_gmp.sh host
    mkdir build_prover && cd build_prover
    cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=../package
    make -j4 && make install
fi
export RAPIDSNARK_PATH=$HOME/rapidsnark/package/bin/prover

# PNPM
ERR_MSG="PNPM setup failed"
cd "$HOME"
if [[ ! -f "$HOME/.local/share/pnpm/pnpm" ]]; then
    # NOTE This sometimes fails with:
    # > ==> Downloading pnpm binaries 8.15.1
    # > WARN using --force I sure hope you know what you are doing
    # > Copying pnpm CLI from /tmp/tmp.a13YBtCUZy/pnpm to /root/.local/share/pnpm/pnpm
    # > ERR_PNPM_UNKNOWN_SHELL Could not infer shell type.
    # In this case just run this manually (with different tmp file):
    # `SHELL="$SHELL"  /tmp/tmp.PZoYjFP8NI/pnpm setup --force`
    curl -fsSL https://get.pnpm.io/install.sh | sh -
fi
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
pnpm add npx -g
pnpm add snarkjs -g

# Setup repo.
if $REPO; then
    ERR_MSG="Repo setup failed"
    REPO_DIR="$REPO_PARENT_DIR/zk-proof-of-assets"

    if [[ ! -d "$REPO_DIR" ]]; then
        cd "$REPO_PARENT_DIR"
        git clone https://github.com/silversixpence-crypto/zk-proof-of-assets
    fi

    cd "$REPO_DIR"

    if [[ ! -z "$BRANCH" ]]; then
        git switch -c "$BRANCH" origin/"$BRANCH"
    fi

    pnpm i

    git submodule init
    git submodule update

    BATCH_ECDSA_DIR="$REPO_DIR/git_modules/batch-ecdsa"
    patch -u "$BATCH_ECDSA_DIR/circuits/batch_ecdsa.circom" -i ./batch-ecdsa.patch

    pip install -r requirements.txt
fi

# TODO instead of checking if the file exists rather check its checksum,
# because the download might have only gotten partway
if [[ ! -f "./powersOfTau28_hez_final_"$PTAU_SIZE".ptau" ]] && $PTAU; then
    wget https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_"$PTAU_SIZE".ptau -P "$HOME/zk-proof-of-assets"
fi

# This is so that the user can set these env vars in their shell.
# This is the 2nd method mentioned here:
# https://stackoverflow.com/questions/16618071/can-i-export-a-variable-to-the-environment-from-a-bash-script-without-sourcing-i/16619261#16619261
# The 1st method in the above tends to break things, so try to avoid that.
echo "export SNARKJS_PATH=\$HOME/snarkjs/cli.js && export RAPIDSNARK_PATH=\$HOME/rapidsnark/package/bin/prover && export PATCHED_NODE_PATH=\$HOME/node/out/Release/node && export PATH=\$PATH:\$HOME/pyenv/bin && eval \"\$(pyenv init -)\" && export PNPM_HOME=\$HOME/.local/share/pnpm && export PATH=\$PNPM_HOME:\$PATH && export NVM_DIR=\$HOME/.nvm && [ -s \$NVM_DIR/nvm.sh ] && \. \$NVM_DIR/nvm.sh && source $HOME/.cargo/env"
