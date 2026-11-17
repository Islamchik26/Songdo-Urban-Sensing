function [s, sFinal] = schmitt_trigger(x, gammaH, gammaL, s0)
%SCHMITT_TRIGGER  Dual-threshold hysteresis latch, eq. (14) of the Handbook.
%
%   [s, sFinal] = songdo.acoustic.schmitt_trigger(x, gammaH, gammaL, s0)
%
%   s[n] = 1 if x[n] >= gammaH, 0 if x[n] <= gammaL, otherwise s[n-1].
%   NaN samples hold the previous state. Pass sFinal back in as s0 on the
%   next block when streaming.

if nargin < 4
    s0 = 0;
end
if gammaH <= gammaL
    error('songdo:acoustic:badThresholds', 'gammaH must be greater than gammaL.');
end

x     = double(x(:));
s     = zeros(size(x));
state = s0;
for n = 1:numel(x)
    if x(n) >= gammaH
        state = 1;
    elseif x(n) <= gammaL
        state = 0;
    end
    s(n) = state;
end
sFinal = state;
end
