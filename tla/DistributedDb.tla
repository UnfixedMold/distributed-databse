---- MODULE DistributedDb ----
EXTENDS FiniteSets, Integers

\* Lab-2: Bracha Byzantine Reliable Broadcast

CONSTANTS
    Nodes,    \* Set of node identifiers
    Keys,     \* Set of possible keys
    Values,   \* Set of possible values
    MsgIds    \* Finite set of unique message identifiers

VARIABLES
    store,             \* store[node][key] = value for each node's local state
    messages,          \* Set of protocol messages in transit
    msgState,          \* Per-node view of Bracha state machines
    availableMsgIds,   \* Remaining identifiers available for broadcasts
    alive              \* Node liveness flags (FALSE = crashed)

vars == <<store, messages, msgState, availableMsgIds, alive>>

\* Special sentinels
NoValue == "empty"
NoKey == "no_key"

\* Per-message bookkeeping entry for a single node
MsgEntryType ==
    [ active: BOOLEAN,
      key: Keys \cup {NoKey},
      value: Values \cup {NoValue},
      seenSend: BOOLEAN,
      sentEcho: BOOLEAN,
      sentReady: BOOLEAN,
      delivered: BOOLEAN,
      echoFrom: SUBSET Nodes,
      readyFrom: SUBSET Nodes ]

InactiveEntry ==
    [ active |-> FALSE,
      key |-> NoKey,
      value |-> NoValue,
      seenSend |-> FALSE,
      sentEcho |-> FALSE,
      sentReady |-> FALSE,
      delivered |-> FALSE,
      echoFrom |-> {},
      readyFrom |-> {} ]

InitMsgEntry(key, value) ==
    [ active |-> TRUE,
      key |-> key,
      value |-> value,
      seenSend |-> FALSE,
      sentEcho |-> FALSE,
      sentReady |-> FALSE,
      delivered |-> FALSE,
      echoFrom |-> {},
      readyFrom |-> {} ]

\* Message records traveling on the asynchronous channel
MessageType ==
    [ phase: {"send", "echo", "ready"},
      from: Nodes,
      to: Nodes,
      id: MsgIds,
      key: Keys,
      value: Values \cup {NoValue} ]

\* Threshold helpers
NodeCount == Cardinality(Nodes)
F == IF NodeCount = 0 THEN 0 ELSE (NodeCount - 1) \div 3
EchoThreshold == NodeCount - (2 * F)
ReadyThreshold == F + 1
DeliverThreshold == (2 * F) + 1

EntryReadyCondition(entry) ==
    (Cardinality(entry.echoFrom) >= EchoThreshold)
        \/ (Cardinality(entry.readyFrom) >= ReadyThreshold)

SendMessages(origin, id, key, value) ==
    { [phase |-> "send", from |-> origin, to |-> n,
       id |-> id, key |-> key, value |-> value] : n \in Nodes }

EchoMessages(node, id, entry) ==
    { [phase |-> "echo", from |-> node, to |-> n,
       id |-> id, key |-> entry.key, value |-> entry.value] : n \in Nodes }

ReadyMessages(node, id, entry) ==
    { [phase |-> "ready", from |-> node, to |-> n,
       id |-> id, key |-> entry.key, value |-> entry.value] : n \in Nodes }

\* Initial state: empty stores, no messages, no active broadcasts
Init ==
    /\ store = [n \in Nodes |-> [k \in Keys |-> NoValue]]
    /\ messages = {}
    /\ msgState = [n \in Nodes |-> [id \in MsgIds |-> InactiveEntry]]
    /\ availableMsgIds = MsgIds
    /\ alive = [n \in Nodes |-> TRUE]

\* Client initiates a broadcast by allocating a fresh id and enqueueing SENDs
Broadcast ==
    \E origin \in Nodes :
    \E id \in availableMsgIds :
    \E key \in Keys :
    \E value \in Values \cup {NoValue} :
        /\ alive[origin]
        /\ ~msgState[origin][id].active
        /\ store' = store
        /\ messages' = messages \cup SendMessages(origin, id, key, value)
        /\ msgState' =
            [msgState EXCEPT ![origin][id] = InitMsgEntry(key, value)]
        /\ availableMsgIds' = availableMsgIds \ {id}
        /\ alive' = alive

\* Process a SEND phase message at its target node
ProcessSend ==
    \E msg \in messages :
        LET id == msg.id IN
        LET node == msg.to IN
        LET entryCurrent == msgState[node][id] IN
        LET entryBase ==
                IF entryCurrent.active
                    THEN entryCurrent
                    ELSE InitMsgEntry(msg.key, msg.value) IN
        /\ msg.phase = "send"
        /\ alive[node]
        /\ availableMsgIds' = availableMsgIds
        /\ store' = store
        /\ IF entryBase.seenSend
              THEN /\ msgState' = msgState
                   /\ messages' = messages \ {msg}
                   /\ alive' = alive
              ELSE
                   LET extraMsgs ==
                           IF entryBase.sentEcho
                              THEN {}
                              ELSE EchoMessages(node, id, entryBase)
                       updatedEntry ==
                           [entryBase EXCEPT !.seenSend = TRUE,
                                                !.sentEcho = TRUE] IN
                   /\ msgState' = [msgState EXCEPT ![node][id] = updatedEntry]
                   /\ messages' = (messages \ {msg}) \cup extraMsgs
                   /\ alive' = alive

