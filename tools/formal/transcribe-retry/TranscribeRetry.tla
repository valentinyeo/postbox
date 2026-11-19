---- MODULE TranscribeRetry ----
EXTENDS Naturals, FiniteSets

CONSTANTS Msgs, Cap, MaxOpens, MaxReloads,
          RecordAttempt, ReopenClearsReady, ParallelRequests

VARIABLES st, attempted, active, requests, doneBefore, lateRequests, opens, reloads

vars == <<st, attempted, active, requests, doneBefore, lateRequests, opens, reloads>>

States == {"none", "loading", "ready", "failed"}

TypeOK ==
    /\ st \in [Msgs -> States]
    /\ attempted \subseteq Msgs
    /\ active \subseteq Msgs
    /\ requests \in [Msgs -> 0..3]
    /\ doneBefore \subseteq Msgs
    /\ lateRequests \in [Msgs -> 0..3]
    /\ opens \in 0..MaxOpens
    /\ reloads \in 0..MaxReloads

Init ==
    /\ st = [m \in Msgs |-> "none"]
    /\ attempted = {}
    /\ active = {}
    /\ requests = [m \in Msgs |-> 0]
    /\ doneBefore = {}
    /\ lateRequests = [m \in Msgs |-> 0]
    /\ opens = 0
    /\ reloads = 0

Open ==
    /\ opens < MaxOpens
    /\ opens' = opens + 1
    /\ requests' = [m \in Msgs |-> 0]
    /\ attempted' = active
    /\ st' = [m \in Msgs |->
                IF st[m] = "failed" THEN "none"
                ELSE IF st[m] = "ready" /\ ReopenClearsReady THEN "none"
                ELSE st[m]]
    /\ UNCHANGED <<active, doneBefore, lateRequests, reloads>>

Reload ==
    /\ reloads < MaxReloads
    /\ reloads' = reloads + 1
    /\ st' = [m \in Msgs |-> IF st[m] = "ready" THEN "ready" ELSE "none"]
    /\ UNCHANGED <<attempted, active, requests, doneBefore, lateRequests, opens>>

WasAttempted(m) == m \in attempted \/ Cardinality(attempted) >= Cap

Mark(m) ==
    IF WasAttempted(m) \/ ~RecordAttempt THEN attempted ELSE attempted \cup {m}

SkipAttempted(m) ==
    /\ st[m] = "none"
    /\ WasAttempted(m)
    /\ st' = [st EXCEPT ![m] = IF m \in active THEN "loading" ELSE "failed"]
    /\ UNCHANGED <<attempted, active, requests, doneBefore, lateRequests, opens, reloads>>

Start(m) ==
    /\ st[m] = "none"
    /\ ~WasAttempted(m)
    /\ (active = {} \/ ParallelRequests)
    /\ attempted' = Mark(m)
    /\ st' = [st EXCEPT ![m] = "loading"]
    /\ active' = active \cup {m}
    /\ requests' = [requests EXCEPT ![m] = IF @ < 3 THEN @ + 1 ELSE @]
    /\ lateRequests' = [lateRequests EXCEPT ![m] = IF m \in doneBefore /\ @ < 3 THEN @ + 1 ELSE @]
    /\ UNCHANGED <<doneBefore, opens, reloads>>

Finish(m, ok) ==
    /\ m \in active
    /\ st' =[st EXCEPT ![m] = IF ok THEN "ready" ELSE "failed"]
    /\ active' = active \ {m}
    /\ doneBefore' = IF ok THEN doneBefore \cup {m} ELSE doneBefore
    /\ UNCHANGED <<attempted, requests, lateRequests, opens, reloads>>

Next ==
    \/ Open
    \/ Reload
    \/ \E m \in Msgs : SkipAttempted(m) \/ Start(m) \/ Finish(m, TRUE) \/ Finish(m, FALSE)

Spec == Init /\ [][Next]_vars

OneRequestPerOpen == \A m \in Msgs : requests[m] <= 1

OneAtATime == Cardinality(active) <= 1

NeverRerequestReady == \A m \in Msgs : lateRequests[m] = 0

====
