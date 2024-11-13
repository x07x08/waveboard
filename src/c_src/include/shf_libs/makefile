SHFOPUSFILEDIR = shfopusfile/

export OS

ifeq ($(OS), Windows_NT)
	OS = Windows
else
	OS = $(shell uname)
endif

shfopusfile_win32:
	$(MAKE) -C "$(SHFOPUSFILEDIR)" win32

shfopusfile_win32release:
	$(MAKE) -C "$(SHFOPUSFILEDIR)" win32release

shfopusfile_win32debug:
	$(MAKE) -C "$(SHFOPUSFILEDIR)" win32debug
