#include <metal_stdlib>
using namespace metal;

// ABI: five packed 32-bit integers; mirrors BlockPrediction in Swift.
struct Prediction { int mode, forwardX, forwardY, backwardX, backwardY; };
struct Dimensions { uint width, height; };

int pixel(device const uchar *plane, int x, int y, constant Dimensions &d) {
    return plane[clamp(y, 0, int(d.height)-1)*d.width + clamp(x, 0, int(d.width)-1)];
}
int predict(device const uchar *plane, int x, int y, int dx, int dy, constant Dimensions &d) {
    // Floor division is essential for negative odd half-pixel motion vectors.
    int ix = int(floor(float(dx)*0.5f)), iy = int(floor(float(dy)*0.5f));
    int hx = dx - 2*ix, hy = dy - 2*iy;
    x += ix; y += iy;
    int a = pixel(plane,x,y,d);
    if (!hx && !hy) return a;
    if (!hy) return (a + pixel(plane,x+1,y,d) + 1)/2;
    if (!hx) return (a + pixel(plane,x,y+1,d) + 1)/2;
    return (a + pixel(plane,x+1,y,d) + pixel(plane,x,y+1,d) + pixel(plane,x+1,y+1,d) + 2)/4;
}

// One threadgroup per 8x8 block, one thread per output pixel. Coefficients are
// natural-order, inverse-quantized MPEG-2 values INCLUDING intra DC scaling and
// mismatch control. Intra IDCT yields absolute pixels (no JPEG-style +128).
kernel void reconstruct(device const short *coefficients [[buffer(0)]],
                        device const Prediction *predictions [[buffer(1)]],
                        device const uchar *forward [[buffer(2)]],
                        device const uchar *backward [[buffer(3)]],
                        device uchar *output [[buffer(4)]],
                        device const float *basis [[buffer(5)]],
                        constant Dimensions &d [[buffer(6)]],
                        uint block [[threadgroup_position_in_grid]],
                        uint lane [[thread_index_in_threadgroup]]) {
    threadgroup float horizontal[64];
    uint x = lane % 8, y = lane / 8;
    float row = 0;
    for (uint u=0; u<8; ++u)
        row += float(coefficients[block*64 + y*8 + u]) * basis[x*8+u];
    horizontal[lane] = row;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float value = 0;
    for (uint v=0; v<8; ++v) value += horizontal[v*8+x] * basis[y*8+v];
    int px = int((block % (d.width/8))*8 + x);
    int py = int((block / (d.width/8))*8 + y);
    Prediction p = predictions[block];
    int prediction = 0;
    if (p.mode == 1 || p.mode == 3) prediction = predict(forward,px,py,p.forwardX,p.forwardY,d);
    if (p.mode == 2) prediction = predict(backward,px,py,p.backwardX,p.backwardY,d);
    if (p.mode == 3) prediction = (prediction + predict(backward,px,py,p.backwardX,p.backwardY,d) + 1)/2;
    output[py*d.width+px] = uchar(clamp(int(floor(value+0.5f)) + prediction, 0, 255));
}
