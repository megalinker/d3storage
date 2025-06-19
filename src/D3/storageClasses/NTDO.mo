module {

    // Name, Type, Data Only
    public object NTDO = {
        public let STORAGE_CLASS_CODE : Nat64 = 1;

        // storage class code
        public func getFileStorageClassCodeRelativeOffset() : Nat64 { 0 };

        // file size
        public func getFileSizeRelativeOffset() : Nat64 {
            getFileStorageClassCodeRelativeOffset() + 8;
        };

        // file-name size
        public func getFileNameSizeRelativeOffset() : Nat64 {
            getFileSizeRelativeOffset() + 8;
        };

        // file-type size
        public func getFileTypeSizeRelativeOffset() : Nat64 {
            getFileNameSizeRelativeOffset() + 8;
        };

        // file-data
        public func getFileDataRelativeoffset() : Nat64 {
            getFileTypeSizeRelativeOffset() + 8;
        };

        // file-name
        public func getFileNameRelativeOffset({
            fileSize : Nat64;
        }) : Nat64 { getFileDataRelativeoffset() + fileSize };

        // file-type
        public func getFileTypeRelativeOffset({
            fileSize : Nat64;
            fileNameSize : Nat64;
        }) : Nat64 { getFileNameRelativeOffset({ fileSize }) + fileNameSize };

        // buffer
        public func getBufferRelativeOffset({
            fileSize : Nat64;
            fileNameSize : Nat64;
            fileTypeSize : Nat64;
        }) : Nat64 {
            getFileTypeRelativeOffset({ fileSize; fileNameSize }) + fileTypeSize;
        };

        public func getAllRelativeOffsets({
            fileSize : Nat64;
            fileNameSize : Nat64;
            fileTypeSize : Nat64;
        }) : {
            fileStorageClassCodeOffset : Nat64;
            fileSizeOffset : Nat64;
            fileNameSizeOffset : Nat64;
            fileTypeSizeOffset : Nat64;
            fileDataOffset : Nat64;
            fileNameOffset : Nat64;
            fileTypeOffset : Nat64;
            bufferOffset : Nat64;
        } {
            {
                fileStorageClassCodeOffset = getFileStorageClassCodeRelativeOffset();
                fileSizeOffset = getFileSizeRelativeOffset();
                fileNameSizeOffset = getFileNameSizeRelativeOffset();
                fileTypeSizeOffset = getFileTypeSizeRelativeOffset();
                fileDataOffset = getFileDataRelativeoffset();
                fileNameOffset = getFileNameRelativeOffset({ fileSize });
                fileTypeOffset = getFileTypeRelativeOffset({
                    fileSize;
                    fileNameSize;
                });
                bufferOffset = getBufferRelativeOffset({
                    fileSize;
                    fileNameSize;
                    fileTypeSize;
                });
            };
        };
    };

};
