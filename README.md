# ZK Proof of Assets

Circom & Groth16 SNARK implementation of Proof of Assets. This repo allows digital asset custodians (such as cryptocurrency exchanges) to prove that they own a certain amount of digital assets, without revealing the addresses that hold the assets.

[Here](https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/rJXtAeyLT) is the original design doc for the protocol. Note, however, that the final design is slightly different to the original (some optimizations were done). See below for final design.

[Here](https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/r1FR-0uBR) is a blog article diving into proof of assets.

Proof of Assets is the first out of 2 protocols that make up a Proof of Reserves protocol. For details on the whole PoR project see [this project doc](https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/S1Ozo-iO2).

## Current state

The code is working as of June 2024 and can be used as is. No audit has been done yet. 

See [the high priority task list](https://github.com/silversixpence-crypto/zk-proof-of-assets/issues?q=is%3Aissue+is%3Aopen+label%3Apriority%3Ahigh) for some important outstanding issues.

The code is at it's first stage: Groth16 & Circom libraries. Second stage involves using different proving systems & libraries for ECDSA verification to gain [hopefully] ~1000x in performance.

## Usage

The code has only been tested on a Linux machine (Debian).

First, you'll need to install some software. There is a script that does all of this for you: [machine_initialization.sh](./scripts/machine_initialization.sh). **The script only works on a Debian machine.** It does some invasive changes to the machine (like changing `vm.max_map_count` in `sysctl`) so it is recommended to run it on a server and not your personal machine; running it in a Docker container is also an option. You can find out more about what this script does [here](https://github.com/silversixpence-crypto/zk-proof-of-assets/tree/stent/readme/scripts#machine-initialization).

Next, you run the [full workflow](./scripts/full_workflow.sh) script, which will run the entire snark proving system. The anonymity set and signuture set will have to be given as input to the script, so these need to be generated first. You can read more about the script and it's inputs [here](https://github.com/silversixpence-crypto/zk-proof-of-assets/tree/stent/readme/scripts#machine-initialization).

Here are some useful commands to copy:
```bash
# Run a docker container:
id=$(docker run --privileged -d -ti -m 100G --memory-swap -1 --name poa_100g --rm ubuntu /bin/bash)
# - `-m` : set max memory (-1 for unlimited), which can be useful if you want to use the machine for other tasks, and you know the zk workflow will take up all the memory
# - `--memory-swap` : max swap (-1 for unlimited)
# - `--privileged` : is needed to change vm.max_map_count (see machine_initialization.sh script)

# Copy over the init script to the container:
wget https://raw.githubusercontent.com/silversixpence-crypto/zk-proof-of-assets/main/scripts/machine_initialization.sh
docker cp ./machine_initialization.sh $id:/home

docker attach $id

# =====================================
# Now in container..

# Make sure the system is up to date:
apt update -y && apt upgrade -y && apt install -y sudo vim

# Run the init script:
cd /home && ./machine_initialization.sh -r /root -P -S

# Run the proving system:
cd /root/zk-proof-of-assets
./full_workflow.sh \
    -s \
    -p "$SOURCE_DIR"/powersOfTau28_hez_final_26.ptau \
    $signatures_file \
    $anon_set_file \
    $blinding_factor
```

TODO talk about how to get the anon set

TODO talk about ptau files and link 

## Design

TODO diagram

## Patches

The [init script](./scripts/machine_initialization.sh) applies a few patches to the submodules.

### batch-ecdsa patch

Workaround for a problem in the circom compiler: https://github.com/iden3/circom/issues/230

### ed25519-circom patch

There are conflicts with function names between ed25519-circom and other dependencies, so the patch renames the functions.

## Testing

There are scripts in the *tests* directory for running the tests. There are only integration tests, no unit tests.


