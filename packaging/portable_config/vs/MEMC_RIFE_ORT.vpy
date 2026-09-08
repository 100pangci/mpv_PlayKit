### RIFE v4.6 interpolation through the bundled ONNX Runtime provider.

import os
from fractions import Fraction

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f
from k7sfunc._external import vsmlrt

core.num_threads = k7f.vs_t_dft
clip = video_in

H_Pre = 1440
Fps_Num = 2
Fps_Den = 1
Gpu = 0
Gpu_T = 2
Lk_Fmt = False

ret = k7f.FPS_CTRL(clip, fps_in=container_fps, fps_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
fmt_in = clip.format.id
colorlv = getattr(clip.get_frame(0).props, "_ColorRange", 0)
clip = core.resize.Bilinear(clip, format=vs.RGBS, matrix_in_s="709")
work_width = clip.width
work_height = clip.height

pad_right = (32 - clip.width % 32) % 32
pad_bottom = (32 - clip.height % 32) % 32
if pad_right or pad_bottom:
    clip = core.std.AddBorders(clip, right=pad_right, bottom=pad_bottom)

backend_name = os.environ.get("MPV_LAZY_VS_BACKEND", "cpu").lower()
if backend_name == "cuda":
    backend = vsmlrt.BackendV2.ORT_CUDA(
        device_id=Gpu,
        num_streams=Gpu_T,
        fp16=False,
    )
elif backend_name == "cpu":
    backend = vsmlrt.BackendV2.ORT_CPU(num_streams=Gpu_T)
else:
    raise vs.Error("MPV_LAZY_VS_BACKEND must be either cpu or cuda")

clip = vsmlrt.RIFE(
    clip,
    multi=Fraction(Fps_Num, Fps_Den),
    model=vsmlrt.RIFEModel.v4_6,
    backend=backend,
    video_player=True,
)
if pad_right or pad_bottom:
    clip = core.std.CropAbs(clip, width=work_width, height=work_height)
clip = core.resize.Bilinear(
    clip,
    format=fmt_in,
    matrix_s="709",
    range=1 if colorlv == 0 else None,
)

clip.set_output()
