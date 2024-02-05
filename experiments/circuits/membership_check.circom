pragma circom 2.0.6;

template MembershipCheck(n, N) {
    // public input
    signal input set[N];

    // private inputs
    signal input values[n];
    signal input indices[n];

    for (var i=0; i<n; i++) {
        var j = indices[i];
        var elem = set[j];
        values[i] === elem;
    }
}

component main { public [ set ] } = MembershipCheck(1, 10);
