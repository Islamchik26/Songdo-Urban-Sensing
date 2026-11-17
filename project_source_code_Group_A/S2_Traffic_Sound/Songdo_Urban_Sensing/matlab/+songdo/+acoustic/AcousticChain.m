classdef AcousticChain < handle
%ACOUSTICCHAIN  Causal streaming S2 acoustic front end (Base MATLAB only).
%
%   48 kHz mic volts -> 60 Hz notch -> anti-alias FIR -> decimate by M
%   -> A-weighting (3 biquads at Fs/M) -> calibrated pressure in Pa.
%
%   chain = songdo.acoustic.AcousticChain();
%   [pA, xDec] = chain.process(voltsBlock);   % call once per timer tick
%
%   Every filter keeps its Direct Form II Transposed state (zi -> zf)
%   between calls, so block-wise output is identical to filtering the whole
%   record in one go. The decimator also keeps its phase, so block lengths
%   do not have to be multiples of the decimation factor. No filtfilt.
%
%   Outputs (both at FsOut = Fs/M):
%     pA   : A-weighted sound pressure in Pa
%     xDec : notch + anti-alias filtered, decimated mic volts (flat)
%
%   Options (name/value): Fs, Decimation, NotchHz, NotchQ, FirLength,
%   FirCutoffHz, Sensitivity (V/Pa), BypassNotch, BypassAntiAlias.
%   The bypass flags exist only to demonstrate what goes wrong without them.

    properties (SetAccess = private)
        Fs          = 48000
        DecimFactor = 6
        FsOut       = 8000
        Sensitivity = 0.020
        NotchB
        NotchA
        FirB
        SosA
        GainA
        BypassNotch     = false
        BypassAntiAlias = false
        SamplesIn       = 0
    end

    properties (Access = private)
        ziNotch
        ziFir
        ziSos
    end

    methods
        function obj = AcousticChain(varargin)
            ip = inputParser;
            addParameter(ip, 'Fs', 48000);
            addParameter(ip, 'Decimation', 6);
            addParameter(ip, 'NotchHz', 60);
            addParameter(ip, 'NotchQ', 30);
            addParameter(ip, 'FirLength', 101);
            addParameter(ip, 'FirCutoffHz', 3600);
            addParameter(ip, 'Sensitivity', 0.020);
            addParameter(ip, 'BypassNotch', false);
            addParameter(ip, 'BypassAntiAlias', false);
            parse(ip, varargin{:});
            r = ip.Results;

            if mod(r.Fs, r.Decimation) ~= 0
                error('songdo:acoustic:badDecimation', ...
                      'Fs (%g) must be an integer multiple of the decimation factor (%g).', ...
                      r.Fs, r.Decimation);
            end

            obj.Fs              = r.Fs;
            obj.DecimFactor     = r.Decimation;
            obj.FsOut           = r.Fs / r.Decimation;
            obj.Sensitivity     = r.Sensitivity;
            obj.BypassNotch     = logical(r.BypassNotch);
            obj.BypassAntiAlias = logical(r.BypassAntiAlias);

            [obj.NotchB, obj.NotchA] = songdo.acoustic.design_notch(r.NotchHz, r.NotchQ, r.Fs);
            obj.FirB = songdo.acoustic.design_fir_lowpass(r.FirLength, r.FirCutoffHz, r.Fs);
            [obj.SosA, obj.GainA] = songdo.acoustic.design_a_weighting(obj.FsOut);

            obj.reset();
        end

        function reset(obj)
            %RESET  Clear all filter state and the decimator phase.
            obj.ziNotch  = zeros(max(numel(obj.NotchB), numel(obj.NotchA)) - 1, 1);
            obj.ziFir    = zeros(numel(obj.FirB) - 1, 1);
            obj.ziSos    = repmat({zeros(2, 1)}, size(obj.SosA, 1), 1);
            obj.SamplesIn = 0;
        end

        function [pA, xDec] = process(obj, v)
            %PROCESS  Push one block of mic volts, get the new 8 kHz samples.
            v = double(v(:));

            if obj.BypassNotch
                x = v;
            else
                [x, obj.ziNotch] = filter(obj.NotchB, obj.NotchA, v, obj.ziNotch);
            end

            if ~obj.BypassAntiAlias
                [x, obj.ziFir] = filter(obj.FirB, 1, x, obj.ziFir);
            end

            % Keep the samples whose global index (0-based) is a multiple of M.
            i0   = mod(-obj.SamplesIn, obj.DecimFactor) + 1;
            xDec = x(i0:obj.DecimFactor:end);
            xDec = reshape(xDec, [], 1);
            obj.SamplesIn = obj.SamplesIn + numel(v);

            if isempty(xDec)
                pA = zeros(0, 1);
                return
            end

            y = obj.GainA * xDec;
            for k = 1:size(obj.SosA, 1)
                [y, obj.ziSos{k}] = filter(obj.SosA(k, 1:3), obj.SosA(k, 4:6), y, obj.ziSos{k});
            end
            pA = y / obj.Sensitivity;
        end
    end
end
