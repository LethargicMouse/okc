bare: u32 = 0,

pub fn init() @This() {
    return .{};
}

pub fn next(self: *@This()) u32 {
    self.bare += 1;
    return self.bare + 1;
}
