---- MODULE SendQueue ----
EXTENDS Naturals, FiniteSets

CONSTANTS Msgs, MaxVer, MaxCrashes,
          HubDedupes,
          AutoFreshId, AckOnAmbiguous, NoAttemptBound, DispatchWhileInflight, DropOnGiveUp

MaxAttempts == 4
SentCap == 7

VARIABLES phase, attempts, ambiguous, ver, sent, userRetried,
          hubIds, hubTotal, inflight, unsaved, crashes

vars == <<phase, attempts, ambiguous, ver, sent, userRetried,
          hubIds, hubTotal, inflight, unsaved, crashes>>

Responses == {"ack", "retryAmb", "retryClear", "heldAmb", "heldClear"}
AmbResponses == {"retryAmb", "heldAmb"}
RetryResponses == {"retryAmb", "retryClear"}
Phases == {"none", "ready", "uncertain", "held", "acked", "deleted", "gone"}
Queued == {"ready", "uncertain", "held"}

TypeOK ==
    /\ phase \in [Msgs -> Phases]
    /\ attempts \in [Msgs -> 0..SentCap]
    /\ ambiguous \in [Msgs -> BOOLEAN]
    /\ ver \in [Msgs -> 0..MaxVer]
    /\ sent \in [Msgs -> 0..SentCap]
    /\ userRetried \in [Msgs -> BOOLEAN]
    /\ hubIds \in [Msgs -> SUBSET (0..MaxVer)]
    /\ hubTotal \in [Msgs -> 0..3]
    /\ inflight \subseteq Msgs
    /\ unsaved \in [Msgs -> Responses \cup {"none"}]
    /\ crashes \in 0..MaxCrashes

Init ==
    /\ phase = [m \in Msgs |-> "none"]
    /\ attempts = [m \in Msgs |-> 0]
    /\ ambiguous = [m \in Msgs |-> FALSE]
    /\ ver = [m \in Msgs |-> 0]
    /\ sent = [m \in Msgs |-> 0]
    /\ userRetried = [m \in Msgs |-> FALSE]
    /\ hubIds = [m \in Msgs |-> {}]
    /\ hubTotal = [m \in Msgs |-> 0]
    /\ inflight = {}
    /\ unsaved = [m \in Msgs |-> "none"]
    /\ crashes = 0

NoUnsaved == \A m \in Msgs : unsaved[m] = "none"

Compose(m) ==
    /\ phase[m] = "none"
    /\ phase' = [phase EXCEPT ![m] = "ready"]
    /\ UNCHANGED <<attempts, ambiguous, ver, sent, userRetried, hubIds, hubTotal, inflight, unsaved, crashes>>

Dispatch(m) ==
    /\ phase[m] = "ready"
    /\ (inflight = {} \/ DispatchWhileInflight)
    /\ NoUnsaved
    /\ sent[m] < SentCap
    /\ phase' = [phase EXCEPT ![m] = "uncertain"]
    /\ sent' = [sent EXCEPT ![m] = @ + 1]
    /\ inflight' = inflight \cup {m}
    /\ UNCHANGED <<attempts, ambiguous, ver, userRetried, hubIds, hubTotal, unsaved, crashes>>

Deliver(m) ==
    /\ hubIds' = [hubIds EXCEPT ![m] = @ \cup {ver[m]}]
    /\ hubTotal' = [hubTotal EXCEPT ![m] =
         IF HubDedupes /\ ver[m] \in hubIds[m] THEN @ ELSE IF @ < 3 THEN @ + 1 ELSE @]

Network(m, r) ==
    /\ m \in inflight
    /\ unsaved[m] = "none"
    /\ unsaved' = [unsaved EXCEPT ![m] = r]
    /\ inflight' = inflight \ {m}
    /\ \/ r = "ack" /\ Deliver(m)
       \/ r \in {"retryClear", "heldClear"} /\ UNCHANGED <<hubIds, hubTotal>>
       \/ r \in AmbResponses /\ Deliver(m)
       \/ r \in AmbResponses /\ UNCHANGED <<hubIds, hubTotal>>
    /\ UNCHANGED <<phase, attempts, ambiguous, ver, sent, userRetried, crashes>>

