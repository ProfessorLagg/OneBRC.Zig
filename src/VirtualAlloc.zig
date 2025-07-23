comptime {
    if (builtin.target.os.tag != .windows) unreachable;
}
const builtin = @import("builtin");
const std = @import("std");
const DWORD = std.os.windows.DWORD;
const SYSTEM_INFO = std.os.windows.SYSTEM_INFO;

const AllocationType = enum(DWORD) {
    pub inline fn dw(self: AllocationType) DWORD {
        return @intFromEnum(self);
    }
    ///Allocates memory charges (from the overall size of memory and the paging files on disk) for the specified reserved memory pages. The function also guarantees that when the caller later initially accesses the memory, the contents will be zero. Actual physical pages are not allocated unless/until the virtual addresses are actually accessed.
    ///
    ///To reserve and commit pages in one step, call **VirtualAlloc** with `MEM_COMMIT | MEM_RESERVE`.
    ///
    ///Attempting to commit a specific address range by specifying **MEM_COMMIT** without **MEM_RESERVE** and a non-**NULL** _lpAddress_ fails unless the entire range has already been reserved. The resulting error code is **ERROR_INVALID_ADDRESS**.
    ///
    ///An attempt to commit a page that is already committed does not cause the function to fail. This means that you can commit pages without first determining the current commitment state of each page.
    ///
    ///If _lpAddress_ specifies an address within an enclave, _flAllocationType_ must be **MEM_COMMIT**.
    MEM_COMMIT = 0x00001000,

    ///Reserves a range of the process's virtual address space without allocating any actual physical storage in memory or in the paging file on disk.
    ///
    ///You can commit reserved pages in subsequent calls to the **VirtualAlloc** function. To reserve and commit pages in one step, call **VirtualAlloc** with **MEM_COMMIT** | **MEM_RESERVE**.
    ///
    ///Other memory allocation functions, such as **malloc** and [LocalAlloc](https://learn.microsoft.com/en-us/windows/desktop/api/winbase/nf-winbase-localalloc), cannot use a reserved range of memory until it is released.s
    MEM_RESERVE = 0x00002000,

    ///Indicates that data in the memory range specified by lpAddress and dwSize is no longer of interest. The pages should not be read from or written to the paging file. However, the memory block will be used again later, so it should not be decommitted. This value cannot be used with any other value.
    ///Using this value does not guarantee that the range operated on with MEM_RESET will contain zeros. If you want the range to contain zeros, decommit the memory and then recommit it.
    ///
    ///When you specify MEM_RESET, the VirtualAlloc function ignores the value of flProtect. However, you must still set flProtect to a valid protection value, such as PAGE_NOACCESS.
    ///
    ///VirtualAlloc returns an error if you use MEM_RESET and the range of memory is mapped to a file. A shared view is only acceptable if it is mapped to a paging file.
    MEM_RESET = 0x00080000,

    ///**MEM_RESET_UNDO** should only be called on an address range to which **MEM_RESET** was successfully applied earlier. It indicates that the data in the specified memory range specified by _lpAddress_ and _dwSize_ is of interest to the caller and attempts to reverse the effects of **MEM_RESET**. If the function succeeds, that means all data in the specified address range is intact. If the function fails, at least some of the data in the address range has been replaced with zeroes.
    ///
    ///This value cannot be used with any other value. If **MEM_RESET_UNDO** is called on an address range which was not **MEM_RESET** earlier, the behavior is undefined. When you specify **MEM_RESET**, the **VirtualAlloc** function ignores the value of _flProtect_. However, you must still set _flProtect_ to a valid protection value, such as **PAGE_NOACCESS**.
    ///
    ///**Windows Server 2008 R2, Windows 7, Windows Server 2008, Windows Vista, Windows Server 2003 and Windows XP:**  The **MEM_RESET_UNDO** flag is not supported until Windows 8 and Windows Server 2012.
    MEM_RESET_UNDO = 0x1000000,
};

var SystemInfo: SYSTEM_INFO = undefined;
var SystemInfoInitialized: bool = false;
inline fn ensureSystemInfo() void {
    if (SystemInfoInitialized) return;
    std.os.windows.kernel32.GetSystemInfo(&SystemInfo);
    SystemInfoInitialized = true;
}

/// Uses VirtualAlloc to allocate an entire AllocationGranularity. Guranteed to be aligned to a page at both ends
pub fn allocBlock() ![]u8 {
    ensureSystemInfo();
    const size: usize = SystemInfo.dwAllocationGranularity;
    const alloc_type: DWORD = AllocationType.MEM_COMMIT.dw() | AllocationType.MEM_RESERVE.dw();
    const ptr = try std.os.windows.VirtualAlloc(
        null, // addr: ?LPVOID
        size, // size: usize
        alloc_type, // alloc_type: DWORD
        std.os.windows.PAGE_READWRITE, // flProtect: DWORD
    );

    var result: []u8 = undefined;
    result.len = size;
    result.ptr = @ptrCast(ptr);
    return result;
}

const FreeType = enum(DWORD) {
    pub inline fn dw(self: FreeType) DWORD {
        return @intFromEnum(self);
    }
    ///Decommits the specified region of committed pages. After the operation, the pages are in the reserved state.
    ///
    ///The function does not fail if you attempt to decommit an uncommitted page. This means that you can decommit a range of pages without first determining the current commitment state.
    ///
    ///The **MEM_DECOMMIT** value is not supported when the _lpAddress_ parameter provides the base address for an enclave. This is true for enclaves that do not support dynamic memory management (i.e. SGX1). SGX2 enclaves permit **MEM_DECOMMIT** anywhere in the enclave.
    MEM_DECOMMIT = 0x00004000,

    ///Releases the specified region of pages, or placeholder (for a placeholder, the address space is released and available for other allocations). After this operation, the pages are in the free state.
    ///
    ///If you specify this value, _dwSize_ must be 0 (zero), and _lpAddress_ must point to the base address returned by the [VirtualAlloc](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-virtualalloc) function when the region is reserved. The function fails if either of these conditions is not met.
    ///
    ///If any pages in the region are committed currently, the function first decommits, and then releases them.
    ///
    ///The function does not fail if you attempt to release pages that are in different states, some reserved and some committed. This means that you can release a range of pages without first determining the current commitment state.
    MEM_RELEASE = 0x00008000,
};

/// Frees a AllocationGranularity sized block allocated with `allocBlock`
pub fn freeBlock(block: []u8) !void {
    ensureSystemInfo();
    const blockSize: usize = SystemInfo.dwAllocationGranularity;
    if (block.len != blockSize) return error.NotAVirtualAllocBlock;
    if (@intFromPtr(block.ptr) % SystemInfo.?.dwPageSize != 0) return error.NotAVirtualAllocBlock;
    std.os.windows.VirtualFree(
        @ptrCast(block.ptr), //lpAddress
        0, // dwSize
        FreeType.MEM_RELEASE.dw(), // dwFreeType
    );
}
