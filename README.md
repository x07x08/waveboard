This is a rewrite of the old [waveboard](https://github.com/x07x08/waveboard_go) project to make it cross-platform
and easier to work with for the end-user.

The application is now a command line interface with a web UI.

Tested on Fedora 40 and Windows 10. Unsure about Mac support.

# Installation

1. Get a [binary](https://github.com/x07x08/waveboard/releases) or preferably compile one yourself
2. Put the [`src/web`](https://github.com/x07x08/waveboard/tree/main/src/web) folder in the same directory as the binary

# Features

* Global keyboard hotkeys / shortcuts for sounds
* In-memory playback
* Source Engine chat commands
* Whitelist and blacklist
* Audio queue
* Video downloader and converter
* Text-To-Speech using [`SAPI`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms720592(v=vs.85)) on Windows
* A barebones [JavaScript API](https://github.com/x07x08/waveboard/blob/a1e42206e7b4476b106a7ab0d544d91c0b422a61/src/web/index.html#L531)
* Supported formats : .ogg (opus and vorbis), .mp3, .wav, .flac

# Screenshots

<table>
	<tr>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/logoutput.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Log tab
			</p>
		</td>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/audio.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Audio tab
			</p>
		</td>
	</tr>
	<tr>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/downloader.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Downloader tab
			</p>
		</td>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/loginput.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Log watch tab
			</p>
		</td>
	</tr>
	<tr>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/queue.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Queue tab
			</p>
		</td>
		<td align = "center">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/tts.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Text-To-Speech tab
			</p>
		</td>
	</tr>
	<tr>
		<td align = "center" colspan = "2">
			<img src="https://github.com/x07x08/waveboard/blob/main/screenshots/settings.PNG?raw=true" width = "100%" height = "100%">
			<p>
				Settings tab
			</p>
		</td>
	</tr>
</table>

# Requirements

1. A virtual audio cable ([`Virtual-Audio-Cable`](https://vac.muzychenko.net) or [`VB-Audio Cable`](https://vb-audio.com/Cable/))
	- Follow [this](https://www.youtube.com/watch?v=fi5I6bzy2f8), [the text](https://github.com/fuck-shithub/STARK#how-to-set-up) tutorial or find another tutorial to install the drivers.
	- You may need to disable ["Driver Signature Enforcement"](https://www.youtube.com/watch?v=71YAIw7_-kg) during the installation process.

2. An audio directory (it is searched recursively)
	- It will be used by the program to play tracks and download videos.

3. <sup>*Optional*</sup> A log file within your Source Engine game using the [`con_logfile <file>`](https://developer.valvesoftware.com/wiki/List_of_console_scripting_commands) command or the [`-condebug`](https://developer.valvesoftware.com/wiki/Command_line_options) launch option
	- This is for the log watching feature, which allows interaction with the application using the game's chat.
	- You can use an `autoexec.cfg` file for easier management.

4. <sup>*Optional*</sup> [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org/download.html) binaries for video downloading and conversion

    The yt-dlp binary needs to be named "ytdl" or "ytdl.exe"

# Compiling

You will need :

* [Zig](https://github.com/ziglang/zig)

<dl>
	<dt>
		Windows :
	</dt>
	<dd>
		Nothing else
	</dd>
</dl>

<dl>
	<dt>
		Linux :
	</dt>
	<dd>
		Check <a href="https://github.com/x07x08/waveboard/blob/main/build.zig">build.zig</a> for the required dependencies
	</dd>
</dl>

# Credits and libraries

* [STARK](https://github.com/axynos/STARK) - I've used it for a long time, but it is half broken and uses the disk to write raw audio data.

---

* [miniaudio](https://github.com/mackron/miniaudio)
* [libuiohook](https://github.com/kwhat/libuiohook) - evdev branch
* [nfd-extended](https://github.com/btzy/nativefiledialog-extended)
* [ogg-container](https://github.com/xiph/ogg)
* [opus](https://github.com/xiph/opus) and [opusfile](https://github.com/xiph/opusfile)
* [vorbis](https://github.com/nothings/stb/tree/master)

---

* [webui](https://github.com/webui-dev/zig-webui)
* [regex](https://github.com/tiehuis/zig-regex)
