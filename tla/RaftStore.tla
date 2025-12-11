---- MODULE RaftStore ----
\* Raft-style replication model aligned to our application (leader/follower, log, store).
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS Nodes, Keys, Values

ASSUME Cardinality(Nodes) >= 3

Roles == {"leader", "follower", "candidate"}
OpPut == "put"
Cmd(op, key, val) == [op |-> op, key |-> key, val |-> val]
Entry(term, cmd) == [term |-> term, cmd |-> cmd]

RPCType ==
  {"rv", "rvResp", "ae", "aeResp"}

Message ==
  [ mtype: RPCType,
    term: Nat,
    from: Nodes,
    to: Nodes,
    lastLogIndex: Nat,
    lastLogTerm: Nat,
    voteGranted: BOOLEAN,
    entries: Seq([term: Nat, cmd: [op: Str, key: Keys, val: Values]]),
    prevLogIndex: Nat,
    prevLogTerm: Nat,
    leaderCommit: Nat,
    success: BOOLEAN ]

NoValue == "empty"
NULL == "none"

VARIABLES
  term, role, votedFor,
  log, commitIndex, lastApplied,
  store,
  nextIndex, matchIndex,
  messages

vars == <<term, role, votedFor, log, commitIndex, lastApplied, store, nextIndex, matchIndex, messages>>

EmptyLog == <<>>

Init ==
  /\ term = [n \in Nodes |-> 0]
  /\ role = [n \in Nodes |-> "follower"]
  /\ votedFor = [n \in Nodes |-> NULL]
  /\ log = [n \in Nodes |-> EmptyLog]
  /\ commitIndex = [n \in Nodes |-> 0]
  /\ lastApplied = [n \in Nodes |-> 0]
  /\ store = [n \in Nodes |-> [k \in Keys |-> NoValue]]
  /\ nextIndex = [n \in Nodes |-> [m \in Nodes |-> 1]]
  /\ matchIndex = [n \in Nodes |-> [m \in Nodes |-> 0]]
  /\ messages = {}

LogTerm(l, i) ==
  IF i = 0 THEN 0 ELSE l[i].term

LastLogIndex(l) == Len(l)
LastLogTerm(l) == LogTerm(l, LastLogIndex(l))

UpToDate(candidate, voter) ==
  /\ LastLogTerm(log[candidate]) > LastLogTerm(log[voter])
     \/ (LastLogTerm(log[candidate]) = LastLogTerm(log[voter])
         /\ LastLogIndex(log[candidate]) >= LastLogIndex(log[voter]))

RequestVoteSend ==
  \E cand \in Nodes :
    /\ role[cand] = "candidate"
    /\ \E peer \in Nodes \ {cand} :
        /\ messages' =
             messages \cup {
               [ mtype |-> "rv",
                 term |-> term[cand],
                 from |-> cand,
                 to |-> peer,
                 lastLogIndex |-> LastLogIndex(log[cand]),
                 lastLogTerm |-> LastLogTerm(log[cand]),
                 voteGranted |-> FALSE,
                 entries |-> <<>>,
                 prevLogIndex |-> 0,
                 prevLogTerm |-> 0,
                 leaderCommit |-> commitIndex[cand],
                 success |-> FALSE ]
             }
        /\ UNCHANGED <<term, role, votedFor, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>

RequestVoteHandle ==
  \E msg \in messages :
    /\ msg.mtype = "rv"
    /\ LET voter == msg.to IN
       IF msg.term < term[voter] THEN
         /\ messages' = messages \ {msg}
         /\ UNCHANGED <<term, role, votedFor, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>
       ELSE
         /\ term' = [term EXCEPT ![voter] = Max(term[voter], msg.term)]
         /\ canVote == (votedFor[voter] = NULL) \/ (votedFor[voter] = msg.from)
         /\ upToDate == UpToDate(msg.from, voter)
         /\ grant == canVote /\ upToDate
         /\ votedFor' =
               IF grant
                 THEN [votedFor EXCEPT ![voter] = msg.from]
                 ELSE votedFor
         /\ messages' =
               (messages \ {msg})
               \cup {
                 [ mtype |-> "rvResp",
                   term |-> term'[voter],
                   from |-> voter,
                   to |-> msg.from,
                   voteGranted |-> grant,
                   lastLogIndex |-> LastLogIndex(log[voter]),
                   lastLogTerm |-> LastLogTerm(log[voter]),
                   entries |-> <<>>,
                   prevLogIndex |-> 0, prevLogTerm |-> 0,
                   leaderCommit |-> commitIndex[voter],
                   success |-> FALSE ]
               }
         /\ UNCHANGED <<role, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>