\* Process an ECHO phase message and potentially transition to READY
ProcessEcho ==
    \E msg \in messages :
        LET id == msg.id IN
        LET node == msg.to IN
        LET fromNode == msg.from IN
        LET entryCurrent == msgState[node][id] IN
        LET entryBase ==
                IF entryCurrent.active
                    THEN entryCurrent
                    ELSE InitMsgEntry(msg.key, msg.value) IN
        /\ msg.phase = "echo"
        /\ alive[node]
        /\ store' = store
        /\ availableMsgIds' = availableMsgIds
        /\ IF fromNode \in entryBase.echoFrom
              THEN /\ msgState' = msgState
                   /\ messages' = messages \ {msg}
                   /\ alive' = alive
              ELSE
                   LET updatedEntryDraft ==
                           [entryBase EXCEPT !.echoFrom = entryBase.echoFrom \cup {fromNode}]
                       readyCond == EntryReadyCondition(updatedEntryDraft)
                       sendReady == ~entryBase.sentReady /\ readyCond
                       updatedEntry ==
                           [updatedEntryDraft EXCEPT !.sentReady = entryBase.sentReady \/ sendReady]
                       extraMsgs ==
                           IF sendReady
                              THEN ReadyMessages(node, id, updatedEntry)
                              ELSE {} IN
                   /\ msgState' = [msgState EXCEPT ![node][id] = updatedEntry]
                   /\ messages' = (messages \ {msg}) \cup extraMsgs
                   /\ alive' = alive

\* Process a READY phase message, maybe rebroadcast READY and deliver locally
ProcessReady ==
    \E msg \in messages :
        LET id == msg.id IN
        LET node == msg.to IN
        LET fromNode == msg.from IN
        LET entryCurrent == msgState[node][id] IN
        LET entryBase ==
                IF entryCurrent.active
                    THEN entryCurrent
                    ELSE InitMsgEntry(msg.key, msg.value) IN
        /\ msg.phase = "ready"
        /\ alive[node]
        /\ availableMsgIds' = availableMsgIds
        /\ IF fromNode \in entryBase.readyFrom
              THEN /\ msgState' = msgState
                   /\ messages' = messages \ {msg}
                   /\ store' = store
                   /\ alive' = alive
              ELSE
                   LET newReadySet == entryBase.readyFrom \cup {fromNode}
                       entryWithReady ==
                           [entryBase EXCEPT !.readyFrom = newReadySet]
                       readyCond == EntryReadyCondition(entryWithReady)
                       sendReady == ~entryBase.sentReady /\ readyCond
                       entryAfterReady ==
                           [entryWithReady EXCEPT !.sentReady = entryBase.sentReady \/ sendReady]
                       deliverCond ==
                           ~entryBase.delivered /\ (Cardinality(newReadySet) >= DeliverThreshold)
                       entryAfterDeliver ==
                           IF deliverCond
                              THEN [entryAfterReady EXCEPT !.delivered = TRUE]
                              ELSE entryAfterReady
                       newStore ==
                           IF deliverCond
                              THEN [store EXCEPT ![node][entryBase.key] = entryBase.value]
                              ELSE store
                       extraMsgs ==
                           IF sendReady
                              THEN ReadyMessages(node, id, entryAfterReady)
                              ELSE {} IN
                   /\ msgState' = [msgState EXCEPT ![node][id] = entryAfterDeliver]
                   /\ messages' = (messages \ {msg}) \cup extraMsgs
                   /\ store' = newStore
                   /\ alive' = alive

Crash ==
    \E node \in Nodes :
        /\ alive[node]
        /\ store' = store
        /\ messages' = messages
        /\ msgState' = msgState
        /\ availableMsgIds' = availableMsgIds
        /\ alive' = [alive EXCEPT ![node] = FALSE]

\* Stuttering step to model quiescent states explicitly
NoOp ==
    UNCHANGED vars

\* Next state relation: any enabled action may occur
Next ==
    Broadcast \/ ProcessSend \/ ProcessEcho \/ ProcessReady \/ Crash \/ NoOp

\* Specification
Spec ==
    Init /\ [][Next]_vars
        /\ WF_vars(ProcessSend)
        /\ WF_vars(ProcessEcho)
        /\ WF_vars(ProcessReady)

\* Type invariant to ensure state shape is preserved
TypeOK ==
    /\ store \in [Nodes -> [Keys -> Values \cup {NoValue}]]
    /\ messages \subseteq MessageType
    /\ msgState \in [Nodes -> [MsgIds -> MsgEntryType]]
    /\ availableMsgIds \in SUBSET MsgIds
    /\ alive \in [Nodes -> BOOLEAN]
    /\ \A node \in Nodes :
           \A id \in MsgIds :
               /\ msgState[node][id].active
                     => /\ msgState[node][id].key \in Keys
                        /\ msgState[node][id].value \in Values \cup {NoValue}
               /\ ~msgState[node][id].active
                     => msgState[node][id] = InactiveEntry

Delivered(node, id) == msgState[node][id].delivered

AliveDelivered(id) == \A n \in Nodes : alive[n] => Delivered(n, id)

CrashTolerance ==
    \A id \in MsgIds :
        \A n \in Nodes :
            (alive[n] /\ Delivered(n, id)) ~> AliveDelivered(id)

==============================
