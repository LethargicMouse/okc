size: u64,
alig: u64,

pub fn new(size: u64, alig: u64) @This() {
    return .{
        .size = size,
        .alig = alig,
    };
}
