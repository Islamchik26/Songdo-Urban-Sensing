function validateTime(time,fsHz,previousTime,originTime,previousSamples,errorId)
%VALIDATETIME One shared replay/streaming clock contract, without resampling.
% Double, dense, nonnegative relative seconds on one 10-Hz lattice. The fixed
% 1e-8 s tolerance applies to both intervals and the origin-based sample grid,
% preventing sub-tolerance per-step drift from accumulating across blocks.
if nargin<3, previousTime=[]; end
if nargin<4||isempty(originTime), if isempty(time), originTime=0; else, originTime=time(1); end, end
if nargin<5, previousSamples=0; end
if nargin<6, errorId='songdo:InvalidTime'; end
tol=1e-8;
if ~isa(time,'double')||issparse(time)||~isreal(time)||~ismatrix(time)||size(time,2)~=1 || ...
        any(~isfinite(time))||any(time<0)
    error(errorId,'time_s must be a dense double-precision column of finite nonnegative relative seconds.');
end
if isempty(time), return; end
if eps(max(1,max(abs(time))))>tol
    error(errorId,'Relative timestamps are too large to resolve the sample grid accurately.');
end
target=1/fsHz;
steps=diff([previousTime;time]);
expected=originTime+(previousSamples+(0:numel(time)-1)')/fsHz;
if any(steps<=0)||any(abs(steps-target)>tol)||any(abs(time-expected)>tol)
    error(errorId,'time_s must follow one uniform %.12g-second grid; missing rows are not resampled.',target);
end
end
