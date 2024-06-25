# Adjust batch size to minimize the number of sigs in final batch.
#
# The total signatures list is split into chunks of size `batch_size`.
# This is because the number of constraints for g16 circuits is limited, and the limit
# is hit for a pretty small number of sigs, so we are forced to cut the list into
# chunks and feed them to different snarks. Dividing the number of sigs by
# `batch_size` will possibly leave a non-zero remainder.
#
# If we want to support any amount of signatures & batch size then the last batch
# could have any number of signatures in the range [0, batch_size].
# Generating zkeys is expensive so we want to minimize this number to make the
# zkey generation as small as possible.
#
# See full equation & calculation here: https://www.desmos.com/calculator/vhryppb3m2
#
# This script can be executed through CLI:
# python ./scripts/batch_size_optimizooor.py <num_sigs> <ideal_num_sigs_per_batch>

import click
import math


# TODO what about the absolute max batch size? This exists because the circuits
# have a constraint limit. We should take in another CLI argument for max, and
# make sure we don't go above that.

def batch_size(num_sigs, ideal_batch_size):
    if num_sigs < ideal_batch_size:
        return num_sigs

    batch_size_diff_pos = math.ceil(ideal_batch_size - num_sigs / (math.floor(num_sigs / ideal_batch_size) + 1))
    batch_size_diff_neg = math.ceil(ideal_batch_size - num_sigs / math.floor(num_sigs / ideal_batch_size))

    if batch_size_diff_pos < abs(batch_size_diff_neg):
        return ideal_batch_size - batch_size_diff_pos
    else:
        return ideal_batch_size - batch_size_diff_neg


@click.command()
@click.argument(
    "num_sigs",
    required=1,
    type=click.INT,
)
@click.argument(
    "ideal_batch_size",
    required=1,
    type=click.INT,
)
def cli(num_sigs, ideal_batch_size):
    adjusted_batch_size = batch_size(num_sigs, ideal_batch_size)
    print("Batch size:", adjusted_batch_size)
    print("Number of signatures in last batch:", num_sigs % adjusted_batch_size)

if __name__ == "__main__":
    cli()
