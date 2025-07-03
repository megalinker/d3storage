# D3 – Decentralized Distributed Data Storage Layer for Motoko

A *zero‑dependency*, **stable‑heap–aware** storage library that turns an Internet Computer canister into a miniature object store.
It is designed for predictable performance, provable invariants, and painless testing.

---

## ✨ Features

| Capability                    | Details                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------- |
| **Chunked file upload**       | Upload arbitrarily‑large blobs in deterministic 1.8 MiB chunks.                               |
| **Constant‑time reads**       | Direct region offsets allow `getFile`/`getFileHTTP` to stream with *O(1)* header overhead.    |
| **Space‑efficient allocator** | Best‑fit + first‑append hybrid with coalescing free lists (offset‑ and size‑indexed B‑Trees). |
| **Runtime‑level safety**      | 100 % trap‑on‑corruption coverage via aggressive defensive checks.                            |
| **Incremental GC**            | `cleanupAbandonedUploads` walks the key‑space in bounded batches to avoid cycle overruns.     |
| **Property & scenario tests** | >2 000 random operations per test run keep invariants honest.                                 |

---

## 📦 Installation

```bash
mops install d3
```

or add directly to your `dfx.json` / Motoko sources:

```motoko
import D3 "path/to/D3";
```

---

## 🚀 Quick Start

```motoko
import D3 "mo:d3";

actor FileBucket {
  stable let d3 = D3.D3(); // 4 GiB budget by default

  public shared func upload(b : Blob, name : Text, typ : Text) : async Text {
    let { fileId } = await D3.storeFile({
      d3;
      storeFileInput = { fileDataObject = b; fileName = name; fileType = typ };
    });
    fileId
  };

  public query func download(id : Text) : async ?Blob {
    switch (D3.getFile({ d3; getFileInput = { fileId = id } })) {
      case (?f) ?f.fileData;
      case null  null;
    }
  };
}
```

---

## 🛠️ Public API

| Operation                 | Description                               | Worst‑case Time  | Notes                                                             |
| ------------------------- | ----------------------------------------- | ---------------- | ----------------------------------------------------------------- |
| `storeFile`               | Atomic single‑blob upload.                | **O(R · log F)** | R = storage regions, F = free blocks in scanned region.           |
| `storeFileMetadata`       | Reserve space, mark file **#Pending**.    | O(R · log F)     | Same allocator path without data write.                           |
| `storeFileChunk`          | Write chunk *k* (0‑based).                | **O(1)**         | Direct region write. Final chunk flip is a single `BTree.insert`. |
| `getFileMetadata`         | Return immutable header.                  | **O(log N)**     | N = number of files (B‑Tree lookup).                              |
| `getFile`                 | Read entire file (≤2 MiB).                | **O(1 + S)**     | S = size copied to return blob.                                   |
| `getFileHTTP`             | Streaming HTTP interface.                 | O(1) per chunk   | Uses callback token strategy.                                     |
| `getFileIds`              | List all files.                           | **O(N)**         | Linear scan over `fileLocationMap`.                               |
| `deleteFile`              | Deallocate + coalesce.                    | **O(log F)**     | Two `BTree` lookups + optional scanLimit(1).                      |
| `cleanupAbandonedUploads` | Batch reclaim stale **#Pending** uploads. | **O(L + log N)** | L = `limit` parameter.                                            |

*Underlying primitives*

| Helper                          | Complexity                  | Rationale                                       |
| ------------------------------- | --------------------------- | ----------------------------------------------- |
| `Allocator.addToFreeLists`      | **O(log F)**                | Two `BTree.insert` calls.                       |
| `Allocator.removeFromFreeLists` | **O(log F)**                | Delete + vector swap‑pop.                       |
| `Allocator._findAvailableSpace` | **O(R · ( log F + log S))** | Single pass: best‑fit scan + append evaluation. |

---

## 🗄️ Data Layout

```text
┌──────────────────────────────────────────────────┐
│ StorageRegion (4 GiB max)                       │
│  • bump‑offset tail                             │
│  • BTree<Nat64,Nat64>  freeBlocksByOffset       │
│  • BTree<Nat64,Vec<Nat64>> freeListBySize       │
├──────────────────────────────────────────────────┤
│ File Record (@ offset)                          │
│  00  Nat64  STORAGE_CLASS_CODE                  │
│  08  Nat64  fileSize                            │
│  10  Nat64  fileNameSize                        │
│  18  Nat64  fileTypeSize                        │
│  20  Blob   fileData                            │
│      Blob   fileName                            │
│      Blob   fileType                            │
└──────────────────────────────────────────────────┘
```

All integer fields are little‑endian **Nat64** and are 8‑byte aligned via `Utils.round_up_to_8`.

---

## 🧪 Testing

```bash
dfx deploy test
dfx canister call test run_all_tests
```

This executes:

* **Deterministic scenario** – full lifecycle of upload → HTTP download → delete → cleanup.
* **Property‑based fuzz** – 200× random allocations / frees with region invariants checked after **every** op.

---

## 📚 Reference Tables

### Enum Types

* `FileStatus = #Pending | #Complete`
* `StreamingStrategy = #Callback { callback; token }`

### Constants

| Symbol         | Value           | Meaning                                     |
| -------------- | --------------- | ------------------------------------------- |
| `PAGE_SIZE`    | 65 536 B        | IC stable‑heap page.                        |
| `CHUNK_SIZE`   | 1 800 000 B     | Fits comfortably under 2 MiB message limit. |
| `BYTES_BUDGET` | 3 758 096 384 B | 3.5 GiB safety ceiling.                     |

---

## 🔒 Safety & Invariants

* **Region accounting** – For every region: `live + free + tail == capacity` (verified in tests).
* **Dual‑map free lists** – Offset ↔︎ size views kept in lock‑step; violations trap.
* **Overflow‑safe math** – All `Nat64` additions use `Utils.checked_add`.

---

## 🔗 Integrating With HTTP

Expose two entrypoints on your actor:

```motoko
public query func http_request(req : HttpRequest) : async HttpResponse {
  D3.getFileHTTP({ d3; httpRequest = req; httpStreamingCallbackActor = this });
};

public shared query func http_request_streaming_callback(tok : StreamingCallbackToken)
  : async StreamingCallbackHttpResponse {
  D3.httpStreamingCallback({ d3; streamingCallbackToken = tok });
}
```

---

## 🤝 Contributing

Issues and PRs are welcome!  Please run `dfx test` and ensure *all* property tests pass before submitting.

---

## 🪪 License

MIT © 2025 Ztudio