AppendEntriesSend ==
  \E leader \in Nodes :
    /\ role[leader] = "leader"
    /\ \E follower \in Nodes \ {leader} :
        /\ let ni == nextIndex[leader][follower] in
           let prevIdx == ni - 1 in
           let prevTerm == LogTerm(log[leader], prevIdx) in
           let entriesToSend ==
                 SubSeq(log[leader], ni, Len(log[leader])) in
           /\ messages' =
                messages \cup {
                  [ mtype |-> "ae",
                    term |-> term[leader],
                    from |-> leader,
                    to |-> follower,
                    prevLogIndex |-> prevIdx,
                    prevLogTerm |-> prevTerm,
                    entries |-> entriesToSend,
                    leaderCommit |-> commitIndex[leader],
                    lastLogIndex |-> LastLogIndex(log[leader]),
                    lastLogTerm |-> LastLogTerm(log[leader]),
                    voteGranted |-> FALSE,
                    success |-> FALSE ]
                }
        /\ UNCHANGED <<term, role, votedFor, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>

AppendEntriesHandle ==
  \E msg \in messages :
    /\ msg.mtype = "ae"
    /\ let node == msg.to in
       /\ term' = term
       /\ role' = role
       /\ votedFor' = votedFor
       /\ store' = store
       /\ IF msg.term < term[node] THEN
             /\ messages' = messages \ {msg}
             /\ log' = log
             /\ commitIndex' = commitIndex
             /\ lastApplied' = lastApplied
             /\ nextIndex' = nextIndex
             /\ matchIndex' = matchIndex
          ELSE
             /\ term1 = [term EXCEPT ![node] = Max(term[node], msg.term)]
             /\ okPrev ==
                  (msg.prevLogIndex = 0)
                  \/ (msg.prevLogIndex <= Len(log[node])
                      /\ LogTerm(log[node], msg.prevLogIndex) = msg.prevLogTerm)
             /\ IF ~okPrev THEN
                   /\ log' = log
                   /\ commitIndex' = commitIndex
                   /\ lastApplied' = lastApplied
                   /\ nextIndex' = nextIndex
                   /\ matchIndex' = matchIndex
                   /\ messages' =
                        (messages \ {msg})
                        \cup {
                          [mtype |-> "aeResp", term |-> term1[node],
                           from |-> node, to |-> msg.from,
                           success |-> FALSE,
                           prevLogIndex |-> msg.prevLogIndex,
                           prevLogTerm |-> msg.prevLogTerm,
                           entries |-> <<>>,
                           leaderCommit |-> commitIndex[node],
                           lastLogIndex |-> Len(log[node]),
                           lastLogTerm |-> LogTerm(log[node], Len(log[node])),
                           voteGranted |-> FALSE]
                        }
                   /\ term' = term1
                ELSE
                   /\ newLog =
                        IF msg.entries = <<>>
                          THEN log[node]
                          ELSE
                            LET truncated ==
                                  SubSeq(log[node], 1, msg.prevLogIndex) IN
                            truncated \o msg.entries
                   /\ log' = [log EXCEPT ![node] = newLog]
                   /\ newCommit =
                        IF msg.leaderCommit > commitIndex[node]
                          THEN Min(msg.leaderCommit, Len(newLog))
                          ELSE commitIndex[node]
                   /\ commitIndex' = [commitIndex EXCEPT ![node] = newCommit]
                   /\ lastApplied' = lastApplied
                   /\ nextIndex' = nextIndex
                   /\ matchIndex' = matchIndex
                   /\ messages' =
                        (messages \ {msg})
                        \cup {
                          [mtype |-> "aeResp", term |-> term1[node],
                           from |-> node, to |-> msg.from,
                           success |-> TRUE,
                           prevLogIndex |-> msg.prevLogIndex,
                           prevLogTerm |-> msg.prevLogTerm,
                           entries |-> <<>>,
                           leaderCommit |-> newCommit,
                           lastLogIndex |-> Len(newLog),
                           lastLogTerm |-> LogTerm(newLog, Len(newLog)),
                           voteGranted |-> FALSE]
                        }
                   /\ term' = term1

