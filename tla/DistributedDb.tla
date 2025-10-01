---- MODULE DistributedDb ----

CONSTANTS Nodes, Keys, Values

VARIABLES store

Init == store = [n \in Nodes |-> [k \in Keys |-> "empty"]]

Put(node, key, value) ==
    store' = [store EXCEPT ![node][key] = value]

Next == \E n \in Nodes, k \in Keys, v \in Values : Put(n, k, v)

==============================
