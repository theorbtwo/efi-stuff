This is the beginning of a set of utilities to take images of EFI
ROM, split them apart, and extract their juicy and delicious innards.

To start, get an image of your ROM.  On non-laptop UNIX-like machines,
this is probably best accomplished with the "flashrom" command.  If
you are running linux, your distro probably has a package for it -- on
Debian, it's in the aptly-named "flashrom" package.  Otherwise,
[[http://www.flashrom.org/Downloads#Binary_packages]] does list
Windows and DOS versions, which I haven't tried.  In any case, you
will want something along the lines of ```sudo flashrom --programmer
internal --read your.rom``` to read your rom out to your.rom.  If you
try this on not-linux, let me know how you get on, please.

You may or may not be able to use an update file for a rom, rather
then dumping out a rom from a living system.  This is, again,
something that I'd welcome feedback on.

Right.  Now that we've got the rom image to slice up, you should be
able to run ```perl slice-dump.pl your.rom >slice.log 2>&1```.  This
will create a slice.log file with a bunch of fairly low-level
information about how your ROM is structured, and creates a whole slew
of directories in the same directory as your.rom.  You will end up
with, mostly, Name.type/part, where each directory is a "file" within
a efi firmware volume, and each file in that directory is an efi
"section".  We'll discuss the different sorts of section next.

```.pe32``` sections are the executables of the efi world.  In fact,
they use the same PE format as windows .exe files -- you can rename
them and use whatever exe-using tools you like, though they won't
actually just execute under windows -- that'd be way too easy.  (Note
that they are called .pe32 files, even if they are compiled for 64-bit
systems.  The file format is still called pe32.)

```.user_interface``` files give you a human-readable name for the
decidedly unreadable GUIDs that serve as filenames for EFI firmware
volume files.  If everything works properly, your files will already
have been named on disk for this human-readable name, where it exists.

```.raw``` files are things that we can't figure out a better name for.

```.dxe_depex```, ```.pei_depex```, and ```.smm_depex``` files give
information about what depends on what, and thus what order things
should be run in.  I don't yet have a tool for dumping them, sorry.
(The three variants depend on what phase of execution and sort of
thingy they are dependencies for.  More on that in a moment.)

Those are all the section types directly defined in the UEFI spec, or at least all the ones I've actually seen.  (There are several that I haven't.)

There's also, however, an extension mechanism for types that OEMs and
Independent BIOS Vendors want to add, called freeform subtype guids.

```.{97e409e6-4cc1-11d9-81f6-000000000000}``` files, at least on
systems with MSI BIOSes, store Internal Forms Representation info --
that is, they tell you what the system's config menus are structured.
You can run read-97-text.pl on these files to dump them.

On a EFI / PI system, there are several phases of boot (note that the
PI phases are optional from the point of view of EFI -- that is, a
system can do the EFI stages without necessarily doing the PI stages
first).  We'll get back to the middle part of the filenames in a
moment, since they mostly refer to stages of boot.

First, the system runs what is called the SEC, which is the first code
executed by the processor.  (PI spec, volume 1, chapter 13.) This is
pretty "dumb" code, in as much as it isn't designed to be modular or
pluggable, but rather to enable later stages to actually do useful
things.  (It's called the SEC for security -- one of the goals of the
SEC is to make sure all code that runs after it is authenticated.)
You should be able to find the SEC in what is technically called the
"Volume Top File" at the end of the ROM.  (PI spec, volume 2, section
3.2.2) It will end up in
```your.rom-{1ba0062e-c779-4582-8566-336ae8f78f09}.freeform.raw``` .
(Or possibly not ".freeform.", it's unclear to me if it has to be a
freeform file.)

Next up is the PEI phase -- Pre-EFI Initialization.  The goal here is
to set up RAM ... mostly, anyway?  First, the ```.pei_core.``` file is
run, and from there, the ``.peim.`` files (Pre-EFI Initialization
Modules).

...cutting a long story slightly shorter: after that, dxe_core,
smm_core, smm, combined_smm_dxe, driver, application.