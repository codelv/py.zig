const py = @import("py.zig");
const std = @import("std");
// Import basic objects
const Object = py.Object;
const Int = py.Int;
const Str = py.Str;
const Module = py.Module;

pub fn add(mod: *Module, args: [*]*Object, n: isize) ?*Object {
    _ = mod;
    if (n != 2) {
        return py.typeErrorObject(null, "sum requires 2 arguments", .{});
    }
    // We can now safely access  indexes 0 and 1
    if (!Int.check(args[0]) or !Int.check(args[1])) {
        return py.typeErrorObject(null, "both arguments must be ints!", .{});
    }

    // We can now safely cast to Int objects and access their methods
    const a_obj: *Int = @ptrCast(args[0]);
    const a = a_obj.as(isize) catch return null;

    // Or use the method statically and do it in one step
    const b = Int.as(@ptrCast(args[1]), isize) catch return null;

    // Add them and create a new Int object
    return @ptrCast(Int.fromNumber(a + b) catch return null);
}

fn modexec(mod: *py.Module) !c_int {
    const stdout = std.io.getStdOut().writer();
    const s = mod.str() catch return -1;
    defer s.decref();
    try stdout.print("modexec on {s}!\n", .{s.asString()});

    // Add a str
    const test_str = try Str.fromSlice("test!");
    defer test_str.decref();
    try mod.addObjectRef("TEST_STR", @ptrCast(test_str));

    return 0;
}

pub export fn py_mod_exec(mod: *py.Module) c_int {
    return modexec(mod) catch |err| switch (err) {
        // py.zig uses error.PyError for any error caught from the python c-api
        error.PyError => -1, // Python error
        // Any other errors need to set an error in python
        else => py.systemError("module init failed", .{}) catch -1,
    };
}

var module_methods = [_]py.MethodDef{
    .{ .ml_name = "add", .ml_meth = @constCast(@ptrCast(&add)), .ml_flags = py.c.METH_FASTCALL, .ml_doc = "Add two numbers" },
    .{}, // sentinel
};

var module_slots = [_]py.SlotDef{
    .{ .slot = py.c.Py_mod_exec, .value = @constCast(@ptrCast(&py_mod_exec)) },
    .{}, // sentinel
};

var moduledef = py.ModuleDef.new(.{
    .m_name = "pyzigtest",
    .m_doc = "pyzigtest module",
    .m_methods = &module_methods,
    .m_slots = &module_slots,
});

pub export fn PyInit_pyzigtest(_: *anyopaque) [*c]Object {
    return moduledef.init();
}
