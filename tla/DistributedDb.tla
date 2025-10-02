---- MODULE DistributedDb ----
EXTENDS FiniteSets

\* Lab-1: Broadcast replication for distributed KV store

CONSTANTS
    Nodes,    \* Set of node identifiers (e.g., {n1, n2})
    Keys,     \* Set of possible keys (e.g., {k1, k2})
    Values    \* Set of possible values (e.g., {v1, v2})

VARIABLES
    store,    \* store[node][key] = value for each node's local state
    messages  \* Set of messages in-transit for replication

vars == <<store, messages>>

\* Special value representing absent/deleted key
NoValue == "empty"

\* Initial state: all nodes have empty stores, no messages
Init ==
    /\ store = [n \in Nodes |-> [k \in Keys |-> NoValue]]
    /\ messages = {}

\* Put: client writes to a node, broadcasts to peers
Put(node, key, value) ==
    /\ value \in Values  \* Cannot put NoValue
    /\ store' = [store EXCEPT ![node][key] = value]
    /\ messages' = messages \cup
                   {[type |-> "put", target |-> n, key |-> key, value |-> value]
                    : n \in Nodes \ {node}}

\* Delete: client deletes from a node, broadcasts to peers
Delete(node, key) ==
    /\ store' = [store EXCEPT ![node][key] = NoValue]
    /\ messages' = messages \cup
                   {[type |-> "delete", target |-> n, key |-> key, value |-> NoValue]
                    : n \in Nodes \ {node}}

\* LocalPut: apply a put message at target node
LocalPut(msg) ==
    /\ msg \in messages
    /\ msg.type = "put"
    /\ store' = [store EXCEPT ![msg.target][msg.key] = msg.value]
    /\ messages' = messages \ {msg}

\* LocalDelete: apply a delete message at target node
LocalDelete(msg) ==
    /\ msg \in messages
    /\ msg.type = "delete"
    /\ store' = [store EXCEPT ![msg.target][msg.key] = NoValue]
    /\ messages' = messages \ {msg}

\* Next state: any action can happen
Next ==
    \/ \E n \in Nodes, k \in Keys, v \in Values : Put(n, k, v)
    \/ \E n \in Nodes, k \in Keys : Delete(n, k)
    \/ \E msg \in messages : LocalPut(msg)
    \/ \E msg \in messages : LocalDelete(msg)

\* Specification
Spec == Init /\ [][Next]_vars

\* Type invariant: check state structure is correct
TypeOK ==
    /\ store \in [Nodes -> [Keys -> Values \cup {NoValue}]]
    /\ messages \in SUBSET [type: {"put", "delete"}, target: Nodes, key: Keys, value: Values \cup {NoValue}]

==============================
