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
                'pyzigtest.zig'
            ],
            extra_compile_args=["-DOptimize=Debug"]
        )
    ],
    setup_requires=['setuptools-zig'],
)
