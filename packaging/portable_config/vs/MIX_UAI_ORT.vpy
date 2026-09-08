### AnimeJaNai x2 upscaling through the bundled ONNX Runtime provider.

import os

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f
from k7sfunc._external import vsmlrt

core.num_threads = k7f.vs_t_dft
clip = video_in

H_Pre = 720
H_Max = 1440
Model = "animejanaiV2L1.onnx"
Gpu = 0
Gpu_T = 2
Lk_Fmt = False

clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
fmt_in = clip.format.id
colorlv = getattr(clip.get_frame(0).props, "_ColorRange", 0)
clip = core.resize.Bilinear(clip, format=vs.RGBS, matrix_in_s="709")

ort_path = os.fsdecode(core.ort.Version()["path"])
model_path = os.path.join(os.path.dirname(ort_path), "models", Model)
if not os.path.isfile(model_path):
    raise vs.Error(f"Required model is missing: {model_path}")

backend_name = os.environ.get("MPV_LAZY_VS_BACKEND", "cpu").lower()
if backend_name == "cuda":
    backend = vsmlrt.BackendV2.ORT_CUDA(
        device_id=Gpu,
        num_streams=Gpu_T,
        fp16=True,
    )
elif backend_name == "cpu":
    backend = vsmlrt.BackendV2.ORT_CPU(num_streams=Gpu_T)
else:
    raise vs.Error("MPV_LAZY_VS_BACKEND must be either cpu or cuda")

clip = vsmlrt.inference(
    clips=clip,
    network_path=model_path,
    backend=backend,
    input_name="input",
)
clip = core.resize.Bilinear(
    clip,
    format=fmt_in,
    matrix_s="709",
    range=1 if colorlv == 0 else None,
)
clip = k7f.FMT_CTRL(clip, h_max=H_Max, fmt_pix=1 if Lk_Fmt else 0)

clip.set_output()
