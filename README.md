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
            extra_compile_args=["-DOptimize=ReleaseSafe"]
        )
    ],
    setup_requires=['setuptools-zig'],
)
```



See the [example](example/) for a complete example.

## Why 

py.zig is designed but a much lighter alternative to something like [ziggy-pydust](https://github.com/spiraldb/ziggy-pydust).

