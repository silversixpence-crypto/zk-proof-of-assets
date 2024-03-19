# Adjust batch size to minimize the number of sigs in final batch.
#
# Generating zkeys is expensive. And if we want to support any amount of
# signatures & batch size then the last batch could have any number of signatures
# in the range [0,batch_size]. We want to minimize this number so that the
# zkey generation is as small as possible.

# https://www.desmos.com/calculator/vhryppb3m2

import click
import math


def batch_size(num_sigs, ideal_batch_size):
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
