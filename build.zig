const std = @import("std");

const CLib = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    inc_path: []const []const u8,
    c_files: []const []const u8,
    makefunc: ?*const fn (*CLib, *std.Build.Step.Compile) void = null,
    cflags: []const []const u8 = &[_][]const u8{},
    dependencies: []const *std.Build.Step.Compile = &[_]*std.Build.Step.Compile{},
    dynamic: bool = false,
    link_libc: bool = true,
    strip: bool = true,

    fn makeLibrary(options: *CLib) *std.Build.Step.Compile {
        const libdyn_option = std.fmt.allocPrint(options.b.allocator, "{s}_dynamic", .{options.name}) catch unreachable;
        defer options.b.allocator.free(libdyn_option);

        options.dynamic = options.b.option(bool, libdyn_option, "") orelse options.dynamic;

        const bin = if (options.dynamic)
            options.b.addSharedLibrary(.{
                .name = options.name,
                .target = options.target,
                .optimize = options.optimize,
                .strip = options.strip,
                .link_libc = options.link_libc,
            })
        else
            options.b.addStaticLibrary(.{
                .name = options.name,
                .target = options.target,
                .optimize = options.optimize,
                .strip = options.strip,
                .link_libc = options.link_libc,
            });

        for (options.dependencies) |dependency| {
            bin.linkLibrary(dependency);
        }

        for (options.inc_path) |path| {
            bin.addIncludePath(options.b.path(path));
        }

        for (options.c_files) |c_file| {
            bin.addCSourceFile(.{
                .file = options.b.path(c_file),
                .flags = options.cflags,
            });
        }

        options.callMakeFunc(bin);

        if (options.dynamic) {
            options.b.getInstallStep().dependOn(&options.b.addInstallArtifact(bin, .{
                .pdb_dir = .disabled,
                .h_dir = .disabled,
                .implib_dir = .disabled,
            }).step);
        }

        return bin;
    }

    fn callMakeFunc(self: *CLib, bin: *std.Build.Step.Compile) void {
        if (self.makefunc) |func| {
            func(self, bin);
        }
    }
};

fn nfde_cpp(options: *CLib, bin: *std.Build.Step.Compile) void {
    bin.defineCMacro("NFD_EXPORT", "1");

    switch (options.target.result.os.tag) {
        .windows => {
            bin.linkSystemLibrary("ole32");
            bin.linkSystemLibrary("uuid");
            bin.linkSystemLibrary("shell32");

            bin.linkLibCpp();
        },

        .linux => {
            bin.linkSystemLibrary("dbus-1");

            bin.linkLibCpp();
        },

        .macos => {
            bin.linkFramework("CoreServices");
            bin.linkFramework("CoreFoundation");
            bin.linkFramework("AppKit");
        },

        else => {},
    }
}

