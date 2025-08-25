pub const _asm = @import("_asm.zig");
test _asm {
    _ = _asm;
}

pub const fileMapping = @import("fileMapping.zig");
test fileMapping {
    _ = fileMapping;
}

const blockReaderNs = @import("BlockReader.zig");
pub const BlockReader = blockReaderNs.BlockReader;
test blockReaderNs {
    _ = blockReaderNs;
}
