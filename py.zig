pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");
    @cInclude("Python.h");
});
const std = @import("std");


const VER_312 = 0x030C0000;
const VER_313 = 0x030D0000;

pub const VersionOp = enum { gt, gte, lt, lte, eq, ne };

// Return true if the compile version is over the given value
pub inline fn versionCheck(comptime op: VersionOp, comptime version: c_int) bool {
    const py_ver = c.PY_VERSION_HEX;
    return switch (op) {
        .gt => py_ver > version,
        .gte => py_ver >= version,
        .lt => py_ver < version,
        .lte => py_ver <= version,
        .eq => py_ver == version,
        .ne => py_ver != version,
    };
}

pub inline fn initialize() void {
    c.Py_Initialize();
}

pub inline fn finalize() !void {
    c.Py_Finalize();
}

// The python error set. If this error type is returned
// The callee must set the python error or python will raise a SystemError.
pub const Error = error{PyError};

// Test whether the error indicator is set. If set, return the exception type (the first
// argument to the last call to one of the PyErr_Set* functions or to PyErr_Restore()).
// If not set, return NULL. You do not own a reference to the return value, so you do not
// need to Py_DECREF() it.
// The caller must hold the GIL.
pub inline fn errorOccurred() ?*Object {
    return @ptrCast(c.PyErr_Occurred());
}

// Clear the error indicator. If the error indicator is not set, there is no effect.
pub inline fn errorClear() void {
    c.PyErr_Clear();
}

// Print a standard traceback to sys.stderr and clear the error indicator.
// Unless the error is a SystemExit, in that case no traceback is printed and the
// Python process will exit with the error code specified by the SystemExit instance.
// Call this function only when the error indicator is set.
// Otherwise it will cause a fatal error!
pub inline fn errorPrint() void {
    if (errorOccurred()) {
        errorPrintUnchecked();
    }
}

// Same as errorPrint but does not check if an error ocurred
pub inline fn errorPrintUnchecked() void {
    c.PyErr_Print();
}

pub inline fn errorString(msg: [:0]const u8) void {
    c.PyErr_SetString(@ptrCast(msg));
}

pub inline fn errorFormat(exc: *Object, msg: [:0]const u8, args: anytype) ?*Object {
    if (args.len == 0) {
        c.PyErr_SetString(@ptrCast(exc), @ptrCast(msg));
        return null;
    }
    return @ptrCast(@call(.auto, c.PyErr_Format, .{
        @as([*c]c.PyObject, @ptrCast(exc)),
        msg
        } ++ args
    ));
}

// Helper that is the equivalent to `TypeError(msg)`
pub inline fn typeError(msg: [:0]const u8, args: anytype) ?*Object {
    return errorFormat(@ptrCast(c.PyExc_TypeError), msg, args);
}

// Helper that is the equivalent to `SystemError(msg)`
pub inline fn systemError(msg: [:0]const u8, args: anytype) ?*Object {
    return errorFormat(@ptrCast(c.PyExc_SystemError), msg, args);
}

// Helper that is the equivalent to `ValueError(msg)`
pub inline fn valueError(msg: [:0]const u8, args: anytype) ?*Object {
    return errorFormat(@ptrCast(c.PyExc_ValueError), msg, args);
}

pub inline fn attributeError(msg: [:0]const u8, args: anytype) ?*Object {
    return errorFormat(@ptrCast(c.PyExc_AttributeError), msg, args);
}

pub inline fn memoryError() ?*Object {
    return @ptrCast(c.PyErr_NoMemory());
}

// Clear a reference to **Object or *?*Object
// If pointer is to **Object it is set to undefined
pub inline fn clear(obj: anytype) void {
    const T = @TypeOf(obj);
    if (comptime canCastToOptionalObjectPtr(T)) {
        xsetref(@ptrCast(obj), null);
    } else if (comptime canCastToObjectPtr(T)) {
        setref(@ptrCast(obj), undefined);
    } else {
        @compileError(std.fmt.comptimePrint("py.clear argument must be castable to **Object or *?*Object, got: {s}", .{T}));
    }
}

// Clear all
pub inline fn clearAll(objs: anytype) void {
    inline for(objs) |obj| {
        clear(obj);
    }
}

pub inline fn None() *Object {
    return @ptrCast(&c._Py_NoneStruct);
}

pub inline fn True() *Object{
    return @ptrCast(&c._Py_TrueStruct);
}

pub inline fn False() *Object{
    return @ptrCast(&c._Py_FalseStruct);
}

pub inline fn NotImplemented() *Object{
    return @ptrCast(&c._Py_NotImplementedStruct);
}

// Replaces the macro Py_RETURN_NONE
pub inline fn returnNone() *Object {
    if (comptime versionCheck(.gte, VER_312)) {
        return None();
    }
    return None().newref();
}

pub inline fn returnBool(value: bool) *Object {
    return if (value) True() else False();
}

// Replaces the macro Py_RETURN_TRUE
pub inline fn returnTrue() *Object {
    if (comptime versionCheck(.gte, VER_312)) {
        return True();
    }
    return True().newref();
}

// Replaces the macro Py_RETURN_FALSE
pub inline fn returnFalse() *Object {
    if (comptime versionCheck(.gte, VER_312)) {
        return False();
    }
    return False().newref();
}

// Replaces the macro Py_NOT_IMPLEMENTED
pub inline fn returnNotImplemented() *Object {
    if (comptime versionCheck(.gte, VER_312)) {
        return NotImplemented();
    }
    return NotImplemented().newref();
}

// Re-export the visitproc
pub const visitproc = c.visitproc;

// Invoke the visitor func if the object is not null orelse return 0;
pub inline fn visit(obj: anytype, func: visitproc, arg: ?*anyopaque) c_int {
    const T = @TypeOf(obj);
    if (comptime canCastToOptionalObject(T)) {
        return if (obj) |p| func.?(@ptrCast(p), arg) else 0;
    } else if (comptime canCastToObject(T)) {
        return func.?(@ptrCast(obj), arg);
    } else {
        @compileError(std.fmt.comptimePrint("py.visit argument must be castable to *Object or ?*Object, got: {}", .{T}));
    }
}

// Invoke the visitor func on all non-null objects and return the first nonzero result if any.
pub inline fn visitAll(objects: anytype, func: visitproc, arg: ?*anyopaque) c_int {
    inline for (objects) |obj| {
        const T = @TypeOf(obj);
        comptime if (!canCastToOptionalObject(T)) {
            @compileError(std.fmt.comptimePrint("py.visitAll arguments must be castable to ?*Object, got: {}", .{T}));
        };

        if (obj) |p| {
            const r = func.?(@ptrCast(p), arg);
            if (r != 0) return r;
        }
    }
    return 0;
}

// Safely release a strong reference to object dst and setting dst to src.
pub inline fn setref(dst: **Object, src: *Object) void {
    const tmp: *Object = dst.*;
    defer tmp.decref();
    dst.* = src;
}

pub inline fn xsetref(dst: *?*Object, src: ?*Object) void {
    const tmp = dst.*;
    defer if (tmp) |o| o.decref();
    dst.* = src;
}

pub inline fn parseTupleAndKeywords(args: *Tuple, kwargs: ?*Dict, format: [:0]const u8, keywords: [*c]const [*c]u8, results: anytype) !void {
    if (@call(.auto, c.PyArg_ParseTupleAndKeywords, .{
        @as([*c]c.PyObject, @ptrCast(args)),
        @as([*c]c.PyObject, @ptrCast(kwargs)),
        format,
        keywords,
    } ++ results) == 0) {
        return error.PyError;
    }
}

// Check that the given type can be safely casted to a *Object
pub inline fn canCastToObject(comptime T: type) bool {
    return switch(@typeInfo(T)) {
        .Pointer => |info| @hasDecl(info.child, "IS_PYOBJECT"),
        else => false,
    };
}


