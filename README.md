# ZK Proof of Assets

Circom implementation of a proof of assets snark.

Design doc for the repo: https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/rJXtAeyLT

High-level project doc: https://hackmd.io/@JI2FtqawSzO-olUw-r48DQ/S1Ozo-iO2

## Current state

Done:
- Circuits written
- Sequential tests run for up to 256 signatures
- Parallel tests run for 6 sigs with a parallelization of 3

Todo:
- [High priority tasks](https://github.com/silversixpence-crypto/zk-proof-of-assets/issues?q=is%3Aissue+is%3Aopen+label%3Apriority%3Ahigh)

## Design

## Patches

The [init script](./scripts/machine_initialization.sh) applies a few patches to the submodules.

### batch-ecdsa patch

Workaround for a problem in the circom compiler: https://github.com/iden3/circom/issues/230

## Testing

Here are some useful commands for running the whole proving system in a Docker container.

```bash
# 'privileged' is needed to change vm.max_map_count (see machine_initialization.sh script)
id=$(docker run --privileged -d -ti --rm ubuntu /bin/bash)

docker cp ./scripts/machine_initialization.sh $id:/home
docker cp ./powersOfTau28_hez_final_XX.ptau $id:/root
docker attach $id

# now in container
apt update -y && apt upgrade -y && apt install -y sudo vim
cd /home && ./machine_initialization.sh -h
```


