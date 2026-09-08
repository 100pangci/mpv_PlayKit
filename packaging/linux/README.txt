mpv-lazy Linux configuration
============================

This archive contains the Linux-adjusted mpv configuration. It starts from the
59 common configuration files in `packaging/portable_config` and applies the
Linux changes from `packaging/linux.patch`; it does not include the mpv player
itself.
Install mpv and any optional VapourSynth/runtime dependencies with your
distribution's package manager. On Fedora/RHEL-like systems, for example:

    sudo dnf install mpv yt-dlp

Then copy or link `portable_config` to `~/.config/mpv/` (or to the location
used by your mpv installation).