AppendEntriesRespHandle ==
  \E msg \in messages :
    /\ msg.mtype = "aeResp"
    /\ let leader == msg.to in
       /\ role[leader] = "leader"
       /\ term' = term
       /\ role' = role
       /\ votedFor' = votedFor
       /\ store' = store
       /\ log' = log
       /\ commitIndex' = commitIndex
       /\ lastApplied' = lastApplied
       /\ IF msg.success THEN
             /\ nextIndex' =
                   [nextIndex EXCEPT ![leader][msg.from] = msg.lastLogIndex + 1]
             /\ matchIndex' =
                   [matchIndex EXCEPT ![leader][msg.from] = msg.lastLogIndex]
          ELSE
             /\ nextIndex' =
                   [nextIndex EXCEPT ![leader][msg.from] = Max(1, nextIndex[leader][msg.from] - 1)]
             /\ matchIndex' = matchIndex
       /\ messages' = messages \ {msg}

AdvanceCommitLeader ==
  \E leader \in Nodes :
    /\ role[leader] = "leader"
    /\ \E idx \in Nat :
        /\ idx > commitIndex[leader]
        /\ idx <= Len(log[leader])
        /\ log[leader][idx].term = term[leader]
        /\ LET replicated ==
              1 + Cardinality({f \in Nodes \ {leader} : matchIndex[leader][f] >= idx}) IN
           /\ replicated > Cardinality(Nodes) \div 2
        /\ commitIndex' = [commitIndex EXCEPT ![leader] = idx]
        /\ UNCHANGED <<term, role, votedFor, log, lastApplied, store, nextIndex, matchIndex, messages>>

ApplyCommitted ==
  \E n \in Nodes :
    /\ commitIndex[n] > lastApplied[n]
    /\ let idx == lastApplied[n] + 1 in
       let entry == log[n][idx] in
       /\ store' = [store EXCEPT ![n][entry.cmd.key] = entry.cmd.val]
       /\ lastApplied' = [lastApplied EXCEPT ![n] = idx]
       /\ UNCHANGED <<term, role, votedFor, log, commitIndex, nextIndex, matchIndex, messages>>

Crash == UNCHANGED vars
NoOp == UNCHANGED vars

Next ==
    RequestVoteSend
    \/ RequestVoteHandle
    \/ AppendEntriesSend
    \/ AppendEntriesHandle
    \/ AppendEntriesRespHandle
    \/ AdvanceCommitLeader
    \/ ApplyCommitted
    \/ Crash
    \/ NoOp

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ term \in [Nodes -> Nat]
  /\ role \in [Nodes -> Roles]
  /\ votedFor \in [Nodes -> (Nodes \cup {NULL})]
  /\ log \in [Nodes -> Seq([term: Nat, cmd: [op: Str, key: Keys, val: Values]])]
  /\ commitIndex \in [Nodes -> Nat]
  /\ lastApplied \in [Nodes -> Nat]
  /\ store \in [Nodes -> [Keys -> Values \cup {NoValue}]]
  /\ nextIndex \in [Nodes -> [Nodes -> Nat]]
  /\ matchIndex \in [Nodes -> [Nodes -> Nat]]
  /\ messages \subseteq Message

LeaderUniqueness ==
  \A t \in Nat :
    \A l1, l2 \in Nodes :
      (role[l1] = "leader" /\ role[l2] = "leader" /\ term[l1] = t /\ term[l2] = t)
        => l1 = l2

LogAgreement ==
  \A n1, n2 \in Nodes :
    \A i \in Nat :
      (commitIndex[n1] >= i /\ commitIndex[n2] >= i /\ i > 0)
        => log[n1][i] = log[n2][i]

StoreConsistency ==
  \A n1, n2 \in Nodes :
    \A k \in Keys :
      (lastApplied[n1] = lastApplied[n2])
        => store[n1][k] = store[n2][k]

==== END MODULE RaftStore ====
