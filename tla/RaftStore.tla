---- MODULE RaftStore ----
\* Raft-style replication model aligned to our application (leader/follower, log, store).
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS Nodes, Keys, Values, MaxTerm, MaxIndex

ASSUME Cardinality(Nodes) >= 3

Roles == {"leader", "follower", "candidate"}
Ops == {"put"}
Cmd(op, key, val) == [op |-> op, key |-> key, val |-> val]
Entry(term, cmd) == [term |-> term, cmd |-> cmd]

Max2(a, b) == IF a >= b THEN a ELSE b
Min2(a, b) == IF a <= b THEN a ELSE b

TermDom == 0..MaxTerm
IndexDom == 0..MaxIndex
NextIdxDom == 0..(MaxIndex + 1)

EntryRec == [term: TermDom, cmd: [op: Ops, key: Keys, val: Values]]
EntrySeq == { s \in Seq(EntryRec) : Len(s) <= MaxIndex }

RPCType ==
  {"rv", "rvResp", "ae", "aeResp"}

Message ==
  [ mtype: RPCType,
    term: TermDom,
    from: Nodes,
    to: Nodes,
    lastLogIndex: IndexDom,
    lastLogTerm: TermDom,
    voteGranted: BOOLEAN,
    entries: EntrySeq,
    prevLogIndex: IndexDom,
    prevLogTerm: TermDom,
    leaderCommit: IndexDom,
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
       LET cand == msg.from IN
         /\ role[cand] = "candidate"
         /\ IF msg.term < term[voter] THEN
               /\ messages' = messages \ {msg}
               /\ UNCHANGED <<term, role, votedFor, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>
            ELSE
               /\ term' = [term EXCEPT ![voter] = Max2(term[voter], msg.term)]
               /\ LET canVote == (votedFor[voter] = NULL) \/ (votedFor[voter] = cand) IN
                  LET upToDate == UpToDate(cand, voter) IN
                  LET grant == canVote /\ upToDate IN
                    /\ votedFor' =
                          IF grant
                            THEN [votedFor EXCEPT ![voter] = cand]
                            ELSE votedFor
                    /\ messages' =
                          (messages \ {msg})
                          \cup {
                            [ mtype |-> "rvResp",
                              term |-> term'[voter],
                              from |-> voter,
                              to |-> cand,
                              voteGranted |-> grant,
                              lastLogIndex |-> LastLogIndex(log[voter]),
                              lastLogTerm |-> LastLogTerm(log[voter]),
                              entries |-> <<>>,
                              prevLogIndex |-> 0,
                              prevLogTerm |-> 0,
                              leaderCommit |-> commitIndex[voter],
                              success |-> FALSE ]
                          }
                    /\ UNCHANGED <<role, log, commitIndex, lastApplied, store, nextIndex, matchIndex>>

AppendEntriesSend ==
  \E leader \in Nodes :
    /\ role[leader] = "leader"
    /\ \E follower \in Nodes \ {leader} :
        /\ LET nextIdx == nextIndex[leader][follower] IN
           LET prevIdx == nextIdx - 1 IN
           LET prevTerm == LogTerm(log[leader], prevIdx) IN
           LET entriesToSend == SubSeq(log[leader], nextIdx, Len(log[leader])) IN
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
    /\ LET node == msg.to IN
       LET term1 == [term EXCEPT ![node] = Max2(term[node], msg.term)] IN
       LET okPrev ==
            (msg.prevLogIndex = 0)
            \/ (msg.prevLogIndex <= Len(log[node])
                /\ LogTerm(log[node], msg.prevLogIndex) = msg.prevLogTerm) IN
         /\ term' = term
         /\ role' = role
         /\ votedFor' = votedFor
         /\ store' = store
         /\ IF msg.term < term[node] THEN
               /\ messages' = messages \ {msg}
               /\ UNCHANGED <<log, commitIndex, lastApplied, nextIndex, matchIndex>>
            ELSE
               /\ IF ~okPrev THEN
                     /\ UNCHANGED <<log, commitIndex, lastApplied, nextIndex, matchIndex>>
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
                     /\ LET truncated == SubSeq(log[node], 1, msg.prevLogIndex) IN
                        LET newLog ==
                              IF msg.entries = <<>>
                                THEN log[node]
                                ELSE truncated \o msg.entries IN
                        LET newCommit ==
                              IF msg.leaderCommit > commitIndex[node]
                                THEN Min2(msg.leaderCommit, Len(newLog))
                                ELSE commitIndex[node] IN
                          /\ log' = [log EXCEPT ![node] = newLog]
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
    /\ LET leader == msg.to IN
       /\ role[leader] = "leader"
       /\ UNCHANGED <<term, role, votedFor, store, log, commitIndex, lastApplied>>
       /\ IF msg.success THEN
             /\ nextIndex' =
                   [nextIndex EXCEPT ![leader][msg.from] = msg.lastLogIndex + 1]
             /\ matchIndex' =
                   [matchIndex EXCEPT ![leader][msg.from] = msg.lastLogIndex]
          ELSE
             /\ nextIndex' =
                   [nextIndex EXCEPT ![leader][msg.from] = Max2(1, nextIndex[leader][msg.from] - 1)]
             /\ matchIndex' = matchIndex
       /\ messages' = messages \ {msg}

AdvanceCommitLeader ==
  \E leader \in Nodes :
    /\ role[leader] = "leader"
    /\ \E idx \in IndexDom :
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
    /\ LET idx == lastApplied[n] + 1 IN
       LET entry == log[n][idx] IN
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
  /\ term \in [Nodes -> TermDom]
  /\ role \in [Nodes -> Roles]
  /\ votedFor \in [Nodes -> (Nodes \cup {NULL})]
  /\ log \in [Nodes -> EntrySeq]
  /\ commitIndex \in [Nodes -> IndexDom]
  /\ lastApplied \in [Nodes -> IndexDom]
  /\ store \in [Nodes -> [Keys -> Values \cup {NoValue}]]
  /\ nextIndex \in [Nodes -> [Nodes -> NextIdxDom]]
  /\ matchIndex \in [Nodes -> [Nodes -> IndexDom]]
  /\ messages \subseteq Message

LeaderUniqueness ==
  \A t \in TermDom :
    \A l1, l2 \in Nodes :
      (role[l1] = "leader" /\ role[l2] = "leader" /\ term[l1] = t /\ term[l2] = t)
        => l1 = l2

==== END MODULE RaftStore ====
