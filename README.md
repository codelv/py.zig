# Lightweight Python bindings for zig

py.zig provides a _lightweight_ interface for creating python extensions in zig. 

It is intended to be used with [setuptools-zig](https://pypi.org/project/setuptools-zig/) by
simply cloning or copying `py.zig` into your python project, adding an `Extension` entry 
in your `setup.py`, and then using `const py = @import("py.zig");`  in your extensions 
source to define the python module. 



```py
from setuptools import Extension, setup

setup(
    name='pyzigtest',
    version='0.1.0',
    python_requires='>=3.10',
    build_zig=True,
    ext_modules=[
        Extension(
            'pyzigtest',
            sources=[
                'src/pyzigtest.zig'
            ],
            extra_compile_args=["-ODebug"] # or -OReleaseFast, etc..
        )
    ],
    setup_requires=['setuptools-zig'],
)
```

See the [example](example/) for a complete example.

## Why 

py.zig is designed to be a much lighter alternative to something like [ziggy-pydust](https://github.com/spiraldb/ziggy-pydust).

## Design

For each builtin python type `py.zig` defines an equivalent `extern struct` that embeds a 
single field `impl` with the underlying python type. For examle a tuple is defined as:

```zig
// c-import Python.h
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");
    @cInclude("Python.h");
});

// ... 

pub const Tuple = extern struct {
    // The underlying python structure
    impl: c.PyTupleObject,

    // Import the object protocol
    pub usingnamespace ObjectProtocol(@This());

    // Import the SequenceProtocol
    pub usingnamespace SequenceProtocol(@This());
        
    // Some more tuple methods here...
};
```

Since these types have the same memory representation as the c-equivalent you can safetly use `@ptrCast`
and pass them to any functions (C/C++, or whatever) that take a tuple object. 

You can also access any members of the python type using `impl`, directly. For example the `Type` 
can get the name like this:

```zig
pub const Type = extern struct {
    // The underlying python structure
    impl: c.PyTypeObject,
    
    // ... 
    
    // Return the name of this type
    pub inline fn className(self: *Type) [:0]const u8 {
        return std.mem.span(self.impl.tp_name);
    }
};
```

However it is generally recommended to use public C-API functions as is done with the wrappers in `py.zig`.


## Status

This is currently very alpha status and is undergoing breaking changes to functions but the 
basic design concept is unlikely to change.


## Plans

Auto generate bindings...
