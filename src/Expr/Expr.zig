const std = @import("std");

pub const Binary = @import("Binary.zig");
const Failer = @import("../Failer.zig");
const Item = @import("../Item.zig");
const Location = @import("../Location.zig");
const Module = @import("../Module.zig");
const Typ = @import("../typ/typ.zig").Typ;
pub const Unary = @import("Unary.zig");

location: Location,
kind: Kind,

fn checkComptime(self: @This(), failer: *Failer) void {
    switch (self.kind) {
        .str, .bool, .char, .int, .sizeof, .vari, .undef => {},
        .call, .method => failer.fail(self.location, "cannot evaluate at compile time", .{}),
        .field => |field| field.expr.checkComptime(failer),
        .unary => |unary| unary.expr.checkComptime(failer),
        .elem => |elem| {
            elem.expr.checkComptime(failer);
            elem.index.checkComptime(failer);
        },
        .binary => |binary| {
            binary.left.checkComptime(failer);
            binary.right.checkComptime(failer);
        },
        .subslice => |subslice| {
            subslice.expr.checkComptime(failer);
            subslice.start.checkComptime(failer);
            subslice.end.checkComptime(failer);
        },
        .array => |array| for (array.exprs) |expr| {
            expr.checkComptime(failer);
        },
        .named_struc => |named| for (named.struc.fields) |field| {
            field.expr.checkComptime(failer);
        },
        .struc => |struc| for (struc.fields) |field| {
            field.expr.checkComptime(failer);
        },
    }
}

pub fn checkConst(self: *@This(), hint: Expr.Hint, ctx: Check) !Typ {
    const info = try self.check(hint, ctx);
    self.checkComptime(ctx.failer);
    return info.typ;
}

pub fn check(self: *@This(), hint: Expr.Hint, ctx: Check) error{OutOfMemory}!Expr.Info {
    switch (self.kind) {
        .method => unreachable,
        .subslice => |subslice| return subslice.check(self.location, ctx),
        .sizeof => |typ| return Sizeof.check(typ),
        .array => |*array| return array.check(hint.typ, ctx),
        .unary => |unary| return unary.check(self.location, hint.typ, ctx),
        .struc => |*struc| return struc.check(self.location, hint.typ, ctx),
        .int => |*int| return int.check(),
        .str => return Str.check(),
        .vari => |*vari| return vari.check(self.location, hint.mutable, ctx),
        .char => return .{
            .typ = .{ .prime = .u8 },
            .mutable = false,
        },
        .bool => return .{
            .typ = .{ .prime = .bool },
            .mutable = false,
        },
        .undef => |*undef| return undef.check(hint.typ),
        .call => |call| return call.check(hint.typ, ctx),
        .binary => |binary| return binary.check(ctx),
        .field => |field| return field.check(self.location, hint.mutable, ctx),
        .named_struc => |*struc| return struc.check(self.location, ctx),
        .elem => |elem| return elem.check(self.location, ctx),
    }
}

pub const Neg = struct {
    expr: Expr,

    pub fn check(expr: *Expr, ctx: Expr.Check) !Expr.Info {
        var info = try expr.check(.{}, ctx);
        if (!info.typ.isNumber()) {
            ctx.failer.wrongTyp(expr.location, .int, info.typ);
            info.typ = .err;
        }
        return .{
            .typ = info.typ,
            .mutable = false,
        };
    }
};

pub const Deref = struct {
    expr: Expr,

    pub fn check(expr: *Expr, location: Location, ctx: Expr.Check) !Expr.Info {
        const info = try expr.check(.{}, ctx);
        const norm = info.typ.normalise();
        const err = Expr.Info{
            .typ = .err,
            .mutable = true,
        };
        switch (norm) {
            .ptr => |ptr| {
                return .{
                    .typ = ptr.typ.*,
                    .mutable = ptr.mutable,
                };
            },
            .err => return err,
            .prime, .name, .any, .array, .slice, .fun, .int, .loc_name => {
                ctx.failer.fail(location, "cannot dereference type `{f}`", .{info.typ});
                return err;
            },
            .lazy => unreachable,
        }
    }
};

