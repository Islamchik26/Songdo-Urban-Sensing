function [sos, gain] = design_a_weighting(Fs)
%DESIGN_A_WEIGHTING  6th-order IIR A-weighting as a 3-biquad cascade.
%
%   [sos, gain] = songdo.acoustic.design_a_weighting(8000)
%
%   The analogue IEC 61672 A-weighting has four zeros at s = 0 and poles at
%   20.6 Hz (x2), 107.7 Hz, 737.9 Hz and 12194 Hz (x2). It is mapped to the
%   z-domain with the plain bilinear transform s = 2*Fs*(1 - z^-1)/(1 + z^-1).
%
%   sos  : 3x6 matrix, each row [b0 b1 b2 a0 a1 a2] with a0 = 1
%   gain : scalar that makes the cascade exactly 0 dB at 1 kHz
%
%   Accuracy at Fs = 8 kHz: within about 0.15 dB of the analytic curve up
%   to 2 kHz. Above about 3 kHz the bilinear mapping droops (-1.4 dB at
%   3 kHz, and the response is forced to zero at Nyquist), so the IEC
%   Class 1 tolerance cannot be met close to 4 kHz at this sample rate.

f1 = 20.598997;
f2 = 107.65265;
f3 = 737.86223;
f4 = 12194.217;
w1 = 2*pi*f1;  w2 = 2*pi*f2;  w3 = 2*pi*f3;  w4 = 2*pi*f4;

c = 2*Fs;

% Analogue sections: (n2 s^2 + n1 s + n0) / (s^2 + d1 s + d0)
num = [1, 0, 0;
       1, 0, 0;
       0, 0, w4^2];
den = [2*w1,   w1^2;
       w2+w3,  w2*w3;
       2*w4,   w4^2];

sos = zeros(3, 6);
for k = 1:3
    n2 = num(k, 1);  n1 = num(k, 2);  n0 = num(k, 3);
    d1 = den(k, 1);  d0 = den(k, 2);

    b = [n2*c^2 + n1*c + n0, -2*n2*c^2 + 2*n0, n2*c^2 - n1*c + n0];
    a = [c^2 + d1*c + d0,    -2*c^2 + 2*d0,    c^2 - d1*c + d0];

    sos(k, :) = [b/a(1), a/a(1)];
end

H1k  = songdo.acoustic.sos_response(sos, 1, 1000, Fs);
gain = 1/abs(H1k);
end
