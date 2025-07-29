const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const webui = @import("webui");
const asy = @import("z_src/zig_async/async.zig");
const rgx = @import("regex");

// https://git.sr.ht/~delitako/nyoomcat/tree/main/item/src/main.zig#L44,379

const win = if (native_os == .windows) struct {
    extern "c" fn signal(sig: c_int, func: *const fn (c_int, c_int) callconv(.winapi) void) callconv(.c) *anyopaque;
} else {};

const c = @cImport({
    @cInclude("miniaudio/miniaudiostatic.h");
    @cInclude("uiohook.h");
    @cInclude("nfd_extended/include/nfd.h");
    @cInclude("time.h");
    @cInclude("stdio.h");
});

const TrackMark = enum(i64) {
    Deletion = -1,
};

const CommandSave = struct {
    allowedOnly: bool = false,
};

const LogCommand = struct {
    name: []const u8,
    description: []const u8,
    func: *const fn (string: []const u8) void,
    defaultAllowedOnly: bool,
    save: CommandSave,

    fn isDefault(self: *LogCommand) bool {
        if (self.save.allowedOnly == self.defaultAllowedOnly) return true;

        return false;
    }

    fn needsSave(self: *LogCommand) void {
        _ = Ctx.settings.savedCommands.map.swapRemove(self.name);

        if (self.isDefault()) return;

        Ctx.settings.savedCommands.map.put(
            Ctx.allocator,
            self.name,
            &self.save,
        ) catch unreachable;
    }

    fn call(self: *LogCommand, arg: []const u8) void {
        self.func(arg);
    }
};

