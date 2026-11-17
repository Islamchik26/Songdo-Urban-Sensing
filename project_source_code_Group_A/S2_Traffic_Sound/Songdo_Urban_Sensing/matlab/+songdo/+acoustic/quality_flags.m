function flags = quality_flags(x, dt, limits, maxRate)
%QUALITY_FLAGS  Handbook eq. (15) quality tagging for one channel.
%
%   flags = songdo.acoustic.quality_flags(x, dt, [xmin xmax], maxRate)
%
%   DROPOUT       x is NaN
%   OUT_OF_RANGE  x < xmin or x > xmax
%   SUSPECT_JUMP  |x[n] - x[n-1]| / dt > maxRate   (maxRate may be Inf)
%   GOOD          otherwise
%
%   flags is a string column. The rate test is skipped when either sample
%   of the pair is NaN.

x = double(x(:));
flags = repmat("GOOD", numel(x), 1);

rate = [0; abs(diff(x))] / dt;
flags(rate > maxRate)                       = "SUSPECT_JUMP";
flags(~isnan(x) & (x < limits(1) | x > limits(2))) = "OUT_OF_RANGE";
flags(isnan(x))                             = "DROPOUT";
end
