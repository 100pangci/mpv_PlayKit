mpv-lazy Linux packages
=======================

The `-linux-config.tar.gz` archive contains the Linux-adjusted mpv configuration.
It starts from the common configuration in `packaging/portable_config` and
applies `packaging/linux.patch`; it does not include the mpv player itself.

The `-linux-vs.tar.gz` archive contains that configuration plus the x86_64
VapourSynth 79, K7sfunc 1.8.1, ONNX Runtime CPU, MVTools and selected model
files. It requires a host Python 3.12 or newer and a system mpv built with
VapourSynth support. Launch it with `bin/mpv-lazy` so the bundled VSScript
library and private configuration are selected:

    ./bin/mpv-lazy [mpv arguments]

The player and yt-dlp are intentionally not bundled. On Fedora/RHEL-like
systems, for example:

    sudo dnf install mpv yt-dlp

The configuration-only archive can instead be copied or linked to
`~/.config/mpv/`. It requires the user's own VapourSynth runtime and models.

The optional `-linux-vs-cuda.tar.gz` archive is an overlay for the matching
`-linux-vs.tar.gz` archive. Extract it into the same directory and launch
`bin/mpv-lazy-cuda`. An NVIDIA display driver is still required from the host.