// Check that the given type can be safely casted to a ?*Object
pub inline fn canCastToOptionalObject(comptime T: type) bool {
    return switch(@typeInfo(T)) {
        .Optional => |info| canCastToObject(info.child),
        else => false,
    };
}

// Check that the given type can be safely casted to a **Object
pub inline fn canCastToObjectPtr(comptime T: type) bool {
    return switch(@typeInfo(T)) {
        .Pointer => |info| canCastToObject(info.child),
        else => false,
    };
}


// Check that the given type can be safely casted to a *?*Object
pub inline fn canCastToOptionalObjectPtr(comptime T: type) bool {
    return switch(@typeInfo(T)) {
        .Pointer => |info| canCastToOptionalObject(info.child),
        else => false,
    };
}

// Object Protocol
pub inline fn ObjectProtocol(comptime T: type) type {
    return struct {
        // Flag py.zig uses to check when casting anytypes
        pub const IS_PYOBJECT = true;

        pub inline fn incref(self: *T) void {
            c.Py_IncRef(@ptrCast(self));
        }

        pub inline fn decref(self: *T) void {
            c.Py_DecRef(@ptrCast(self));
        }

        // Create a new strong reference to an object: call Py_INCREF()
        // on o and return the object o.
        pub inline fn newref(self: *T) *T {
            return @ptrCast(c.Py_NewRef(@ptrCast(self)));
        }

        // Returns a new reference to the type
        pub inline fn typenewref(self: *T) [*c]Type {
            return @ptrCast(c.PyObject_Type(@ptrCast(self)));
        }

        // Returns a borrwed reference to the type
        pub inline fn typeref(self: *T) *Type {
            return @ptrCast(c.Py_TYPE(@ptrCast(self)));
        }

        pub inline fn hasAttr(self: *T, attr: *Str) bool {
            return c.PyObject_HasAttr(@ptrCast(self), @ptrCast(attr)) == 0;
        }

        pub inline fn hasAttrString(self: *Object, attr: [:0]const u8) bool {
            return c.PyObject_HasAttr(@ptrCast(self), @ptrCast(attr)) == 0;
        }

        pub inline fn hasAttrWithError(self: *Object, attr: *Str) !bool {
            const r = c.PyObject_HasAttrWithError(@ptrCast(self), @ptrCast(attr));
            if (r < 0) return error.PyError;
            return r == 1;
        }

        pub inline fn hasAttrStringWithError(self: *Object, attr: [:0]const u8) !bool {
            const r = c.PyObject_HasAttrWithError(@ptrCast(self), @ptrCast(attr));
            if (r < 0) return error.PyError;
            return r == 1;
        }

        pub inline fn getAttr(self: *T, attr: *Str) !*Object {
            const r = c.PyObject_GetAttr(@ptrCast(self), @ptrCast(attr));
            if (r == 0) return error.PyError;
            return r;
        }

        pub inline fn getAttrString(self: *T, attr: [:0]const u8) !*Object {
            const r = c.PyObject_GetAttrString(@ptrCast(self), @ptrCast(attr));
            if (r == 0) return error.PyError;
            return r;
        }

        pub inline fn getAttrOptional(self: *T, attr: *Str) !?*Object {
            var result: ?*Object = undefined;
            const r = c.PyObject_GetOptionalAttr(@ptrCast(self), @ptrCast(attr), @ptrCast(&result));
            if (r == -1) return error.PyError;
            return result;
        }

        // Set the value of the attribute named attr_name, for object o, to the value v.
        // This is the equivalent of the Python statement o.attr_name = v.
        // If v is NULL, the attribute is deleted. This behaviour is deprecated in favour of using
        // PyObject_DelAttr(), but there are currently no plans to remove it.
        pub inline fn setAttr(self: *T, attr: *Str, value: ?*Object) !void {
            if (c.PyObject_SetAttr(@ptrCast(self), @ptrCast(attr), @ptrCast(value)) < 0) {
                return error.PyError;
            }
        }

        // Same as setAttr but attr is a [:0]const u8.
        pub inline fn setAttrString(self: *T, attr: [:0]const u8, value: ?*Object) !void {
            if (c.PyObject_SetAttrString(@ptrCast(self), attr, @ptrCast(value)) < 0) {
                return error.PyError;
            }
        }

        // Delete attribute named attr_name, for object o.
        // This is the equivalent of the Python statement del o.attr_name.
        pub inline fn delAttr(self: *T, attr: *Str) !void {
            if (c.PyObject_DelAttr(@ptrCast(self), @ptrCast(attr)) < 0) {
                return error.PyError;
            }
        }

        // Same as detAttr but attr is a [:0]const u8.
        pub inline fn delAttrString(self: *T, attr: [:0]const u8) !void {
            if (c.PyObject_DelAttrString(@ptrCast(self), attr) < 0) {
                return error.PyError;
            }
        }

        // Return the length of object o. If the object o provides either the sequence and mapping
        // protocols, the sequence length is returned. On error, -1 is returned. This is the equivalent
        // to the Python expression len(o).
        pub inline fn objectLength(self: *T) !usize {
            const s = c.PyObject_Length(@ptrCast(self));
            if (s < 0) {
                return error.PyError;
            }
            return @intCast(s);
        }

        // Same as length but no error checking
        pub inline fn objectSize(self: *T) isize {
            return c.PyObject_Size(@ptrCast(self));
        }

        // Compute and return the hash value of an object o.
        // This is the equivalent of the Python expression hash(o).
        pub inline fn hash(self: *T) !isize {
            const r = c.PyObject_Hash(@ptrCast(self));
            if (r == -1) {
                return error.PyError;
            }
            return r;
        }

        // This is equivalent to the Python expression iter(o).
        // It returns a new iterator for the object argument, or the object itself if the object is
        // already an iterator.  Raises TypeError and returns NULL if the object cannot be iterated.
        pub inline fn iter(self: *T) !*Object {
            if (c.PyObject_GetIter(@ptrCast(self))) |r| {
                return @ptrCast(r);
            }
            return error.PyError;
        }

        // Compute a string representation of object o. Null and type check the result is a Str.
        pub inline fn str(self: *T) !*Str {
            if (self.strUnchecked()) |s| {
                if (Str.check(s)) {
                    return @ptrCast(s);
                }
                // Set an error message
                _ = typeError("str did not return a str", .{});
            }
            return error.PyError;
        }

        // Calls PyObject_Str(self). Compute a string representation of object o.
        // Returns the string representation on success, NULL on failure.
        pub inline fn strUnchecked(self: *T) ?*Object {
            return @ptrCast(c.PyObject_Str(@ptrCast(self)));
        }

        // Compute a bytes representation of object o. NULL is returned on failure and a bytes object on
        // success. This is equivalent to the Python expression bytes(o), when o is not an integer.
        // Unlike bytes(o), a TypeError is raised when o is an integer instead of a zero-initialized bytes object.
        pub inline fn bytes(self: *T) ?*Object {
            return @ptrCast(c.PyObject_Bytes(@ptrCast(self)));
        }

        pub inline fn repr(self: *T) ?*Object {
            return @ptrCast(c.PyObject_Repr(@ptrCast(self)));
        }

        // Return non-zero if the object o is of type type or a subtype of type,
        // and 0 otherwise. Both parameters must be non-NULL.
        pub inline fn typeCheck(self: *T, tp: *Type) bool {
            return c.PyObject_TypeCheck(@ptrCast(self), @ptrCast(tp)) != 0;
        }

        // Shortcut to check that the given pointer for correctly typed
        // This is equivalent to `T.check(@ptrCast(self))`
        // If this returns false it means *T was incorrectly casted or the assumed type is wrong
        pub inline fn typeCheckSelf(self: *T) bool {
            return T.check(@ptrCast(self));
        }

        // Shortcut to check that the given pointer for correctly typed
        // This is equivalent to `T.checkExact(@ptrCast(self))`
        // If this returns false it means *T was incorrectly casted or the assumed type is wrong
        pub inline fn typeCheckExactSelf(self: *T) bool {
            return T.checkExact(@ptrCast(self));
        }

        // Return 1 if the class derived is identical to or derived from the class cls,
        // otherwise return 0. In case of an error, return -1.
        // If cls is a tuple, the check will be done against every entry in cls.
        // The result will be 1 when at least one of the checks returns 1, otherwise it will be 0.
        pub inline fn isSubclass(self: *T, cls: *Object) !bool {
            const r = self.isSubclassUnchecked(cls);
            if (r < 0) return error.PyError;
            return r != 0;
        }

        // Same as isSubclass but does not check for errors
        pub inline fn isSubclassUnchecked(self: *T, cls: *Object) c_int {
            return c.PyObject_IsSubclass(@ptrCast(self), @ptrCast(cls));
        }

        // Return 1 if inst is an instance of the class cls or a subclass of cls,
        // or 0 if not. On error, returns -1 and sets an exception.
        // If cls is a tuple, the check will be done against every entry in cls.
        // The result will be 1 when at least one of the checks returns 1, otherwise it
        // will be 0.
        pub inline fn isInstance(self: *T, cls: *Object) !bool {
            const r = self.isInstanceUnchecked(cls);
            if (r < 0) return error.PyError;
            return r != 0;
        }

        // Calls PyObject_IsInstance(self, cls). Same as isInstance but without error checking
        pub inline fn isInstanceUnchecked(self: *T, cls: *Object) c_int {
            return c.PyObject_IsInstance(@ptrCast(self), @ptrCast(cls));
        }

        pub inline fn is(self: *const T, other: anytype) bool {
            return self == @as(*const T, @ptrCast(other));
        }

        // Returns 1 if the object o is considered to be true, and 0 otherwise.
        // This is equivalent to the Python expression `not not o`.
        pub inline fn isTrue(self: *T) !bool {
            const r = self.isTrueUnchecked();
            if (r < 0) return error.PyError;
            return r != 0;
        }

        // Calls PyObject_IsTrue on self. Same as isTrue but without error checking
        // On failure, return -1.
        pub inline fn isTrueUnchecked(self: *T) c_int {
            return c.PyObject_IsTrue(@ptrCast(self));
        }

        // Returns 1 if the object o is considered to be true, and 0 otherwise.
        // This is equivalent to the Python expression not not o.
        pub inline fn isNot(self: *T) !bool {
            const r = self.isNotUnchecked();
            if (r < 0) return error.PyError;
            return r != 0;
        }

        // Calls PyObject_Not on self. Same as isNot but without error checking
        // On failure, return -1.
        pub inline fn isNotUnchecked(self: *T) c_int {
            return c.PyObject_Not(@ptrCast(self));
        }

        // Determine if the object o is callable. Return 1 if the object is callable and 0 otherwise. This function always succeeds.
        pub inline fn isCallable(self: *T) bool {
            return c.PyCallable_Check(@ptrCast(self)) == 1;
        }

        pub inline fn gcUntrack(self: *T) void {
            c.PyObject_GC_UnTrack(@ptrCast(self));
        }

        // Return a pointer to __dict__ of the object obj. If there is no __dict__,
        // return NULL without setting an exception.
        pub inline fn getDictPtr(self: *T) ?**Dict {
            return @ptrCast(c._PyObject_GetDictPtr(@ptrCast(self)));
        }

        // Add the mapping protocol
        pub usingnamespace MappingProtocol(T);

        // Add the call protocol
        pub usingnamespace CallProtocol(T);
    };
}

