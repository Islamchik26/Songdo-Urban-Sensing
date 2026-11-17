function L = reference_level_dba(p, Fs, mask, fmax)
%REFERENCE_LEVEL_DBA  Analytic A-weighted level of a pressure signal.
%
%   L = songdo.acoustic.reference_level_dba(p, Fs, mask, fmax)
%
%   Applies the exact analytic A-weighting magnitude in the FFT domain
%   (zero phase, no filter design involved), band-limits to fmax (default
%   3600 Hz, what the 8 kHz chain can see), and returns the level in dBA
%   over the samples selected by mask (default: all). Used to build the
%   fixture to a known level and as the ground truth the digital chain is
%   checked against.

if nargin < 3 || isempty(mask)
    mask = true(numel(p), 1);
end
if nargin < 4
    fmax = 3600;
end

p    = double(p(:));
mask = logical(mask(:));
N    = numel(p);

f = (0:N-1).' * Fs / N;
hi = f > Fs/2;
f(hi) = Fs - f(hi);                 % fold so the weighting is Hermitian

Aw = 10.^(songdo.acoustic.a_weight_db(max(f, 1e-3)) / 20);
Aw(f > fmax) = 0;
Aw(f == 0)   = 0;

xa = real(ifft(fft(p) .* Aw));
L  = 10*log10(mean(xa(mask).^2) / (20e-6)^2);
end
