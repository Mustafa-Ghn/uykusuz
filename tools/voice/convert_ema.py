#!/usr/bin/env python3
"""EMA Lightning (ema.pt + decoder.pt) to four Core ML programs, with a parity check against PyTorch.

    convert_ema.py <folder holding ema_lightning/> <folder with ema.pt and decoder.pt> <out dir>

    python 3.12, torch 2.7, coremltools 9.0, numpy < 2.3. ema-lightning 1.1.2 for model.py and decoder.py.

The sampling loop of ema_lightning.model.Acoustic is cut where the app can run the arithmetic itself:

    text    ids [1, L] int32                     -> h [1, L, 224], dur [1, L]
    align   h, cg [1, L], fg [1, T], allow [1, T, L] -> cond [1, T, 224]
    step    x [1, T, 64], cond, t [1], pos [1, T]    -> x1 [1, T, 64]  (x + (1 - t) * backbone)
    decode  z [1, 64, F]                         -> audio [1, F * 1920 + 8]  (the app keeps the first F * 1920)

Batch is always 1 and nothing is padded, so every mask of the PyTorch code is all ones and goes away. The
positions the aligner needs (letter and frame positions, which letters a frame may read) need only a few sums,
so the app computes them; that leaves the graphs free of dynamically sized scatters. Reshapes use -1 throughout
so that the lengths stay flexible.
"""
import argparse
import math
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

parser = argparse.ArgumentParser()
parser.add_argument("package")
parser.add_argument("weights")
parser.add_argument("out")
args = parser.parse_args()
# The two model files need only torch; the package's __init__ would also pull in its downloader and normalizer.
sys.path.insert(0, f"{args.package}/ema_lightning")

import coremltools as ct  # noqa: E402
from decoder import load_decoder  # noqa: E402
from model import apply_rope, load_acoustic, rope  # noqa: E402

torch.manual_seed(0)
acoustic = load_acoustic(f"{args.weights}/ema.pt", "cpu")
decoder = load_decoder(f"{args.weights}/decoder.pt", "cpu")
OUT = Path(args.out)
OUT.mkdir(parents=True, exist_ok=True)


def group_norm(x, norm):
    """masked_group_norm with every position real."""
    mean = x.mean((1, 2), keepdim=True)
    var = ((x - mean) ** 2).mean((1, 2), keepdim=True)
    return (x - mean) / torch.sqrt(var + norm.eps) * norm.weight[None, :, None] + norm.bias[None, :, None]


class TextGraph(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, ids):
        text = self.m.text
        x = text.emb(ids)
        for block in text.conv:
            y = block.norm(block.dw(x.transpose(1, 2)).transpose(1, 2))
            x = x + block.gamma * block.pw2(F.gelu(block.pw1(y)))
        h = text.norm(x)
        dur = self.m.chardur
        x = group_norm(F.silu(dur.net[0](h.transpose(1, 2))), dur.net[2])
        x = group_norm(F.silu(dur.net[4](x)), dur.net[6])
        log_d = dur.out(x.transpose(1, 2)).squeeze(-1)
        return h, (torch.exp(log_d.clamp(max=6.0)) - 1.0).clamp(min=1e-3)


class AlignGraph(nn.Module):
    def __init__(self, a):
        super().__init__()
        self.a = a

    def forward(self, h, cg, fg, allow):
        a = self.a
        q = a.q(a.frame_q).expand(1, fg.shape[1], -1).reshape(1, -1, a.h, a.dh).transpose(1, 2)
        k = a.k(h).reshape(1, -1, a.h, a.dh).transpose(1, 2)
        v = a.v(h).reshape(1, -1, a.h, a.dh).transpose(1, 2)
        q = apply_rope(q, *(t[:, None] for t in rope(fg * a.pos_scale, a.dh)))
        k = apply_rope(k, *(t[:, None] for t in rope(cg * a.pos_scale, a.dh)))
        logits = (q @ k.transpose(-2, -1)) / math.sqrt(a.dh) * a.log_temp.exp()
        sig2 = (a.log_sigma.exp() ** 2).reshape(1, a.h, 1, 1)
        dist2 = ((fg[:, :, None] - cg[:, None, :]) ** 2)[:, None]
        logits = logits - a.bias_w.reshape(1, a.h, 1, 1) * dist2 / (2 * sig2)
        gate = allow[:, None]
        attn = (logits * gate + (1.0 - gate) * -1e4).softmax(-1) * gate
        return a.o((attn @ v).transpose(1, 2).reshape(1, -1, h.shape[2]))


