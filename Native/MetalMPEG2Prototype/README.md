# Metal MPEG-2 reconstruction prototype

Standalone macOS Swift package for the GPU reconstruction portion of a future
hybrid MPEG-2 decoder. It runs real Metal compute work without launching a video
player. It is deliberately outside both app targets and does not change VLC,
Plex, Live TV tuning, signing identities, preferences, or engine selection.

This is **not a complete MPEG-2 decoder** and cannot open a transport stream,
elementary stream, HLS URL, or media file. Do not wire it into playback yet.

## Run

From the repository root on a Mac with a Metal GPU and the Xcode toolchain:

```sh
swift test --package-path Native/MetalMPEG2Prototype -c release
swift run --package-path Native/MetalMPEG2Prototype -c release mpeg2-metal-benchmark
```

The package has no external dependencies. The Metal source is copied as a Swift
package resource and compiled by Metal at initialization. Initial shader
compilation is excluded from benchmark timing. Build products stay in the
package's ignored `.build/` directory. No network access, media credentials,
Plex requests, GUI, or app launch is involved.

## Implemented boundary

`ReconstructionInput` describes a single tightly packed 8-bit Y, Cb, or Cr plane:

- Dimensions are multiples of eight, at most 2048 in either direction.
- Coefficients are signed, inverse-quantized values in natural 8x8 order, with
  MPEG-2 DC scaling, saturation and mismatch control **already applied**.
- Blocks are raster ordered. Each has intra, forward, backward, or bidirectional
  prediction. Vectors are half-pixel units in the current plane. A future adapter
  must derive chroma vectors correctly rather than reuse luma vectors unchanged.
- Reference buffers have exactly the plane dimensions. Edge samples are clamped.
  Negative odd vectors use floor division. Half-pixel filtering and averaging
  use integer rounding; the final residual plus predictor saturates to 0...255.
- Intra IDCT produces absolute pixel values; no JPEG-style +128 offset is added.

`Reconstruct.metal` uses one 64-thread group per block. A separable floating-point
8x8 inverse DCT passes through threadgroup memory, followed by integer motion
compensation and output. The CPU oracle uses Double precision. GPU float
rounding can differ by one sample value; this is not an IEEE 1180 conformance
claim. Prepared jobs reuse shared buffers and are synchronous, single-caller
objects. They retain their reconstructor and cannot be submitted to a different
instance. A job's `pixels()` is only meaningful after a successful `run`.

The coefficient buffer is approximately 4 MiB for padded HD luma, plus references,
output, predictions and a small transform table. Shared memory avoids a separate
PCIe transfer, but preparing a job still copies its inputs. The benchmark reports
that setup separately. Actual streaming needs a bounded buffer pool, reference
frame ownership and asynchronous scheduling before this can be economical.

## Automated checks

Eight XCTest cases execute the Metal kernel on the actual local GPU. They check
known DC and AC results, intra scaling, saturation, all half-pixel directions
including negative vectors and boundaries, backward/bidirectional prediction,
residual addition, deterministic mixed AC blocks against the Double oracle,
input validation, repeated dispatch, and job ownership. Analytic and known-value
checks supplement CPU/GPU comparisons so agreement alone is not the oracle.

Metal absence/failure fails the suite rather than silently skipping GPU checks.
These synthetic checks do not cover real broadcast bitstreams or codec fidelity.

## Initial measurement

2026-10-25, Apple M5, release build, 60 iterations after five warmup dispatches:

| Measurement | Result |
| --- | --- |
| Workload | 1920x1088 padded luma; mixed prediction modes; sparse AC coefficients |
| Buffer preparation | 0.912 ms |
| Mean GPU execution | 1.101 ms/plane |
| Mean submission, execution and synchronous wait | 1.421 ms/plane |
| Scalar Double CPU oracle, one plane | 26.735 ms |
| Maximum sample difference for benchmark | 0 |

This is a repeated synthetic plane, with reusable buffers and reference data.
It excludes entropy parsing, inverse quantization, chroma, field prediction,
deinterlacing, audio, renderer integration and per-frame input updates. The CPU
oracle is intentionally simple and is **not** representative of optimized VLC
or FFmpeg decoding. Do not interpret these numbers as an end-to-end frame rate,
a speedup over the running app, reduced power, or measured Live TV CPU savings.
Other workloads, GPU contention and thermal conditions may change results.

## Next checkpoints

1. Add a bounded elementary-stream parser or an audited adapter that emits the
   coefficient/prediction contract before CPU IDCT. A stock decoder returning
   already decoded pixels would not offload reconstruction. Start with a small
   supported progressive MPEG-2 Main Profile subset and explicitly reject other
   syntax; include reproducible, legally distributable encoded fixtures.
2. Compare complete Y/Cb/Cr frames against an independent established decoder,
   including reference reordering, skipped blocks, alternate scans, quantization
   matrices, mismatch control and resolution changes. Test truncated input.
3. Implement interlaced frame/field prediction, field DCT, dual-prime modes,
   chroma positioning and field-order behavior before testing broadcast 1080i.
   Current per-block frame prediction cannot represent those modes.
4. Measure CPU time, energy, latency and total throughput against the same
   optimized CPU decoder on identical media, including uploads and all planes.
5. Only then consider an opt-in `PlaybackEngine` or VLC module integration,
   retaining subtitles, audio synchronization, copy-only delivery and fallback.

No production playback selection is changed by this experiment. tvOS is outside
its scope.

## References and provenance

The implementation here is original, not copied from Mesa or libmpeg2.
[Mesa's Gallium MPEG-1/2 reconstruction source](https://android.googlesource.com/platform/external/mesa3d/+/ef0b6f8262d691287dfd7a90b1e166b39eed960b/src/gallium/auxiliary/vl/vl_mpeg12_decoder.c)
is a useful architectural reference for splitting bitstream handling, inverse
DCT and motion compensation. It is not a drop-in Metal library.
[Apple's Metal compute documentation](https://developer.apple.com/documentation/metal/performing-calculations-on-a-gpu)
describes the compute pipeline used by this harness. Any future imported parser
or shader code needs its own license review and retained notices.