pub const Notb = struct {
    expr: Expr,

    pub fn check(expr: *Expr, ctx: Expr.Check) !Expr.Info {
        var info = try expr.check(.{}, ctx);
        if (!info.typ.isNumber()) {
            ctx.failer.wrongTyp(expr.location, .int, info.typ);
            info.typ = .err;
        }
        return .{
            .typ = info.typ,
            .mutable = false,
        };
    }
};

pub const Ptr = struct {
    expr: Expr,

    pub fn check(expr: *Expr, hint: Typ, ctx: Expr.Check) !Info {
        const mutable = if (hint == .ptr) hint.ptr.mutable else false;
        const info = try expr.check(.{ .mutable = mutable }, ctx);
        const ptr = try Typ.memo.box(info.typ);
        return .{
            .typ = .{ .ptr = .{
                .typ = ptr,
                .mutable = info.mutable,
            } },
            .mutable = false,
        };
    }
};

pub const Kind = union(enum) {
    array: Array,
    binary: *Binary,
    bool: bool,
    call: *Call,
    char: u8,
    elem: *Elem,
    field: *Field,
    int: Int,
    method: *Method,
    named_struc: Struct.Named,
    sizeof: Typ,
    str: []const u8,
    struc: Struct,
    subslice: *Subslice,
    unary: *Unary,
    undef: Undef,
    vari: Var,
};

pub const Sizeof = struct {
    typ: Typ,

    fn check(typ: Typ) !Expr.Info {
        _ = typ;
        return .{
            .typ = .{ .prime = .u64 },
            .mutable = false,
        };
    }
};

pub const Str = struct {
    bare: []const u8,

    pub fn check() !Expr.Info {
        const ptr = try Typ.memo.box(.{ .prime = .u8 });
        return .{
            .typ = .{ .slice = .{
                .typ = ptr,
                .mutable = false,
            } },
            .mutable = false,
        };
    }
};

pub const Var = struct {
    name: []const u8,
    fun_meta: ?FunMeta = null,

    pub fn check(
        self: *@This(),
        location: Location,
        hint_mutable: bool,
        ctx: Check,
    ) !Expr.Info {
        const err = Expr.Info{
            .typ = .err,
            .mutable = true,
        };
        const item = ctx.items.getPtr(self.name) orelse {
            ctx.failer.notDeclared(location, self.name);
            return err;
        };
        switch (item.kind) {
            .fun => |header| {
                item.used = true;
                self.fun_meta = @as(Expr.FunMeta, undefined);
                return self.fun_meta.?.fillFromHeader(ctx.gpa, header.*);
            },
            .struc, .typ => {
                ctx.failer.fail(location, "it is a type", .{});
                return err;
            },
            .vari => |*vari_decl| {
                item.used = true;
                if (hint_mutable) {
                    if (vari_decl.mutable) {
                        vari_decl.mutated = true;
                    } else {
                        if (vari_decl.can_be_mutable) {
                            std.log.info("add `mut` before name in {f}", .{item.location});
                        }
                    }
                }
                return .{
                    .typ = vari_decl.typ,
                    .mutable = vari_decl.mutable,
                };
            },
        }
    }
};

const Expr = @This();

pub const Method = struct {
    expr: Expr,
    vari: Var,
    args: []Expr,
    name_location: Location,
};