class StepGraph(nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def attention(self, attn, x, cos, sin):
        D = x.shape[2]
        q, k, v = (t.reshape(1, -1, attn.h, attn.dh).transpose(1, 2) for t in attn.qkv(x).chunk(3, -1))
        q, k = apply_rope(q, cos, sin), apply_rope(k, cos, sin)
        w = (q @ k.transpose(-2, -1)) / math.sqrt(attn.dh)
        y = w.softmax(-1) @ v
        return attn.proj(y.transpose(1, 2).reshape(1, -1, D))

    def forward(self, x0, cond, t, pos):
        m = self.m
        cos, sin = rope(pos, m.dh)
        c = m.t_embed(t)
        bc = m.ada_shared(c).reshape(-1, 6, m.d)
        x = m.in_proj(x0) + cond
        for block in m.blocks:
            sa, ga, aa, sf, gf, af = (s.unsqueeze(1) for s in (bc + block.ada_offset[None]).unbind(1))
            x = x + aa * self.attention(block.attn, block.n1(x) * (1 + ga) + sa, cos, sin)
            x = x + af * block.ff(block.n2(x) * (1 + gf) + sf)
        s, g = m.ada_out(c).chunk(2, -1)
        v = m.out_proj(m.norm_out(x) * (1 + g.unsqueeze(1)) + s.unsqueeze(1))
        return x0 + (1 - t) * v


class DecodeGraph(nn.Module):
    def __init__(self, d):
        super().__init__()
        self.d = d

    def forward(self, z):
        d = self.d
        x = d.pre(z)
        for i, up in enumerate(d.ups):
            x = up(F.leaky_relu(x, 0.1))
            x = sum(b(x) for b in d.blocks[i * d.nk:(i + 1) * d.nk]) / d.nk
        return torch.tanh(d.post(F.leaky_relu(x)))[:, 0]


# ---- real inputs, by the original code, as the parity reference ---------------------------------------------------
TEXT = "ridmi dosyasını güncelledim, komiti meyn dalına puşladım. klod kod hukları çalışıyor."
ids_list = [acoustic.stoi.get(ch, 1) for ch in TEXT]
starts = [i for i, ch in enumerate(TEXT) if ch != " " and (i == 0 or TEXT[i - 1] == " ")] or [0]
bounds = [0] + starts[1:] + [len(TEXT)]
cw_list, wstart_list = [], []
for w, (a, b) in enumerate(zip(bounds, bounds[1:])):
    cw_list += [w] * (b - a)
    wstart_list += [a] * (b - a)
ids = torch.tensor([ids_list])
cw = torch.tensor([cw_list])
wstart = torch.tensor([wstart_list])
mask = ids != 0
with torch.no_grad():
    ref_h, ref_dur = acoustic.text_stage(ids, mask)
counts = torch.zeros_like(ref_dur).scatter_add_(1, cw, ref_dur).round().clamp(1, 250).long()[0, : int(cw[0, -1]) + 1]
frames = int(counts.sum())
fw = torch.repeat_interleave(torch.arange(counts.numel()), counts)[None]
fp = ((torch.arange(frames) - (counts.cumsum(0) - counts)[fw[0]]).double() / counts[fw[0]].double()).float()[None]
fmask = torch.ones(1, frames, dtype=torch.bool)
noise = torch.randn((len(acoustic.times), frames, acoustic.latent_dim), generator=torch.Generator().manual_seed(0))[None]
with torch.no_grad():
    ref_latents = acoustic.sound_stage(ref_h, ref_dur, mask, cw, wstart, fw, fp, fmask, noise)
    ref_audio = decoder(ref_latents.transpose(1, 2))

# The positions the app will compute.
c = ref_dur.clamp(min=1e-4)
done = c.cumsum(-1)
before = done - c
total = torch.zeros_like(c).scatter_add_(1, cw, c).gather(1, cw)
cp = ((done - before.gather(1, wstart) - 0.5 * c) / total.clamp(min=1e-8)).clamp(0.0, 1.0)
wlen = torch.zeros(1, int(cw.max()) + 1).scatter_add_(1, cw, torch.ones_like(c)).clamp(min=1.0)
woff = wlen.cumsum(-1) - wlen
cg = woff.gather(1, cw) + cp * wlen.gather(1, cw)
fg = woff.gather(1, fw) + fp * wlen.gather(1, fw)
rel = cw[:, None, :] - fw[:, :, None]
allow = ((rel >= -acoustic.aligner.lookback) & (rel <= acoustic.aligner.lookahead)).float()
pos = torch.arange(frames).float()[None]

text_graph, align_graph, step_graph, decode_graph = TextGraph(acoustic).eval(), AlignGraph(acoustic.aligner).eval(), StepGraph(acoustic).eval(), DecodeGraph(decoder).eval()
with torch.no_grad():
    h2, dur2 = text_graph(ids)
    cond2 = align_graph(h2, cg, fg, allow)
    x = noise[:, 0]
    for k, t in enumerate(acoustic.times):
        x1 = step_graph(x, cond2, torch.tensor([t]), pos)
        if k + 1 < len(acoustic.times):
            x = (1 - acoustic.times[k + 1]) * noise[:, k + 1] + acoustic.times[k + 1] * x1
    audio2 = decode_graph(x1.transpose(1, 2))


def report(name, a, b):
    a, b = a.numpy().astype(np.float64), b.numpy().astype(np.float64)
    if a.shape != b.shape:  # the upsampling by 5 leaves 8 extra samples at the end, which the app drops
        b = b[..., : a.shape[-1]]
    print(f"  {name:8} max diff {np.abs(a - b).max():.2e}  rel {np.abs(a - b).max() / (np.abs(a).max() + 1e-12):.2e}", flush=True)


print("graphs vs original PyTorch:")
report("h", ref_h, h2)
report("dur", ref_dur, dur2)
report("latents", ref_latents, x1)
report("audio", ref_audio, audio2)

# ---- conversion ---------------------------------------------------------------------------------------------------
flex = lambda low=1: ct.RangeDim(lower_bound=low, upper_bound=3000, default=64)  # noqa: E731
PRECISION = ct.precision.FLOAT32


def convert(name, graph, example, inputs, outputs):
    print(f"converting {name}", flush=True)
    with torch.no_grad():
        traced = torch.jit.trace(graph, example, strict=False, check_trace=False)
    model = ct.convert(
        traced,
        inputs=inputs,
        outputs=[ct.TensorType(name=o) for o in outputs],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=PRECISION,
        compute_units=ct.ComputeUnit.CPU_ONLY,
        skip_model_load=False,
    )
    path = OUT / f"{name}.mlpackage"
    if path.exists():
        shutil.rmtree(path)
    model.save(str(path))
    return model


models = {}
models["text"] = convert("text", text_graph, (ids,), [ct.TensorType(name="ids", shape=ct.Shape((1, flex())), dtype=np.int32)], ["h", "dur"])
models["align"] = convert(
    "align", align_graph, (h2, cg, fg, allow),
    [
        ct.TensorType(name="h", shape=ct.Shape((1, flex(), 224)), dtype=np.float32),
        ct.TensorType(name="cg", shape=ct.Shape((1, flex())), dtype=np.float32),
        ct.TensorType(name="fg", shape=ct.Shape((1, flex())), dtype=np.float32),
        ct.TensorType(name="allow", shape=ct.Shape((1, flex(), flex())), dtype=np.float32),
    ], ["cond"])
models["step"] = convert(
    "step", step_graph, (noise[:, 0], cond2, torch.tensor([0.25]), pos),
    [
        ct.TensorType(name="x", shape=ct.Shape((1, flex(), 64)), dtype=np.float32),
        ct.TensorType(name="cond", shape=ct.Shape((1, flex(), 224)), dtype=np.float32),
        ct.TensorType(name="t", shape=ct.Shape((1,)), dtype=np.float32),
        ct.TensorType(name="pos", shape=ct.Shape((1, flex())), dtype=np.float32),
    ], ["x1"])
models["decode"] = convert(
    "decode", decode_graph, (ref_latents.transpose(1, 2),),
    [ct.TensorType(name="z", shape=ct.Shape((1, 64, flex())), dtype=np.float32)], ["audio"])

# ---- Core ML against the same graphs in PyTorch, stage by stage ----------------------------------------------------
# A whole run differs a little more than any stage: the four steps magnify rounding. The comparison that says whether
# it is the same voice is on real audio: with torch's noise, a run in the app came out at 35 dB waveform SNR and 0.2 dB
# log-mel distance from the published engine, against 4.3 dB between two seeds.
print("Core ML vs PyTorch, stage by stage:")
with torch.no_grad():
    out = models["text"].predict({"ids": ids.numpy().astype(np.int32)})
    report("h", h2, torch.tensor(out["h"]))
    report("dur", dur2, torch.tensor(out["dur"]))
    report("cond", cond2, torch.tensor(models["align"].predict({"h": h2.numpy(), "cg": cg.numpy(), "fg": fg.numpy(), "allow": allow.numpy()})["cond"]))
    for t in acoustic.times:
        ml = models["step"].predict({"x": noise[:, 0].numpy(), "cond": cond2.numpy(), "t": np.array([t], np.float32), "pos": pos.numpy()})["x1"]
        report(f"t={t}", step_graph(noise[:, 0], cond2, torch.tensor([t]), pos), torch.tensor(ml))
    z = ref_latents.transpose(1, 2)
    report("audio", decode_graph(z), torch.tensor(models["decode"].predict({"z": z.numpy()})["audio"]))

for name in models:
    subprocess.run(["xcrun", "coremlcompiler", "compile", str(OUT / f"{name}.mlpackage"), str(OUT)], check=True, capture_output=True)
    shutil.rmtree(OUT / f"{name}.mlpackage")
print("compiled into", OUT)
