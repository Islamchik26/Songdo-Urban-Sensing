function r = block_rms(x, blockLen)
%BLOCK_RMS  RMS of consecutive non-overlapping blocks (column vector out).
%
%   r = songdo.acoustic.block_rms(x, blockLen)

x = double(x(:));
n = floor(numel(x) / blockLen);
if n < 1
    r = zeros(0, 1);
    return
end
r = sqrt(mean(reshape(x(1:n*blockLen), blockLen, n).^2, 1)).';
end
