"""Small auditable LGPL FFmpeg patch; no changes to parsing or MC semantics."""
from pathlib import Path
import sys
root = Path(sys.argv[1])
p = root / 'libavcodec/idctdsp.c'
s = p.read_text()
marker = '    ff_init_scantable_permutation(c->idct_permutation,'
replacement = '''    // Cinerama experimental MPEG-2 IDCT. Configure before scan permutation.
    extern void cinerama_mpeg2_idct_configure(void *, AVCodecContext *);
    if (avctx->codec_id == AV_CODEC_ID_MPEG2VIDEO && avctx->opaque)
        cinerama_mpeg2_idct_configure(c, avctx);

'''
if 'cinerama_mpeg2_idct_configure' not in s:
    assert s.count(marker) == 1
    p.write_text(s.replace(marker,replacement+marker))
p = root / 'libavcodec/mpegvideo_dec.c'
s = p.read_text()
marker = 'void ff_mpeg_draw_horiz_band(MpegEncContext *s, int y, int h)\n{'
replacement = '''
    // Commit before a completed row can be used as a prediction reference,
    // including first-field references during interlaced decoding.
    extern void cinerama_mpeg2_idct_flush(void *);
    if (s->avctx->codec_id == AV_CODEC_ID_MPEG2VIDEO && s->avctx->opaque)
        cinerama_mpeg2_idct_flush(s->avctx->opaque);
'''
if 'cinerama_mpeg2_idct_flush' not in s:
    assert s.count(marker) == 1
    p.write_text(s.replace(marker,marker+replacement))