const Constants = struct {
    const channelCount = 2;
    const settingsFileName = "waveboard.settings.json";
    const deleteKey = c.VC_BACKSPACE;
    var filtersList = c.nfdfilteritem_t{
        .name = "Text",
        .spec = "log,txt",
    };
    var allowedExt = &.{ "mp3", "wav", "ogg", "flac" };
    var decodingBackendVtableLibopus: c.ma_decoding_backend_vtable = .{
        .onInit = c.ma_decoding_backend_init__libopus,
        .onInitFile = c.ma_decoding_backend_init_file__libopus,
        .onInitFileW = null,
        .onInitMemory = null,
        .onUninit = c.ma_decoding_backend_uninit__libopus,
    };
    const commands = struct {
        pub var play = LogCommand{
            .name = "play",
            .description = "Adds a track to the queue",
            .func = WatchTabInterface.playCommand,
            .defaultAllowedOnly = false,
            .save = .{ .allowedOnly = false },
        };
        pub var fPlay = LogCommand{
            .name = "fplay",
            .description = "Plays a track",
            .func = WatchTabInterface.fPlayCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var oPlay = LogCommand{
            .name = "oplay",
            .description = "Plays an overlapped track",
            .func = WatchTabInterface.oPlayCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var volume = LogCommand{
            .name = "volume",
            .description = "Adjusts the volume of the current tracks",
            .func = WatchTabInterface.volumeCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var gVolume = LogCommand{
            .name = "gvolume",
            .description = "Adjusts the global volume",
            .func = WatchTabInterface.gVolumeCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var samplerate = LogCommand{
            .name = "samplerate",
            .description = "Adjusts the sampling rate",
            .func = WatchTabInterface.samplerateCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var tts = LogCommand{
            .name = "tts",
            .description = "Plays Text to Speech",
            .func = WatchTabInterface.ttsCommand,
            .defaultAllowedOnly = false,
            .save = .{ .allowedOnly = false },
        };
        pub var video = LogCommand{
            .name = "video",
            .description = "Downloads and adds a video to the queue",
            .func = WatchTabInterface.videoCommand,
            .defaultAllowedOnly = false,
            .save = .{ .allowedOnly = false },
        };
        pub var fVideo = LogCommand{
            .name = "fvideo",
            .description = "Downloads and plays a video",
            .func = WatchTabInterface.fVideoCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var oVideo = LogCommand{
            .name = "ovideo",
            .description = "Downloads and overlaps the video",
            .func = WatchTabInterface.oVideoCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var skip = LogCommand{
            .name = "skip",
            .description = "Skips the current track",
            .func = WatchTabInterface.skipCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var skipAll = LogCommand{
            .name = "skipall",
            .description = "Stops all tracks",
            .func = WatchTabInterface.skipAllCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var block = LogCommand{
            .name = "block",
            .description = "Adds a user to the blacklist",
            .func = WatchTabInterface.blockCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var allow = LogCommand{
            .name = "allow",
            .description = "Adds a user to the whitelist",
            .func = WatchTabInterface.allowCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
        pub var remove = LogCommand{
            .name = "remove",
            .description = "Removes a user",
            .func = WatchTabInterface.removeCommand,
            .defaultAllowedOnly = true,
            .save = .{ .allowedOnly = true },
        };
    };
    const cmdsLen = @typeInfo(Constants.commands).@"struct".decls.len;
    var commandsList: [cmdsLen]*LogCommand = [_]*LogCommand{undefined} ** cmdsLen;
    const timestampRegex =
        \\\d{2}/\d{2}/\d{4} - \d{2}:\d{2}:\d{2}: 
    ;
    const separatorRegex =
        \\ :\s{1,2}\.
    ;
    const chatRegex =
        \\\(TEAM\) |\*DEAD\*\(TEAM\) |\(Spectator\) |\*DEAD\* |\*SPEC\* |\*COACH\* 
    ;
    const voicesCmd = "ListVoices";
    const voicesListEnd = "End of voices list";
    const setDeviceCmd = "SetDevice";
    const speakCmd = "SpeakText";
    const setRateCmd = "SetRate";
    const setVolumeCmd = "SetVolume";
    const newline = if (native_os == .windows) "\r\n" else "\n";
};

// https://github.com/dylagit/audio-limiter/blob/main/src/compressor.rs

const Compressor = struct {
    peakAtTime: f32 = 0.0,
    peakRTime: f32 = 0.0,
    peakAvg: f32 = 0.0,
    gainAtTime: f32 = 0.0,
    gainRTime: f32 = 0.0,
    gainAvg: f32 = 0.0,
    threshold: f32 = 0.0,

    fn update(self: *Compressor, sampleRate: u32, attackTime: f32, releaseTime: f32, threshold: f32) void {
        self.peakAtTime = Compressor.calctau(sampleRate, 0.01);
        self.peakRTime = Compressor.calctau(sampleRate, 10.0);
        self.peakAvg = 0;
        self.gainAtTime = Compressor.calctau(sampleRate, attackTime);
        self.gainRTime = Compressor.calctau(sampleRate, releaseTime);
        self.gainAvg = 1.0;
        self.threshold = threshold;
    }

    fn compress(self: *Compressor, input: f32) f32 {
        if (self.threshold == 0.0) return input;

        self.peakAvg = Compressor.attRAverage(self.peakAvg, self.peakAtTime, self.peakRTime, @abs(input));
        const gain = Compressor.limiter(self.peakAvg, self.threshold);
        self.gainAvg = Compressor.attRAverage(self.gainAvg, self.gainRTime, self.gainAtTime, gain);

        return input * self.gainAvg;
    }

    fn attRAverage(average: f32, attackTime: f32, releaseTime: f32, input: f32) f32 {
        const tau = if (input > average)
            attackTime
        else
            releaseTime;

        return ((1.0 - tau) * average + (tau * input));
    }

    fn limiter(input: f32, threshold: f32) f32 {
        const decibels = 20.0 * std.math.log10(@abs(input));
        const gain = @min(threshold - decibels, 0.0);
        return std.math.pow(f32, 10, 0.05 * gain);
    }

    fn calctau(sampleRate: u32, timeMs: f32) f32 {
        return 1.0 - std.math.exp(-2200.0 / (timeMs * @as(f32, @floatFromInt(sampleRate))));
    }
};

const Errors = error{
    NullFileName,
    FailedResourceManager,
    DownloadDirIsTopLevel,
    LogWatchIsOutput,
};

const TabInterface = struct {
    tabPtr: *anyopaque,
    initFunc: ?*const fn (self: *anyopaque) void = null,
    initUIFunc: ?*const fn (self: *anyopaque, *webui.Event) void = null,
    initSettingsFunc: ?*const fn (self: *anyopaque) void = null,
    deinitFunc: ?*const fn (self: *anyopaque) void = null,

    fn callInit(self: TabInterface) void {
        if (self.initFunc) |func| {
            func(self.tabPtr);
        }
    }

    fn callInitUI(self: TabInterface, event: *webui.Event) void {
        if (self.initUIFunc) |func| {
            func(self.tabPtr, event);
        }
    }

    fn callInitSettings(self: TabInterface) void {
        if (self.initSettingsFunc) |func| {
            func(self.tabPtr);
        }
    }

    fn callDeinit(self: TabInterface) void {
        if (self.deinitFunc) |func| {
            func(self.tabPtr);
        }
    }
};

const Ctx = struct {
    var gpa_config = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa_config.allocator();
    var window: webui = undefined;
    var mustExit = false;
    var mainThreadFuncs = std.ArrayList(*const fn () void).init(allocator);
    var mainThreadEvent: std.Thread.ResetEvent = .{};
    const tabs = struct {
        var logOut: LogTabInterface = .{};
        var audio: AudioTabInterface = .{};
        var downloader: DownloaderTabInterface = .{};
        var watch: WatchTabInterface = .{};
        var tts: TTSTabInterface = .{};
        var settings: SettingsTabInterface = .{};
    };
    const settings = &tabs.settings.values;
    const tabsList = &[_]TabInterface{
        .{
            .tabPtr = &tabs.settings,
            .initFunc = @ptrCast(&SettingsTabInterface.init),
            .initUIFunc = @ptrCast(&SettingsTabInterface.initUI),
            .deinitFunc = @ptrCast(&SettingsTabInterface.deinit),
        },
        .{
            .tabPtr = &tabs.downloader,
            .initFunc = @ptrCast(&DownloaderTabInterface.init),
            .initUIFunc = @ptrCast(&DownloaderTabInterface.initUI),
            .deinitFunc = @ptrCast(&DownloaderTabInterface.deinit),
        },
        .{
            .tabPtr = &tabs.audio,
            .initFunc = @ptrCast(&AudioTabInterface.init),
            .initUIFunc = @ptrCast(&AudioTabInterface.initUI),
            .initSettingsFunc = @ptrCast(&AudioTabInterface.initSettings),
            .deinitFunc = @ptrCast(&AudioTabInterface.deinit),
        },
        .{
            .tabPtr = &tabs.watch,
            .initFunc = @ptrCast(&WatchTabInterface.init),
            .initUIFunc = @ptrCast(&WatchTabInterface.initUI),
            .initSettingsFunc = @ptrCast(&WatchTabInterface.initSettings),
            .deinitFunc = @ptrCast(&WatchTabInterface.deinit),
        },
        .{
            .tabPtr = &tabs.tts,
            .initFunc = @ptrCast(&TTSTabInterface.init),
            .initUIFunc = @ptrCast(&TTSTabInterface.initUI),
            .initSettingsFunc = @ptrCast(&TTSTabInterface.initSettings),
            .deinitFunc = @ptrCast(&TTSTabInterface.deinit),
        },
        .{
            .tabPtr = &tabs.logOut,
            .initUIFunc = @ptrCast(&LogTabInterface.initUI),
            .initSettingsFunc = @ptrCast(&LogTabInterface.initSettings),
            .deinitFunc = @ptrCast(&LogTabInterface.deinit),
        },
    };

    fn handleSigIntWin(sig: c_int, _: c_int) callconv(.c) void {
        handleSigInt(sig);
    }

    fn handleSigInt(sig: i32) callconv(.c) void {
        switch (sig) {
            std.c.SIG.INT => {
                Ctx.mustExit = true;

                Ctx.mainThreadEvent.set();
            },
            else => unreachable,
        }
    }

    fn init() void {
        inline for (@typeInfo(Constants.commands).@"struct".decls, 0..) |decl, id| {
            Constants.commandsList[id] = &@field(Constants.commands, decl.name);
        }

        if (native_os == .windows) {
            _ = win.signal(std.c.SIG.INT, &handleSigIntWin);
        } else {
            const handler = std.posix.Sigaction{
                .handler = .{ .handler = &handleSigInt },
                .mask = std.posix.empty_sigset,
                .flags = 0,
            };
            std.posix.sigaction(std.c.SIG.INT, &handler, null);
        }

        window = webui.newWindow();
        _ = c.NFD_Init();

        tabs.logOut.init();

        for (tabsList) |tab| {
            tab.callInit();
            tab.callInitSettings();
        }

        webui.setConfig(.multi_client, settings.multiClient);
        webui.setConfig(.ui_event_blocking, false);

        window.setPort(settings.defaultPort) catch {
            @panic("Port already in use. Open the generated settings file to change it");
        };

        window.setPublic(settings.publicHost);

        _ = window.bind("initializeUI", initUI) catch unreachable;
        _ = window.startServer("web") catch unreachable;

        std.debug.print("Navigate to any of these URLs to open up the GUI :\n", .{});

        const addressesListLocal = std.net.getAddressList(
            allocator,
            "localhost",
            @intCast(settings.defaultPort),
        ) catch unreachable;
        defer addressesListLocal.deinit();

        for (addressesListLocal.addrs) |address| {
            if (address.in.sa.family != std.posix.AF.INET) {
                continue;
            }

            std.debug.print("http://{f}\n", .{address});
        }

        if (settings.publicHost) {
            const addressesList = std.net.getAddressList(
                allocator,
                "",
                @intCast(settings.defaultPort),
            ) catch unreachable;
            defer addressesList.deinit();

            for (addressesList.addrs) |address| {
                if (address.in.sa.family != std.posix.AF.INET) {
                    continue;
                }

                std.debug.print("http://{f}\n", .{address});
            }
        }

        tabs.logOut.logToEntry("Initialized web server", .{});

        asy.Spawn(initKbHook, .{}) catch unreachable;
    }

    fn initUI(event: *webui.Event) void {
        for (tabsList) |tab| {
            tab.callInitUI(event);
        }
    }

    fn start() void {
        while (true) {
            for (mainThreadFuncs.items) |func| {
                func();
            }

            mainThreadFuncs.clearAndFree();

            if (mustExit) break;

            mainThreadEvent.reset();
            mainThreadEvent.wait();
        }
    }

    fn deinit() void {
        // If this order is not kept, there will be problems for some reason
        // These functions should not be related to each other
        // It was a pain to debug without a debugger...

        mainThreadFuncs.deinit();

        c.NFD_Quit();

        for (tabsList) |tab| {
            tab.callDeinit();
        }

        webui.exit();
        webui.clean();

        _ = gpa_config.deinit();

        cleanKbHook();
    }

    fn kbHookCallback(event: [*c]c.uiohook_event, _: ?*anyopaque) callconv(.c) void {
        if ((event.*.type != c.EVENT_KEY_PRESSED) or
            (Ctx.tabs.audio.tracksList.items.len == 0) or
            Ctx.mustExit) return;

        var keyCode = event.*.data.keyboard.keycode;

        if (native_os == .windows) {
            // The 1.2 version of uiohook was less buggy
            // Only the arrow keys were swapped
            // libuiohook/windows/input_helper.c#296 on why this is needed

            switch (keyCode) {
                c.VC_UP | 0xEE00,
                c.VC_DOWN | 0xEE00,
                c.VC_RIGHT | 0xEE00,
                c.VC_LEFT | 0xEE00,
                c.VC_INSERT | 0xEE00,
                c.VC_DELETE | 0xEE00,
                c.VC_HOME | 0xEE00,
                c.VC_END | 0xEE00,
                c.VC_PAGE_UP | 0xEE00,
                c.VC_PAGE_DOWN | 0xEE00,
                => {
                    keyCode &= ~@as(u16, 0xEE00);
                },

                c.VC_UP => {
                    keyCode = c.VC_KP_UP;
                },

                c.VC_DOWN => {
                    keyCode = c.VC_KP_DOWN;
                },

                c.VC_LEFT => {
                    keyCode = c.VC_KP_LEFT;
                },

                c.VC_RIGHT => {
                    keyCode = c.VC_KP_RIGHT;
                },

                c.VC_ENTER | 0x0E00 => {
                    keyCode = c.VC_KP_ENTER;
                },

                else => {},
            }
        }

        if (tabs.audio.bindingRow == -1) {
            if (keyCode == Constants.deleteKey) return;

            if (tabs.audio.boundTracks.get(keyCode)) |boundTrack| {
                boundTrack.play(tabs.audio.selectedDevice, true);
            }

            return;
        }

        const track = tabs.audio.tracksList.items[@intCast(tabs.audio.bindingRow)];

        // Rare

        if (keyCode == c.VC_UNDEFINED) {
            tabs.logOut.logToEntry("This key is not recognized : {}", .{event.*.data.keyboard});

            jsCode("updateTrackBinding({d}, `{s}`)", .{ tabs.audio.bindingRow, keyToName(track.saveData.binding) });
            tabs.audio.bindingRow = -1;

            return;
        }

        if (keyCode == Constants.deleteKey) {
            if (track.saveData.binding == c.VC_UNDEFINED) {
                jsCode("updateTrackBinding({d}, `{s}`)", .{ tabs.audio.bindingRow, keyToName(c.VC_UNDEFINED) });
                tabs.audio.bindingRow = -1;

                return;
            }

            _ = tabs.audio.boundTracks.remove(track.saveData.binding);
            track.setBinding(c.VC_UNDEFINED);

            jsCode("updateTrackBinding({d}, `{s}`)", .{ tabs.audio.bindingRow, keyToName(c.VC_UNDEFINED) });
            tabs.audio.bindingRow = -1;

            tabs.settings.saveDebounced.call();

            return;
        }

        if (tabs.audio.boundTracks.fetchRemove(keyCode)) |boundTrack| {
            boundTrack.value.setBinding(c.VC_UNDEFINED);
            jsCode("updateTrackBinding({d}, `{s}`)", .{ boundTrack.value.id, keyToName(c.VC_UNDEFINED) });
        }

        _ = tabs.audio.boundTracks.remove(track.saveData.binding);
        tabs.audio.boundTracks.put(keyCode, track) catch unreachable;
        track.setBinding(keyCode);
        jsCode("updateTrackBinding({d}, `{s}`)", .{ tabs.audio.bindingRow, keyToName(keyCode) });

        tabs.settings.saveDebounced.call();

        tabs.audio.bindingRow = -1;
    }

    fn debugLogCallback(_: c_uint, _: ?*anyopaque, format: [*c]const u8, args: *anyopaque) callconv(.c) void {
        _ = c.vprintf(format, @alignCast(@ptrCast(args)));
    }

    fn initKbHook() void {
        tabs.logOut.logToEntry("Initialized settings and keyboard hook", .{});

        c.hook_set_dispatch_proc(&kbHookCallback, null);

        if (settings.debug) {
            c.hook_set_logger_proc(@ptrCast(&debugLogCallback), null);
        }

        _ = c.hook_run();
    }

    fn cleanKbHook() void {
        _ = c.hook_stop();
    }
};

const Settings = struct {
    logOutFile: ?[]const u8 = null,
    publicHost: bool = false,
    defaultPort: usize = 8080,
    debug: bool = false,
    multiClient: bool = true,
    darkMode: bool = true,
    animations: bool = true,
    audioDirectory: ?[]const u8 = null,
    globalVolume: f32 = 100.0,
    sampleRate: u32 = 44100,
    hiddenSampleRate: u32 = 48000,
    outputDevice: ?[]const u8 = null,
    videoSizeLimitMB: f64 = 20,
    downloadsFolder: ?[]const u8 = null,
    ytdlPath: ?[]const u8 = null,
    watchFile: ?[]const u8 = null,
    timestampedLog: bool = true,
    timestampRegex: ?[]const u8 = null,
    separatorRegex: ?[]const u8 = null,
    chatRegex: ?[]const u8 = null,
    queueLimit: usize = 10,
    ttsPath: ?[]const u8 = null,
    ttsFile: ?[]const u8 = null,
    ttsArgs: ?[]const u8 = null,
    ttsVoice: ?[]const u8 = null,
    ttsRate: i8 = 0,
    ttsVolume: i8 = 100,
    ttsTimeoutNs: u64 = 1 * std.time.ns_per_s,
    limiterThreshold: f32 = 0.0,
    attackTime: f32 = 25.0,
    releaseTime: f32 = 50.0,
    // Pointer to json.ArrayHashMap causes integer overflow when parsing. Zig bug?
    savedTracks: std.json.ArrayHashMap(*AudioTrackSave) = .{},
    savedCommands: std.json.ArrayHashMap(*CommandSave) = .{},
    usersList: std.json.ArrayHashMap(bool) = .{},

    fn defaultString(self: *Settings, comptime field: []const u8) void {
        if (std.mem.eql(u8, field, "timestampRegex")) {
            @field(self, field) = Ctx.allocator.dupe(
                u8,
                Constants.timestampRegex,
            ) catch unreachable;
        } else if (std.mem.eql(u8, field, "separatorRegex")) {
            @field(self, field) = Ctx.allocator.dupe(
                u8,
                Constants.separatorRegex,
            ) catch unreachable;
        } else if (std.mem.eql(u8, field, "chatRegex")) {
            @field(self, field) = Ctx.allocator.dupe(
                u8,
                Constants.chatRegex,
            ) catch unreachable;
        }
    }

    fn initDefault(self: *Settings) void {
        inline for (@typeInfo(Settings).@"struct".fields) |field| {
            if (@typeInfo(field.type) != .optional) {
                continue;
            }

            switch (field.type) {
                ?[]const u8 => {
                    self.defaultString(field.name);
                },
                else => {},
            }
        }
    }

    fn init(self: *Settings, parsed: std.json.Parsed(Settings)) void {
        self.* = parsed.value;

        inline for (@typeInfo(Settings).@"struct".fields) |field| {
            if (@typeInfo(field.type) != .optional) {
                continue;
            }

            @field(self, field.name) = null;

            if (@field(parsed.value, field.name)) |val| {
                switch (@TypeOf(val)) {
                    []const u8 => {
                        @field(self, field.name) = Ctx.allocator.dupe(u8, val) catch unreachable;
                    },
                    else => {},
                }
            } else {
                switch (field.type) {
                    ?[]const u8 => {
                        self.defaultString(field.name);
                    },
                    else => {},
                }
            }
        }

        self.savedTracks = .{};

        var trackIter = parsed.value.savedTracks.map.iterator();

        while (trackIter.next()) |entry| {
            const dupeData = Ctx.allocator.create(AudioTrackSave) catch unreachable;
            dupeData.* = entry.value_ptr.*.*;

            self.savedTracks.map.put(
                Ctx.allocator,
                Ctx.allocator.dupe(u8, entry.key_ptr.*) catch unreachable,
                dupeData,
            ) catch unreachable;
        }

        self.savedCommands = .{};

        for (Constants.commandsList) |cmd| {
            self.savedCommands.map.put(
                Ctx.allocator,
                cmd.name,
                &cmd.save,
            ) catch unreachable;
        }

        var cmdIter = parsed.value.savedCommands.map.iterator();

        while (cmdIter.next()) |entry| {
            if (self.savedCommands.map.get(entry.key_ptr.*)) |cmd| {
                cmd.allowedOnly = entry.value_ptr.*.allowedOnly;
            }
        }

        for (Constants.commandsList) |cmd| {
            cmd.needsSave();
        }

        self.usersList = .{};

        var usersIter = parsed.value.usersList.map.iterator();

        while (usersIter.next()) |entry| {
            self.usersList.map.put(
                Ctx.allocator,
                Ctx.allocator.dupe(u8, entry.key_ptr.*) catch unreachable,
                entry.value_ptr.*,
            ) catch unreachable;
        }
    }

    fn deinit(self: *Settings) void {
        inline for (@typeInfo(Settings).@"struct".fields) |field| {
            if (@typeInfo(field.type) != .optional) {
                continue;
            }

            if (@field(self, field.name)) |val| {
                switch (@TypeOf(val)) {
                    []const u8 => {
                        Ctx.allocator.free(val);

                        @field(self, field.name) = null;
                    },
                    else => {},
                }
            }
        }

        var saveIter = self.savedTracks.map.iterator();

        while (saveIter.next()) |entry| {
            Ctx.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }

        var usersIter = self.usersList.map.iterator();

        while (usersIter.next()) |entry| {
            Ctx.allocator.free(entry.key_ptr.*);
        }

        self.usersList.deinit(Ctx.allocator);
        self.savedTracks.deinit(Ctx.allocator);
        self.savedCommands.deinit(Ctx.allocator);
    }
};

const SettingsTabInterface = struct {
    values: Settings = .{},
    canSave: bool = true,
    cwd: std.fs.Dir = undefined,
    file: ?std.fs.File = null,
    saveDebounced: asy.Debouncer(500 * std.time.ns_per_ms, SettingsTabInterface.saveSettings) = .{},

    fn updateSettings(self: *SettingsTabInterface) !void {
        if (!self.canSave) {
            Ctx.tabs.logOut.logToEntry("Corrupt {s} file. Saving is disabled", .{Constants.settingsFileName});

            return;
        }

        if (self.file == null) {
            return;
        }

        self.file.?.close();
        self.file = null;

        self.file = try self.cwd.createFile(Constants.settingsFileName, .{
            .truncate = true,
        });

        const currentSettings = try std.json.Stringify.valueAlloc(Ctx.allocator, self.values, .{
            .whitespace = .indent_tab,
        });
        defer Ctx.allocator.free(currentSettings);

        _ = try self.file.?.write(currentSettings);
    }

    fn saveSettings() void {
        Ctx.tabs.settings.updateSettings() catch |err| Ctx.tabs.logOut.logToEntry("{}", .{err});
    }

    fn call_setAnimations(event: *webui.Event) void {
        Ctx.settings.animations = event.getBoolAt(0);

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setDarkMode(event: *webui.Event) void {
        Ctx.settings.darkMode = event.getBoolAt(0);

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn init(self: *SettingsTabInterface) void {
        _ = Ctx.window.bind("call_setAnimations", SettingsTabInterface.call_setAnimations) catch unreachable;
        _ = Ctx.window.bind("call_setDarkMode", SettingsTabInterface.call_setDarkMode) catch unreachable;

        self.cwd = std.fs.cwd();

        self.file = self.cwd.openFile(Constants.settingsFileName, .{
            .mode = .read_write,
        }) catch self.cwd.createFile(Constants.settingsFileName, .{
            .read = true,
        }) catch {
            self.file = null;

            return;
        };

        const fileStat = self.file.?.stat() catch unreachable;

        if (self.file.?.readToEndAlloc(Ctx.allocator, fileStat.size)) |settingsContents| {
            defer Ctx.allocator.free(settingsContents);

            if (std.json.parseFromSlice(Settings, Ctx.allocator, settingsContents, .{
                .ignore_unknown_fields = true,
            })) |parsed| {
                defer parsed.deinit();

                self.values.init(parsed);
            } else |_| {
                self.values.initDefault();

                if (fileStat.size != 0) {
                    Ctx.tabs.logOut.logToEntry("Corrupt {s} file. Saving is disabled", .{Constants.settingsFileName});

                    self.canSave = false;

                    return;
                }
            }
        } else |_| {
            self.values.initDefault();
        }

        SettingsTabInterface.saveSettings();
    }

    fn initUI(self: *SettingsTabInterface, _: *webui.Event) void {
        jsCode("setDarkMode({})", .{self.values.darkMode});
        jsCode("setAnimations({})", .{self.values.animations});
    }

    fn deinit(self: *SettingsTabInterface) void {
        if (self.file) |file| {
            file.close();

            self.file = null;
        }

        self.values.deinit();
    }
};

const LogTabInterface = struct {
    contents: []const u8 = undefined,
    file: ?std.fs.File = null,

    fn logToFile(self: *LogTabInterface, message: []const u8) void {
        if (self.file) |file| {
            file.seekFromEnd(0) catch unreachable;

            _ = file.write(message) catch unreachable;
        }
    }

    fn logToEntry(self: *LogTabInterface, comptime format: []const u8, args: anytype) void {
        const msTime = std.time.milliTimestamp();
        var sTime = @divTrunc(msTime, std.time.ms_per_s);
        const currTime = c.localtime(&sTime);

        const newMsg = std.fmt.allocPrintSentinel(
            Ctx.allocator,
            "{d:02}/{d:02}/{d:04} - {d:02}:{d:02}:{d:02}.{d:04}: " ++ format ++ "\n",
            .{
                @as(c_uint, @bitCast(currTime.*.tm_mday)),
                @as(c_uint, @bitCast(currTime.*.tm_mon + 1)),
                @as(c_uint, @bitCast(currTime.*.tm_year + 1900)),
                @as(c_uint, @bitCast(currTime.*.tm_hour)),
                @as(c_uint, @bitCast(currTime.*.tm_min)),
                @as(c_uint, @bitCast(currTime.*.tm_sec)),
                @as(u64, @bitCast(msTime - sTime * std.time.ms_per_s)),
            } ++ args,
            0,
        ) catch unreachable;
        defer Ctx.allocator.free(newMsg);

        const concatMsg = std.mem.concat(Ctx.allocator, u8, &.{ self.contents, newMsg }) catch unreachable;

        Ctx.allocator.free(self.contents);
        self.contents = concatMsg;

        self.logToFile(newMsg);
        jsCode("logout_entry.value += `{s}`", .{newMsg});
    }

    fn clearLogOutFile(self: *LogTabInterface) void {
        if (self.file) |file| {
            file.close();
            self.file = null;

            Ctx.allocator.free(Ctx.settings.logOutFile.?);
            Ctx.settings.logOutFile = null;
            jsCode("logout_filename.innerText = ``", .{});
        }
    }

    fn setLogOutFile(self: *LogTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return Errors.NullFileName;
        }

        self.clearLogOutFile();

        if (Ctx.settings.watchFile) |inLog| {
            if (std.mem.eql(u8, inLog, path.?)) {
                return Errors.LogWatchIsOutput;
            }
        }

        self.file = std.fs.openFileAbsolute(path.?, .{
            .mode = .read_write,
        }) catch |err| {
            if (Ctx.settings.logOutFile != null) {
                Ctx.allocator.free(Ctx.settings.logOutFile.?);
                Ctx.settings.logOutFile = null;
                jsCode("logout_filename.innerText = ``", .{});

                Ctx.tabs.settings.saveDebounced.call();
            }

            return err;
        };

        if (Ctx.settings.logOutFile == null) {
            Ctx.settings.logOutFile = std.fmt.allocPrint(Ctx.allocator, "{s}", .{path.?}) catch unreachable;
        }

        jsCode("logout_filename.innerText = `{s}`", .{path.?});

        self.logToFile(self.contents);
    }

    fn selectLogOutFile() void {
        var outPath: [*c]u8 = null;

        const res = c.NFD_OpenDialog(&outPath, @ptrCast(&Constants.filtersList), 1, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outPath);

        Ctx.tabs.logOut.setLogOutFile(std.mem.sliceTo(outPath, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_clearLogOutFile(_: *webui.Event) void {
        Ctx.tabs.logOut.clearLogOutFile();

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_selectLogOutFile(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(LogTabInterface.selectLogOutFile) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn init(self: *LogTabInterface) void {
        _ = Ctx.window.bind("call_selectLogOutFile", LogTabInterface.call_selectLogOutFile) catch unreachable;
        _ = Ctx.window.bind("call_clearLogOutFile", LogTabInterface.call_clearLogOutFile) catch unreachable;

        self.contents = Ctx.allocator.alloc(u8, 0) catch unreachable;

        self.logToEntry("Initialized log tab", .{});
    }

    fn initUI(self: *LogTabInterface, _: *webui.Event) void {
        if (Ctx.settings.logOutFile) |path| {
            jsCode("logout_filename.innerText = `{s}`", .{path});
        }

        jsCode("logout_entry.value = `{s}`", .{self.contents});
    }

    fn initSettings(self: *LogTabInterface) void {
        self.setLogOutFile(Ctx.settings.logOutFile) catch |err| {
            if (err != Errors.NullFileName) {
                self.logToEntry("{}", .{err});
            }
        };
    }

    fn deinit(self: *LogTabInterface) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        Ctx.allocator.free(self.contents);
    }
};

const AudioTrackSave = struct {
    volume: f32 = 100.0,
    solo: bool = true,
    binding: c_ushort = c.VC_UNDEFINED,

    fn isDefault(self: *AudioTrackSave) bool {
        inline for (@typeInfo(AudioTrackSave).@"struct".fields) |field| {
            const defVal: *const field.type = @alignCast(@ptrCast(field.default_value_ptr.?));

            if (defVal.* != @field(self, field.name)) {
                return false;
            }
        }

        return true;
    }

    fn deinit(self: *AudioTrackSave) void {
        Ctx.allocator.destroy(self);
    }
};

const ClosableEngine = struct {
    closed: bool = false,
    closing: bool = false,
    engine: *c.ma_engine,

    fn deinit(self: *ClosableEngine) void {
        c.ma_device_uninit(self.engine.*.pDevice);
        c.ma_engine_uninit(self.engine);

        Ctx.allocator.destroy(@as(*c.ma_device, @ptrCast(self.engine.*.pDevice)));
        Ctx.allocator.destroy(self.engine);

        Ctx.allocator.destroy(self);
    }
};

const AudioTrack = struct {
    id: i64,
    data: ?*c.ma_resource_manager_data_source = null,
    sounds: std.ArrayList(*c.ma_sound) = std.ArrayList(*c.ma_sound).init(Ctx.allocator),
    path: [:0]const u8,
    saveData: *AudioTrackSave,

    fn queue(self: *AudioTrack) void {
        if ((Ctx.tabs.audio.playingTracks.count() == 0) or
            (!self.saveData.solo))
        {
            self.play(Ctx.tabs.audio.selectedDevice, true);

            return;
        }

        if ((Ctx.settings.queueLimit != 0) and
            (Ctx.tabs.watch.queueList.items.len >= Ctx.settings.queueLimit))
        {
            return;
        }

        const dupeTrack = Ctx.allocator.create(AudioTrack) catch unreachable;
        const dupeSave = Ctx.allocator.create(AudioTrackSave) catch unreachable;
        dupeSave.* = self.saveData.*;
        dupeTrack.* = .{
            .path = Ctx.allocator.dupeZ(u8, self.path) catch unreachable,
            .id = -1,
            .saveData = dupeSave,
        };

        Ctx.tabs.watch.queueList.append(dupeTrack) catch unreachable;
        jsCode("addQueued(`{s}`)", .{dupeTrack.path});
    }

    fn play(self: *AudioTrack, device: i32, fSolo: bool) void {
        if (Ctx.tabs.audio.enginesList.items.len == 0) {
            Ctx.tabs.logOut.logToEntry("No audio devices found", .{});

            return;
        }

        const outDevice: usize = if (device == -1)
            @intCast(Ctx.tabs.audio.defaultDevice)
        else
            @intCast(device);

        if (Ctx.tabs.audio.enginesList.items[outDevice].closing == true) {
            return;
        }

        if (fSolo and self.saveData.solo) {
            for (Ctx.tabs.audio.enginesList.items) |engine| {
                engine.closed = true;
                engine.closing = true;
                _ = c.ma_engine_stop(engine.engine);
                engine.closing = false;
            }

            var tracksIter = Ctx.tabs.audio.playingTracks.iterator();

            while (tracksIter.next()) |entry| {
                entry.key_ptr.*.deinitSounds();
                entry.key_ptr.*.sounds.clearAndFree();

                if (entry.key_ptr.*.id == @intFromEnum(TrackMark.Deletion)) {
                    entry.key_ptr.*.deinit();
                }
            }

            Ctx.tabs.audio.playingTracks.clearAndFree();
        }

        const tempPath = if (native_os == .windows) std.unicode.utf8ToUtf16LeAllocZ(
            Ctx.allocator,
            self.path,
        ) catch unreachable else self.path;
        defer {
            if (native_os == .windows) {
                Ctx.allocator.free(tempPath);
            }
        }

        if (self.data == null) {
            self.data = Ctx.allocator.create(@TypeOf(self.data.?.*)) catch unreachable;

            if (native_os == .windows) {
                _ = c.ma_resource_manager_data_source_init_w(
                    Ctx.tabs.audio.resourceManager.?,
                    tempPath,
                    c.MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_ASYNC | c.MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_WAIT_INIT,
                    null,
                    self.data,
                );
            } else {
                _ = c.ma_resource_manager_data_source_init(
                    Ctx.tabs.audio.resourceManager.?,
                    tempPath,
                    c.MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_ASYNC | c.MA_RESOURCE_MANAGER_DATA_SOURCE_FLAG_WAIT_INIT,
                    null,
                    self.data,
                );
            }
        }

        const newSound = Ctx.allocator.create(c.ma_sound) catch unreachable;
        if (native_os == .windows) {
            _ = c.ma_sound_init_from_file_w(
                Ctx.tabs.audio.enginesList.items[outDevice].engine,
                tempPath,
                c.MA_SOUND_FLAG_ASYNC | c.MA_SOUND_FLAG_NO_SPATIALIZATION,
                null,
                null,
                newSound,
            );
        } else {
            _ = c.ma_sound_init_from_file(
                Ctx.tabs.audio.enginesList.items[outDevice].engine,
                tempPath,
                c.MA_SOUND_FLAG_ASYNC | c.MA_SOUND_FLAG_NO_SPATIALIZATION,
                null,
                null,
                newSound,
            );
        }
        //newSound.ownsDataSource = 0;

        _ = c.ma_sound_set_volume(newSound, self.saveData.volume / 100.0);

        self.sounds.append(newSound) catch unreachable;

        if (!Ctx.tabs.audio.playingTracks.contains(self)) {
            Ctx.tabs.audio.playingTracks.put(self, {}) catch unreachable;
        }

        Ctx.tabs.audio.enginesList.items[outDevice].closed = false;
        _ = c.ma_engine_start(Ctx.tabs.audio.enginesList.items[outDevice].engine);
        _ = c.ma_sound_start(newSound);
    }

    fn needsSave(self: *AudioTrack) void {
        if (Ctx.settings.savedTracks.map.fetchSwapRemove(self.path)) |entry| {
            Ctx.allocator.free(entry.key);
            entry.value.deinit();
        }

        if (self.saveData.isDefault()) return;

        const dupeData = Ctx.allocator.create(AudioTrackSave) catch unreachable;
        dupeData.* = self.saveData.*;

        Ctx.settings.savedTracks.map.put(
            Ctx.allocator,
            Ctx.allocator.dupe(u8, self.path) catch unreachable,
            dupeData,
        ) catch unreachable;
    }

    fn setVolume(self: *AudioTrack, newVolume: f32) void {
        self.saveData.volume = newVolume;

        for (self.sounds.items) |sound| {
            _ = c.ma_sound_set_volume(sound, self.saveData.volume / 100.0);
        }

        self.needsSave();
    }

    fn setSolo(self: *AudioTrack, val: bool) void {
        self.saveData.solo = val;

        self.needsSave();
    }

    fn setBinding(self: *AudioTrack, newBind: c_ushort) void {
        self.saveData.binding = newBind;

        self.needsSave();
    }

    fn deinitSound(_: *AudioTrack, sound: *c.ma_sound) void {
        c.ma_sound_uninit(sound);
        Ctx.allocator.destroy(sound);
    }

    fn deinitSounds(self: *AudioTrack) void {
        for (self.sounds.items) |sound| {
            self.deinitSound(sound);
        }
    }

    fn canDelete(self: *AudioTrack) bool {
        for (self.sounds.items) |sound| {
            if (c.ma_sound_is_playing(sound) == 1) {
                return false;
            }
        }

        return true;
    }

    fn deinit(self: *AudioTrack) void {
        Ctx.allocator.free(self.path);
        self.saveData.deinit();

        self.sounds.deinit();

        if (self.data != null) {
            _ = c.ma_resource_manager_data_source_uninit(self.data);
            Ctx.allocator.destroy(self.data.?);
        }

        Ctx.allocator.destroy(self);
    }
};

const AudioTabInterface = struct {
    tracksList: std.ArrayList(*AudioTrack) = std.ArrayList(*AudioTrack).init(Ctx.allocator),
    playingTracks: std.AutoHashMap(*AudioTrack, void) = std.AutoHashMap(*AudioTrack, void).init(Ctx.allocator),
    boundTracks: std.AutoHashMap(c_ushort, *AudioTrack) = std.AutoHashMap(c_ushort, *AudioTrack).init(Ctx.allocator),
    audioContext: c.ma_context = .{},
    devicesInfo: [*c]c.ma_device_info = null,
    resourceManager: ?*c.ma_resource_manager = null,
    selectedDevice: i32 = -1,
    defaultDevice: i32 = undefined,
    enginesList: std.ArrayList(*ClosableEngine) = std.ArrayList(*ClosableEngine).init(Ctx.allocator),
    bindingRow: i64 = -1,
    watchLoop: asy.Ticker(500 * std.time.ns_per_ms, AudioTabInterface.loopFunc) = .{},
    directory: ?std.fs.Dir = null,
    previousMTime: i128 = 0,
    limiter: Compressor = .{},
    shouldRefresh: bool = true,

    fn loopFunc() void {
        const self = &Ctx.tabs.audio;

        if ((self.directory == null) or (!self.shouldRefresh)) return;

        const stat = self.directory.?.stat() catch unreachable;

        if (stat.mtime == self.previousMTime) return;

        self.fillTracksList() catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };
    }

    fn findTrackByName(self: *AudioTabInterface, name: []const u8) ?usize {
        if (self.tracksList.items.len == 0) return null;

        for (self.tracksList.items, 0..) |track, index| {
            const trackBase = std.fs.path.basename(track.path);
            const extensionPos = std.mem.indexOf(u8, trackBase, std.fs.path.extension(trackBase));

            if (extensionPos == null) continue;

            const trackName = trackBase[0..extensionPos.?];

            if (!std.mem.eql(u8, trackName, name)) {
                continue;
            }

            return index;
        }

        return null;
    }

    fn clearTracksList(self: *AudioTabInterface) void {
        for (self.tracksList.items) |track| {
            if (!track.canDelete()) {
                track.id = @intFromEnum(TrackMark.Deletion);

                continue;
            }

            track.deinitSounds();
            track.deinit();
        }

        jsCode("clearTracks()", .{});

        self.tracksList.clearAndFree();
        self.boundTracks.clearAndFree();
    }

    fn walkDir(self: *AudioTabInterface, item: std.fs.Dir.Walker.Entry, dir: []const u8) void {
        const currID: i64 = @intCast(self.tracksList.items.len);
        var skip: bool = true;

        if (item.kind == .directory) {
            return;
        }

        skip = true;

        inline for (Constants.allowedExt) |ext| {
            if (std.mem.endsWith(u8, item.basename, ext)) {
                skip = false;

                break;
            }
        }

        if (skip) {
            return;
        }

        const trackPath = std.fs.path.joinZ(Ctx.allocator, &.{
            dir,
            item.path,
        }) catch unreachable;

        const newSave = Ctx.allocator.create(AudioTrackSave) catch unreachable;
        var tempSave: AudioTrackSave = .{};

        if (Ctx.settings.savedTracks.map.get(trackPath)) |savedVal| {
            tempSave = savedVal.*;
        }

        newSave.* = tempSave;

        const newTrack = Ctx.allocator.create(AudioTrack) catch unreachable;
        const tempTrack: AudioTrack = .{
            .id = currID,
            .path = trackPath,
            .saveData = newSave,
        };
        newTrack.* = tempTrack;

        self.tracksList.append(newTrack) catch unreachable;

        jsCode("addTrack({d}, `{s}`, {d}, {}, `{s}`)", .{
            newTrack.id,
            newTrack.path,
            newTrack.saveData.volume,
            newTrack.saveData.solo,
            keyToName(newTrack.saveData.binding),
        });

        if (newTrack.saveData.binding != c.VC_UNDEFINED) {
            self.boundTracks.put(newTrack.saveData.binding, newTrack) catch unreachable;
        }
    }

    fn fillTracksList(self: *AudioTabInterface) !void {
        self.clearTracksList();

        if (self.directory) |*dir| {
            dir.close();
        }

        self.directory = std.fs.openDirAbsolute(Ctx.settings.audioDirectory.?, .{
            .iterate = true,
        }) catch |err| {
            Ctx.allocator.free(Ctx.settings.audioDirectory.?);
            Ctx.settings.audioDirectory = null;
            jsCode("audiofolder_name.innerText = ``", .{});

            Ctx.tabs.settings.saveDebounced.call();

            return err;
        };

        const stat = self.directory.?.stat() catch unreachable;
        self.previousMTime = stat.mtime;

        var dirWalker = try self.directory.?.walk(Ctx.allocator);
        defer dirWalker.deinit();

        while (try dirWalker.next()) |item| {
            self.walkDir(item, Ctx.settings.audioDirectory.?);
        }

        if (Ctx.settings.downloadsFolder) |path| {
            if (std.mem.indexOf(u8, path, Ctx.settings.audioDirectory.?)) |_| {
                return;
            } else if (std.mem.indexOf(u8, Ctx.settings.audioDirectory.?, path)) |_| {
                return Errors.DownloadDirIsTopLevel;
            }

            var dlDir = std.fs.openDirAbsolute(path, .{
                .iterate = true,
            }) catch |err| {
                if (Ctx.settings.downloadsFolder != null) {
                    Ctx.allocator.free(Ctx.settings.downloadsFolder.?);
                    Ctx.settings.downloadsFolder = null;
                    jsCode("downloadsfolder_name.innerText = ``", .{});

                    Ctx.tabs.settings.saveDebounced.call();
                }

                return err;
            };
            defer dlDir.close();

            var dlWalker = try dlDir.walk(Ctx.allocator);
            defer dlWalker.deinit();

            while (try dlWalker.next()) |item| {
                self.walkDir(item, path);
            }
        }
    }

    fn setAudioDir(self: *AudioTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return;
        }

        // First time check for settings initialization
        if (self.directory != null) {
            Ctx.allocator.free(Ctx.settings.audioDirectory.?);

            Ctx.settings.audioDirectory = null;
        }

        if (Ctx.settings.audioDirectory == null) {
            Ctx.settings.audioDirectory = std.fmt.allocPrint(Ctx.allocator, "{s}", .{path.?}) catch unreachable;
        }

        jsCode("audiofolder_name.value = `{s}`", .{path.?});

        try self.fillTracksList();
    }

    fn selectAudioDir() void {
        var outDir: [*c]u8 = null;

        const res = c.NFD_PickFolder(&outDir, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outDir);

        Ctx.tabs.audio.setAudioDir(std.mem.sliceTo(outDir, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setDevice(event: *webui.Event) void {
        const newDevice = event.getIntAt(0);

        if ((newDevice == Ctx.tabs.audio.selectedDevice) or (newDevice == -1)) {
            return;
        }

        Ctx.tabs.audio.selectedDevice = @intCast(newDevice);

        const deviceName = std.mem.sliceTo(&Ctx.tabs.audio.devicesInfo[@intCast(newDevice)].name, 0);

        Ctx.tabs.logOut.logToEntry("Selected device : {s}", .{deviceName});

        if (Ctx.settings.outputDevice != null) {
            Ctx.allocator.free(Ctx.settings.outputDevice.?);
        }

        Ctx.settings.outputDevice = Ctx.allocator.dupe(u8, deviceName) catch unreachable;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setBinding(event: *webui.Event) void {
        if (Ctx.tabs.audio.tracksList.items.len != 0) {
            Ctx.tabs.audio.bindingRow = event.getIntAt(0);
        }
    }

    fn call_play(event: *webui.Event) void {
        if (Ctx.tabs.audio.tracksList.items.len != 0) {
            Ctx.tabs.audio.tracksList.items[@intCast(event.getIntAt(0))].play(
                @intCast(event.getIntAt(1)),
                event.getBoolAt(2),
            );
        } else {
            Ctx.tabs.logOut.logToEntry("No audio tracks found", .{});
        }
    }

    fn setSampleRate(self: *AudioTabInterface, newSampleRate: u32) void {
        const oldSampleRate = Ctx.settings.sampleRate;

        Ctx.tabs.audio.resourceManager.?.config.decodedSampleRate = newSampleRate;

        for (self.enginesList.items) |engine| {
            engine.closed = true;
            engine.closing = true;
            _ = c.ma_engine_stop(engine.engine);
            engine.closing = false;
        }

        var tracksIter = self.playingTracks.iterator();

        while (tracksIter.next()) |entry| {
            for (entry.key_ptr.*.sounds.items) |*sound| {
                const tempPath = if (native_os == .windows) std.unicode.utf8ToUtf16LeAllocZ(
                    Ctx.allocator,
                    entry.key_ptr.*.path,
                ) catch unreachable else entry.key_ptr.*.path;

                const newSound = Ctx.allocator.create(c.ma_sound) catch unreachable;
                if (native_os == .windows) {
                    _ = c.ma_sound_init_from_file_w(
                        sound.*.engineNode.pEngine,
                        tempPath,
                        c.MA_SOUND_FLAG_ASYNC | c.MA_SOUND_FLAG_NO_SPATIALIZATION,
                        null,
                        null,
                        newSound,
                    );
                } else {
                    _ = c.ma_sound_init_from_file(
                        sound.*.engineNode.pEngine,
                        tempPath,
                        c.MA_SOUND_FLAG_ASYNC | c.MA_SOUND_FLAG_NO_SPATIALIZATION,
                        null,
                        null,
                        newSound,
                    );
                }
                //newSound.ownsDataSource = 0;
                var pos: u64 = 0;

                _ = c.ma_sound_get_cursor_in_pcm_frames(sound.*, &pos);

                if (oldSampleRate > newSampleRate) {
                    _ = c.ma_sound_seek_to_pcm_frame(
                        newSound,
                        @intFromFloat(@as(f64, @floatFromInt(pos)) /
                            (@as(f64, @floatFromInt(oldSampleRate)) /
                                @as(f64, @floatFromInt(newSampleRate)))),
                    );
                } else {
                    _ = c.ma_sound_seek_to_pcm_frame(
                        newSound,
                        @intFromFloat(@as(f64, @floatFromInt(pos)) *
                            (@as(f64, @floatFromInt(newSampleRate)) /
                                @as(f64, @floatFromInt(oldSampleRate)))),
                    );
                }

                entry.key_ptr.*.deinitSound(sound.*);

                _ = c.ma_sound_set_volume(newSound, entry.key_ptr.*.saveData.volume / 100.0);
                sound.* = newSound;
                _ = c.ma_sound_start(sound.*);

                if (native_os == .windows) {
                    Ctx.allocator.free(tempPath);
                }
            }
        }

        for (self.enginesList.items) |engine| {
            engine.closed = false;
            _ = c.ma_engine_start(engine.engine);
        }

        Ctx.settings.sampleRate = newSampleRate;

        Ctx.tabs.audio.limiter.update(
            Ctx.settings.sampleRate,
            Ctx.settings.attackTime,
            Ctx.settings.releaseTime,
            Ctx.settings.limiterThreshold,
        );
    }

    fn call_setSampleRate(event: *webui.Event) void {
        const newSampleRate: u32 = @intCast(event.getIntAt(0));

        if ((Ctx.settings.sampleRate == newSampleRate) or (newSampleRate == 0)) return;

        Ctx.tabs.audio.setSampleRate(newSampleRate);

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setGlobalVolume(event: *webui.Event) void {
        Ctx.settings.globalVolume = @floatCast(event.getFloatAt(0));

        for (Ctx.tabs.audio.enginesList.items) |engine| {
            _ = c.ma_engine_set_volume(engine.engine, Ctx.settings.globalVolume / 100.0);
        }

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setSolo(event: *webui.Event) void {
        if (Ctx.tabs.audio.tracksList.items.len != 0) {
            Ctx.tabs.audio.tracksList.items[@intCast(event.getIntAt(0))].setSolo(event.getBoolAt(1));

            Ctx.tabs.settings.saveDebounced.call();
        }
    }

    fn call_setVolume(event: *webui.Event) void {
        if (Ctx.tabs.audio.tracksList.items.len != 0) {
            Ctx.tabs.audio.tracksList.items[@intCast(event.getIntAt(0))].setVolume(@floatCast(event.getFloatAt(1)));

            Ctx.tabs.settings.saveDebounced.call();
        }
    }

    fn call_setThreshold(event: *webui.Event) void {
        Ctx.settings.limiterThreshold = @floatCast(event.getFloatAt(0));

        Ctx.tabs.audio.limiter.update(
            Ctx.settings.sampleRate,
            Ctx.settings.attackTime,
            Ctx.settings.releaseTime,
            Ctx.settings.limiterThreshold,
        );

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setAttackTime(event: *webui.Event) void {
        Ctx.settings.attackTime = @floatCast(event.getFloatAt(0));

        Ctx.tabs.audio.limiter.update(
            Ctx.settings.sampleRate,
            Ctx.settings.attackTime,
            Ctx.settings.releaseTime,
            Ctx.settings.limiterThreshold,
        );

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setReleaseTime(event: *webui.Event) void {
        Ctx.settings.releaseTime = @floatCast(event.getFloatAt(0));

        Ctx.tabs.audio.limiter.update(
            Ctx.settings.sampleRate,
            Ctx.settings.attackTime,
            Ctx.settings.releaseTime,
            Ctx.settings.limiterThreshold,
        );

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_selectAudioDir(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(AudioTabInterface.selectAudioDir) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn closeEngine(engine: *ClosableEngine) void {
        if (engine.closing == false) {
            return;
        }

        _ = c.ma_engine_stop(engine.engine);
        engine.closing = false;

        if (Ctx.tabs.watch.queueList.items.len == 0) return;

        asy.Spawn(AudioTrack.play, .{
            Ctx.tabs.watch.queueList.orderedRemove(0),
            Ctx.tabs.audio.selectedDevice,
            true,
        }) catch unreachable;
        jsCode("removeQueued(queuedList[0])", .{});
    }

    fn PlaybackDeviceDataCallback(
        pDevice: [*c]c.ma_device,
        pOutput: ?*anyopaque,
        _: ?*const anyopaque,
        iFrameCount: c.ma_uint32,
    ) callconv(.c) void {
        var castEngine: *ClosableEngine = @alignCast(@ptrCast(pDevice.*.pUserData));

        if (castEngine.closed) {
            return;
        }

        var finished = if (Ctx.tabs.audio.playingTracks.count() == 0) true else false;
        var canDelete: bool = true;

        var tracksIter = Ctx.tabs.audio.playingTracks.iterator();

        while (tracksIter.next()) |entry| {
            for (entry.key_ptr.*.sounds.items, 0..) |sound, soundID| {
                if (c.ma_sound_at_end(sound) != 1) {
                    finished = false;
                    canDelete = false;

                    continue;
                }

                entry.key_ptr.*.deinitSound(sound);
                _ = entry.key_ptr.*.sounds.swapRemove(soundID);
            }

            if (!canDelete) {
                canDelete = true;

                continue;
            }

            if (Ctx.tabs.audio.playingTracks.fetchRemove(entry.key_ptr.*)) |track| {
                if (track.key.id == @intFromEnum(TrackMark.Deletion)) {
                    track.key.deinit();
                }
            }
        }

        if (!finished) {
            const tempOut = Ctx.allocator.alloc(f32, iFrameCount * Constants.channelCount) catch unreachable;
            const arrOut: [*c]f32 = @alignCast(@ptrCast(pOutput));

            _ = c.ma_engine_read_pcm_frames(castEngine.engine, @ptrCast(tempOut), iFrameCount, null);

            for (0..iFrameCount * Constants.channelCount) |index| {
                arrOut[index] = Ctx.tabs.audio.limiter.compress(tempOut[index]);
            }

            Ctx.allocator.free(tempOut);

            return;
        }

        // If closing is set in another thread, its value won't get updated here?
        // It doesn't make sense to me because a pointer is passed, not a value.
        castEngine.closed = true;
        castEngine.closing = true;
        asy.Spawn(AudioTabInterface.closeEngine, .{castEngine}) catch unreachable;
    }

    fn initializeDevices(self: *AudioTabInterface) void {
        var deviceConfig: c.ma_device_config = c.ma_device_config_init(c.ma_device_type_playback);
        deviceConfig.playback.format = c.ma_format_f32;
        deviceConfig.playback.channels = Constants.channelCount;
        deviceConfig.sampleRate = Ctx.settings.hiddenSampleRate;
        deviceConfig.dataCallback = &AudioTabInterface.PlaybackDeviceDataCallback;

        var engineConfig: c.ma_engine_config = c.ma_engine_config_init();
        engineConfig.sampleRate = Ctx.settings.hiddenSampleRate;
        engineConfig.channels = Constants.channelCount;
        engineConfig.pResourceManager = self.resourceManager;
        engineConfig.noAutoStart = 1;

        for (0..self.enginesList.capacity) |index| {
            const audioDevice = Ctx.allocator.create(c.ma_device) catch unreachable;

            if (self.devicesInfo[index].isDefault == 1) {
                self.defaultDevice = @intCast(index);
            }

            deviceConfig.playback.pDeviceID = &self.devicesInfo[index].id;

            if (c.ma_device_init(&self.audioContext, &deviceConfig, audioDevice) != c.MA_SUCCESS) {
                Ctx.allocator.destroy(audioDevice);

                continue;
            }

            const audioEngine = Ctx.allocator.create(ClosableEngine) catch unreachable;
            audioEngine.engine = Ctx.allocator.create(c.ma_engine) catch unreachable;

            engineConfig.pDevice = audioDevice;

            if (c.ma_engine_init(&engineConfig, audioEngine.engine) != c.MA_SUCCESS) {
                c.ma_device_uninit(audioDevice);
                Ctx.allocator.destroy(audioDevice);
                Ctx.allocator.destroy(audioEngine.engine);
                Ctx.allocator.destroy(audioEngine);

                continue;
            }

            _ = c.ma_engine_set_volume(audioEngine.engine, Ctx.settings.globalVolume / 100.0);
            audioDevice.pUserData = audioEngine;
            self.enginesList.append(audioEngine) catch unreachable;
        }
    }

    fn retrieveDevicesList(self: *AudioTabInterface) void {
        var devicesCount: u32 = 0;

        _ = c.ma_context_get_devices(&self.audioContext, &self.devicesInfo, &devicesCount, null, null);

        self.enginesList.ensureTotalCapacityPrecise(devicesCount) catch unreachable;
    }

    fn initResourceManager(self: *AudioTabInterface) !void {
        var managerConfig: c.ma_resource_manager_config = c.ma_resource_manager_config_init();
        managerConfig.decodedFormat = c.ma_format_f32;
        managerConfig.ppCustomDecodingBackendVTables = @constCast(@ptrCast(&&Constants.decodingBackendVtableLibopus));
        managerConfig.customDecodingBackendCount = 1;
        managerConfig.pCustomDecodingBackendUserData = null;
        managerConfig.decodedSampleRate = Ctx.settings.sampleRate;

        self.resourceManager = Ctx.allocator.create(c.ma_resource_manager) catch unreachable;

        errdefer {
            Ctx.allocator.destroy(self.resourceManager.?);

            self.resourceManager = null;
        }

        if (c.ma_resource_manager_init(&managerConfig, self.resourceManager) != c.MA_SUCCESS) {
            return Errors.FailedResourceManager;
        }
    }

    fn initAudio(self: *AudioTabInterface) void {
        if (c.ma_context_init(null, 0, null, &self.audioContext) != c.MA_SUCCESS) {
            Ctx.tabs.logOut.logToEntry("Failed to initialize audio context", .{});

            return;
        }

        self.initResourceManager() catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        self.retrieveDevicesList();

        self.initializeDevices();

        Ctx.tabs.logOut.logToEntry("Initialized {d} engines", .{self.enginesList.items.len});
    }

    fn init(self: *AudioTabInterface) void {
        _ = Ctx.window.bind("call_selectAudioDir", AudioTabInterface.call_selectAudioDir) catch unreachable;
        _ = Ctx.window.bind("call_play", AudioTabInterface.call_play) catch unreachable;
        _ = Ctx.window.bind("call_setVolume", AudioTabInterface.call_setVolume) catch unreachable;
        _ = Ctx.window.bind("call_setSolo", AudioTabInterface.call_setSolo) catch unreachable;
        _ = Ctx.window.bind("call_setDevice", AudioTabInterface.call_setDevice) catch unreachable;
        _ = Ctx.window.bind("call_setBinding", AudioTabInterface.call_setBinding) catch unreachable;
        _ = Ctx.window.bind("call_setSampleRate", AudioTabInterface.call_setSampleRate) catch unreachable;
        _ = Ctx.window.bind("call_setGlobalVolume", AudioTabInterface.call_setGlobalVolume) catch unreachable;
        _ = Ctx.window.bind("call_setThreshold", AudioTabInterface.call_setThreshold) catch unreachable;
        _ = Ctx.window.bind("call_setAttackTime", AudioTabInterface.call_setAttackTime) catch unreachable;
        _ = Ctx.window.bind("call_setReleaseTime", AudioTabInterface.call_setReleaseTime) catch unreachable;

        self.watchLoop.data.terminate = &Ctx.mustExit;
        self.watchLoop.call();

        self.initAudio();

        self.limiter.update(
            Ctx.settings.sampleRate,
            Ctx.settings.attackTime,
            Ctx.settings.releaseTime,
            Ctx.settings.limiterThreshold,
        );

        Ctx.tabs.logOut.logToEntry("Initialized audio tab", .{});
    }

    fn initUI(self: *AudioTabInterface, _: *webui.Event) void {
        jsCode("samplerate_input.value = {d}", .{Ctx.settings.sampleRate});
        jsCode("globalvolume_input.value = {d}", .{Ctx.settings.globalVolume});

        if (Ctx.settings.audioDirectory) |path| {
            jsCode("audiofolder_name.value = `{s}`", .{path});
        }

        for (self.tracksList.items) |track| {
            jsCode("addTrack({d}, `{s}`, {d}, {}, `{s}`)", .{
                track.id,
                track.path,
                track.saveData.volume,
                track.saveData.solo,
                keyToName(track.saveData.binding),
            });
        }

        jsCode("addDevice({d}, `{s}`, {})", .{
            -1,
            "Select a device",
            self.selectedDevice == -1,
        });

        for (0..self.enginesList.items.len) |index| {
            jsCode("addDevice({d}, `{s}`, {})", .{
                index,
                std.mem.sliceTo(&self.devicesInfo[index].name, 0),
                index == self.selectedDevice,
            });
        }

        jsCode("limiterthreshold_input.value = {d}", .{Ctx.settings.limiterThreshold});
        jsCode("attacktime_input.value = {d}", .{Ctx.settings.attackTime});
        jsCode("releasetime_input.value = {d}", .{Ctx.settings.releaseTime});
    }

    fn initSettings(self: *AudioTabInterface) void {
        self.setAudioDir(Ctx.settings.audioDirectory) catch |err| {
            if (err != Errors.NullFileName) {
                Ctx.tabs.logOut.logToEntry("{}", .{err});
            }
        };

        if (Ctx.settings.outputDevice) |val| {
            for (0..self.enginesList.items.len) |index| {
                if (std.mem.eql(u8, std.mem.sliceTo(&self.devicesInfo[index].name, 0), val)) {
                    self.selectedDevice = @intCast(index);

                    break;
                }
            }

            if (self.selectedDevice == -1) {
                Ctx.tabs.logOut.logToEntry("Could not find preferred device", .{});
            }
        }
    }

    fn deinit(self: *AudioTabInterface) void {
        if (self.directory) |*dir| {
            dir.close();

            self.directory = null;
        }

        for (self.enginesList.items) |engine| {
            engine.closed = true;
            engine.closing = true;
            _ = c.ma_engine_stop(engine.engine);
            engine.closing = false;
        }

        var tracksIter = Ctx.tabs.audio.playingTracks.iterator();

        while (tracksIter.next()) |entry| {
            if (Ctx.tabs.audio.playingTracks.fetchRemove(entry.key_ptr.*)) |track| {
                if (track.key.id != @intFromEnum(TrackMark.Deletion)) continue;

                track.key.deinitSounds();
                track.key.deinit();
            }
        }

        for (self.tracksList.items) |track| {
            track.deinitSounds();
            track.deinit();
        }

        self.tracksList.deinit();
        self.playingTracks.deinit();
        self.boundTracks.deinit();

        for (self.enginesList.items) |engine| {
            engine.deinit();
        }

        self.enginesList.deinit();

        c.ma_resource_manager_uninit(self.resourceManager);

        if (self.resourceManager) |_| {
            Ctx.allocator.destroy(self.resourceManager.?);

            self.resourceManager = null;
        }

        _ = c.ma_context_uninit(&self.audioContext);
    }
};

const DownloaderTabInterface = struct {
    comptime ytdlName: []const u8 = if (native_os == .windows) "ytdl.exe" else "ytdl",
    ytdlPath: ?[]const u8 = null,
    playAfter: bool = false,

    fn setDownloadsDir(_: *DownloaderTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return;
        }

        var dir = std.fs.openDirAbsolute(path.?, .{}) catch |err| {
            if (Ctx.settings.downloadsFolder != null) {
                Ctx.allocator.free(Ctx.settings.downloadsFolder.?);
                Ctx.settings.downloadsFolder = null;
                jsCode("downloadsfolder_name.innerText = ``", .{});

                Ctx.tabs.settings.saveDebounced.call();
            }

            return err;
        };
        dir.close();

        if (Ctx.settings.downloadsFolder != null) {
            Ctx.allocator.free(Ctx.settings.downloadsFolder.?);
        }

        Ctx.settings.downloadsFolder = Ctx.allocator.dupe(u8, path.?) catch unreachable;

        jsCode("downloadsfolder_name.value = `{s}`", .{path.?});
    }

    fn selectDownloadsDir() void {
        var outDir: [*c]u8 = null;

        const res = c.NFD_PickFolder(&outDir, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outDir);

        Ctx.tabs.downloader.setDownloadsDir(std.mem.sliceTo(outDir, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn setYTDLBinary(self: *DownloaderTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return Errors.NullFileName;
        }

        if (self.ytdlPath != null) {
            Ctx.allocator.free(self.ytdlPath.?);
        }

        if (Ctx.settings.ytdlPath != null) {
            Ctx.allocator.free(Ctx.settings.ytdlPath.?);
        }

        self.ytdlPath = Ctx.allocator.dupe(u8, path.?) catch unreachable;
        Ctx.settings.ytdlPath = Ctx.allocator.dupe(u8, path.?) catch unreachable;

        jsCode("ytdlpath_name.value = `{s}`", .{path.?});
    }

    fn selectYTDLBinary() void {
        var outPath: [*c]u8 = null;

        const res = c.NFD_OpenDialog(&outPath, null, 0, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outPath);

        Ctx.tabs.downloader.setYTDLBinary(std.mem.sliceTo(outPath, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_selectYTDLBinary(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(DownloaderTabInterface.selectYTDLBinary) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn call_selectDownloadsDir(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(DownloaderTabInterface.selectDownloadsDir) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn call_setVideoSizeLimit(event: *webui.Event) void {
        Ctx.settings.videoSizeLimitMB = event.getFloatAt(0);

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setPlayAfter(event: *webui.Event) void {
        Ctx.tabs.downloader.playAfter = event.getBoolAt(0);
    }

    fn downloadVideo(
        self: *DownloaderTabInterface,
        url: []const u8,
        name: []const u8,
        owned: bool,
        cb: ?*const fn (index: i64) void,
    ) void {
        // defer { if ()...} != if () {defer...}

        Ctx.tabs.audio.shouldRefresh = false;

        defer {
            Ctx.tabs.audio.shouldRefresh = true;

            if (owned) {
                Ctx.allocator.free(url);
                Ctx.allocator.free(name);
            }
        }

        if ((self.ytdlPath == null) and (Ctx.settings.audioDirectory == null)) {
            return;
        }

        if (Ctx.settings.downloadsFolder) |path| {
            if (Ctx.settings.audioDirectory) |path2| {
                if (std.mem.indexOf(u8, path2, path)) |_| {
                    Ctx.tabs.logOut.logToEntry("{}", .{Errors.DownloadDirIsTopLevel});

                    return;
                }
            }
        }

        const outDir = if (Ctx.settings.downloadsFolder != null)
            Ctx.settings.downloadsFolder.?
        else if (Ctx.settings.audioDirectory != null)
            Ctx.settings.audioDirectory.?
        else
            "";

        const outName = if (name.len < 1)
            "download"
        else
            name;

        // Strings...

        var arena_config = std.heap.ArenaAllocator.init(Ctx.allocator);
        const arena_allocator = arena_config.allocator();

        const argOutPath = std.fs.path.join(arena_allocator, &.{
            outDir,
            std.mem.concat(arena_allocator, u8, &.{ outName, ".%(ext)s" }) catch unreachable,
        }) catch unreachable;

        const expectedOutPath = std.fs.path.join(arena_allocator, &.{
            outDir,
            std.mem.concat(arena_allocator, u8, &.{ outName, ".ogg" }) catch unreachable,
        }) catch unreachable;

        const limitSize = std.fmt.allocPrint(arena_allocator, "{d}M", .{Ctx.settings.videoSizeLimitMB}) catch unreachable;

        var proc = std.process.Child.init(
            &.{
                self.ytdlPath.?,
                "-o",
                argOutPath,
                "-q",
                "-x",
                "--recode-video",
                "ogg",
                "--max-filesize",
                limitSize,
                "--max-downloads",
                "1",
                "--force-overwrites",
                "--no-playlist",
                "--no-part",
                "--no-continue",
                "--no-cache-dir",
                "--no-mtime",
                "--", // https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html
                url,
            },
            Ctx.allocator,
        );

        const res = proc.spawnAndWait() catch unreachable;

        defer arena_config.deinit();

        if (outDir.len < 1) {
            Ctx.tabs.logOut.logToEntry("Downloaded {s} to the current directory", .{url});

            return;
        }

        if (std.fs.openFileAbsolute(expectedOutPath, .{})) |file| {
            file.close();
        } else |fErr| {
            Ctx.tabs.logOut.logToEntry("{}", .{fErr});
            Ctx.tabs.logOut.logToEntry("YT-DL info : {}", .{res});

            return;
        }

        if (Ctx.settings.audioDirectory == null) return;

        Ctx.tabs.audio.fillTracksList() catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        if (cb == null) return;

        for (Ctx.tabs.audio.tracksList.items) |track| {
            if (!std.mem.eql(u8, expectedOutPath, track.path)) {
                continue;
            }

            cb.?(track.id);

            break;
        }
    }

    fn playAfterDownload(index: i64) void {
        Ctx.tabs.audio.tracksList.items[@intCast(index)].play(Ctx.tabs.audio.defaultDevice, true);
    }

    fn call_downloadVideo(event: *webui.Event) void {
        const url = Ctx.allocator.dupe(u8, event.getStringAt(0)) catch unreachable;
        const name = Ctx.allocator.dupe(u8, event.getStringAt(1)) catch unreachable;

        asy.Spawn(DownloaderTabInterface.downloadVideo, .{
            &Ctx.tabs.downloader,
            url,
            name,
            true,
            if (Ctx.tabs.downloader.playAfter)
                &DownloaderTabInterface.playAfterDownload
            else
                null,
        }) catch unreachable;
    }

    fn init(self: *DownloaderTabInterface) void {
        _ = Ctx.window.bind("call_selectDownloadsDir", DownloaderTabInterface.call_selectDownloadsDir) catch unreachable;
        _ = Ctx.window.bind("call_selectYTDLBinary", DownloaderTabInterface.call_selectYTDLBinary) catch unreachable;
        _ = Ctx.window.bind("call_setVideoSizeLimit", DownloaderTabInterface.call_setVideoSizeLimit) catch unreachable;
        _ = Ctx.window.bind("call_setPlayAfter", DownloaderTabInterface.call_setPlayAfter) catch unreachable;
        _ = Ctx.window.bind("call_downloadVideo", DownloaderTabInterface.call_downloadVideo) catch unreachable;

        if (Ctx.settings.ytdlPath) |path| {
            if (Ctx.tabs.settings.cwd.openFile(path, .{})) |file| {
                file.close();
            } else |_| {
                Ctx.tabs.logOut.logToEntry("Invalid path to youtube-dl binary", .{});

                return;
            }

            self.ytdlPath = Ctx.allocator.dupe(u8, path) catch unreachable;
        } else {
            if (Ctx.tabs.settings.cwd.openFile(self.ytdlName, .{})) |file| {
                file.close();
            } else |_| {
                Ctx.tabs.logOut.logToEntry("Couldn't find a youtube-dl binary (ytdl.exe / ytdl) in the current directory", .{});

                return;
            }

            const cwdPath = Ctx.tabs.settings.cwd.realpathAlloc(Ctx.allocator, ".") catch unreachable;
            defer Ctx.allocator.free(cwdPath);

            const tempPath = std.fs.path.join(
                Ctx.allocator,
                &.{
                    cwdPath,
                    self.ytdlName,
                },
            ) catch unreachable;

            self.ytdlPath = tempPath;
        }

        Ctx.tabs.logOut.logToEntry("Initialized downloader tab", .{});
    }

    fn initUI(self: *DownloaderTabInterface, _: *webui.Event) void {
        jsCode("playafterdownload_checkmark.checked = {}", .{self.playAfter});
        jsCode("videosizelimit_input.value = {d}", .{Ctx.settings.videoSizeLimitMB});

        if (Ctx.settings.ytdlPath) |path| {
            jsCode("ytdlpath_name.value = `{s}`", .{path});
        }

        if (Ctx.settings.downloadsFolder) |path| {
            jsCode("downloadsfolder_name.value = `{s}`", .{path});
        }
    }

    fn deinit(self: *DownloaderTabInterface) void {
        if (self.ytdlPath) |path| {
            Ctx.allocator.free(path);

            self.ytdlPath = null;
        }
    }
};

const WatchTabInterface = struct {
    file: ?std.fs.File = null,
    previousPos: u64 = 0,
    commands: std.StringHashMapUnmanaged(*LogCommand) = .{},
    watchLoop: asy.Ticker(100 * std.time.ns_per_ms, WatchTabInterface.loopFunc) = .{},
    timestampRegex: rgx.Regex = undefined,
    separatorRegex: rgx.Regex = undefined,
    chatRegex: rgx.Regex = undefined,
    queueList: std.ArrayList(*AudioTrack) = std.ArrayList(*AudioTrack).init(Ctx.allocator),

    fn removeCommand(arg: []const u8) void {
        if (Ctx.settings.usersList.map.fetchSwapRemove(arg)) |val| {
            Ctx.allocator.free(val.key);
        }

        jsCode("removeUser(`{s}`)", .{arg});

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn allowCommand(arg: []const u8) void {
        const user = Ctx.allocator.dupe(u8, arg) catch unreachable;

        if (user.len < 1) {
            Ctx.allocator.free(user);

            return;
        }

        if (Ctx.settings.usersList.map.fetchSwapRemove(user)) |val| {
            Ctx.allocator.free(val.key);
        }

        Ctx.settings.usersList.map.put(Ctx.allocator, user, true) catch unreachable;

        jsCode("addUser(`{s}`, {})", .{ user, true });

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn blockCommand(arg: []const u8) void {
        const user = Ctx.allocator.dupe(u8, arg) catch unreachable;

        if (user.len < 1) {
            Ctx.allocator.free(user);

            return;
        }

        if (Ctx.settings.usersList.map.fetchSwapRemove(user)) |val| {
            Ctx.allocator.free(val.key);
        }

        Ctx.settings.usersList.map.put(Ctx.allocator, user, false) catch unreachable;

        jsCode("addUser(`{s}`, {})", .{ user, false });

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn skipAllCommand(_: []const u8) void {
        for (Ctx.tabs.watch.queueList.items) |track| {
            track.deinit();

            jsCode("removeQueued(queuedList[0])", .{});
        }

        Ctx.tabs.watch.queueList.clearAndFree();

        var tracksIter = Ctx.tabs.audio.playingTracks.iterator();
        var temp: u64 = 0;

        while (tracksIter.next()) |entry| {
            for (entry.key_ptr.*.sounds.items) |*sound| {
                _ = c.ma_sound_get_length_in_pcm_frames(sound.*, &temp);
                _ = c.ma_sound_seek_to_pcm_frame(sound.*, temp);
            }
        }
    }

    fn skipCommand(_: []const u8) void {
        var tracksIter = Ctx.tabs.audio.playingTracks.iterator();
        var temp: u64 = 0;

        while (tracksIter.next()) |entry| {
            for (entry.key_ptr.*.sounds.items) |*sound| {
                _ = c.ma_sound_get_length_in_pcm_frames(sound.*, &temp);
                _ = c.ma_sound_seek_to_pcm_frame(sound.*, temp);
            }
        }
    }

    fn overlapDownloaded(index: i64) void {
        Ctx.tabs.audio.tracksList.items[@intCast(index)].play(Ctx.tabs.audio.selectedDevice, false);
    }

    fn oVideoCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        asy.Spawn(DownloaderTabInterface.downloadVideo, .{
            &Ctx.tabs.downloader,
            Ctx.allocator.dupe(u8, arg) catch unreachable,
            Ctx.allocator.dupe(u8, "") catch unreachable,
            true,
            &WatchTabInterface.overlapDownloaded,
        }) catch unreachable;
    }

    fn fVideoCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        asy.Spawn(DownloaderTabInterface.downloadVideo, .{
            &Ctx.tabs.downloader,
            Ctx.allocator.dupe(u8, arg) catch unreachable,
            Ctx.allocator.dupe(u8, "") catch unreachable,
            true,
            &DownloaderTabInterface.playAfterDownload,
        }) catch unreachable;
    }

    fn queueDownloaded(index: i64) void {
        Ctx.tabs.audio.tracksList.items[@intCast(index)].queue();
    }

    fn videoCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        asy.Spawn(DownloaderTabInterface.downloadVideo, .{
            &Ctx.tabs.downloader,
            Ctx.allocator.dupe(u8, arg) catch unreachable,
            Ctx.allocator.dupe(u8, "") catch unreachable,
            true,
            &WatchTabInterface.queueDownloaded,
        }) catch unreachable;
    }

    fn ttsCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        Ctx.tabs.tts.speak(arg);
    }

    fn samplerateCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        const newSampleRate: u32 = std.fmt.parseUnsigned(u32, arg, 10) catch return;

        if ((Ctx.settings.sampleRate == newSampleRate) or (newSampleRate == 0)) return;

        Ctx.tabs.audio.setSampleRate(newSampleRate);

        jsCode("samplerate_input.value = {d}", .{Ctx.settings.sampleRate});

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn gVolumeCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        const newVolume = std.fmt.parseFloat(f32, arg) catch return;

        if (Ctx.settings.globalVolume == newVolume) return;

        Ctx.settings.globalVolume = newVolume;

        for (Ctx.tabs.audio.enginesList.items) |engine| {
            _ = c.ma_engine_set_volume(engine.engine, newVolume / 100.0);
        }

        jsCode("globalvolume_input.value = {d}", .{Ctx.settings.globalVolume});

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn volumeCommand(arg: []const u8) void {
        if ((arg.len < 1) or
            (Ctx.tabs.audio.playingTracks.count() > 1))
        {
            return;
        }

        const newVolume = std.fmt.parseFloat(f32, arg) catch return;

        var tracksIter = Ctx.tabs.audio.playingTracks.iterator();

        while (tracksIter.next()) |entry| {
            entry.key_ptr.*.setVolume(newVolume);

            if (entry.key_ptr.*.id != -1) {
                jsCode("tracksList[{d}].volumeInput.value = {d}", .{
                    entry.key_ptr.*.id,
                    newVolume,
                });
            }
        }

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn oPlayCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        const index = Ctx.tabs.audio.findTrackByName(arg) orelse std.fmt.parseUnsigned(usize, arg, 10) catch return;

        if (index >= Ctx.tabs.audio.tracksList.items.len) return;

        Ctx.tabs.audio.tracksList.items[index].play(Ctx.tabs.audio.selectedDevice, false);
    }

    fn fPlayCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        const index = Ctx.tabs.audio.findTrackByName(arg) orelse std.fmt.parseUnsigned(usize, arg, 10) catch return;

        if (index >= Ctx.tabs.audio.tracksList.items.len) return;

        Ctx.tabs.audio.tracksList.items[index].play(Ctx.tabs.audio.selectedDevice, true);
    }

    fn playCommand(arg: []const u8) void {
        if (arg.len < 1) return;

        const index = Ctx.tabs.audio.findTrackByName(arg) orelse std.fmt.parseUnsigned(usize, arg, 10) catch return;

        if (index >= Ctx.tabs.audio.tracksList.items.len) return;

        Ctx.tabs.audio.tracksList.items[index].queue();
    }

    fn handleLine(self: *WatchTabInterface, line: []const u8) void {
        var separated = self.separatorRegex.captures(line) catch return;

        defer {
            if (separated) |*pos| {
                pos.deinit();
            }
        }

        if (separated) |*pos| {
            const sepSpan = pos.boundsAt(0).?;

            var playerName = line[0..sepSpan.lower];
            const fullCmd = line[sepSpan.upper..];

            if (Ctx.settings.timestampedLog) {
                var timeSep = self.timestampRegex.captures(playerName) catch {
                    return;
                };

                if (timeSep) |*timePos| {
                    const timeSpan = timePos.boundsAt(0);

                    playerName = playerName[timeSpan.?.upper..];

                    timePos.deinit();
                }
            }

            var chatSep = self.chatRegex.captures(playerName) catch {
                return;
            };

            if (chatSep) |*chatPos| {
                const chatSpan = chatPos.boundsAt(0);

                playerName = playerName[chatSpan.?.upper..];

                chatPos.deinit();
            }

            const status = Ctx.settings.usersList.map.get(playerName) orelse
                Ctx.settings.usersList.map.get("*");

            const isAllowed = if (status == null) false else status.?;
            const isBlocked = if (status == null) false else !status.?;

            const firstSpace = std.mem.indexOf(u8, fullCmd, " ");

            if (firstSpace == null) {
                const command = self.commands.get(std.mem.trim(u8, fullCmd, " "));

                if (command) |val| {
                    if ((val.save.allowedOnly and !isAllowed) or isBlocked) {
                        return;
                    }

                    val.call("");
                }

                return;
            }

            const command = self.commands.get(fullCmd[0..firstSpace.?]);

            if (command) |val| {
                if ((val.save.allowedOnly and !isAllowed) or isBlocked) {
                    return;
                }

                const arg = std.mem.trim(u8, fullCmd[firstSpace.? + 1 ..], " ");

                if (arg.len < 1) return;

                val.call(arg);
            }
        }
    }

    fn loopFunc() void {
        const self = &Ctx.tabs.watch;

        if (self.file == null) return;

        const stat = self.file.?.stat() catch unreachable;

        if (stat.size <= self.previousPos) return;

        const newLines = Ctx.allocator.alloc(u8, stat.size - self.previousPos) catch unreachable;
        defer Ctx.allocator.free(newLines);

        _ = self.file.?.read(newLines) catch unreachable;

        var splitLines = std.mem.splitAny(u8, newLines, Constants.newline);

        while (splitLines.next()) |line| {
            if (line.len < 1) continue;

            self.handleLine(line);
        }

        self.previousPos = stat.size;
    }

    fn setWatchFile(self: *WatchTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return Errors.NullFileName;
        }

        if (self.file) |file| {
            file.close();
            self.previousPos = 0;
            self.file = null;

            Ctx.allocator.free(Ctx.settings.watchFile.?);
            Ctx.settings.watchFile = null;
            jsCode("loginput_name.value = ``", .{});
        }

        if (Ctx.settings.logOutFile) |outLog| {
            if (std.mem.eql(u8, outLog, path.?)) {
                return Errors.LogWatchIsOutput;
            }
        }

        self.file = std.fs.openFileAbsolute(path.?, .{}) catch |err| {
            if (Ctx.settings.watchFile != null) {
                Ctx.allocator.free(Ctx.settings.watchFile.?);
                Ctx.settings.watchFile = null;
                jsCode("loginput_name.innerText = ``", .{});

                Ctx.tabs.settings.saveDebounced.call();
            }

            return err;
        };

        if (Ctx.settings.watchFile == null) {
            Ctx.settings.watchFile = std.fmt.allocPrint(Ctx.allocator, "{s}", .{path.?}) catch unreachable;
        }

        const stat = self.file.?.stat() catch unreachable;

        self.file.?.seekTo(stat.size) catch unreachable;
        self.previousPos = stat.size;

        jsCode("loginput_name.value = `{s}`", .{path.?});
    }

    fn selectWatchFile() void {
        var outPath: [*c]u8 = null;

        const res = c.NFD_OpenDialog(&outPath, @ptrCast(&Constants.filtersList), 1, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outPath);

        Ctx.tabs.watch.setWatchFile(std.mem.sliceTo(outPath, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_selectWatchFile(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(WatchTabInterface.selectWatchFile) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn call_setAllowed(event: *webui.Event) void {
        const name = event.getStringAt(0);

        if (Ctx.tabs.watch.commands.get(name)) |cmd| {
            cmd.save.allowedOnly = event.getBoolAt(1);

            cmd.needsSave();

            Ctx.tabs.settings.saveDebounced.call();
        }
    }

    fn call_setTimestampedLog(event: *webui.Event) void {
        Ctx.settings.timestampedLog = event.getBoolAt(0);

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setChatRegex(event: *webui.Event) void {
        const chatRegex = Ctx.allocator.dupe(u8, event.getStringAt(0)) catch unreachable;

        const tempRegex = rgx.Regex.compile(Ctx.allocator, chatRegex) catch {
            Ctx.tabs.logOut.logToEntry("Invalid chat prefix regex", .{});

            Ctx.allocator.free(chatRegex);

            return;
        };

        Ctx.tabs.watch.chatRegex.deinit();
        Ctx.tabs.watch.chatRegex = tempRegex;

        if (Ctx.settings.chatRegex) |old| {
            Ctx.allocator.free(old);
        }

        Ctx.settings.chatRegex = chatRegex;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setSeparatorRegex(event: *webui.Event) void {
        const separatorRegex = Ctx.allocator.dupe(u8, event.getStringAt(0)) catch unreachable;

        const tempRegex = rgx.Regex.compile(Ctx.allocator, separatorRegex) catch {
            Ctx.tabs.logOut.logToEntry("Invalid chat prefix regex", .{});

            Ctx.allocator.free(separatorRegex);

            return;
        };

        Ctx.tabs.watch.separatorRegex.deinit();
        Ctx.tabs.watch.separatorRegex = tempRegex;

        if (Ctx.settings.separatorRegex) |old| {
            Ctx.allocator.free(old);
        }

        Ctx.settings.separatorRegex = separatorRegex;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_addUser(event: *webui.Event) void {
        const user = Ctx.allocator.dupe(u8, event.getStringAt(0)) catch unreachable;

        if (user.len < 1) {
            Ctx.allocator.free(user);

            return;
        }

        const block = event.getBoolAt(1);

        if (Ctx.settings.usersList.map.fetchSwapRemove(user)) |val| {
            Ctx.allocator.free(val.key);
        }

        Ctx.settings.usersList.map.put(Ctx.allocator, user, block) catch unreachable;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_removeUser(event: *webui.Event) void {
        const user = event.getStringAt(0);

        if (user.len < 1) {
            return;
        }

        if (Ctx.settings.usersList.map.fetchSwapRemove(user)) |val| {
            Ctx.allocator.free(val.key);
        }

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_removeQueued(event: *webui.Event) void {
        Ctx.tabs.watch.queueList.orderedRemove(@intCast(event.getIntAt(0))).deinit();
    }

    fn call_setQueueLimit(event: *webui.Event) void {
        Ctx.settings.queueLimit = @intCast(event.getIntAt(0));

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn init(self: *WatchTabInterface) void {
        _ = Ctx.window.bind("call_selectWatchFile", WatchTabInterface.call_selectWatchFile) catch unreachable;
        _ = Ctx.window.bind("call_setAllowed", WatchTabInterface.call_setAllowed) catch unreachable;
        _ = Ctx.window.bind("call_setTimestampedLog", WatchTabInterface.call_setTimestampedLog) catch unreachable;
        _ = Ctx.window.bind("call_setChatRegex", WatchTabInterface.call_setChatRegex) catch unreachable;
        _ = Ctx.window.bind("call_setSeparatorRegex", WatchTabInterface.call_setSeparatorRegex) catch unreachable;
        _ = Ctx.window.bind("call_addUser", WatchTabInterface.call_addUser) catch unreachable;
        _ = Ctx.window.bind("call_removeUser", WatchTabInterface.call_removeUser) catch unreachable;
        _ = Ctx.window.bind("call_removeQueued", WatchTabInterface.call_removeQueued) catch unreachable;
        _ = Ctx.window.bind("call_setQueueLimit", WatchTabInterface.call_setQueueLimit) catch unreachable;

        self.watchLoop.data.terminate = &Ctx.mustExit;
        self.watchLoop.call();

        for (Constants.commandsList) |cmd| {
            self.commands.put(Ctx.allocator, cmd.name, cmd) catch unreachable;
        }

        self.chatRegex = rgx.Regex.compile(Ctx.allocator, Ctx.settings.chatRegex.?) catch blk: {
            Ctx.tabs.logOut.logToEntry("Invalid chat prefix regex", .{});

            break :blk rgx.Regex.compile(Ctx.allocator, Constants.chatRegex) catch unreachable;
        };

        self.separatorRegex = rgx.Regex.compile(Ctx.allocator, Ctx.settings.separatorRegex.?) catch blk: {
            Ctx.tabs.logOut.logToEntry("Invalid separator regex", .{});

            break :blk rgx.Regex.compile(Ctx.allocator, Constants.separatorRegex) catch unreachable;
        };

        self.timestampRegex = rgx.Regex.compile(Ctx.allocator, Ctx.settings.timestampRegex.?) catch blk: {
            Ctx.tabs.logOut.logToEntry("Invalid timestamp regex", .{});

            break :blk rgx.Regex.compile(Ctx.allocator, Constants.timestampRegex) catch unreachable;
        };

        Ctx.tabs.logOut.logToEntry("Initialized watcher tab", .{});
    }

    fn initUI(self: *WatchTabInterface, _: *webui.Event) void {
        if (Ctx.settings.watchFile) |path| {
            jsCode("loginput_name.value = `{s}`", .{path});
        }

        if (Ctx.settings.chatRegex) |regex| {
            jsCode("chatregex_input.value = `{s}`", .{regex});
        }

        if (Ctx.settings.separatorRegex) |regex| {
            jsCode("separatorregex_input.value = `{s}`", .{regex});
        }

        jsCode("loginputtimestamp_checkmark.checked = {}", .{Ctx.settings.timestampedLog});
        jsCode("queuelimit_input.value = {d}", .{Ctx.settings.queueLimit});

        for (Constants.commandsList) |cmd| {
            jsCode("addCommand(`{s}`, `{s}`, {})", .{ cmd.name, cmd.description, cmd.save.allowedOnly });
        }

        var usersIter = Ctx.settings.usersList.map.iterator();

        while (usersIter.next()) |entry| {
            jsCode("addUser(`{s}`, {})", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        for (self.queueList.items) |queued| {
            jsCode("addQueued(`{s}`)", .{queued.path});
        }
    }

    fn initSettings(self: *WatchTabInterface) void {
        self.setWatchFile(Ctx.settings.watchFile) catch |err| {
            if (err != Errors.NullFileName) {
                Ctx.tabs.logOut.logToEntry("{}", .{err});
            }
        };
    }

    fn deinit(self: *WatchTabInterface) void {
        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        self.commands.deinit(Ctx.allocator);

        self.chatRegex.deinit();
        self.separatorRegex.deinit();
        self.timestampRegex.deinit();

        for (self.queueList.items) |track| {
            track.deinit();
        }

        self.queueList.deinit();
    }
};

const TTSTabInterface = struct {
    ttsBin: ?std.process.Child = null,
    voicesList: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(Ctx.allocator),
    selectedVoice: i8 = -1,

    fn speak(self: *TTSTabInterface, text: []const u8) void {
        if ((self.ttsBin == null) or
            (Ctx.settings.outputDevice == null) or
            (self.selectedVoice == -1))
        {
            return;
        }

        const cmdDevice = std.mem.concat(Ctx.allocator, u8, &.{
            Constants.setDeviceCmd,
            " ",
            Ctx.settings.outputDevice.?,
            Constants.newline,
        }) catch unreachable;
        defer Ctx.allocator.free(cmdDevice);

        _ = self.ttsBin.?.stdin.?.write(cmdDevice) catch unreachable;

        const cmdSpeak = std.fmt.allocPrint(Ctx.allocator, "{s} {d} {s}" ++ Constants.newline, .{
            Constants.speakCmd,
            self.selectedVoice,
            text,
        }) catch unreachable;
        defer Ctx.allocator.free(cmdSpeak);

        _ = self.ttsBin.?.stdin.?.write(cmdSpeak) catch unreachable;
    }

    fn updateBin(self: *TTSTabInterface) void {
        if (self.ttsBin != null) {
            _ = self.ttsBin.?.kill() catch {};
        }

        for (self.voicesList.items) |voice| {
            Ctx.allocator.free(voice);
        }

        self.voicesList.clearAndFree();

        jsCode("clearVoices()", .{});

        self.ttsBin = std.process.Child.init(&.{
            Ctx.settings.ttsPath.?,
            if (Ctx.settings.ttsFile == null)
                ""
            else
                Ctx.settings.ttsFile.?,
            if (Ctx.settings.ttsArgs == null)
                ""
            else
                Ctx.settings.ttsArgs.?,
        }, Ctx.allocator);

        self.ttsBin.?.stdout_behavior = .Pipe;
        self.ttsBin.?.stdin_behavior = .Pipe;

        self.ttsBin.?.spawn() catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            self.ttsBin = null;

            return;
        };

        jsCode("addVoice({d}, `{s}`, {})", .{
            -1,
            "Select a voice",
            self.selectedVoice == -1,
        });

        if (self.ttsBin.?.stdin) |in| {
            _ = in.write(Constants.voicesCmd ++ Constants.newline) catch unreachable;
        }

        const start = std.time.Instant.now() catch unreachable;

        if (self.ttsBin.?.stdout) |out| {
            top: while (true) {
                const now = std.time.Instant.now() catch unreachable;

                if (now.since(start) >= Ctx.settings.ttsTimeoutNs) {
                    Ctx.tabs.logOut.logToEntry("Voice search timed out", .{});

                    _ = self.ttsBin.?.kill() catch {};
                    self.ttsBin = null;

                    break;
                }

                const pos = out.getEndPos() catch continue;

                if (pos == 0) continue;

                const buf = Ctx.allocator.alloc(u8, pos) catch unreachable;

                _ = out.read(buf) catch unreachable;
                var iter = std.mem.splitAny(u8, buf, Constants.newline);

                while (iter.next()) |line| {
                    if (std.mem.eql(u8, "End of voices list", line)) {
                        Ctx.allocator.free(buf);

                        break :top;
                    }

                    if (line.len >= 1) {
                        self.voicesList.append(Ctx.allocator.dupe(u8, line) catch unreachable) catch unreachable;

                        jsCode("addVoice({d}, `{s}`, {})", .{
                            (self.voicesList.items.len - 1),
                            line,
                            (self.voicesList.items.len - 1) == self.selectedVoice,
                        });
                    }
                }

                Ctx.allocator.free(buf);
            }
        }
    }

    fn setScriptFile(_: *TTSTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return Errors.NullFileName;
        }

        if (Ctx.settings.ttsFile != null) {
            Ctx.allocator.free(Ctx.settings.ttsFile.?);
        }

        Ctx.settings.ttsFile = Ctx.allocator.dupe(u8, path.?) catch unreachable;

        jsCode("ttsfile_name.value = `{s}`", .{path.?});
    }

    fn selectScriptFile() void {
        var outPath: [*c]u8 = null;

        const res = c.NFD_OpenDialog(&outPath, @ptrCast(&Constants.filtersList), 1, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outPath);

        Ctx.tabs.tts.setScriptFile(std.mem.sliceTo(outPath, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn setTTSBinary(self: *TTSTabInterface, path: ?[]const u8) !void {
        if (path == null) {
            return Errors.NullFileName;
        }

        if (Ctx.settings.ttsPath != null) {
            Ctx.allocator.free(Ctx.settings.ttsPath.?);
        }

        Ctx.settings.ttsPath = Ctx.allocator.dupe(u8, path.?) catch unreachable;

        self.updateBin();

        jsCode("ttspipe_name.value = `{s}`", .{path.?});
    }

    fn selectTTSBinary() void {
        var outPath: [*c]u8 = null;

        const res = c.NFD_OpenDialog(&outPath, null, 0, null);

        if (res != c.NFD_OKAY) return;

        defer c.NFD_FreePath(outPath);

        Ctx.tabs.tts.setTTSBinary(std.mem.sliceTo(outPath, 0)) catch |err| {
            Ctx.tabs.logOut.logToEntry("{}", .{err});

            return;
        };

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_selectTTSFile(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(TTSTabInterface.selectScriptFile) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn call_selectTTSBinary(_: *webui.Event) void {
        Ctx.mainThreadFuncs.append(TTSTabInterface.selectTTSBinary) catch unreachable;

        Ctx.mainThreadEvent.set();
    }

    fn call_setTTSArgs(event: *webui.Event) void {
        const args = Ctx.allocator.dupe(u8, event.getStringAt(0)) catch unreachable;

        if (Ctx.settings.ttsArgs) |old| {
            Ctx.allocator.free(old);
        }

        Ctx.settings.ttsArgs = args;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setTTSRate(event: *webui.Event) void {
        Ctx.settings.ttsRate = @intCast(event.getIntAt(0));

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setTTSVolume(event: *webui.Event) void {
        Ctx.settings.ttsVolume = @intCast(event.getIntAt(0));

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_setTTSVoice(event: *webui.Event) void {
        const index: i8 = @intCast(event.getIntAt(0));

        if ((index == Ctx.tabs.tts.selectedVoice) or (index == -1)) return;

        Ctx.tabs.tts.selectedVoice = index;

        if (Ctx.settings.ttsVoice) |old| {
            Ctx.allocator.free(old);
        }

        Ctx.settings.ttsVoice = Ctx.allocator.dupe(u8, Ctx.tabs.tts.voicesList.items[@intCast(index)]) catch unreachable;

        Ctx.tabs.settings.saveDebounced.call();
    }

    fn call_speakTTS(event: *webui.Event) void {
        Ctx.tabs.tts.speak(event.getStringAt(0));
    }

    fn init(_: *TTSTabInterface) void {
        _ = Ctx.window.bind("call_setTTSArgs", TTSTabInterface.call_setTTSArgs) catch unreachable;
        _ = Ctx.window.bind("call_selectTTSBinary", TTSTabInterface.call_selectTTSBinary) catch unreachable;
        _ = Ctx.window.bind("call_selectTTSFile", TTSTabInterface.call_selectTTSFile) catch unreachable;
        _ = Ctx.window.bind("call_setTTSRate", TTSTabInterface.call_setTTSRate) catch unreachable;
        _ = Ctx.window.bind("call_setTTSVolume", TTSTabInterface.call_setTTSVolume) catch unreachable;
        _ = Ctx.window.bind("call_setTTSVoice", TTSTabInterface.call_setTTSVoice) catch unreachable;
        _ = Ctx.window.bind("call_speakTTS", TTSTabInterface.call_speakTTS) catch unreachable;

        Ctx.tabs.logOut.logToEntry("Initialized TTS tab", .{});
    }

    fn initUI(self: *TTSTabInterface, _: *webui.Event) void {
        if (Ctx.settings.ttsPath) |pipe| {
            jsCode("ttspipe_name.value = `{s}`", .{pipe});
        }

        if (Ctx.settings.ttsFile) |path| {
            jsCode("ttsfile_name.value = `{s}`", .{path});
        }

        if (Ctx.settings.ttsArgs) |args| {
            jsCode("ttspipeargs_name.value = `{s}`", .{args});
        }

        jsCode("ttsspeed_input.value = {d}", .{Ctx.settings.ttsRate});
        jsCode("ttsvolume_input.value = {d}", .{Ctx.settings.ttsVolume});

        jsCode("addVoice({d}, `{s}`, {})", .{
            -1,
            "Select a voice",
            self.selectedVoice == -1,
        });

        for (self.voicesList.items, 0..) |voice, index| {
            jsCode("addVoice({d}, `{s}`, {})", .{
                index,
                voice,
                index == self.selectedVoice,
            });
        }
    }

    fn initSettings(self: *TTSTabInterface) void {
        if (Ctx.settings.ttsPath) |_| {
            self.updateBin();
        }

        if (Ctx.settings.ttsVoice) |val| {
            for (0..self.voicesList.items.len) |index| {
                if (std.mem.eql(u8, self.voicesList.items[index], val)) {
                    self.selectedVoice = @intCast(index);

                    break;
                }
            }

            if (self.selectedVoice == -1) {
                Ctx.tabs.logOut.logToEntry("Could not find preferred voice", .{});
            }
        }
    }

    fn deinit(self: *TTSTabInterface) void {
        for (self.voicesList.items) |voice| {
            Ctx.allocator.free(voice);
        }

        self.voicesList.deinit();

        if (self.ttsBin) |*bin| {
            _ = bin.kill() catch {};
        }
    }
};

fn jsCode(comptime format: []const u8, args: anytype) void {
    const newCmd = std.fmt.allocPrintSentinel(Ctx.allocator, format, args, 0) catch unreachable;
    defer Ctx.allocator.free(newCmd);

    const cmdString = Ctx.allocator.allocSentinel(
        u8,
        std.mem.replacementSize(u8, newCmd, "\\", "\\\\"),
        0,
    ) catch unreachable;
    defer Ctx.allocator.free(cmdString);

    _ = std.mem.replace(u8, newCmd, "\\", "\\\\", cmdString);

    Ctx.window.run(cmdString);
}

pub fn main() !void {
    Ctx.init();

    Ctx.start();

    Ctx.deinit();
}

fn keyToName(key: c_ushort) []const u8 {
    return switch (key) {
        // Begin Virtual Key Codes
        c.VC_ESCAPE => "Escape",

        // Begin Function Keys
        c.VC_F1 => "F1",
        c.VC_F2 => "F2",
        c.VC_F3 => "F3",
        c.VC_F4 => "F4",
        c.VC_F5 => "F5",
        c.VC_F6 => "F6",
        c.VC_F7 => "F7",
        c.VC_F8 => "F8",
        c.VC_F9 => "F9",
        c.VC_F10 => "F10",
        c.VC_F11 => "F11",
        c.VC_F12 => "F12",

        c.VC_F13 => "F13",
        c.VC_F14 => "F14",
        c.VC_F15 => "F15",
        c.VC_F16 => "F16",
        c.VC_F17 => "F17",
        c.VC_F18 => "F18",
        c.VC_F19 => "F19",
        c.VC_F20 => "F20",
        c.VC_F21 => "F21",
        c.VC_F22 => "F22",
        c.VC_F23 => "F23",
        c.VC_F24 => "F24",
        // End Function Keys

        // Begin Alphanumeric Zone
        c.VC_BACK_QUOTE => "Back quote",

        c.VC_0 => "0",
        c.VC_1 => "1",
        c.VC_2 => "2",
        c.VC_3 => "3",
        c.VC_4 => "4",
        c.VC_5 => "5",
        c.VC_6 => "6",
        c.VC_7 => "7",
        c.VC_8 => "8",
        c.VC_9 => "9",

        c.VC_PLUS => "Plus",
        c.VC_MINUS => "Minus",
        c.VC_EQUALS => "Equals",
        c.VC_ASTERISK => "Asterisk",

        c.VC_AT => "At",
        c.VC_AMPERSAND => "Ampersand",
        c.VC_DOLLAR => "Dollar",
        c.VC_EXCLAMATION_MARK => "Exclamation mark",
        c.VC_EXCLAMATION_DOWN => "Exclamation down",

        c.VC_BACKSPACE => "Backspace",

        c.VC_TAB => "Tab",
        c.VC_CAPS_LOCK => "Caps lock",

        c.VC_A => "A",
        c.VC_B => "B",
        c.VC_C => "C",
        c.VC_D => "D",
        c.VC_E => "E",
        c.VC_F => "F",
        c.VC_G => "G",
        c.VC_H => "H",
        c.VC_I => "I",
        c.VC_J => "J",
        c.VC_K => "K",
        c.VC_L => "L",
        c.VC_M => "M",
        c.VC_N => "N",
        c.VC_O => "O",
        c.VC_P => "P",
        c.VC_Q => "Q",
        c.VC_R => "R",
        c.VC_S => "S",
        c.VC_T => "T",
        c.VC_U => "U",
        c.VC_V => "V",
        c.VC_W => "W",
        c.VC_X => "X",
        c.VC_Y => "Y",
        c.VC_Z => "Z",

        c.VC_OPEN_BRACKET => "Open bracket",
        c.VC_CLOSE_BRACKET => "Close bracket",
        c.VC_BACK_SLASH => "Back slash",

        c.VC_COLON => "Colon",
        c.VC_SEMICOLON => "Semicolon",
        c.VC_QUOTE => "Quote",
        c.VC_QUOTEDBL => "Quotedbl",
        c.VC_ENTER => "Enter",

        c.VC_LESS => "Less",
        c.VC_GREATER => "Greater",
        c.VC_COMMA => "Comma",
        c.VC_PERIOD => "Period",
        c.VC_SLASH => "Slash",
        c.VC_NUMBER_SIGN => "Number sign",

        c.VC_OPEN_BRACE => "Open brace",
        c.VC_CLOSE_BRACE => "Close brace",

        c.VC_OPEN_PARENTHESIS => "Open parenthesis",
        c.VC_CLOSE_PARENTHESIS => "Close parenthesis",

        c.VC_SPACE => "Space",
        // End Alphanumeric Zone

        // Begin Edit Key Zone
        c.VC_PRINT_SCREEN => "Print screen",
        c.VC_SCROLL_LOCK => "Scroll lock",
        c.VC_PAUSE => "Pause",
        c.VC_CANCEL => "Cancel",

        c.VC_INSERT => "Insert",
        c.VC_DELETE => "Delete",
        c.VC_HOME => "Home",
        c.VC_END => "End",
        c.VC_PAGE_UP => "Page up",
        c.VC_PAGE_DOWN => "Page down",
        // End Edit Key Zone

        // Begin Cursor Key Zone
        c.VC_UP => "Up",
        c.VC_LEFT => "Left",
        c.VC_BEGIN => "Begin",
        c.VC_RIGHT => "Right",
        c.VC_DOWN => "Down",
        // End Cursor Key Zone

        // Begin Numeric Zone
        c.VC_NUM_LOCK => "Num lock",
        c.VC_KP_CLEAR => "Clear",

        c.VC_KP_DIVIDE => "Kp divide",
        c.VC_KP_MULTIPLY => "Kp multiply",
        c.VC_KP_SUBTRACT => "Kp subtract",
        c.VC_KP_EQUALS => "Kp equals",
        c.VC_KP_ADD => "Kp add",
        c.VC_KP_ENTER => "Kp enter",
        c.VC_KP_DECIMAL => "Kp decimal",
        c.VC_KP_SEPARATOR => "Kp separator",
        c.VC_KP_COMMA => "Kp comma",

        c.VC_KP_0 => "Kp 0",
        c.VC_KP_1 => "Kp 1",
        c.VC_KP_2 => "Kp 2",
        c.VC_KP_3 => "Kp 3",
        c.VC_KP_4 => "Kp 4",
        c.VC_KP_5 => "Kp 5",
        c.VC_KP_6 => "Kp 6",
        c.VC_KP_7 => "Kp 7",
        c.VC_KP_8 => "Kp 8",
        c.VC_KP_9 => "Kp 9",

        c.VC_KP_END => "Kp end",
        c.VC_KP_DOWN => "Kp down",
        c.VC_KP_PAGE_DOWN => "Kp page down",
        c.VC_KP_LEFT => "Kp left",
        c.VC_KP_BEGIN => "Kp begin",
        c.VC_KP_RIGHT => "Kp right",
        c.VC_KP_HOME => "Kp home",
        c.VC_KP_UP => "Kp up",
        c.VC_KP_PAGE_UP => "Kp page up",
        c.VC_KP_INSERT => "Kp insert",
        c.VC_KP_DELETE => "Kp delete",
        // End Numeric Zone

        // Begin Modifier and Control Keys
        c.VC_SHIFT_L => "Shift l",
        c.VC_SHIFT_R => "Shift r",
        c.VC_CONTROL_L => "Control l",
        c.VC_CONTROL_R => "Control r",
        c.VC_ALT_L => "Alt l",
        c.VC_ALT_R => "Alt r",
        c.VC_ALT_GRAPH => "Alt graph",
        c.VC_META_L => "Meta l",
        c.VC_META_R => "Meta r",
        c.VC_CONTEXT_MENU => "Context menu",
        // End Modifier and Control Keys

        // Begin Shortcut Keys
        c.VC_POWER => "Power",
        c.VC_SLEEP => "Sleep",
        c.VC_WAKE => "Wake",

        c.VC_MEDIA_PLAY => "Media play",
        c.VC_MEDIA_STOP => "Media stop",
        c.VC_MEDIA_PREVIOUS => "Media previous",
        c.VC_MEDIA_NEXT => "Media next",
        c.VC_MEDIA_SELECT => "Media select",
        c.VC_MEDIA_EJECT => "Media eject",

        //c.VC_VOLUME_MUTE => "Volume mute",
        c.VC_VOLUME_DOWN => "Volume down",
        c.VC_VOLUME_UP => "Volume up",

        c.VC_APP_BROWSER => "App browser",
        c.VC_APP_CALCULATOR => "App calculator",
        c.VC_APP_MAIL => "App mail",
        c.VC_APP_MUSIC => "App music",
        c.VC_APP_PICTURES => "App pictures",

        c.VC_BROWSER_SEARCH => "Browser search",
        c.VC_BROWSER_HOME => "Browser home",
        c.VC_BROWSER_BACK => "Browser back",
        c.VC_BROWSER_FORWARD => "Browser forward",
        c.VC_BROWSER_STOP => "Browser stop",
        c.VC_BROWSER_REFRESH => "Browser refresh",
        c.VC_BROWSER_FAVORITES => "Browser favorites",
        // End Shortcut Keys

        // Begin European Language Keys
        c.VC_CIRCUMFLEX => "Circumflex",
        c.VC_DEAD_GRAVE => "Dead grave",
        c.VC_DEAD_ACUTE => "Dead acute",
        c.VC_DEAD_CIRCUMFLEX => "Dead circumflex",
        c.VC_DEAD_TILDE => "Dead tilde",
        c.VC_DEAD_MACRON => "Dead macron",
        c.VC_DEAD_BREVE => "Dead breve",
        c.VC_DEAD_ABOVEDOT => "Dead abovedot",
        c.VC_DEAD_DIAERESIS => "Dead diaeresis",
        c.VC_DEAD_ABOVERING => "Dead abovering",
        c.VC_DEAD_DOUBLEACUTE => "Dead doubleacute",
        c.VC_DEAD_CARON => "Dead caron",
        c.VC_DEAD_CEDILLA => "Dead cedilla",
        c.VC_DEAD_OGONEK => "Dead ogonek",
        c.VC_DEAD_IOTA => "Dead iota",
        c.VC_DEAD_VOICED_SOUND => "Dead voiced sound",
        c.VC_DEAD_SEMIVOICED_SOUND => "Dead semivoiced sound",
        // End European Language Keys

        // Begin Asian Language Keys
        c.VC_KATAKANA => "Katakana",
        c.VC_KANA => "Kana",
        c.VC_KANA_LOCK => "Kana lock",

        c.VC_KANJI => "Kanji",
        c.VC_HIRAGANA => "Hiragana",

        c.VC_ACCEPT => "Accept",
        c.VC_CONVERT => "Convert",
        c.VC_COMPOSE => "Compose",
        c.VC_INPUT_METHOD_ON_OFF => "Input method on off",

        c.VC_ALL_CANDIDATES => "All candidates",
        c.VC_ALPHANUMERIC => "Alphanumeric",
        c.VC_CODE_INPUT => "Code input",
        c.VC_FULL_WIDTH => "Full width",
        c.VC_HALF_WIDTH => "Half width",
        c.VC_NONCONVERT => "Nonconvert",
        c.VC_PREVIOUS_CANDIDATE => "Previous candidate",
        c.VC_ROMAN_CHARACTERS => "Roman characters",

        c.VC_UNDERSCORE => "Underscore",
        // End Asian Language Keys

        // Begin Sun Keys
        c.VC_SUN_HELP => "Sun help",

        c.VC_SUN_STOP => "Sun stop",
        c.VC_SUN_PROPS => "Sun props",
        c.VC_SUN_FRONT => "Sun front",
        c.VC_SUN_OPEN => "Sun open",
        //c.VC_SUN_FIND => "Sun find",
        c.VC_SUN_AGAIN => "Sun again",
        c.VC_SUN_UNDO => "Sun undo",
        c.VC_SUN_COPY => "Sun copy",
        c.VC_SUN_PASTE => "Sun paste",
        c.VC_SUN_CUT => "Sun cut",
        // End Sun Keys

        c.VC_UNDEFINED => "Undefined",
        // End Virtual Key Codes

        else => "Undefined",
    };
}
