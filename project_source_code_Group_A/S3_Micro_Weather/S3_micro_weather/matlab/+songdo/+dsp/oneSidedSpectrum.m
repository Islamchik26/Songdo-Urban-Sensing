function [frequencyHz,amplitude] = oneSidedSpectrum(x,fsHz)
%ONESIDEDSPECTRUM One-sided Hann-windowed amplitude (not PSD).
% A periodic Hann window is used. Sum(window), not N, is the coherent-gain
% denominator. Double positive-frequency interior bins, never DC/Nyquist.
% Nonfinite input is refused rather than fabricated by interpolation.
% Off-bin tones exhibit leakage and scalloping despite coherent-gain scaling.
validateattributes(x,{'numeric'},{'real','vector','finite','nonempty'},mfilename,'x');
validateattributes(fsHz,{'numeric'},{'real','scalar','positive','finite'},mfilename,'fsHz');
fsHz = double(fsHz);
x = full(double(x(:))); n = numel(x);
if n < 3
    error('songdo:SpectrumLength','At least three samples are required.');
end
window = 0.5-0.5*cos(2*pi*(0:n-1)'/n);
y = fft(x.*window);
last = floor(n/2)+1;
amplitude = abs(y(1:last))/sum(window);
if mod(n,2) == 0
    amplitude(2:end-1) = 2*amplitude(2:end-1);
else
    amplitude(2:end) = 2*amplitude(2:end);
end
frequencyHz = (0:last-1)'*(fsHz/n);
end
