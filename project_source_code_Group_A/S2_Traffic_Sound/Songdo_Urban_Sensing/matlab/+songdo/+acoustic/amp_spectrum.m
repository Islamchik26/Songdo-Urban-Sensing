function [f, A] = amp_spectrum(x, Fs)
%AMP_SPECTRUM  One-sided amplitude spectrum with Hann coherent-gain correction.
%
%   [f, A] = songdo.acoustic.amp_spectrum(x, Fs)
%
%   A sinusoid of amplitude 1 that falls on a bin reads 1.0 in A.

x = double(x(:));
N = numel(x);
w = 0.5 - 0.5*cos(2*pi*(0:N-1).'/(N - 1));

X = fft(x .* w);
K = floor(N/2) + 1;
A = 2*abs(X(1:K)) / sum(w);
A(1) = A(1)/2;                       % DC is not doubled
if mod(N, 2) == 0
    A(K) = A(K)/2;                   % neither is Nyquist
end
f = (0:K-1).' * Fs / N;
end
