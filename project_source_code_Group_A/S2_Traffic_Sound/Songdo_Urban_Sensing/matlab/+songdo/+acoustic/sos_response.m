function H = sos_response(sos, gain, f, Fs)
%SOS_RESPONSE  Complex frequency response of a biquad cascade.
%
%   H = songdo.acoustic.sos_response(sos, gain, f, Fs)
%
%   sos  : Kx6 matrix, rows [b0 b1 b2 a0 a1 a2]
%   gain : overall scalar gain
%   f    : frequencies in Hz
%   H    : column vector, same length as f

zi = exp(-1j*2*pi*f(:)/Fs);        % z^-1 on the unit circle
H  = gain * ones(numel(f), 1);
for k = 1:size(sos, 1)
    b = sos(k, 1:3);
    a = sos(k, 4:6);
    H = H .* (b(1) + b(2)*zi + b(3)*zi.^2) ./ (a(1) + a(2)*zi + a(3)*zi.^2);
end
end
