% MATLAB equivalent of goertzel_q15 + TB (N=256, k_target=16)
clear; clc;

N = 256;
k_target = 16;
A = 0.7;

% --------- helper quantizers ----------
q15  = @(x) int32(max(min(round(x * 2^15),  32767), -32768));  % signed 16-bit range, stored in int32
q214 = @(x) int32(max(min(round(x * 2^14),  32767), -32768));  % signed 16-bit range, stored in int32

% arithmetic shift right for int32 (MATLAB uses arithmetic for negative with bitsra)
ashr = @(x, sh) bitsra(int32(x), sh);

% mul: Q2.14 * Q1.15 -> (shift 14) -> Q?.15 (like Verilog)
mul_q214_q115_to_q115 = @(a_q214, b_q115) ashr(int64(a_q214) .* int64(b_q115), 14);

% mul: Q1.15 * Q1.15 -> (shift 15) -> Q?.15
mul_q115_q115_to_q115 = @(a_q15, b_q115) ashr(int64(a_q15) .* int64(b_q115), 15);

% --------- coefficients for k_target ----------
w = 2*pi*k_target/N;

COEFF_2COS = q214(2*cos(w));   % Q2.14
COS_W      = q15(cos(w));      % Q1.15
SIN_W      = q15(sin(w));      % Q1.15

fprintf("Coeffs (hex): COEFF_2COS=%s  COS_W=%s  SIN_W=%s\n", ...
    dec2hex(typecast(int16(COEFF_2COS), 'uint16'),4), ...
    dec2hex(typecast(int16(COS_W),      'uint16'),4), ...
    dec2hex(typecast(int16(SIN_W),      'uint16'),4));

% --------- function: run one frame exactly like DUT ----------
run_goertzel_frame = @(x_q15) goertzel_frame_fixed( ...
    x_q15, N, COEFF_2COS, COS_W, SIN_W, ...
    mul_q214_q115_to_q115, mul_q115_q115_to_q115);

% --------- Frame 1: input sine at k=16 (should be BIG) ----------
k_in = 16;
n = 0:N-1;
x1 = A*sin(2*pi*k_in*n/N);
x1_q15 = q15(x1);   % input samples quantized like FPGA

[Xre1, Xim1, Xre1_q15, Xim1_q15] = run_goertzel_frame(x1_q15);

fprintf("\nFrame1 input k=%d\n", k_in);
fprintf("Xre(real)=%+.6f  Xim(real)=%+.6f\n", Xre1, Xim1);
fprintf("Xre(q15)=0x%s    Xim(q15)=0x%s\n", ...
    dec2hex(typecast(int16(Xre1_q15),'uint16'),4), ...
    dec2hex(typecast(int16(Xim1_q15),'uint16'),4));

% --------- Frame 2: input sine at k=20 (should be SMALL) ----------
k_in = 20;
x2 = A*sin(2*pi*k_in*n/N);
x2_q15 = q15(x2);

[Xre2, Xim2, Xre2_q15, Xim2_q15] = run_goertzel_frame(x2_q15);

fprintf("\nFrame2 input k=%d\n", k_in);
fprintf("Xre(real)=%+.6f  Xim(real)=%+.6f\n", Xre2, Xim2);
fprintf("Xre(q15)=0x%s    Xim(q15)=0x%s\n", ...
    dec2hex(typecast(int16(Xre2_q15),'uint16'),4), ...
    dec2hex(typecast(int16(Xim2_q15),'uint16'),4));

% --------- compare magnitudes (real-scale) ----------
mag1 = hypot(Xre1, Xim1);
mag2 = hypot(Xre2, Xim2);
fprintf("\nMagnitude compare: |X| frame1=%.6f  frame2=%.6f  ratio=%.2f\n", mag1, mag2, mag1/max(mag2,1e-12));

% ==================== local function ====================
function [Xre_real, Xim_real, Xre_q15, Xim_q15] = goertzel_frame_fixed( ...
    x_q15, N, COEFF_2COS, COS_W, SIN_W, mul_q214_q115_to_q115, mul_q115_q115_to_q115)

  v1 = int32(0);
  v2 = int32(0);

  % process N samples
  for i = 1:N
      x32 = int32(x_q15(i)); % sign-extended already in int32
      fb  = int32(mul_q214_q115_to_q115(COEFF_2COS, v1));
      v0  = int32(int64(x32) + int64(fb) - int64(v2));

      % update states
      v2 = v1;
      v1 = v0;
  end

  % After loop:
  % v1 now holds v(N-1), v2 holds v(N-2)
  cosv2 = int32(mul_q115_q115_to_q115(COS_W, v2));
  sinv2 = int32(mul_q115_q115_to_q115(SIN_W, v2));

  Xre32 = int32(int64(v1) - int64(cosv2));
  Xim32 = int32(sinv2);

  % Same as your DUT trunc16: take lower 16 bits (wrap)
  Xre_q15 = int16(bitand(uint32(Xre32), uint32(65535)));
  Xim_q15 = int16(bitand(uint32(Xim32), uint32(65535)));

  % For readable real numbers (Q1.15 interpretation of the 16-bit outputs)
  Xre_real = double(Xre_q15) / 2^15;
  Xim_real = double(Xim_q15) / 2^15;
end