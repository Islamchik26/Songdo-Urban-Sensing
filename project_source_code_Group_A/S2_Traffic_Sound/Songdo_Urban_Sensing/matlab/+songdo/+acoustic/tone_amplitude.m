function A = tone_amplitude(x, Fs, f0)
%TONE_AMPLITUDE  Amplitude of the strongest spectral line within +-3 bins of f0.
%
%   A = songdo.acoustic.tone_amplitude(x, Fs, f0)
%
%   Uses the Hann-windowed, coherent-gain-corrected spectrum, so the result
%   is in the same unit as x (volts for mic data).

[f, Aspec] = songdo.acoustic.amp_spectrum(x, Fs);
df  = Fs / numel(x);
sel = abs(f - f0) <= 3*df;
A   = max(Aspec(sel));
end