pub const FunMeta = struct {
    generics: []Typ,
    typ: Typ,

    pub fn fillFromHeader(
        self: *@This(),
        gpa: std.mem.Allocator,
        header: Item.Fun.Header,
    ) !Info {
        var resolve_map: std.StringHashMap(Typ) = .init(gpa);
        defer resolve_map.deinit();
        self.generics = try Module.arena.alloc(Typ, header.generics.len);
        @memset(self.generics, .any);
        for (header.generics, self.generics) |generic, *typ| {
            try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
        }
        const params = try gpa.alloc(Typ, header.params.len);
        defer gpa.free(params);
        for (header.params, params) |param, *target| {
            target.* = try param.typ.resolve(resolve_map);
        }
        const ret_typ = try header.ret_typ.resolve(resolve_map);
        self.typ = .{ .fun = .{
            .params = try Typ.memo.save(params),
            .ret_typ = try Typ.memo.box(ret_typ),
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }
};

pub const Subslice = struct {
    expr: Expr,
    start: Expr,
    end: Expr,

    fn check(self: *@This(), location: Location, ctx: Expr.Check) !Expr.Info {
        const info = try self.expr.check(.{}, ctx);
        const start = try self.start.check(.{}, ctx);
        const expected: Typ = .{ .prime = .u64 };
        _ = expected.unify(start.typ, self.start.location, ctx.failer);
        const end = try self.end.check(.{}, ctx);
        _ = expected.unify(end.typ, self.end.location, ctx.failer);
        switch (info.typ.normalise()) {
            .array => |array| return .{
                .typ = .{ .slice = .{
                    .typ = array.typ,
                    .mutable = info.mutable,
                } },
                .mutable = false,
            },
            .slice => return .{
                .typ = info.typ,
                .mutable = info.mutable,
            },
            else => |typ| {
                ctx.failer.fail(location, "cannot take slice of `{f}`", .{typ});
                return .{
                    .typ = .{ .slice = .{
                        .typ = try Typ.memo.box(.err),
                        .mutable = true,
                    } },
                    .mutable = false,
                };
            },
        }
    }
};

pub const Array = struct {
    mtyp: ?Typ,
    exprs: []Expr,
    typ: Typ = .any,

    fn check(self: *@This(), hint: Typ, ctx: Expr.Check) !Info {
        var inner_typ: Typ = .any;
        var inner_hint: Typ = .any;
        if (self.mtyp) |typ| {
            inner_typ = typ;
            inner_hint = typ;
        } else if (hint == .array) {
            inner_hint = hint.array.typ.*;
        }
        if (self.exprs.len == 0) {
            const typ = Typ{ .array = .{
                .typ = try Typ.memo.box(inner_hint),
                .len = 0,
            } };
            return .{
                .typ = typ,
                .mutable = false,
            };
        }
        for (self.exprs) |*expr| {
            const info = try expr.check(.{ .typ = inner_hint }, ctx);
            inner_typ = inner_typ.unify(info.typ, expr.location, ctx.failer);
        }
        self.typ = Typ{ .array = .{
            .typ = try Typ.memo.box(inner_typ),
            .len = self.exprs.len,
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }
};

pub const Struct = struct {
    fields: []Struct.Field,
    typ: Typ = .any,

    fn check(
        self: *@This(),
        location: Location,
        hint: Typ,
        ctx: Expr.Check,
    ) error{OutOfMemory}!Expr.Info {
        const err = Expr.Info{
            .typ = .err,
            .mutable = false,
        };
        const name = switch (hint) {
            .loc_name => |located| located.bare,
            .name => |name| name,
            .slice => |slice| return self.checkSlice(slice, location, ctx),
            .err => return err,
            .lazy => unreachable,
            .prime, .ptr, .any, .array, .fun, .int => {
                ctx.failer.cannotInfer(.any, location);
                for (self.fields) |*field| {
                    _ = try field.expr.check(.{}, ctx);
                }
                return err;
            },
        };
        return self.checkTyped(name, location, ctx);
    }

    fn checkSlice(
        self: *@This(),
        slice: Typ.Slice,
        location: Location,
        ctx: Expr.Check,
    ) !Expr.Info {
        var was_ptr: ?*const Typ = null;
        var was_len = false;
        for (self.fields) |*field| {
            if (std.mem.eql(u8, field.name, "ptr")) {
                if (was_ptr) |_| {
                    ctx.failer.newFieldSecond(field.location, field.name);
                }
                const expected = Typ{ .ptr = .{
                    .typ = slice.typ,
                    .mutable = slice.mutable,
                } };
                const info = try field.expr.check(.{ .typ = expected }, ctx);
                const typ = expected.unify(info.typ, field.expr.location, ctx.failer);
                was_ptr = if (typ == .ptr) typ.ptr.typ else try Typ.memo.box(.err);
            } else if (std.mem.eql(u8, field.name, "len")) {
                if (was_len) {
                    ctx.failer.newFieldSecond(field.location, field.name);
                }
                const info = try field.expr.check(.{ .typ = .{ .prime = .u64 } }, ctx);
                const expected: Typ = .{ .prime = .u64 };
                _ = expected.unify(info.typ, field.expr.location, ctx.failer);
                was_len = true;
            }
        }
        if (!was_len) {
            ctx.failer.notInit(location, "len");
        }
        if (was_ptr == null) {
            ctx.failer.notInit(location, "ptr");
        }
        self.typ = Typ{ .slice = .{
            .typ = was_ptr.?,
            .mutable = slice.mutable,
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }

    pub fn checkTyped(
        self: *@This(),
        name: Typ.Name,
        location: Location,
        ctx: Check,
    ) !Expr.Info {
        const err = Expr.Info{
            .typ = .err,
            .mutable = false,
        };
        const item = ctx.items.getPtr(name.name) orelse {
            ctx.failer.notDeclared(location, name.name);
            return err;
        };
        item.used = true;
        const decl = if (item.kind == .struc) item.kind.struc else {
            ctx.failer.notStruct(location, .{ .name = name });
            return err;
        };
        const generics = try ctx.gpa.alloc(Typ, decl.generics.len);
        defer ctx.gpa.free(generics);
        if (name.generics.len == 0) {
            @memset(generics, .any);
        } else {
            @memcpy(generics, name.generics);
        }
        var resolve_map: std.StringHashMap(Typ) = .init(ctx.gpa);
        defer resolve_map.deinit();
        for (decl.generics, generics) |generic, *typ| {
            try resolve_map.put(generic.name, .{ .lazy = .from(typ) });
        }
        for (self.fields) |*field| {
            try field.check(.{ .name = name }, decl.fields, resolve_map, ctx);
        }
        var iter = decl.fields.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.defaulted) {
                continue;
            }
            var not_init = true;
            for (self.fields) |field| {
                if (std.mem.eql(u8, entry.key_ptr.*, field.name)) {
                    not_init = false;
                    break;
                }
            }
            if (not_init) {
                ctx.failer.notInit(location, entry.key_ptr.*);
            }
        }
        self.typ = Typ{ .name = .{
            .generics = try Typ.memo.save(generics),
            .name = name.name,
        } };
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }

    pub const Field = struct {
        name: []const u8,
        expr: Expr,
        location: Location,

        fn check(
            self: *@This(),
            struc_typ: Typ,
            decl_fields: std.StringHashMap(Item.Struct.Field.Info),
            resolve_map: std.StringHashMap(Typ),
            ctx: Check,
        ) !void {
            const f_decl = decl_fields.get(self.name) orelse {
                ctx.failer.noField(self.location, self.name, struc_typ);
                return;
            };
            const decl_typ = try f_decl.typ.resolve(resolve_map);
            const info = try self.expr.check(.{ .typ = try decl_typ.solve() }, ctx);
            _ = decl_typ.unify(info.typ, self.expr.location, ctx.failer);
        }
    };

    pub const Named = struct {
        name: []const u8,
        struc: Struct,

        pub fn check(self: *@This(), location: Location, ctx: Check) !Expr.Info {
            return self.struc.checkTyped(.{ .name = self.name }, location, ctx);
        }
    };
};

pub const Int = struct {
    val: u64,
    typ: Typ = .int,

    pub fn check(self: *@This()) !Info {
        std.debug.assert(self.typ == .int);
        return .{
            .typ = .{ .lazy = .from(&self.typ) },
            .mutable = false,
        };
    }
};

// lol
pub const Undef = struct {
    typ: Typ = .any,

    pub fn check(self: *@This(), typ: Typ) !Info {
        self.typ = typ;
        return .{
            .typ = self.typ,
            .mutable = false,
        };
    }
};

pub const Call = struct {
    expr: Expr,
    args: []Expr,

    pub fn check(self: *@This(), hint: Typ, ctx: Check) !Expr.Info {
        const callee_info = try self.expr.check(.{}, ctx);
        const fun = callee_info.typ.getFun(self.expr.location, ctx.failer) orelse
            return self.checkBad(ctx);
        // to propagate hint to generics
        _ = fun.ret_typ.unifyOrNull(hint, .active);
        for (self.args, fun.params) |*arg, param| {
            const info = try arg.check(.{ .typ = param.normalise() }, ctx);
            _ = param.unify(info.typ, arg.location, ctx.failer);
        }
        return .{
            .typ = fun.ret_typ.*,
            .mutable = false,
        };
    }

    fn checkBad(call: *@This(), ctx: Check) !Info {
        for (call.args) |*arg| {
            _ = try arg.check(.{}, ctx);
        }
        return .{
            .typ = .err,
            .mutable = false,
        };
    }
};

pub const Field = struct {
    expr: Expr,
    name: []const u8,

    pub fn check(
        self: *@This(),
        location: Location,
        hint_mutable: bool,
        ctx: Check,
    ) !Expr.Info {
        var info = try self.expr.check(.{ .mutable = hint_mutable }, ctx);
        const err = Expr.Info{
            .typ = .err,
            .mutable = true,
        };
        var norm = info.typ.normalise();
        if (norm == .ptr) {
            info.mutable = norm.ptr.mutable;
            norm = norm.ptr.typ.normalise();
        }
        if (norm == .slice) {
            return norm.slice.checkField(info.mutable, self.name, location, ctx.failer);
        }
        const name = norm.getStructName(self.expr.location, ctx.failer) orelse return err;
        const item = ctx.items.get(name.name) orelse {
            ctx.failer.notStruct(self.expr.location, norm);
            return err;
        };
        const struc = if (item.kind == .struc) item.kind.struc else {
            ctx.failer.notStruct(self.expr.location, norm);
            return err;
        };
        const fiel = struc.fields.getPtr(self.name) orelse {
            ctx.failer.noField(location, self.name, .{ .name = name });
            return err;
        };
        fiel.used = true;
        var resolve_map: std.StringHashMap(Typ) = .init(ctx.gpa);
        defer resolve_map.deinit();
        for (struc.generics, name.generics) |generic, typ| {
            try resolve_map.put(generic.name, typ);
        }
        return .{
            .typ = try fiel.typ.resolve(resolve_map),
            .mutable = info.mutable,
        };
    }
};

pub const Elem = struct {
    expr: Expr,
    index: Expr,

    fn check(self: *@This(), location: Location, ctx: Check) !Info {
        const info = try self.expr.check(.{}, ctx);
        const index = try self.index.check(.{}, ctx);
        const expected: Typ = .{ .prime = .u64 };
        _ = expected.unify(index.typ, self.index.location, ctx.failer);
        return info.getElem(location, ctx.failer) orelse .{
            .typ = .err,
            .mutable = true,
        };
    }
};

pub const Info = struct {
    typ: Typ,
    mutable: bool,

    pub fn getElem(self: @This(), location: Location, failer: *Failer) ?@This() {
        switch (self.typ.normalise()) {
            .array => |array| return .{
                .typ = array.typ.*,
                .mutable = self.mutable,
            },
            .slice => |slice| return .{
                .typ = slice.typ.*,
                .mutable = slice.mutable,
            },
            .err => return null,
            .prime, .name, .loc_name, .ptr, .any, .fun, .int => {
                failer.fail(location, "type `{f}` does not support indexing", .{self.typ});
                return null;
            },
            .lazy => unreachable,
        }
    }
};

pub const Hint = struct {
    typ: Typ = .any,
    mutable: bool = false,
};

pub const Check = struct {
    gpa: std.mem.Allocator,
    items: std.StringHashMap(Item.Info),
    failer: *Failer,
};
