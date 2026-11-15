<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Proposals: 0022-repeats

Modified: 2026-11-15

# A request sent again is answered as the first was

This proposes that every write the silo takes recognise itself when it is sent again, and answer as
the first was answered: with the record it made or the state it reached, as they stand. A route that
makes a record recognises the record by what the request asks for, which is a natural key rather than
one the client keeps. A route that changes a state answers a repeat as made when the state it asked
for is the state there is. A delete answers a repeat as made because the silo remembers, for a while,
what it deleted. Where a route cannot tell a repeat from a refusal, the refusal says what it found.

[0021-stores](Stores.md) made this true of the container routes and of a store. Its second principle,
*every write can be sent twice*, is stated for every write; this proposal makes it so for the rest. It
is what makes it safe for a client to send a request again when its answer was lost, which the worker
and the node do not yet do ([silo-server#196](https://github.com/media-silo/silo-server/issues/196)).

## The problem

**A request sent again makes a second record.** Five routes mint a new record for each request, so a
client that sends one again because the first answer was lost has made two
([silo-server#194](https://github.com/media-silo/silo-server/issues/194)):

- a binding sent twice is two bindings of one entry, each with its own id;
- a ruleset applied twice makes a second set of resolved recipes beside the first;
- a binding's rules put twice are two versions with one document, the second in force;
- a ruleset stored twice without `basedOn` is two versions with one document, and with `basedOn` the
  second is refused as if another editor had stored before it;
- a source registered twice without a natural key is two sources of one file.

**A request sent again after it was made is refused, as a real refusal is.** Most of the other writes
refuse their own repeat in the same words as a conflict
([silo-server#195](https://github.com/media-silo/silo-server/issues/195)):

- a job made again from its recipe is 409, *the recipe is committed*, without the job's id;
- a job cancelled, retried, placed, completed or failed again is 409, *the wrong state*, told apart
  from a real wrong state only by the state its detail names;
- a placement made again is 409, *already exists; nothing is overwritten*, as a collision with another
  file is, and without the presentation's id;
- a library added again is 409, as an id another library holds is;
- a branch started again is 409, as a name taken is, and a branch promoted again is 409, *closed*;
- a library removed, a recipe discarded or a trial deleted again is 404, as an id that never existed is.

The silo's state after each is right. The answer is not, so a client whose first answer was lost has to
read the silo back and guess what happened, or report a failure for work that was done. A worker that
completed a job and lost the answer, asked to send again, is told its job is in the wrong state.

## What this is

**A repeat is answered with what it made.** A request whose effect the silo already holds is answered
with the record that effect is, as it stands now, and changes nothing. A route that answered the first
request 200 or 204 answers the repeat the same. A route that answered 201, because it made a record,
answers the repeat 200, because it found one: the silo already answers a source found by its natural
key so, and a store sent again under its key. What the answer says the request did — the writes a
placement made, the folders an edit moved — is what the repeat did, which is nothing, as 0021 answers an
edit sent again.

**A record is recognised by what it is.** No route takes a key a client keeps for its requests. Each
route that makes a record compares the request with the records it holds, by the fields that say what
the record is:

- *A source* by its natural key, which becomes required. A producer that knows no identity of its own
  for a file sends its content hash, a scheme the natural key already names. A source whose key the
  silo holds is answered as now: 200, taking the copy given, and 409 when the input spec differs.
- *A binding* by everything it says but its lineage's documents: its library; its item, as the item's
  container's id and the item's id; its alternative; its segments, in order, each a source and a span;
  its feature map; and its chapter names. A binding that says all of these is the binding there is,
  and is answered 200. The documents are left out because they are a copy of the library's containers
  as the producer read them, which the silo reads afresh from the library whenever it resolves or
  checks the binding, so a newer copy of them does not make a different entry.
- *An application* by the recipes it would make. The silo resolves the application as it does now, and
  for each output, a recipe the binding already holds whose facts and recipe are the ones just resolved —
  the same ruleset version, the same stack, the same output and the same decisions — is answered in
  place of a new one. An application all of whose recipes the binding holds is answered 200 with them,
  and stores nothing; one that makes any is answered 201 with every recipe it answers, made or found.
  An application that names no version takes the head, as now, so one sent again after the head moved
  makes recipes of the new head: that is what it asks for.
- *A binding's rules* by their document. A document whose bytes are the version in force's is answered
  200 as that version, and stores nothing.
- *A ruleset version* by its document. A document whose bytes are the head's of the branch it is stored
  on is answered 200 as the head, and stores nothing, whatever its `basedOn`. `basedOn` becomes required
  to store on a ruleset that exists, so that a store made without having read the head is refused rather
  than taken, and a repeat is told from another editor's store by the document, not by the base.

**A state is recognised by what it is.** A route that changes a state answers 200 with the record when
the state it asks for is the state there is:

- *A job made from a recipe* whose job the silo holds, of the same kind, trial or not, is answered with
  that job, as it stands. One asked for as the other kind is refused naming the job, and a recipe whose
  job was deleted is refused saying so.
- *A job cancelled* that is cancelled or cancelling is answered with it.
- *A job retried* that is pending is answered with it. One a node has claimed since cannot be told from a
  job that was never failed, and is refused as now, naming its state.
- *A job placed* that is placed is answered with it, its placement included. One whose placement is under
  way is refused as now, since how it ends is not yet known.
- *A job completed* that holds the output and the result sent is answered with it, encoded or failed as
  the result made it, and a trial is queued for fetching once. One that holds another output or another
  result is refused.
- *A job failed* that is failed with the reason sent, or cancelled because it was cancelling, is answered
  with it.
- *A file placed* whose presentation the library already holds, at the path the placement would write,
  with the tracks and chapters it asks for, is answered 200 as applied, with that presentation's id and no
  writes. A destination that holds anything else is refused as now.
- *A library added* that the silo serves, under the same id at the same path, is answered with it. The
  same id at another path is refused as now.
- *A branch started* that the ruleset has, from the same base, is answered with the branch as it stands.
  From another base, it is refused as now.
- *A branch promoted* that is closed by its promotion is answered with the standard's version the
  promotion made.

Two copies of one request sent at once are the same: the copy that finds the state the other made is
answered as made, where today it is refused as the wrong state.

**What was deleted is remembered.** The silo keeps a record of each library, recipe and trial it has
deleted, by id, for thirty days, in one file in its state directory. A delete of an id the record holds
is answered 204, and an id that was never there, or was deleted longer ago, is 404 as now, so a delete
of a mistyped id is still refused. The record is written once the delete has been made, so a delete
whose record could not be written is answered as made and its repeat is 404, which is how the silo
answers today. A library's id is taken off the record when a library is added under it again.

## Principles

0021's principles stand, and the second is now true of every write. This proposal adds three.

1. **A repeat is answered with the record.** The answer carries the record as it stands, with the status
   the first answer had, except that a record found rather than made is 200.
2. **The silo recognises a repeat by what it asks for.** A route compares the request with what it
   holds. No client keeps a key for each request, which would be state the silo has to store and a
   client can still leave out.
3. **A refusal that cannot tell says what it found.** Where the silo cannot tell a repeat from a
   conflict, it refuses, and names the record or the state that stands in the way.

## Vocabulary

- **Repeat** — a request whose effect the silo already holds: the record it would make, or the state it
  would reach.
- **Natural key** — the fields a route recognises its record by: what the record is, not who asked.
- **Deleted record** — the silo's record of the ids it has deleted in the last thirty days.

## What this looks like to the operator

The operator makes trial jobs of a branch's recipes from SiloAdmin, as the Mac's network drops. The
answers do not arrive, and the console sends the requests again when the network is back. The silo
answers each with the trial job it made the first time, and the console lists four trials, not eight,
and no error.

A node completes an encode as the silo restarts. The node's request reached the silo before it stopped,
and its answer did not reach the node. When the node sends the completion again, the silo answers with
the job, encoded, and the node goes on to its next job rather than reporting a failure for work that was
done.

The operator deletes a trial, and the console's request times out. They press *Delete* again; the silo
answers that it is deleted, and the console removes it from the list.

## What this asks of an implementation

Six steps, each a pull request carrying its spec change, in `openspec/changes/`: `repeats-1-sources`,
`repeats-2-bindings`, `repeats-3-versions`, `repeats-4-jobs`, `repeats-5-placement-and-branches` and
`repeats-6-deletes`. Each answer a repeat now gets is in `openapi.yaml` with the step that makes it.

### 1. A source's natural key is required

`POST /v1/sources` without a natural key is 400. A source whose key the silo holds is answered as now.

Tests: a source registered without a key is refused and nothing is stored; a source registered twice
with one key and spec is one source, answered 201 then 200.

### 2. A binding and an application are recognised

A binding that says what one the silo holds says, but for its lineage's documents, is answered 200 with
it. An application whose recipes the binding already holds is answered with them, 200 when it makes
none.

Tests: a binding sent twice is one binding, answered 201 then 200; a binding with another span of the
same source is another binding; a binding sent again with a newer copy of its container's document is
the binding there is; an application sent twice makes one set of recipes, answered 201 then 200; an
application after a recipe was committed answers the committed recipe; an application after the head
moved makes recipes of the new head; an application of two outputs, one already held, answers both with
201 and makes one.

### 3. A document already in force is that version

A binding's rules whose document is the version in force's are answered 200 as that version. A ruleset
version whose document is its branch's head's is answered 200 as the head, whatever its `basedOn`, and a
store on a ruleset that exists without `basedOn` is 400.

Tests: rules put twice are one version; rules put again after another version are a third; a ruleset
version stored twice on its base is one version, answered 201 then 200; a store of another document on
a stale base is still 409; a store without `basedOn` on a ruleset that exists is 400; a ruleset's first
version needs none.

### 4. Jobs

A job made again from its recipe, and each state change sent again, answered with the job; two copies
of one change sent at once both answered with it.

Tests: a job made twice is one job, answered 201 then 200, and answered as it stands after a claim; a
trial asked for again as a job is refused naming the trial; a recipe whose trial was deleted is refused
saying so; a cancel, a place, a completion and a failure
sent twice each answer the job; a completion sent again with another result is refused; a retry of a
job claimed since is refused naming its state; a completion and a failure raced keep one outcome, and a
completion raced with itself is answered both times.

### 5. Placements and branches

A placement whose presentation is at its destination, a branch started again from its base, and a branch
promoted again, each answered as made.

Tests: a file placed twice answers the same presentation id, the second writing nothing; another file at
that destination is still 409; a branch started twice from one base answers the branch; from another
base, 409; a branch promoted twice answers the version the promotion made.

### 6. Deletes, and a library added again

The deleted record; a library, a recipe or a trial deleted again answered 204; a library added again at
its path answered 200.

Tests: a library, a recipe and a trial each deleted twice answer 204 both times; a delete of an id
never held is 404; an id deleted more than thirty days ago is 404; the record survives a restart; a
library added again under its id after it was removed is taken off the record, and a removal of it after
that is the new library's; a library added twice at one path answers 201 then 200, and at another path,
409.
