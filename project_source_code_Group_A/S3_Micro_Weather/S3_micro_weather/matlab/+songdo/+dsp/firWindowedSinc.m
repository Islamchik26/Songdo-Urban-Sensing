function coefficients = firWindowedSinc(numTaps,cutoffHz,fsHz)
%FIRWINDOWEDSINC Toolbox-free symmetric Hann-windowed lowpass FIR.
% The normalized DC gain is one. The linear-phase group delay is exactly
% (numTaps-1)/2 samples wherever the real signed amplitude is nonzero.
% Use filter(coefficients,1,x,zi) and retain zf for causal streaming.
validateattributes(numTaps,{'numeric'},{'scalar','real','finite','integer','>=',3},mfilename,'numTaps');
validateattributes(fsHz,{'numeric'},{'scalar','real','finite','positive'},mfilename,'fsHz');
validateattributes(cutoffHz,{'numeric'},{'scalar','real','finite','positive'},mfilename,'cutoffHz');
if cutoffHz >= fsHz/2, error('songdo:InvalidCutoff','Cutoff must be below Nyquist.'); end
numTaps = double(numTaps); cutoffHz = double(cutoffHz); fsHz = double(fsHz);
index = 0:numTaps-1;
centered = index-(numTaps-1)/2;
arg = 2*cutoffHz/fsHz*centered;
sincValue = ones(size(arg));
nonzero = arg ~= 0;
sincValue(nonzero) = sin(pi*arg(nonzero))./(pi*arg(nonzero));
window = 0.5-0.5*cos(2*pi*index/(numTaps-1));
coefficients = (2*cutoffHz/fsHz)*sincValue.*window;
coefficients = coefficients/sum(coefficients);
% Remove asymmetric floating-point roundoff without changing the design.
coefficients = (coefficients+fliplr(coefficients))/2;
end
