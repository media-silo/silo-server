<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 the media-silo project authors -->

# A file longer than the socket buffer arrives whole

## Why
A file served by range came back short of the `Content-Length` it was answered with, at a different
length each time, whenever it was longer than the socket buffer: artwork put from TMDb never showed in
the library's views, and the same was true of the silo's media and of a node's outputs. swift-http-server
hands a connection back to its keep-alive loop only once the request has been read to its end, and a
handler that answers without reading it has the connection closed behind it, with whatever of the
response is still queued. Proposal: [Silo proposal — Files move once](../../../Proposals/Silo.md).

## What Changes
- A node's file server reads each request to its end, discarding any body, before it answers.
- The silo's own routes take wire-mvc's reading of what a route leaves unread, by moving to the
  wire-mvc that does it (swift-wire/wire-mvc#257).