Commit(m) ==
    /\ unsaved[m] # "none"
    /\ LET r == unsaved[m]
           acked == r = "ack" \/ (AckOnAmbiguous /\ r \in AmbResponses)
           nextAttempts == IF attempts[m] < SentCap THEN attempts[m] + 1 ELSE attempts[m]
           canRetry == r \in RetryResponses /\ (NoAttemptBound \/ nextAttempts < MaxAttempts)
           giveUp == r \in RetryResponses /\ ~canRetry
       IN /\ unsaved' = [unsaved EXCEPT ![m] = "none"]
          /\ IF acked
               THEN /\ phase' = [phase EXCEPT ![m] = "acked"]
                    /\ UNCHANGED <<attempts, ambiguous, ver>>
               ELSE /\ attempts' = [attempts EXCEPT ![m] = nextAttempts]
                    /\ ambiguous' = [ambiguous EXCEPT ![m] = @ \/ r \in AmbResponses]
                    /\ phase' = [phase EXCEPT ![m] =
                         IF canRetry THEN "ready"
                         ELSE IF giveUp /\ DropOnGiveUp THEN "gone"
                         ELSE "held"]
                    /\ ver' = [ver EXCEPT ![m] =
                         IF canRetry /\ AutoFreshId /\ ver[m] < MaxVer THEN ver[m] + 1 ELSE ver[m]]
    /\ UNCHANGED <<sent, userRetried, hubIds, hubTotal, inflight, crashes>>

Crash ==
    /\ crashes < MaxCrashes
    /\ crashes' = crashes + 1
    /\ inflight' = {}
    /\ unsaved' = [m \in Msgs |-> "none"]
    /\ UNCHANGED <<phase, attempts, ambiguous, ver, sent, userRetried, hubIds, hubTotal>>

UserRetry(m) ==
    /\ phase[m] \in {"held", "uncertain"}
    /\ m \notin inflight
    /\ NoUnsaved
    /\ ver[m] < MaxVer
    /\ ver' = [ver EXCEPT ![m] = @ + 1]
    /\ phase' = [phase EXCEPT ![m] = "ready"]
    /\ attempts' = [attempts EXCEPT ![m] = 0]
    /\ ambiguous' = [ambiguous EXCEPT ![m] = FALSE]
    /\ sent' = [sent EXCEPT ![m] = 0]
    /\ userRetried' = [userRetried EXCEPT ![m] = TRUE]
    /\ UNCHANGED <<hubIds, hubTotal, inflight, unsaved, crashes>>

UserDelete(m) ==
    /\ phase[m] \in Queued
    /\ m \notin inflight
    /\ NoUnsaved
    /\ phase' = [phase EXCEPT ![m] = "deleted"]
    /\ UNCHANGED <<attempts, ambiguous, ver, sent, userRetried, hubIds, hubTotal, inflight, unsaved, crashes>>

Next ==
    \/ Crash
    \/ \E m \in Msgs :
         \/ Compose(m) \/ Dispatch(m) \/ Commit(m) \/ UserRetry(m) \/ UserDelete(m)
         \/ \E r \in Responses : Network(m, r)

Fairness ==
    /\ \A m \in Msgs : WF_vars(Dispatch(m))
    /\ \A m \in Msgs : WF_vars(Commit(m))
    /\ \A m \in Msgs : WF_vars(\E r \in Responses : Network(m, r))

Spec == Init /\ [][Next]_vars /\ Fairness

NoLoss ==
    \A m \in Msgs :
        /\ phase[m] # "gone"
        /\ (phase[m] = "acked" => hubTotal[m] >= 1)

NoDouble == \A m \in Msgs : ~userRetried[m] => hubTotal[m] <= 1

AutoSendsBounded == \A m \in Msgs : sent[m] <= MaxAttempts

SingleInflight == Cardinality(inflight) <= 1

InflightIsUncertain == \A m \in inflight : phase[m] = "uncertain"

ReadyResolves == \A m \in Msgs : (phase[m] = "ready") ~> (phase[m] # "ready")

====
