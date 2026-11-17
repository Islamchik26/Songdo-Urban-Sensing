function value = finiteMean(x)
%FINITEMEAN Finite-only mean without overflowing a sum of large finite values.
% Scaling before reduction retains valid means near realmax. Missing values
% are omitted; an empty/all-missing input is NaN. This is not imputation.
validateattributes(x,{'numeric'},{'real'},mfilename,'x');
x=double(x(:)); x=x(isfinite(x));
if isempty(x), value=NaN; return; end
scale=max(abs(x));
if scale==0, value=0; return; end
normalized=mean(x/scale);
% Exact mean is in [-1,1]; bound only floating-point reduction roundoff.
value=scale*max(-1,min(1,normalized));
end