pub inline fn MappingProtocol(comptime T: type) type {
    return struct {
        // Return element of o corresponding to the object key or NULL on failure.
        // This is the equivalent of the Python expression o[key].
        // Returns a New reference.
        pub inline fn getItem(self: *T, key: *Object) !*Object {
            if (self.getItemUnchecked(key)) |item| {
                return @ptrCast(item);
            }
            return error.PyError;
        }

        // Calls PyObject_GetItem(self, key). Same as getItem with no error checking.
        // Returns a New reference.
        pub inline fn getItemUnchecked(self: *T, key: *Object) ?*Object {
            return @ptrCast(c.PyObject_GetItem(@ptrCast(self), @ptrCast(key)));
        }

        // Map the object key to the value v.
        // This is the equivalent of the Python statement o[key] = v.
        // This function does not steal a reference to v.
        pub inline fn setItem(self: *T, key: *Object, value: *Object) !void {
            if (self.setItemUnchecked(key, value) < 0) {
                return error.PyError;
            }
        }

        // Same as setItem without error checking
        pub inline fn setItemUnchecked(self: *T, key: *Object, value: *Object) c_int {
            return c.PyObject_SetItem(@ptrCast(self), @ptrCast(key), @ptrCast(value));
        }

        // Remove the mapping for the object key from the object o.
        // This is equivalent to the Python statement del o[key].
        pub inline fn delItem(self: *T, key: *Object) !void {
            if (self.delItemUnchecked(key) < 0) {
                return error.PyError;
            }
        }

        // Same as delItem without error checking
        pub inline fn delItemUnchecked(self: *T, key: *Object) c_int {
            return c.PyObject_DelItem(@ptrCast(self), @ptrCast(key));
        }
    };
}

