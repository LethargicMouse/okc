size: u64,
alig: u64,

pub fn new(size: u64, alig: u64) @This() {
    return .{
        .size = size,
        .alig = alig,
    };
}

pub fn add(self: *@This(), other: @This()) void {
    self.alig = @max(self.alig, other.alig);
    // padding
    if (other.size % other.alig != 0) {
        self.size += other.alig - (self.size % other.alig);
    }
    self.size += other.size;
}
