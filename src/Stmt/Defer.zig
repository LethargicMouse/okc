const okc = @import("okc");

inner: *okc.Stmt,

pub fn check(self: @This(), ctx: *okc.Stmt.Check) !okc.ControlFlow {
    const cflow = try self.inner.check(ctx);
    switch (cflow) {
        .cont => {},
        .ret => ctx.failer.fail(self.inner.location, "no returns inside defer!", .{}),
        .brek => ctx.failer.fail(self.inner.location, "no breaks inside defer!", .{}),
        .never => ctx.failer.fail(
            self.inner.location,
            "please don't put diverging code inside defer",
            .{},
        ),
    }
    return .cont;
}

pub fn parseStmt(ctx: *okc.Parser) !okc.Stmt {
    const location = ctx.getLocation();
    try ctx.expect(.deferr, .quiet);
    const inner = try okc.Stmt.parse(ctx);
    const ptr = try ctx.arena.allocator().create(okc.Stmt);
    ptr.* = inner;
    return .{ .location = location, .kind = .{ .deferr = .{ .inner = ptr } } };
}
