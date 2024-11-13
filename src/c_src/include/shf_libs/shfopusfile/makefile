CC = gcc
BINARY = shfopusfile
DEBUGBINARY = debugbuild
BINARYOUTPUT = ${BINARY}
DEBUGBINARYOUTPUT = ${DEBUGBINARY}
OSSUFFIX = _unknownos.c
LIBOGGDIR = libogg
LIBOPUSDIR = libopus
LIBOPUSFILEDIR = libopusfile
CFLAGS = -std=c99 -Wall -Wextra -pedantic-errors -shared
DEFINES =

ifeq ($(OS), Windows)
	BINARYOUTPUT = ${BINARY}.dll
	DEBUGBINARYOUTPUT = ${DEBUGBINARY}.dll
	OSSUFFIX = _win32.c
	CFLAGS += -Wl,--subsystem,windows,--out-implib="${BINARYOUTPUT}.a",--export-all-symbols,--enable-auto-import
	LIBS +=
endif

SOURCE = ${BINARY}${OSSUFFIX}

win32:
	$(CC) -I"$(LIBOGGDIR)/src" -I"$(LIBOGGDIR)/include" -I"$(LIBOPUSDIR)/src" -I"$(LIBOPUSDIR)/celt" -I"$(LIBOPUSDIR)/silk" -I"$(LIBOPUSDIR)/include" -I"$(LIBOPUSFILEDIR)/src" -I"$(LIBOPUSFILEDIR)/include" "$(SOURCE)" -o "$(BINARYOUTPUT)" $(DEFINES) -O0 $(CFLAGS) $(LIBS)

win32release:
	$(CC) -I"$(LIBOGGDIR)/src" -I"$(LIBOGGDIR)/include" -I"$(LIBOPUSDIR)/src" -I"$(LIBOPUSDIR)/celt" -I"$(LIBOPUSDIR)/silk" -I"$(LIBOPUSDIR)/include" -I"$(LIBOPUSFILEDIR)/src" -I"$(LIBOPUSFILEDIR)/include" "$(SOURCE)" -o "$(BINARYOUTPUT)" $(DEFINES) -O3 $(CFLAGS) $(LIBS)

win32debug:
	$(CC) -I"$(LIBOGGDIR)/src" -I"$(LIBOGGDIR)/include" -I"$(LIBOPUSDIR)/src" -I"$(LIBOPUSDIR)/celt" -I"$(LIBOPUSDIR)/silk" -I"$(LIBOPUSDIR)/include" -I"$(LIBOPUSFILEDIR)/src" -I"$(LIBOPUSFILEDIR)/include" "$(SOURCE)" -o "$(DEBUGBINARYOUTPUT)" $(DEFINES) -g $(CFLAGS) $(LIBS)
