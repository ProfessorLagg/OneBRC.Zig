const builtin = @import("builtin");
const std = @import("std");

pub const FileMapping = switch (builtin.os.tag) {
    .windows => _windows.FileMapping,
    else => {
        // std.log.err("Unsupported OS: {s}", .{@tagName(builtin.os.tag)});
        @panic("Unsupported OS: " ++ @tagName(builtin.os.tag));
    },
};

pub const FileView = switch (builtin.os.tag) {
    .windows => _windows.FileView,
    else => @panic("Unsupported OS: " ++ @tagName(builtin.os.tag)),
};

pub const _windows = struct {
    const Windows_h = @cImport({
        @cDefine("WIN32_LEAN_AND_MEAN", "1");
        @cInclude("Windows.h");
    });

    pub const FileMapping = struct {
        const ProtectionFlag = enum(Windows_h.DWORD) {
            /// Allows views to be mapped for read-only, copy-on-write, or execute access.
            /// The file handle specified by the hFile parameter must be created with the GENERIC_READ and GENERIC_EXECUTE access rights.
            PAGE_EXECUTE_READ = Windows_h.PAGE_EXECUTE_READ,
            /// Allows views to be mapped for read-only, copy-on-write, read/write, or execute access.
            /// The file handle that the hFile parameter specifies must be created with the GENERIC_READ, GENERIC_WRITE, and GENERIC_EXECUTE access rights.
            PAGE_EXECUTE_READWRITE = Windows_h.PAGE_EXECUTE_READWRITE,
            /// Allows views to be mapped for read-only, copy-on-write, or execute access. This value is equivalent to PAGE_EXECUTE_READ.
            /// The file handle that the hFile parameter specifies must be created with the GENERIC_READ and GENERIC_EXECUTE access rights.
            PAGE_EXECUTE_WRITECOPY = Windows_h.PAGE_EXECUTE_WRITECOPY,
            /// Allows views to be mapped for read-only or copy-on-write access. An attempt to write to a specific region results in an access violation.
            /// The file handle that the hFile parameter specifies must be created with the GENERIC_READ access right.
            PAGE_READONLY = Windows_h.PAGE_READONLY,
            /// Allows views to be mapped for read-only, copy-on-write, or read/write access.
            /// The file handle that the hFile parameter specifies must be created with the GENERIC_READ and GENERIC_WRITE access rights.
            PAGE_READWRITE = Windows_h.PAGE_READWRITE,
            /// Allows views to be mapped for read-only or copy-on-write access. This value is equivalent to PAGE_READONLY.
            /// The file handle that the hFile parameter specifies must be created with the GENERIC_READ access right.
            PAGE_WRITECOPY = Windows_h.PAGE_WRITECOPY,

            pub inline fn asDWORD(flag: ProtectionFlag) Windows_h.DWORD {
                return @as(Windows_h.DWORD, @intFromEnum(flag));
            }
        };
        const SecFlags = enum(Windows_h.DWORD) {
            /// If the file mapping object is backed by the operating system paging file (the hfile parameter is INVALID_HANDLE_VALUE), specifies that when a view of the file is mapped into a process address space, the entire range of pages is committed rather than reserved. The system must have enough committable pages to hold the entire mapping. Otherwise, CreateFileMapping fails.
            /// This attribute has no effect for file mapping objects that are backed by executable image files or data files (the hfile parameter is a handle to a file).
            ///
            /// SEC_COMMIT cannot be combined with SEC_RESERVE.
            ///
            /// If no attribute is specified, SEC_COMMIT is assumed.
            SEC_COMMIT = Windows_h.SEC_COMMIT,
            /// Specifies that the file that the hFile parameter specifies is an executable image file.
            /// The SEC_IMAGE attribute must be combined with a page protection value such as PAGE_READONLY. However, this page protection value has no effect on views of the executable image file. Page protection for views of an executable image file is determined by the executable file itself.
            ///
            /// No other attributes are valid with SEC_IMAGE.
            SEC_IMAGE = Windows_h.SEC_IMAGE,
            // Specifies that the file that the hFile parameter specifies is an executable image file that will not be executed and the loaded image file will have no forced integrity checks run. Additionally, mapping a view of a file mapping object created with the SEC_IMAGE_NO_EXECUTE attribute will not invoke driver callbacks registered using the PsSetLoadImageNotifyRoutine kernel API.
            // The SEC_IMAGE_NO_EXECUTE attribute must be combined with the PAGE_READONLY page protection value. No other attributes are valid with SEC_IMAGE_NO_EXECUTE.
            SEC_IMAGE_NO_EXECUTE = Windows_h.SEC_IMAGE_NO_EXECUTE,
            /// Enables large pages to be used for file mapping objects that are backed by the operating system paging file (the hfile parameter is INVALID_HANDLE_VALUE). This attribute is not supported for file mapping objects that are backed by executable image files or data files (the hFile parameter is a handle to an executable image or data file).
            /// The maximum size of the file mapping object must be a multiple of the minimum size of a large page returned by the GetLargePageMinimum function. If it is not, CreateFileMapping fails. When mapping a view of a file mapping object created with SEC_LARGE_PAGES, the base address and view size must also be multiples of the minimum large page size.
            ///
            /// SEC_LARGE_PAGES requires the SeLockMemoryPrivilege privilege to be enabled in the caller's token.
            ///
            /// If SEC_LARGE_PAGES is specified, SEC_COMMIT must also be specified.
            SEC_LARGE_PAGES = Windows_h.SEC_LARGE_PAGES,
            /// Sets all pages to be non-cacheable.
            /// Applications should not use this attribute except when explicitly required for a device. Using the interlocked functions with memory that is mapped with SEC_NOCACHE can result in an EXCEPTION_ILLEGAL_INSTRUCTION exception.
            ///
            /// SEC_NOCACHE requires either the SEC_RESERVE or SEC_COMMIT attribute to be set.
            SEC_NOCACHE = Windows_h.SEC_NOCACHE,
            /// If the file mapping object is backed by the operating system paging file (the hfile parameter is INVALID_HANDLE_VALUE), specifies that when a view of the file is mapped into a process address space, the entire range of pages is reserved for later use by the process rather than committed.
            /// Reserved pages can be committed in subsequent calls to the VirtualAlloc function. After the pages are committed, they cannot be freed or decommitted with the VirtualFree function.
            ///
            /// This attribute has no effect for file mapping objects that are backed by executable image files or data files (the hfile parameter is a handle to a file).
            ///
            /// SEC_RESERVE cannot be combined with SEC_COMMIT.
            SEC_RESERVE = Windows_h.SEC_RESERVE,
            /// Sets all pages to be write-combined.
            /// Applications should not use this attribute except when explicitly required for a device. Using the interlocked functions with memory that is mapped with SEC_WRITECOMBINE can result in an EXCEPTION_ILLEGAL_INSTRUCTION exception.
            ///
            /// SEC_WRITECOMBINE requires either the SEC_RESERVE or SEC_COMMIT attribute to be set.
            SEC_WRITECOMBINE = Windows_h.SEC_WRITECOMBINE,

            pub inline fn asDWORD(flag: SecFlags) Windows_h.DWORD {
                return @as(Windows_h.DWORD, @intFromEnum(flag));
            }
        };

        handle: Windows_h.HANDLE,
        size: u64,

        /// Creates the file mapping in PAGE_READONLY mode
        pub fn initRead(file: *const std.fs.File) !_windows.FileMapping {
            const hFile = file.handle;

            const stat = try file.stat();
            const hMap = Windows_h.CreateFileMappingA( // NO
                hFile, // hFile
                null, // Mapping attributes
                ProtectionFlag.PAGE_READONLY.asDWORD(), // Protection flags
                0, // MaximumSizeHigh
                0, // MaximumSizeLow
                null // Name
            );

            if (hMap == null) {
                const err: std.os.windows.Win32Error = std.os.windows.GetLastError();
                _ = Windows_h.CloseHandle(hMap);
                return std.os.windows.unexpectedError(err);
            }

            return _windows.FileMapping{
                .handle = hMap,
                .size = stat.size,
            };
        }

        pub fn deinit(self: *const _windows.FileMapping) void {
            _ = Windows_h.CloseHandle(self.handle);
        }
    };

    pub const FileView = struct {
        basePtr: Windows_h.LPVOID,
        slice: []u8,

        const DesiredAccess = enum(Windows_h.DWORD) {
            /// A read/write view of the file is mapped. The file mapping object must have been created with PAGE_READWRITE or PAGE_EXECUTE_READWRITE protection.
            /// When used with the MapViewOfFile function, FILE_MAP_ALL_ACCESS is equivalent to FILE_MAP_WRITE.
            FILE_MAP_ALL_ACCESS = Windows_h.FILE_MAP_ALL_ACCESS,
            /// A read-only view of the file is mapped. An attempt to write to the file view results in an access violation.
            /// The file mapping object must have been created with PAGE_READONLY, PAGE_READWRITE, PAGE_EXECUTE_READ, or PAGE_EXECUTE_READWRITE protection.
            FILE_MAP_READ = Windows_h.FILE_MAP_READ,
            /// A read/write view of the file is mapped. The file mapping object must have been created with PAGE_READWRITE or PAGE_EXECUTE_READWRITE protection.
            /// When used with MapViewOfFile, (FILE_MAP_WRITE | FILE_MAP_READ) and FILE_MAP_ALL_ACCESS are equivalent to FILE_MAP_WRITE.
            FILE_MAP_WRITE = Windows_h.FILE_MAP_WRITE,

            pub inline fn asDWORD(flag: DesiredAccess) Windows_h.DWORD {
                return @as(Windows_h.DWORD, @intFromEnum(flag));
            }
        };

        pub fn initRead(fileMapping: *const _windows.FileMapping) !_windows.FileView {
            const basePtr = Windows_h.MapViewOfFile( // NO FOLD
                fileMapping.handle, // hMap
                DesiredAccess.FILE_MAP_READ.asDWORD(), // dwDesiredAccess
                0, // dwFileOffsetHigh
                0, // dwFileOffsetLow
                0 // dwNumberOfBytesToMap
            );

            if (basePtr == null) {
                const err = std.os.windows.GetLastError();
                _ = Windows_h.UnmapViewOfFile(basePtr);
                return std.os.windows.unexpectedError(err);
            }

            const ptr: [*]u8 = @ptrCast(basePtr.?);

            return _windows.FileView{
                .basePtr = basePtr,
                .slice = ptr[0..fileMapping.size],
            };
        }
        pub fn deinit(self: *const _windows.FileView) void {
            _ = Windows_h.UnmapViewOfFile(self.basePtr);
        }
    };
};
