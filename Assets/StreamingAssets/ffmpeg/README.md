# FFmpeg

Place `ffmpeg.exe` here:

`Assets/StreamingAssets/ffmpeg/bin/ffmpeg.exe`

The runtime recorder searches this location first, then falls back to `ffmpeg` on PATH. If neither is available, it records PNG frames instead of MP4.