fn uiohook_func(options: *CLib, bin: *std.Build.Step.Compile) void {
    switch (options.target.result.os.tag) {
        .linux => {
            // This works on headers as well
            bin.linkSystemLibrary("X11");

            // This subdirectory is found at least on Fedora (40)
            bin.addSystemIncludePath(.{ .cwd_relative = "/usr/include/libevdev-1.0" });
            bin.linkSystemLibrary("evdev");

            bin.linkSystemLibrary("X11-xcb");
            bin.linkSystemLibrary("xkbcommon");
            bin.linkSystemLibrary("xkbcommon-x11");
        },

        else => {},
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    switch (target.result.os.tag) {
        .windows, .linux, .macos => {},

        else => {
            @panic("Unknown OS.");
        },
    }

    const optimize = b.standardOptimizeOption(.{});
    const strippdb = b.option(bool, "strippdb", "Strip debug symbols file for executable") orelse (optimize != .Debug);

    const liboptimize = b.option(std.builtin.OptimizeMode, "liboptimize", "Optimize libraries") orelse std.builtin.OptimizeMode.ReleaseFast;
    const libstrippdb = b.option(bool, "libstrippdb", "Strip debug symbols for libraries") orelse true;

    const exe = b.addExecutable(.{
        .name = "waveboard_zig",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strippdb,
        .link_libc = true,
    });

    if (target.result.os.tag == .windows) {
        exe.addWin32ResourceFile(.{
            .file = b.path("src/win32/waveboard_zig.rc"),
        });
    }

    const inc_path = "src/c_src/include/";
    exe.addIncludePath(b.path(inc_path));

    var shfof = CLib{
        .name = "shfopusfile",
        .b = b,
        .target = target,
        .optimize = liboptimize,
        .inc_path = &[_][]const u8{
            inc_path,
            "src/c_src/include/shf_libs/shfopusfile/libogg/include",
            "src/c_src/include/shf_libs/shfopusfile/libogg/src",
            "src/c_src/include/shf_libs/shfopusfile/libopusfile/include",
            "src/c_src/include/shf_libs/shfopusfile/libopusfile/src",
            "src/c_src/include/shf_libs/shfopusfile/libopus/include",
            "src/c_src/include/shf_libs/shfopusfile/libopus/src",
            "src/c_src/include/shf_libs/shfopusfile/libopus/celt",
            "src/c_src/include/shf_libs/shfopusfile/libopus/silk",
        },
        .c_files = &[_][]const u8{
            "src/c_src/include/shf_libs/shfopusfile/shfopusfile_win32.c",
        },
        .dynamic = false,
        .strip = libstrippdb,
    };

    const shfof_bin = shfof.makeLibrary();
    exe.linkLibrary(shfof_bin);

    var miniaudio = CLib{
        .name = "miniaudio",
        .b = b,
        .target = target,
        .optimize = liboptimize,
        .dependencies = &[_]*std.Build.Step.Compile{
            shfof_bin,
        },
        .inc_path = &[_][]const u8{
            inc_path,
        },
        .c_files = &[_][]const u8{
            "src/c_src/include/miniaudio/miniaudiostatic.c",
        },
        .dynamic = true,
        .strip = libstrippdb,
        .cflags = &.{
            "-fno-sanitize=undefined",
        },
    };

    const ma_bin = miniaudio.makeLibrary();
    exe.linkLibrary(ma_bin);

    const uiohook_src = if (target.result.os.tag == .windows)
        [_][]const u8{
            "src/c_src/include/libuiohook/windows/logger.c",
            "src/c_src/include/libuiohook/windows/input_helper.c",
            "src/c_src/include/libuiohook/windows/dispatch_event.c",
            "src/c_src/include/libuiohook/windows/input_hook.c",
            "src/c_src/include/libuiohook/windows/post_event.c",
            "src/c_src/include/libuiohook/windows/system_properties.c",
        }
    else if (target.result.os.tag == .macos)
        [_][]const u8{
            "src/c_src/include/libuiohook/darwin/logger.c",
            "src/c_src/include/libuiohook/darwin/input_helper.c",
            "src/c_src/include/libuiohook/darwin/dispatch_event.c",
            "src/c_src/include/libuiohook/darwin/input_hook.c",
            "src/c_src/include/libuiohook/darwin/post_event.c",
            "src/c_src/include/libuiohook/darwin/system_properties.c",
        }
    else
        [_][]const u8{
            "src/c_src/include/libuiohook/evdev/logger.c",
            "src/c_src/include/libuiohook/evdev/input_helper.c",
            "src/c_src/include/libuiohook/evdev/dispatch_event.c",
            "src/c_src/include/libuiohook/evdev/input_hook.c",
            "src/c_src/include/libuiohook/evdev/post_event.c",
            "src/c_src/include/libuiohook/evdev/system_properties.c",
        };

    var uiohook = CLib{
        .name = "uiohook",
        .b = b,
        .target = target,
        .optimize = liboptimize,
        .inc_path = &[_][]const u8{
            inc_path,
        },
        .c_files = &uiohook_src,
        .dynamic = true,
        .strip = libstrippdb,
        .makefunc = &uiohook_func,
    };

    const uiohook_bin = uiohook.makeLibrary();
    exe.linkLibrary(uiohook_bin);

    const nfd_src = if (target.result.os.tag == .windows)
        "src/c_src/include/nfd_extended/nfd_win.cpp"
    else if (target.result.os.tag == .macos)
        "src/c_src/include/nfd_extended/nfd_cocoa.m"
    else
        "src/c_src/include/nfd_extended/nfd_portal.cpp";

    var nfd = CLib{
        .name = "nfd_e",
        .b = b,
        .target = target,
        .optimize = liboptimize,
        .inc_path = &[_][]const u8{
            inc_path,
            "src/c_src/include/nfd_extended/include/",
        },
        .c_files = &[_][]const u8{
            nfd_src,
        },
        .dynamic = true,
        .makefunc = &nfde_cpp,
        .strip = libstrippdb,
    };

    const nfd_bin = nfd.makeLibrary();
    exe.linkLibrary(nfd_bin);

    b.installArtifact(exe);

    // Can't find the webui artifact using .artifact on dynamic lib

    const webui = b.dependency("zig-webui", .{
        .target = target,
        .optimize = liboptimize,
        .enable_tls = false,
        .is_static = false,
    }).module("webui");

    b.getInstallStep().dependOn(&b.addInstallArtifact(webui.link_objects.items[0].other_step, .{
        .pdb_dir = .disabled,
        .h_dir = .disabled,
        .implib_dir = .disabled,
    }).step);

    exe.root_module.addImport("webui", webui);

    const regex = b.dependency("regex", .{
        .target = target,
        .optimize = liboptimize,
    });

    exe.root_module.addImport("regex", regex.module("regex"));
    //exe.root_module.addImport("win32", b.dependency("zigwin32", .{}).module("zigwin32"));
}
