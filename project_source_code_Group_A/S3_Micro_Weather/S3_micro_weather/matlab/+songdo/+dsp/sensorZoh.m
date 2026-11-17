function [y,finalState,model] = sensorZoh(x,fsHz,tauSeconds,gain,initialState)
%SENSORZOH Exact first-order zero-order-hold sensor discretization.
% tau*dy/dt + y = gain*x. For an input held over one sample interval:
% y[n+1] = a*y[n] + b*x[n], a=exp(-Ts/tau), b=gain*(1-a).
% y(n) is the sensor state BEFORE x(n) drives the next interval. finalState
% is the state at the next sample after this block. Pass it into the next
% call to obtain exactly the same result as a single whole-record call.
% Default initialState=0 is explicit, not an inferred equilibrium condition.
if nargin < 4 || isempty(gain), gain = 1; end
if nargin < 5 || isempty(initialState), initialState = 0; end
validateattributes(x,{'numeric'},{'real','finite'},mfilename,'x');
if ~(isvector(x) || isempty(x)), error('songdo:InvalidSignal','x must be a vector.'); end
validateattributes(fsHz,{'numeric'},{'real','scalar','finite','positive'},mfilename,'fsHz');
validateattributes(tauSeconds,{'numeric'},{'real','scalar','finite','positive'},mfilename,'tauSeconds');
validateattributes(gain,{'numeric'},{'real','scalar','finite'},mfilename,'gain');
validateattributes(initialState,{'numeric'},{'real','scalar','finite'},mfilename,'initialState');
fsHz = double(fsHz); tauSeconds = double(tauSeconds); gain = double(gain);
model.a = exp(-1/(fsHz*tauSeconds));
if model.a <= 0 || model.a >= 1
    error('songdo:DegeneratePole','Sampling/tau combination cannot represent a stable pole accurately.');
end
model.b = -gain*expm1(-1/(fsHz*tauSeconds));
model.Ts = 1/fsHz;
model.tauSeconds = tauSeconds;
model.gain = gain;
y = zeros(size(x));
finalState = double(initialState);
for k = 1:numel(x)
    y(k) = finalState;
    finalState = model.a*finalState+model.b*double(x(k));
end
end
