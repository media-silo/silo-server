<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# Stores

## Why
A walk's store is hundreds of requests the console makes one after another, any of which can outlast
the connection it is sent on, and none of which can be asked after when its answer is lost. A store
handed to the silo whole, under a key, is answered at once, made by the silo, and asked after.
Proposal: [0021-stores](../../../Proposals/Stores.md).

## What Changes
- `POST /v1/libraries/{library}/stores` takes a store's steps under a key, checks them before making
  any, records the store and answers at once.
- The silo makes a store's steps in order, in one turn of the library's lane, walking after a step
  that moves folders, and stops at the first refusal.
- The same key with the same steps is answered the store's record; with other steps, 409.
- `GET /v1/libraries/{library}/stores/{key}` says the store's state, how many steps are made, and the
  refusal.
- Each store is kept as a JSON file in the state directory for thirty days, and a store under way when
  the silo stops is resumed when it starts.

## Impact
- Added: a library's store taken and made in the background; a store said and resumed.
