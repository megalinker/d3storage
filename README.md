# D3 Library

A robust and efficient library for managing file storage, retrieval, and cleanup using Motoko on the Internet Computer platform.

## Features

* **File Storage**: Efficiently stores files, automatically managing storage regions and allocation.
* **Chunked Uploads**: Supports uploading large files through chunked upload methods.
* **File Retrieval**: Fetches metadata and file contents with convenient query methods.
* **Cleanup Mechanism**: Automatically removes abandoned uploads after specified timeouts, freeing up storage.
* **HTTP Interface**: Provides HTTP endpoints for direct file access and streaming.

## Structure

* **modules**: Core functionalities including storage (`put`), retrieval (`get`), deletion (`delete`), cleanup (`cleanup`), and HTTP handling (`getHttp`).
* **types**: Defines core data structures and operation input/output types.
* **storageClasses**: Manages specific storage details, notably offsets and metadata handling.
* **utils**: Auxiliary functions, including ULID generation.
* **service**: Unified interface for executing update and query operations.

## Usage

### Initializing D3

```motoko
import D3 "D3";
stable let d3 = D3.D3();
```

### Store File

```motoko
await D3.storeFile({
  d3,
  storeFileInput = {
    fileDataObject = Blob.fromArray(dataArray),
    fileName = "file.jpeg",
    fileType = "image/jpeg",
  }
});
```

### Retrieve File Metadata

```motoko
D3.getFileMetadata({
  d3,
  getFileMetadataInput = { fileId }
});
```

### Delete File

```motoko
D3.deleteFile({
  d3,
  deleteFileInput = { fileId }
});
```

### Cleanup Abandoned Uploads

```motoko
D3.cleanupAbandonedUploads({
  d3,
  timeoutNanos = 86400000000000 // Example: 1 day in nanoseconds
});
```

### HTTP Streaming

Files larger than the message limit can be streamed via the HTTP interface.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

This project is licensed under the MIT License. See [LICENSE.md](LICENSE.md) for more information.

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

Developed with Motoko for secure and scalable file management on the Internet Computer.