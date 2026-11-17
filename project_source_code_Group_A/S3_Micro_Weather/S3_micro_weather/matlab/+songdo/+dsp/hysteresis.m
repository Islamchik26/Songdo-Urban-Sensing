function [output,finalState] = hysteresis(x,lowThreshold,highThreshold,initialState)
%HYSTERESIS Dual-threshold latch: >= high turns on, <= low turns off.
% Values strictly between thresholds, including missing values, hold state.
% Invalid values are not quality-flagged by this primitive; caller owns flags.
if nargin < 4, initialState = false; end
validateattributes(x,{'numeric'},{'real'},mfilename,'x');
validateattributes(lowThreshold,{'numeric'},{'real','scalar','finite'},mfilename,'lowThreshold');
validateattributes(highThreshold,{'numeric'},{'real','scalar','finite'},mfilename,'highThreshold');
if lowThreshold >= highThreshold
    error('songdo:InvalidThresholds','Low threshold must be less than high threshold.');
end
if ~isscalar(initialState) || ~ismember(initialState,[false true])
    error('songdo:InvalidState','Initial latch state must be logical 0 or 1.');
end
finalState = logical(initialState);
output = false(size(x));
for k = 1:numel(x)
    if isfinite(x(k))
        if x(k) >= highThreshold, finalState = true;
        elseif x(k) <= lowThreshold, finalState = false;
        end
    end
    output(k) = finalState;
end
end
