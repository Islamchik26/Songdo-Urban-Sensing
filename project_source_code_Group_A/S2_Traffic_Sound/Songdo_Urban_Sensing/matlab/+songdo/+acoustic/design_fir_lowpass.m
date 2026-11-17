function h = design_fir_lowpass(N, fc, Fs)
%DESIGN_FIR_LOWPASS  Causal Type-I linear-phase FIR, Hann-windowed sinc.
%
%   h = songdo.acoustic.design_fir_lowpass(101, 3600, 48000)
%
%   Returns a row vector of N taps, symmetric about (N-1)/2, normalised to
%   unity DC gain. Group delay is (N-1)/2 samples at every frequency.
%   Base MATLAB only (no sinc(), no fir1()).

if mod(N, 2) == 0
    error('songdo:acoustic:evenLength', ...
          'FIR length N must be odd for a Type-I linear-phase filter.');
end

M  = (N - 1)/2;
n  = (0:N-1).';
k  = n - M;
wc = 2*fc/Fs;                       % cutoff as a fraction of Fs/2

hid = wc * ones(N, 1);              % limit of wc*sinc(wc*k) at k = 0
nz  = (k ~= 0);
hid(nz) = wc * sin(pi*wc*k(nz)) ./ (pi*wc*k(nz));

w = 0.5 - 0.5*cos(2*pi*n/(N - 1));  % Hann window, eq. (33)
h = hid .* w;

h = (h + flipud(h))/2;              % enforce exact symmetry
h = h / sum(h);                     % unity DC gain
h = h.';
end
