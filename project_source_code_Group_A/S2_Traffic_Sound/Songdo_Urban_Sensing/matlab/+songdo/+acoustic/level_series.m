function [L, t] = level_series(p, Fs, windowSec, hopSec)
%LEVEL_SERIES  Causal equivalent-continuous level Leq, eq. (12) of the Handbook.
%
%   [L, t] = songdo.acoustic.level_series(p, Fs, windowSec, hopSec)
%
%   p         pressure in Pa (A-weighted for dBA)
%   windowSec averaging window length, s
%   hopSec    output spacing, s (windowSec must be a multiple of hopSec)
%
%   L(j) is 10*log10(mean(p^2)/p0^2) over the window that ENDS at t(j), so
%   nothing in the future is used. The first output appears once a full
%   window has been collected.
%
%   SPL_DBA_100MS: level_series(pA, Fs, 0.1, 0.1)
%   LEQ_1S_DBA   : level_series(pA, Fs, 1.0, 0.1)

p0       = 20e-6;
blockLen = round(hopSec * Fs);
nWin     = round(windowSec / hopSec);
if nWin < 1 || abs(nWin*hopSec - windowSec) > 1e-9
    error('songdo:acoustic:badWindow', 'windowSec must be a positive multiple of hopSec.');
end

p       = double(p(:));
nBlocks = floor(numel(p) / blockLen);
if nBlocks < nWin
    L = zeros(0, 1);
    t = zeros(0, 1);
    return
end

ms   = mean(reshape(p(1:nBlocks*blockLen), blockLen, nBlocks).^2, 1).';
c    = [0; cumsum(ms)];
j    = (nWin:nBlocks).';
msW  = (c(j + 1) - c(j + 1 - nWin)) / nWin;

L = 10*log10(max(msW, realmin) / p0^2);
t = j * hopSec;
end
