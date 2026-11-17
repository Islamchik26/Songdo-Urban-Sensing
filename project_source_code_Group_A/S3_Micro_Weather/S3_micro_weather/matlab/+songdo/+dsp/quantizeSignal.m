function [quantized,step,meta] = quantizeSignal(x,bits,range)
%QUANTIZESIGNAL Saturating uniform MIDRISE ADC, with 2^bits levels.
% range=[low high] gives the input full-scale interval. The reproduction
% levels are low+step/2 through high-step/2, with step=(high-low)/2^bits.
% No dithering is added. Nonfinite samples return NaN and invalid=true.
% delta^2/12 and 6.02B+1.76 dB assume a sufficiently resolved, unclipped,
% full-scale sinusoid with quantization error approximately uniform.
validateattributes(x,{'numeric'},{'real'},mfilename,'x');
validateattributes(bits,{'numeric'},{'real','scalar','integer','>=',1,'<=',24},mfilename,'bits');
validateattributes(range,{'numeric'},{'real','finite','numel',2},mfilename,'range');
range = double(range); bits = double(bits);
if range(1) >= range(2), error('songdo:InvalidRange','Quantizer bounds must increase.'); end
levels = 2^bits;
step = (range(2)-range(1))/levels;
quantized = nan(size(x));
valid = isfinite(x);
code = floor((double(x(valid))-range(1))/step);
code = min(max(code,0),levels-1);
quantized(valid) = range(1)+(code+0.5)*step;
meta.invalid = ~valid;
meta.clipped = valid & (x < range(1) | x > range(2));
meta.levels = levels;
meta.type = 'midrise';
meta.theoreticalNoiseVariance = step^2/12;
meta.fullScaleSineSqnrDb = 6.020599913*bits+1.760912591;
end
