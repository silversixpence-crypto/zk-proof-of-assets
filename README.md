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

## Testing

```bash
> id=$(docker run --privileged -d -ti --rm ubuntu /bin/bash)
> docker cp ./scripts/machine_initialization.sh $id:/home
> docker cp ./powersOfTau28_hez_final_XX.ptau $id:/root
> docker attach $id
root@xyz: apt update -y && apt upgrade -y && apt install -y sudo vim
root@xyz: cd /home && ./machine_initialization.sh -h
```