pub inline fn CallProtocol(comptime T: type) type {
    return struct {
        // Call a callable Python object callable, with arguments given by the tuple args, and named arguments given by the dictionary kwargs.
        // args must not be NULL; use an empty tuple if no arguments are needed. If no named arguments are needed, kwargs can be NULL.
        // This is the equivalent of the Python expression: callable(*args, **kwargs).
        // Returns new reference
        pub inline fn call(self: *T, args: *Tuple, kwargs: ?*Dict) !*Object {
            if (self.callGenericUnchecked(args, kwargs)) |r| {
                return r;
            }
            return error.PyError;
        }

        // Calls PyObject_Call. Return the result of the call on success, or raise an exception and return NULL on failure.
        pub inline fn callUnchecked(self: *T, args: *Tuple, kwargs: ?*Dict) ?*Object {
            return @ptrCast(c.PyObject_Call(@ptrCast(self), @ptrCast(args), @ptrCast(kwargs)));
        }

        // Call a callable Python object callable with a zig tuple of arguments.
        // Selects at comptime which function to call based on the number of arguments
        // Eg PyObject_CallNoArgs, PyObject_CallOneArg, or PyObject_Vectorcall
        // Returns new reference
        pub inline fn callArgs(self: *T, args: anytype) !*Object {
            if (self.callArgsUnchecked(args)) |r| {
                return r;
            }
            return error.PyError;
        }

        // Calls PyObject_CallNoArgs. PyObject_CallOneArg, or
        // Return the result of the call on success, or raise an exception and return NULL on failure.
        pub inline fn callArgsUnchecked(self: *T, args: anytype) ?*Object {
            return @ptrCast(switch (args.len) {
                0 => c.PyObject_CallNoArgs(@ptrCast(self)),
                1 => c.PyObject_CallOneArg(@ptrCast(self), @ptrCast(args[0])),
                else => blk: {
                    var objs: [args.len][*c]c.PyObject = undefined;
                    inline for (args, 0..) |arg, i| {
                        objs[i] = @ptrCast(arg);
                    }
                    break :blk c.PyObject_Vectorcall(@ptrCast(self), @ptrCast(&objs), objs.len, null);
                },
            });
        }

        // Call a callable Python object callable, with arguments given by the tuple args.
        // If no arguments are needed, then args can be NULL.
        // This is the equivalent of the Python expression: callable(*args).
        // Returns new reference
        pub inline fn callObject(self: *T, args: ?*Object) !*Object {
            if (self.callObjectUnchecked(args)) |r| {
                return r;
            }
            return error.PyError;
        }

        // Calls PyObject_CallObject. Return the result of the call on success, or raise an exception and return NULL on failure.
        pub inline fn callObjectUnchecked(self: *T, args: ?*Object) ?*Object {
            return @ptrCast(c.PyObject_CallObject(@ptrCast(self), @ptrCast(args)));
        }

        // Call a method of the Python object obj, where the name of the method is given as a Python string object in name.
        // Selects at comptime which function to call based on the number of arguments
        // Eg PyObject_CallMethodNoArgs, PyObject_CallMethodOneArg, or PyObject_VectorcallMethod
        // Returns new reference
        pub inline fn callMethod(self: *T, name: *Str, args: anytype) !*Object {
            if (self.callMethodUnchecked(name, args)) |r| {
                return r;
            }
            return error.PyError;
        }

        // Same as callMethod with no error checking
        pub inline fn callMethodUnchecked(self: *T, name: *Str, args: anytype) ?*Object {
            return @ptrCast(switch (args.len) {
                0 => c.PyObject_CallMethodNoArgs(@ptrCast(self), @ptrCast(name)),
                1 => c.PyObject_CallMethodOneArg(@ptrCast(self), @ptrCast(name), @ptrCast(args[0])),
                else => blk: {
                    var objs: [args.len + 1][*c]c.PyObject = undefined;
                    objs[0] = @ptrCast(self);
                    inline for (args, 1..) |arg, i| {
                        objs[i] = @ptrCast(arg);
                    }
                    break :blk c.PyObject_VectorcallMethod(@ptrCast(name), @ptrCast(&objs), objs.len, null);
                },
            });
        }

        // Call a callable Python object callable. The arguments are the same as for vectorcallfunc.
        // If callable supports vectorcall, this directly calls the vectorcall function stored in callable.
        pub inline fn vectorCall(self: *T, args: anytype, kwnames: ?*Object) !*Object {
            if (self.vectorCallUnchecked(args, kwnames)) |r| {
                return r;
            }
            return error.PyError;
        }

        pub inline fn vectorCallUnchecked(self: *T, args: anytype, kwnames: ?*Object) ?*Object {
            return @ptrCast(c.PyObject_Vectorcall(@ptrCast(self), args, args.len, kwnames));
        }

        pub inline fn vectorCallMethod(self: *T, name: *Str, args: anytype, kwnames: ?*Object) !*Object {
            if (self.vectorCallMethodUnchecked(name, args, kwnames)) |r| {
                return r;
            }
            return error.PyError;
        }

        pub inline fn vectorCallMethodUnchecked(self: *T, name: *Str, args: anytype, kwnames: ?*Object) ?*Object {
            return @ptrCast(c.PyObject_Vectorcall(@ptrCast(name), .{self} + args, args.len + 1, kwnames));
        }
    };
}

pub const Object = extern struct {
    pub const BaseType = c.PyObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Perform a type check against T and if it passes cast the result to T.
    // If the check fails this returns error.PyCastError and but does. NOT set a python error.
    pub inline fn cast(self: *Object, comptime T: type) !*T {
        if (T.check(self)) {
            return @ptrCast(self);
        }
        return error.PyCastError; // Does not set a python error!
    }

    // Same as cast but calls T.checkExact
    pub inline fn castExact(self: *Object, comptime T: type) !*T {
        if (T.checkExact(self)) {
            return @ptrCast(self);
        }
        return error.PyCastError; // Does not set a python error!
    }
};


pub const TypeSlot = c.PyType_Slot;
pub const TypeSpec = c.PyType_Spec;

