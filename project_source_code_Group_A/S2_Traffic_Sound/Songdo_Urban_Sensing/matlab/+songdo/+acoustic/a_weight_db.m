function L = a_weight_db(f)
%A_WEIGHT_DB  IEC 61672 analytic A-weighting curve in dB (0 dB at 1 kHz).
%
%   L = songdo.acoustic.a_weight_db(f)   f in Hz (array), L in dB.
%
%   Reference values: 63 Hz -> -26.2 dB, 100 Hz -> -19.1 dB,
%                     1 kHz ->   0.0 dB, 2 kHz -> +1.2 dB.
%
%   Note: the Handbook text for S2-2 quotes "+1.2 dB at 1 kHz" and
%   "-26.2 dB at 100 Hz". Those values belong to 2 kHz and 63 Hz.

f  = double(f);
f1 = 20.598997;
f2 = 107.65265;
f3 = 737.86223;
f4 = 12194.217;

fsq = f.^2;
ra  = (f4^2 * fsq.^2) ./ ((fsq + f1^2) .* sqrt((fsq + f2^2) .* (fsq + f3^2)) .* (fsq + f4^2));
L   = 20*log10(max(ra, realmin)) + 2.0;
end
