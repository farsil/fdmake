# `fdmake`

`fdmake` is a DOS utility that creates floppy disk images that can be mounted
with DOSBox. It is written in assembly language and should work with any
x86 processor, even the ancient 8086.

# Build

`fdmake` requires Borland Turbo Assembler to be built. The build process was
tested against version 5.0, but may work with lower versions as no version 5.0
specific directives were used.

Assuming the `BIN` folder of Turbo Assembler is in your `PATH` environment
variable, run these two commands at the DOS command line prompt:
```bat
> tasm fdmake.asm
> tlink fdmake.obj /t
```
The `/t` switch instructs the linker to create a `.COM` executable.

# Usage

If you run `fdmake` without arguments you get a detailed help screen:
```
Creates a floppy disk image.

FDMAKE filename [/T type] [/L label] [/U] [/F]

  filename  Image file to create.
  /T        Type of image: 360k, 720k, 1.2m, 1.44m (default), 2.88m.
  /L        Volume label (max 11 characters), ignored if /U is set.
  /U        Writes an unformatted image.
  /F        Overwrites the existing image file if it exists.
```

# `imgmake`

This small utility implements a subset of the functionalities provided by
the `imgmake` tool, which also allows creation of hard disk images. It is
present in `DOSBox-X` as a builtin, or is available as a standalone port at
the following repository:

https://github.com/farsil/imgmake