pub const Type = extern struct {
    pub const BaseType = c.PyTypeObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Create a new type.
    // This is equivalent to the Python expression:  type.__new__(self, name, bases, dict)
    // Returns new reference
    pub inline fn new(meta: *Type, name: *Str, bases: *Tuple, dict: *Dict) !*Object {
        const builtin_type: *Object = @ptrCast(&c.PyType_Type);
        const new_str = try Str.internFromString("__new__");
        return try builtin_type.callMethod(new_str, .{ meta, name, bases, dict });
    }

    // Generic handler for the tp_new slot of a type object.
    // Calls PyType_GenericNew.
    // Create a new instance using the type’s tp_alloc slot.
    // Returns a new reference
    pub inline fn genericNew(self: *Type, args: ?*Tuple, kwargs: ?*Dict) !*Object {
        if (self.genericNewUnchecked(args, kwargs)) |obj| {
            return obj;
        }
        return error.PyError;
    }

    // Calls PyType_GenericNew(self, args, kwargs). without error checking
    pub inline fn genericNewUnchecked(self: *Type, args: ?*Tuple, kwargs: ?*Dict) ?*Object {
        return @ptrCast(c.PyType_GenericNew(@ptrCast(self), @ptrCast(args), @ptrCast(kwargs)));
    }

    // Return true if the object o is a type object, including instances of types derived
    // from the standard type object. Return 0 in all other cases. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyType_Check(@ptrCast(obj)) != 0;
    }

    // Return non-zero if the object o is a type object, but not a subtype of the standard type object.
    // Return 0 in all other cases. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyType_CheckExact(@ptrCast(obj)) != 0;
    }

    // Create and return a heap type from the spec (see Py_TPFLAGS_HEAPTYPE).
    // The metaclass metaclass is used to construct the resulting type object. When metaclass is NULL, the metaclass is derived from bases (or Py_tp_base[s] slots if bases is NULL, see below).
    // Metaclasses that override tp_new are not supported, except if tp_new is NULL. (For backwards compatibility, other PyType_From* functions allow such metaclasses. They ignore tp_new, which may result in incomplete initialization. This is deprecated and in Python 3.14+ such metaclasses will not be supported.)
    // The bases argument can be used to specify base classes; it can either be only one class or a tuple of classes. If bases is NULL, the Py_tp_bases slot is used instead. If that also is NULL, the Py_tp_base slot is used instead. If that also is NULL, the new type derives from object.
    // The module argument can be used to record the module in which the new class is defined. It must be a module object or NULL. If not NULL, the module is associated with the new type and can later be retrieved with PyType_GetModule(). The associated module is not inherited by subclasses; it must be specified for each class individually.
    pub inline fn fromMetaclass(meta: ?*Type, module: ?*Module, spec: *TypeSpec, bases: ?*Object) !*Type {
        if (c.PyType_FromMetaclass(@ptrCast(meta), @ptrCast(module), @ptrCast(spec), @ptrCast(bases))) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    // New reference
    pub inline fn fromSpecWithBases(spec: *TypeSpec, base: *Object) !*Type {
        if (c.PyType_FromSpecWithBases(@ptrCast(spec), @ptrCast(base))) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    // New reference
    pub inline fn fromSpec(spec: *TypeSpec) !*Type {
        if (c.PyType_FromSpec(@ptrCast(spec))) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    pub fn free(self: *Type, obj: ?*Object) void {
        self.impl.tp_free.?(obj);
    }
};

pub const Metaclass = extern struct {
    pub const BaseType = c.PyHeapTypeObject;
    impl: BaseType,
    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());
};

pub const Bool = extern struct {
    pub const BaseType = c.PyLongObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    pub inline fn check(obj: *Object) bool {
        return c.PyBool_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }
    pub const checkExact = check;

    pub inline fn fromLong(value: c_long) ?*Bool {
        return @ptrCast(c.PyBool_FromLong(value));
    }

    pub inline fn fromBool(value: bool) ?*Bool {
        return fromLong(@intFromBool(value));
    }
};

pub const Int = extern struct {
    pub const BaseType = c.PyLongObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if its argument is a PyLongObject or a subtype of PyLongObject. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyLong_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if its argument is a PyLongObject, but not a subtype of PyLongObject. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyLong_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Convert to the given zig type
    pub inline fn as(self: *Int, comptime T: type) !T {
        comptime var error_value = -1;
        const n = @bitSizeOf(c_long);
        const r: T = switch (@typeInfo(T)) {
            .Int => |info| switch (info.bits) {
                0...n => @intCast(if (info.signedness == .signed)
                    c.PyLong_AsLong(@ptrCast(self))
                else blk: {
                    error_value = std.math.maxInt(c_ulong); // Update error value
                    break :blk c.PyLong_AsUnsignedLong(@ptrCast(self));
                }),
                else => @intCast(if (info.signedness == .signed)
                    c.PyLong_AsLongLong(@ptrCast(self))
                else blk: {
                    error_value = std.math.maxInt(c_ulonglong); // Update error value
                    break :blk c.PyLong_AsUnsignedLongLong(@ptrCast(self));
                }),
            },
            .Float => @floatCast(c.PyLong_AsDouble(@ptrCast(self))),
            else => @compileError("Cannot convert python in to " ++ @typeName(T)),
        };

        if (r == error_value and errorOccurred() != null) {
            return error.PyError;
        }
        return r;
    }

    // Create a pyton Int from any zig integer or float type. This will
    // Call the approprate python function based on the value type.
    pub inline fn new(value: anytype) !*Int {
        if (newUnchecked(value)) |r| {
            return r;
        }
        return error.PyError;
    }

    // Create an int from any zig integer type. This will
    // Call the approprate python function based on the value type.
    pub inline fn newUnchecked(value: anytype) ?*Int {
        const T = @TypeOf(value);
        switch (T) {
            isize => return @ptrCast(c.PyLong_FromSsize_t(value)),
            usize => return @ptrCast(c.PyLong_FromSize_t(value)),
            c_uint, c_ulong => return @ptrCast(c.PyLong_FromUnsignedLong(value)),
            c_int, c_long => return @ptrCast(c.PyLong_FromLong(value)),
            comptime_int,c_longlong => return @ptrCast(c.PyLong_FromLongLong(value)),
            c_ulonglong => return @ptrCast(c.PyLong_FromUnsignedLongLong(value)),
            else => {}, // Might be a float another zig int size
        }
        const n1 = @bitSizeOf(c_long);
        const n2 = @bitSizeOf(c_longlong);

        switch (@typeInfo(T)) {
            .Int => |info| if (n1 == n2) switch (info.bits) {
                0...n1 => return @ptrCast(if (info.signedness == .signed)
                    c.PyLong_FromLong(@intCast(value))
                else
                    c.PyLong_FromUnsignedLong(@intCast(value))),
                else => @compileError("Int bit width too large to convert to python int"),
            } else switch (info.bits) {
                0...n1 => return @ptrCast(if (info.signedness == .signed)
                    c.PyLong_FromLong(@intCast(value))
                else
                    c.PyLong_FromUnsignedLong(@intCast(value))),
                n1 + 1...n2 => return @ptrCast(if (info.signedness == .signed)
                    c.PyLong_FromLongLong(@intCast(value))
                else
                    c.PyLong_FromUnsignedLongLong(@intCast(value))),
                else => @compileError("Int bit width too large to convert to python int"),
            },
            .ComptimeFloat, .Float => return @ptrCast(c.PyLong_FromDouble(@floatCast(value))),
            else => {},
        }
        @compileError("Int.fromInt value must be an integer or float type");
    }

    // Alias
    pub const fromNumber = new;
    pub const fromNumberUnchecked = newUnchecked;

};

pub const Float = extern struct {
    pub const BaseType = c.PyFloatObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if its argument is a PyFloatObject or a subtype of PyFloatObject. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyFloat_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if its argument is a PyFloatObject, but not a subtype of PyFloatObject. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyFloat_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Get the value of the Float object as the given type with error checking.
    pub inline fn as(self: *Float, comptime T: type) !T {
        if (@typeInfo(T) != .Float) {
            @compileError("py.Float.as() type must a float");
        }
        const r = c.PyFloat_AsDouble(@ptrCast(self));
        if (r == -1 and errorOccurred() != null) {
            return error.PyError;
        }
        return @floatCast(r);
    }

    // Create a new PyFloatObject object from a floating point type.
    // Returns new reference.
    pub inline fn new(value: anytype) !*Float {
        if (newUnchecked(value)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Same as new but without error checking
    pub inline fn newUnchecked(value: anytype) ?*Float {
        return @ptrCast(c.PyFloat_FromDouble(@floatCast(value)));
    }

    // Same as new just using the python's naming.
    pub const fromDouble = new;
    pub const fromDoubleUnchecked = newUnchecked;

    // Create a PyFloatObject object based on the string value in str, or NULL on failure.
    pub inline fn fromString(value: [:0]const u8) !*Float {
        if (fromStringUnchecked(value)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn fromStringUnchecked(value: [:0]const u8) ?*Float {
        return @ptrCast(c.PyFloat_FromString(@ptrCast(value)));
    }
};

// TODO: Fix zig bug preventing this from importing...
const PyASCIIObject = extern struct {
    ob_base: c.PyObject = .{},
    length: c.Py_ssize_t = 0,
    hash: c.Py_hash_t = 0,
    state: u32 = 0, // TODO: Fix zig bug
};

const PyCompactUnicodeObject = extern struct {
    _base: PyASCIIObject = .{},
    utf8_length: c.Py_ssize_t = 0,
};

const PyUnicodeObject = extern struct {
    _base: PyCompactUnicodeObject,
    data: ?*anyopaque,
};

pub const Str = extern struct {
    pub const BaseType = PyUnicodeObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if the object obj is a Unicode object or an instance of a Unicode subtype.
    // This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyUnicode_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if the object obj is a Unicode object, but not an instance of a subtype.
    // This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyUnicode_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return the length of the Unicode string, in code points. unicode has to be a
    // Unicode object in the “canonical” representation (not checked).
    pub inline fn length(self: *Str) isize {
        return c.PyUnicode_GET_LENGTH(@ptrCast(self));
    }

    // Return 1 if the string is a valid identifier according to the language definition, section
    // Identifiers and keywords. Return 0 otherwise.
    pub inline fn isIdentifier(self: *Str) bool {
        return c.PyUnicode_IsIdentifier(@ptrCast(self)) == 1;
    }

    // Create a Unicode object from the char buffer str. The bytes will be interpreted as
    // being UTF-8 encoded. The buffer is copied into the new object.
    // The return value might be a shared object, i.e. modification of the
    // data is not allowed.
    pub inline fn fromSlice(str: []const u8) !*Str {
        if (c.PyUnicode_FromStringAndSize(str.ptr, @intCast(str.len))) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    pub inline fn fromString(str: [*c]const u8) !*Str {
        if (c.PyUnicode_FromString(str)) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    // A combination of PyUnicode_FromString() and PyUnicode_InternInPlace(),
    // meant for statically allocated strings.
    // Return a new (“owned”) reference to either a new Unicode string object
    // that has been interned, or an earlier interned string object with
    // the same value.
    pub inline fn internFromString(str: [:0]const u8) !*Str {
        if (c.PyUnicode_InternFromString(str)) |o| {
            return @ptrCast(o);
        }
        return error.PyError;
    }

    pub inline fn internInPlace(str: **Str) void {
        c.PyUnicode_InternInPlace(@ptrCast(str));
    }

    // Return data as utf8
    pub inline fn asString(self: *Str) [*c]const u8 {
        return c.PyUnicode_AsUTF8(@ptrCast(self));
    }

    // Alias to asString
    pub const data = asString;
};


pub const Bytes = extern struct {
    pub const BaseType = c.PyBytesObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if the object o is a bytes object or an instance of a subtype of the bytes type. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyBytes_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if the object o is a bytes object, but not an instance of a subtype of the bytes type. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyBytes_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // TODO: finish
};

pub const Tuple = extern struct {
    pub const BaseType = c.PyTupleObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    pub inline fn parse(self: *Tuple, format: [:0]const u8, args: anytype) !void {
        const r = @call(.auto, c.PyArg_ParseTuple, .{ @as([*c]c.PyObject, @ptrCast(self)), format } ++ args);
        if (r == 0) return error.PyError;
    }

    pub inline fn parseTyped(self: *Tuple, args: anytype) !void {
        const n = try self.size();
        if (n != args.len) {
            _ = typeError("Expected {} arguments got {}", .{args.len, n}); // TODO: Better message
            return error.PyError;
        }
        inline for(args, 0..) |arg, i| {
            const T = @TypeOf(arg);
            if (comptime !canCastToObjectPtr(T)) {
                @compileError(std.fmt.comptimePrint("parseTyped args must be *Object or subclasses: got {}",.{T}));
            }
            // Eg var arg: *Str: undefined
            // then &arg is **Str
            const ArgType = @typeInfo(@typeInfo(T).Pointer.child).Pointer.child;
            const obj = try self.get(i);
            if (!ArgType.check(obj)) {
                _ = typeError("Argument at {} must be {}", .{i, @typeName(ArgType)});
                return error.PyError;
            }
            arg.* = @ptrCast(obj);
        }
    }

    // Return true if p is a tuple object or an instance of a subtype of the tuple type.
    // This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyTuple_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if p is a tuple object, but not an instance of a subtype of the tuple type.
    // This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyTuple_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return a new tuple object of size len, or NULL with an exception set on failure.
    pub inline fn new(len: isize) !*Tuple {
        if (c.PyTuple_New(len)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Return a new tuple filled with the provided values from a zig tuple.
    // This steals a reference to every value.
    pub inline fn newFromArgs(args: anytype) !*Tuple {
        if (c.PyTuple_New(args.len)) |r| {
            inline for (args, 0..) |arg, i| {
                // FIXME: Zig thinks this writes out of bounds
                //c.PyTuple_SET_ITEM(@ptrCast(r), @intCast(i), @ptrCast(arg));
                _ = c.PyTuple_SetItem(@ptrCast(r), @intCast(i), @ptrCast(arg));
            }
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Get size with error checking
    pub inline fn size(self: *Tuple) !usize {
        const r = c.PyTuple_Size(@ptrCast(self));
        if (r < 0) return error.PyError;
        return @intCast(r);
    }

    pub inline fn sizeUnsafe(self: *Tuple) isize {
        return c.PyTuple_GET_SIZE(@ptrCast(self));
    }

    // Return the object at position pos in the tuple pointed to by p.
    // If pos is negative or out of bounds,
    // return NULL and set an IndexError exception.
    // Returns borrowed reference
    pub inline fn get(self: *Tuple, pos: usize) !*Object {
        if (c.PyTuple_GetItem(@ptrCast(self), @intCast(pos))) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn getUnsafe(self: *Tuple, pos: usize) ?*Object {
        // TODO: fix PyTuple_GET_ITEM
        return @ptrCast(c.PyTuple_GetItem(@ptrCast(self), pos));
    }

    // Insert a reference to object o at position pos of the tuple pointed to by p.
    // If pos is out of bounds, return -1 and set an IndexError exception.
    // This function “steals” a reference to o and discards a reference to an item already
    // in the tuple at the affected position.
    pub inline fn set(self: *Tuple, pos: usize, obj: *Object) !void {
        if (c.PyTuple_SetItem(@ptrCast(self), @intCast(pos), @ptrCast(obj)) < 0) {
            return error.PyError;
        }
    }

    // Same as set but no error checking. This function “steals” a reference to o, and,
    // unlike PyTuple_SetItem(), does not discard a reference to any item that is being replaced;
    // any reference in the tuple at position pos will be leaked.
    pub inline fn setUnsafe(self: *Tuple, pos: usize, obj: *Object) c_int {
        return c.PyTuple_SET_ITEM(@ptrCast(self), @intCast(pos), @ptrCast(obj));
    }

    // Return the slice of the tuple pointed to by p between low and high,
    // or NULL with an exception set on failure.
    // This is the equivalent of the Python expression p[low:high].
    // Indexing from the end of the tuple is not supported.
    // Returns new reference
    pub inline fn slice(self: *Tuple, low: usize, high: usize) !*Tuple {
        if (self.sliceUnchecked(low, high)) |r| {
            return r;
        }
        return error.PyError;
    }

    // Same as slice but no error checking
    pub inline fn sliceUnchecked(self: *Tuple, low: usize, high: usize) ?*Tuple {
        return @ptrCast(c.PyTuple_GetSlice(@ptrCast(self), @intCast(low), @intCast(high)));
    }

    // Create a copy of the tuple. Same as slice(0, size())
    // Returns new reference
    pub inline fn copy(self: *Tuple) !*Tuple {
        const end = try self.size();
        return try self.slice(0, end);
    }
};

pub const List = extern struct {
    pub const BaseType = c.PyListObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if p is a list object or an instance of a subtype of the list type. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyList_Check(@ptrCast(obj)) != 0;
    }

    // Return true if p is a list object, but not an instance of a subtype of the list type. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyList_Check(@ptrCast(obj)) != 0;
    }

    // Return a new empty dictionary, or NULL on failure.
    // Returns a new reference
    pub inline fn new(len: isize) !*List {
        if (c.PyList_New(len)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Same as length but no error checking
    pub inline fn size(self: *List) isize {
        return c.PyList_Size(@ptrCast(self));
    }

    // Get a borrowed reference to the list item.
    // The position must be non-negative; indexing from the end of the list
    // is not supported.  If index is out of bounds (<0 or >=len(list)),
    pub inline fn get(self: *List, index: isize) !*Object {
        if (self.getSafeUnchecked(index)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Get list item at index without error checking the result
    // Calls PyList_GetItem(self, index).
    pub inline fn getSafeUnchecked(self: *List, index: isize) ?*Object {
        return c.PyList_GetItem(@ptrCast(self), index);
    }

    // Get borrowed refernce to list item at index without type or bounds checking
    // Calls PyList_GET_ITEM(self, index).
    pub inline fn getUnsafe(self: *List, index: isize) ?*Object {
        return c.PyList_GET_ITEM(@ptrCast(self), index);
    }

    // Set the item at index index in list to item. Return 0 on success.
    // If index is out of bounds, return -1 and set an IndexError exception.
    // This function “steals” a reference to item and discards a reference
    // to an item already in the list at the affected position.
    pub inline fn set(self: *List, index: isize, item: *Object) !void {
        if (self.setSafeUnchecked(index, item)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Calls PyList_SetItem(self, index, item). Like set without checking the result for errors.
    pub inline fn setSafeUnchecked(self: *List, index: isize, item: *Object) c_int {
        return c.PyList_SetItem(@ptrCast(self), index, item);
    }

    // Macro form of PyList_SetItem() without error checking.
    // This is normally only used to fill in new lists where there is no previous
    // content. This macro “steals” a reference to item, and, unlike PyList_SetItem(),
    // does not discard a reference to any item that is being replaced;
    // any reference in list at position i will be leaked.
    pub inline fn setUnsafe(self: *List, index: isize, item: *Object) c_int {
        return c.PyList_SET_ITEM(@ptrCast(self), index, item);
    }

    // Insert the item item into list list in front of index index.
    // Analogous to list.insert(index, item).
    pub inline fn insert(self: *List, index: isize, item: *Object) !void {
        if (self.insertUnchecked(index, item) < 0) {
            return error.PyError;
        }
    }

    // Calls PyList_Insert(self, index, item). Same as insert without error checking.
    pub inline fn insertUnchecked(self: *List, index: isize, item: *Object) c_int {
        return c.PyList_Insert(@ptrCast(self), index, @ptrCast(item));
    }

    // Append the object item at the end of list list.
    // Analogous to list.append(item).
    pub inline fn append(self: *List, item: *Object) !void {
        if (self.appendUnchecked(item) < 0) {
            return error.PyError;
        }
    }

    // Calls PyList_Append(self, item). Same as append without error checking.
    pub inline fn appendUnchecked(self: *List, item: *Object) c_int {
        return c.PyList_Append(@ptrCast(self), @ptrCast(item));
    }

    // Return a list of the objects in list containing the objects between low and high.
    // Analogous to list[low:high]. Indexing from the end of the list is not supported.
    pub inline fn getSlice(self: *List, low: isize, high: isize) !*List {
        if (self.getSliceUnchecked(low, high)) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Same as getSlice without error checking. Return NULL and set an exception if unsuccessful.
    pub inline fn getSliceUnchecked(self: *List, low: isize, high: isize) ?*Object {
        return @ptrCast(c.PyList_GetSlice(@ptrCast(self), low, high));
    }

    // Set the slice of list between low and high to the contents of itemlist.
    // Analogous to list[low:high] = itemlist. The itemlist may be NULL,
    // indicating the assignment of an empty list (slice deletion).
    // Indexing from the end of the list is not supported.
    pub inline fn setSlice(self: *List, low: isize, high: isize, items: ?*Object) !void {
        if (self.setSliceUnchecked(low, high, items) < 0) {
            return error.PyError;
        }
    }

    // Calls PyList_SetSlice. Same as setSlice without error checking. Return 0 on success, -1 on failure.
    pub inline fn setSliceUnchecked(self: *List, low: isize, high: isize, items: ?*Object) c_int {
        return @ptrCast(c.PyList_SetSlice(@ptrCast(self), low, high, @ptrCast(items)));
    }

    // Extend list with the contents of iterable.
    // This is the same as PyList_SetSlice(list, PY_SSIZE_T_MAX, PY_SSIZE_T_MAX, iterable)
    // and analogous to list.extend(iterable) or list += iterable.
    pub inline fn extend(self: *List, iterable: *Object) !void {
        if (self.extendUnchecked(iterable) < 0) {
            return error.PyError;
        }
    }

    // Calls PyList_Extend. Same as extend without error checking.
    pub inline fn extendUnchecked(self: *List, iterable: *Object) c_int {
        if (comptime versionCheck(.gte, VER_313)) {
            return c.PyList_Extend(@ptrCast(self), @ptrCast(iterable));
        }
        return c.PyList_SetSlice(@ptrCast(self), c.PY_SSIZE_T_MAX, c.PY_SSIZE_T_MAX, @ptrCast(iterable));
    }

    // Remove all items from list. This is the same as PyList_SetSlice(list, 0, PY_SSIZE_T_MAX, NULL)
    // and analogous to list.clear() or del list[:].
    pub inline fn clear(self: *List) !void {
        if (self.clearUnchecked() < 0) {
            return error.PyError;
        }
    }

    // Same as clear() without error checking the result.
    pub inline fn clearUnchecked(self: *List) c_int {
        if (comptime versionCheck(.gte, VER_313)) {
            return c.PyList_Clear(@ptrCast(self));
        }
        return c.PyList_SetSlice(@ptrCast(self), 0, c.PY_SSIZE_T_MAX, null);
    }

    // Sort the items of list in place. This is equivalent to list.sort().
    pub inline fn sort(self: *List) !void {
        if (self.sortUnchecked() < 0) {
            return error.PyError;
        }
    }

    // Same as sort but no error checking. Return 0 on success, -1 on failure.
    pub inline fn sortUnchecked(self: *List) c_int {
        return c.PyList_Sort(@ptrCast(self));
    }

    // Reverse the items of list in place. This is the equivalent of list.reverse().
    pub inline fn reverse(self: *List) !void {
        if (self.reverseUnchecked() < 0) {
            return error.PyError;
        }
    }

    // Same as reverse but no error checking. Return 0 on success, -1 on failure.
    pub inline fn reverseUnchecked(self: *List) c_int {
        return c.PyList_Reverse(@ptrCast(self));
    }

    // Return a new tuple object containing the contents of list; equivalent to tuple(list).
    // Returns a new reference
    pub inline fn asTuple(self: *List) !*Tuple {
        if (self.asTupleUnchecked()) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn asTupleUnchecked(self: *List) ?*Object {
        return @ptrCast(c.PyList_AsTuple(@ptrCast(self)));
    }
};

pub const Dict = extern struct {
    pub const BaseType = c.PyDictObject;
    // Iteration item
    pub const Item = struct { key: *Object, value: *Object };

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if p is a dict object or an instance of a subtype of the dict type. This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyDict_Check(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return true if p is a dict object, but not an instance of a subtype of the dict type. This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyDict_CheckExact(@as([*c]c.PyObject, @ptrCast(obj))) != 0;
    }

    // Return a new empty dictionary, or NULL on failure.
    // Returns a new reference
    pub inline fn new() !*Dict {
        if (c.PyDict_New()) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Return a new dictionary that contains the same key-value pairs as p.
    // Returns a new reference
    pub inline fn copy(self: *Dict) !*Dict {
        if (c.PyDict_Copy(@ptrCast(self))) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Return a types.MappingProxyType object for a mapping which enforces read-only behavior.
    // This is normally used to create a view to prevent modification of the dictionary for non-dynamic
    // class types. Returns a new reference
    pub inline fn newProxy(mapping: *Object) !*Dict {
        if (c.PyDictProxy_New(@ptrCast(mapping))) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    // Return a borrowed reference to the object from dictionary p which has a key key.
    // Return NULL if the key key is missing without setting an exception.
    pub inline fn get(self: *Dict, key: *Object) ?*Object {
        return @ptrCast(c.PyDict_GetItem(@ptrCast(self), @ptrCast(key)));
    }

    pub inline fn getString(self: *Dict, key: [:0]const u8) ?*Object {
        return @ptrCast(c.PyDict_GetItemString(@ptrCast(self), @ptrCast(key)));
    }

    // Insert val into the dictionary p with a key of key. key must be hashable;
    // if it isn’t, TypeError will be raised.
    // This function does not steal a reference to val.
    pub inline fn set(self: *Dict, key: *Object, value: *Object) !void {
        if (c.PyDict_SetItem(@ptrCast(self), @ptrCast(key), @ptrCast(value)) < 0) {
            return error.PyError;
        }
    }

    // Same as set but uses a string as the key
    pub inline fn setString(self: *Dict, key: [:0]const u8, value: *Object) !void {
        if (c.PyDict_SetItemString(@ptrCast(self), key, @ptrCast(value)) < 0) {
            return error.PyError;
        }
    }

    // Remove the entry in dictionary p with key key. key must be hashable; if it isn’t,
    // TypeError is raised. If key is not in the dictionary, KeyError is raised.
    // Return 0 on success or -1 on failure.
    pub inline fn del(self: *Dict, key: *Object) !void {
        if (c.PyDict_DelItem(@ptrCast(self), @ptrCast(key))) {
            return error.PyError;
        }
    }

    pub inline fn delString(self: *Dict, key: [:0]const u8) !void {
        if (c.PyDict_DelItemString(@ptrCast(self), @ptrCast(key)) < 0) {
            return error.PyError;
        }
    }

    // Iterate over mapping object b adding key-value pairs to dictionary a. b may be a dictionary
    // If override is true, existing pairs in a will be replaced if a matching key is found in b,
    // otherwise pairs will only be added if there is not a matching key in a.
    // Return 0 on success or -1 if an exception was raised.
    pub inline fn merge(self: *Dict, other: *Object, override: bool) !void {
        if (self.mergeUnchecked(other, override) < 0) {
            return error.PyError;
        }
    }

    // Calls PyDict_Merge(self, other, override) without error checking
    pub inline fn mergeUnchecked(self: *Dict, other: *Object, override: bool) c_int {
        return @ptrCast(c.PyDict_Merge(@ptrCast(self), @ptrCast(other), @intFromBool(override)));
    }

    // This is the same as merge(a, b, 1) in C, and is similar to a.update(b) in Python
    // except that PyDict_Update() doesn’t fall back to the iterating over a sequence of key
    // value pairs if the second argument has no “keys” attribute. Return 0 on success or -1
    // if an exception was raised.
    pub inline fn update(self: *Dict, other: *Object) !void {
        if (self.updateUnchecked(other) < 0) {
            return error.PyError;
        }
    }
    pub inline fn updateUnchecked(self: *Dict, other: *Object) c_int {
        return @ptrCast(c.PyDict_Update(@ptrCast(self), @ptrCast(other)));
    }

    // Empty an existing dictionary of all key-value pairs.
    pub inline fn clear(self: *Dict) void {
        c.PyDict_Clear(@ptrCast(self));
    }

    // Determine if dictionary p contains key.
    // If an item in p is matches key, return true.
    // This is equivalent to the Python expression key in p.
    pub inline fn contains(self: *Dict, key: *Object) !bool {
        const r = self.containsUnchecked(key);
        if (r < 0) return error.PyError;
        return r == 1;
    }

    // Call PyDict_Contains() without error checking. On error, return -1.
    pub inline fn containsUnchecked(self: *Dict, key: *Object) c_int {
        return c.PyDict_Contains(@ptrCast(self), @ptrCast(key));
    }

    // Same as contains but key is a [:0]const u8 instead of *Object
    pub inline fn containsString(self: *Dict, key: [:0]const u8) !bool {
        const r = self.containsStringUnchecked(self, key);
        if (r < 0) return error.PyError;
        return r == 1;
    }

    // This is the same as PyDict_Contains(), but key is specified as a
    // const char* UTF-8 encoded bytes string, rather than a PyObject*.
    pub inline fn containsStringUnchecked(self: *Dict, key: [:0]const u8) c_int {
        return c.PyDict_ContainsString(@ptrCast(self), key);
    }

    // Same as length but no error checking
    pub inline fn size(self: *Dict) isize {
        return c.PyDict_Size(@ptrCast(self));
    }

    // Iterate over all key-value pairs in the dictionary p. The Py_ssize_t referred to by ppos must be initialized to 0
    // prior to the first call to this function to start the iteration;
    // the function returns true for each pair in the dictionary, and false
    // once all pairs have been reported.
    pub inline fn next(self: *Dict, pos: *isize) ?Item {
        var item: Item = undefined;
        if (c.PyDict_Next(@ptrCast(self), pos, @ptrCast(&item.key), @ptrCast(&item.value)) != 0) {
            return item;
        }
        return null;
    }

    // Return a List containing all the items from the dictionary.
    // Returns a new reference
    pub inline fn items(self: *Dict) !*List {
        if (self.itemsUnchecked()) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn itemsUnchecked(self: *Dict) ?*Object {
        return @ptrCast(c.PyDict_Items(@ptrCast(self)));
    }

    // Return a List containing all the keys from the dictionary.
    // Returns a new reference
    pub inline fn keys(self: *Dict) !*List {
        if (self.keysUnchecked()) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn keysUnchecked(self: *Dict) ?*Object {
        return @ptrCast(c.PyDict_Keys(@ptrCast(self)));
    }

    // Return a List containing all the values from the dictionary.
    // Returns a new reference
    pub inline fn values(self: *Dict) !*List {
        if (self.valuesUnchecked()) |r| {
            return @ptrCast(r);
        }
        return error.PyError;
    }

    pub inline fn valuesUnchecked(self: *Dict) ?*Object {
        return @ptrCast(c.PyDict_Values(@ptrCast(self)));
    }
};

pub const Set = extern struct {
    pub const BaseType = c.PySetObject;

    // The underlying python structure
    impl: BaseType,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());


    // TODO: finish
};

pub const Module = extern struct {
    // https://docs.python.org/3/c-api/module.html
    // The underlying python structure
    impl: c.PyTypeObject,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Return true if p is a module object, or a subtype of a module object.
    // This function always succeeds.
    pub inline fn check(obj: *Object) bool {
        return c.PyModule_Check(@ptrCast(obj)) == 1;
    }

    // Return true if p is a module object, but not a subtype of PyModule_Type.
    // This function always succeeds.
    pub inline fn checkExact(obj: *Object) bool {
        return c.PyModule_CheckExact(@ptrCast(obj)) == 1;
    }

    // Add an object to module as name. This is a convenience function which can be used
    // from the module’s initialization function.
    // This does not steal a reference to value.
    pub inline fn addObjectRef(self: *Module, name: [:0]const u8, value: *Object) !void {
        const r = c.PyModule_AddObjectRef(@ptrCast(self), name, @ptrCast(value));
        if (r < 0) return error.PyError;
    }

    // Like addObjectRef but steals a reference to value
    pub inline fn addObject(self: *Module, name: [:0]const u8, value: *Object) !void {
        const f = if (comptime versionCheck(.gte, VER_313)) c.PyModule_Add else c.PyModule_AddObject;
        const r = f(@ptrCast(self), name, @ptrCast(value));
        if (r < 0) return error.PyError;
    }

    pub inline fn create(def: *ModuleDef) ?*Module {
        const mod = @as([*c]c.PyModuleDef, @ptrCast(def));
        return @ptrCast(c.PyModule_Create(mod));
    }
};

// Returns a new reference.
// const builtins = try py.importModule("builtins");
// defer builtins.decref();
pub inline fn importModule(name: [:0]const u8) !*Module {
    if (c.PyImport_ImportModule(@ptrCast(name))) |mod| {
        return @ptrCast(mod);
    }
    return error.PyError;
}

pub const MethodDef = c.PyMethodDef;
pub const GetSetDef = c.PyGetSetDef;
pub const SlotDef = c.PyModuleDef_Slot;

pub const ModuleDef = extern struct {
    const BaseType = c.PyModuleDef;
    const Self = @This();
    impl: BaseType,
    pub inline fn new(v: BaseType) Self {
        return Self{ .impl = v };
    }

    pub inline fn init(self: *Self) ?*Object {
        return @ptrCast(c.PyModuleDef_Init(@ptrCast(self)));
    }
};

// Zig allocator using python functions
const Allocator = struct {
    const Self = @This();
    const Alignment = u8;
    intepreter: ?*c.PyObject = null,

    pub fn alloc(self: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = self;
        _ = alignment;
        _ = ret_addr;
        return @ptrCast(c.PyMem_Malloc(len));
    }

    pub fn resize(self: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        _ = self;
        _ = alignment;
        _ = ret_addr;
        return c.PyMem_Realloc(mem.ptr, new_len) != null;
    }

    pub fn remap(self: *anyopaque, mem: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = self;
        _ = alignment;
        _ = ret_addr;
        return @ptrCast(c.PyMem_Realloc(mem.ptr, new_len));
    }

    pub fn free(self: *anyopaque, mem: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = self;
        _ = alignment;
        _ = ret_addr;
        c.PyMem_Free(mem.ptr);
    }

    // Create an allocator that can be used with zig types but uses PyMem calls
    pub inline fn allocator(self: *Self) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = @ptrCast(self),
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                // .remap = remap,
                .free = free,
            },
        };
    }
};
// TODO: per interpreter?
var global_allocator = Allocator{};

pub const allocator = global_allocator.allocator();

test "interpreter init" {
    initialize();
    defer finalize();
}
