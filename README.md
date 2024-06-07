# ZK Proof of Assets

Circom & Groth16 SNARK implementation of Proof of Assets. This repo allows digital asset custodians (such as cryptocurrency exchanges) to prove that they own a certain amount of digital assets, without revealing the addresses that hold the assets.

[Here](https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/rJXtAeyLT) is the original design doc for the protocol. Note, however, that the final design is slightly different to the original (some optimizations were done). See below for final design.

Proof of Assets is the first out of 2 protocols that make up a Proof of Reserves protocol. For details on the whole PoR project see [this project doc](https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/S1Ozo-iO2).

## Current state

The code is working (April 2024) and can be used. There are some caveats: still waiting for test results, no audit done. See [the high priority task list](https://github.com/silversixpence-crypto/zk-proof-of-assets/issues?q=is%3Aissue+is%3Aopen+label%3Apriority%3Ahigh) for more details.

The code is at it's first stage. Second stage involves using different proving systems & libraries for ECDSA verification to gain [hopefully] ~1000x in performance.

## Usage

## Design

TODO diagram

## Patches

The [init script](./scripts/machine_initialization.sh) applies a few patches to the submodules.

### batch-ecdsa patch

Workaround for a problem in the circom compiler: https://github.com/iden3/circom/issues/230

### ed25519-circom patch

There are conflicts with function names between ed25519-circom and other dependencies, so the patch renames the functions.

## Testing

Here are some useful commands for running the whole proving system in a Docker container.

```bash
id=$(docker run --privileged -d -ti -m 100G --memory-swap -1 --name poa_100g --rm ubuntu /bin/bash)

docker cp ./scripts/machine_initialization.sh $id:/home
docker cp ./powersOfTau28_hez_final_XX.ptau $id:/root
docker attach $id

# now in container..
apt update -y && apt upgrade -y && apt install -y sudo vim
cd /home && ./machine_initialization.sh -h
```
- `-m` : set max memory (-1 for unlimited), which can be useful if you want to use the machine for other tasks, and you know the zk workflow will take up all the memory
- `--memory-swap` : max swap (-1 for unlimited)
- `--privileged` : is needed to change vm.max_map_count (see machine_initialization.sh script)


