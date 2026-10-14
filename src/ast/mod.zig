const std = @import("std");

pub const Module = @import("Module.zig");
pub const Stmt = @import("Stmt.zig");

pub var arena: std.heap.ArenaAllocator = undefined;
