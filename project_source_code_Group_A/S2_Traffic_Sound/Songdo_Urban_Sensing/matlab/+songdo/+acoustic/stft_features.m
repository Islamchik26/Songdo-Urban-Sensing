function F = stft_features(x, Fs, varargin)
%STFT_FEATURES  Hann STFT with spectral centroid, HF ratio and siren-band ratio.
%
%   F = songdo.acoustic.stft_features(x, Fs)
%   F = songdo.acoustic.stft_features(x, Fs, 'WindowLength', 512, 'Hop', 256, ...)
%
%   Frame m uses samples m*R+1 ... m*R+Nw only, and is time-stamped at its
%   LAST sample, so the features are causal (latency Nw/Fs).
%
%   Fields of F (frames are columns / rows as noted):
%     Time        [nFrames x 1]  frame end time, s
%     Freq        [Nw/2+1 x 1]   bin centres, Hz
%     Power       [Nw/2+1 x nFrames]  one-sided |X[m,k]|^2
%     Centroid    [nFrames x 1]  spectral centroid, Hz (DC bin excluded)
%     HfRatio     [nFrames x 1]  energy above HfCutoffHz / total energy
%     SirenRatio  [nFrames x 1]  eta = E[600,1000] / E[100,4000]
%
%   The Handbook writes eta = E[600,1000]/E_total. The total here is taken
%   over TotalBandHz (default 100-4000 Hz) so that sub-100 Hz engine and
%   road rumble does not dilute the ratio.

ip = inputParser;
addParameter(ip, 'WindowLength', 512);
addParameter(ip, 'Hop', 256);
addParameter(ip, 'SirenBandHz', [600 1000]);
addParameter(ip, 'TotalBandHz', [100 4000]);
addParameter(ip, 'HfCutoffHz', 2500);
parse(ip, varargin{:});
o = ip.Results;

x  = double(x(:));
Nw = o.WindowLength;
R  = o.Hop;
fb = (0:Nw/2).' * Fs / Nw;

nFrames = floor((numel(x) - Nw)/R) + 1;
if nFrames < 1
    F = struct('Time', zeros(0,1), 'Freq', fb, 'Power', zeros(Nw/2+1, 0), ...
               'Centroid', zeros(0,1), 'HfRatio', zeros(0,1), 'SirenRatio', zeros(0,1));
    return
end

w   = 0.5 - 0.5*cos(2*pi*(0:Nw-1).'/(Nw - 1));
idx = (1:Nw).' + (0:nFrames-1)*R;
X   = fft(x(idx) .* w, [], 1);
P   = abs(X(1:Nw/2+1, :)).^2;

totalMask = fb >= o.TotalBandHz(1) & fb <= o.TotalBandHz(2);
sirenMask = fb >= o.SirenBandHz(1) & fb <= o.SirenBandHz(2);
hfMask    = fb >  o.HfCutoffHz;

totBand = max(sum(P(totalMask, :), 1), realmin);
totAll  = max(sum(P, 1), realmin);
totNoDc = max(sum(P(2:end, :), 1), realmin);

F.Time       = ((0:nFrames-1).' * R + Nw) / Fs;
F.Freq       = fb;
F.Power      = P;
F.Centroid   = (sum(fb(2:end) .* P(2:end, :), 1) ./ totNoDc).';
F.HfRatio    = (sum(P(hfMask, :), 1) ./ totAll).';
F.SirenRatio = (sum(P(sirenMask, :), 1) ./ totBand).';
end
