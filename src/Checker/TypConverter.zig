const std = @import("std");

const Ast = @import("../Ast/mod.zig");
const Typ = @import("typ.zig").Typ;
const Location = @import("../Location.zig");
const HashMap = @import("../hash_map.zig").HashMap;
const Failer = @import("Failer.zig");
const Memo = @import("../memo.zig").Memo;

const Self = @This();
gpa: std.mem.Allocator,
queue: std.ArrayList(Request) = .empty,
failer: *Failer,
ast_typ_memo: *Memo(Ast.Typ),
memo: HashMap(Typ, Ast.Typ),

pub fn init(gpa: std.mem.Allocator, failer: *Failer, ast_typ_memo: *Memo(Ast.Typ)) Self {
    return .{
        .gpa = gpa,
        .failer = failer,
        .ast_typ_memo = ast_typ_memo,
        .memo = .init(gpa),
    };
}

pub fn addRequest(self: *Self, request: Request) !void {
    try self.queue.append(self.gpa, request);
}

pub fn flush(self: *Self) !void {
    for (self.queue.items) |req| {
        if (try self.maybeConvert(req.from, req.location)) |ast_typ| {
            req.to.* = ast_typ;
        }
    }
    self.queue.clearRetainingCapacity();
}

pub fn deinit(self: *Self) void {
    self.queue.deinit(self.gpa);
    self.memo.deinit();
}

fn maybeConvert(self: *Self, typ: Typ, location: ?Location) !?Ast.Typ {
    return self.convert(typ) catch |err| switch (err) {
        error.BadConvert => return null,
        error.ConvertAny => {
            if (location) |loc| {
                self.failer.cannotInfer(typ, loc);
            }
            return null;
        },
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn convert(self: *Self, typ: Typ) !Ast.Typ {
    if (self.memo.get(typ)) |res| {
        return res;
    }
    const res = try self.convertFirstTime(typ);
    try self.memo.put(typ, res);
    return res;
}

const Error = error{
    OutOfMemory,
    BadConvert,
    ConvertAny,
};

fn convertFirstTime(self: *Self, typ: Typ) Error!Ast.Typ {
    switch (typ) {
        .name => |name| {
            const generics =
                try self.ast_typ_memo.arena.allocator().alloc(Ast.Typ, name.generics.len);
            for (generics, name.generics) |*target, generic| {
                target.* = try self.convert(generic);
            }
            return .{ .name = .{
                .name = name.name,
                .generics = generics,
            } };
        },
        .fun => |fun| {
            const params = try self.ast_typ_memo.arena.allocator().alloc(Ast.Typ, fun.params.len);
            for (params, fun.params) |*target, param| {
                target.* = try self.convert(param);
            }
            const ret_typ = try self.convert(fun.ret_typ.*);
            const ptr = try self.ast_typ_memo.box(ret_typ);
            return .{ .fun = .{
                .params = params,
                .ret_typ = ptr,
            } };
        },
        .slice => |slice| {
            const new = try self.convert(slice.typ.*);
            const ptr = try self.ast_typ_memo.box(new);
            return .{ .slice = .{
                .typ = ptr,
                .mutable = slice.mutable,
            } };
        },
        .prime => |prime| return .{ .prime = prime },
        .ptr => |ptr| {
            const inner = try self.convert(ptr.typ.*);
            const new = try self.ast_typ_memo.box(inner);
            return .{ .ptr = .{
                .typ = new,
                .mutable = ptr.mutable,
            } };
        },
        .array => |array| {
            const inner = try self.convert(array.typ.*);
            const new = try self.ast_typ_memo.box(inner);
            return .{ .array = .{
                .len = array.len,
                .typ = new,
            } };
        },
        .err => return error.BadConvert,
        .any, .int => return error.ConvertAny,
        .lazy => |inner| return self.convert(inner.*),
    }
}

const Request = struct {
    to: *Ast.Typ,
    from: Typ,
    location: Location,
};
