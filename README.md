# MOV → MP4 in the macOS Context Menu

A Finder Quick Action: **right-click a MOV file → Quick Actions → Convert MOV to MP4**. Depending on your macOS settings, the action is also available in the **Services** submenu.

MP4 files are saved in the same folder as the originals. Original files are preserved. If `video.mp4` already exists, the action creates `video (1).mp4`, then `video (2).mp4`. You can select multiple MOV files at once.

## Installation

1. FFmpeg is required. If it is not installed, install it with [Homebrew](https://brew.sh):

   ```sh
   brew install ffmpeg
   ```

2. Double-click `install.command`, or run the following from this folder:

   ```sh
   ./install.command
   ```

The action is installed for the current user only; `sudo` is not required. The conversion script is embedded in the workflow, so you can move this project folder after installation.

If the menu item does not appear immediately, close and reopen the Finder context menu. Also check **Finder → Services** and enable the action in macOS settings under **Keyboard → Keyboard Shortcuts → Services**. Quick Action settings vary by macOS version; see [Apple's guide](https://support.apple.com/guide/automator/aut73234890a/mac).

## Conversion Behavior

- H.264 and HEVC video is copied into MP4 without re-encoding, preserving video quality. HEVC uses the `hvc1` tag.
- Other video codecs, such as ProRes, are converted to H.264 (`CRF 18`, `preset fast`, `yuv420p`). Odd widths or heights are padded by one pixel for compatibility.
- Audio tracks are converted to AAC at 192 kbps per track. Videos without audio are supported.
- The first video stream and all audio tracks are included. Subtitles and MOV data tracks are omitted.
- Both `.mov` and `.MOV` extensions, spaces, and Unicode filenames are supported. Other extensions are skipped.
- System notifications mark the start and end of conversion. Errors are shown in a separate alert. Log file: `~/Library/Logs/MOV-to-MP4.log`.

Conversion options are described in the [FFmpeg documentation](https://ffmpeg.org/ffmpeg.html) and [codec documentation](https://ffmpeg.org/ffmpeg-codecs.html).

To run from Terminal:

```sh
./convert-mov-to-mp4.sh "/path/to/video.mov"
```

After editing the script, run `./install.command` again. Previous installations, including actions with an older localized name, are moved to `~/Library/Application Support/MOV-to-MP4/Backups/`.

## Uninstalling

In Finder, press **⌘⇧G**, open `~/Library/Services/`, and move **Convert MOV to MP4.workflow** to the Trash. Converted videos are preserved.
