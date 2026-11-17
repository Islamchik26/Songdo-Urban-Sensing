function [b, a] = design_notch(f0, Q, Fs)
%DESIGN_NOTCH  Second-order IIR notch (zeros on the unit circle at f0).
%
%   [b, a] = songdo.acoustic.design_notch(60, 30, 48000)
%
%   -3 dB bandwidth is f0/Q (2 Hz for 60 Hz, Q = 30). The numerator zeros
%   sit exactly on the unit circle, so the gain at f0 is zero.

w0   = 2*pi*f0/Fs;
beta = tan(w0/(2*Q));
g    = 1/(1 + beta);

b = g*[1, -2*cos(w0), 1];
a = [1, -2*g*cos(w0), 2*g - 1];
end
