function jsonText = export_s2_json(m, station, startUtc)
%EXPORT_S2_JSON  Package S2 metrics as a Sensor Grid JSON packet (schema 1.0).
%
%   jsonText = songdo.acoustic.export_s2_json(m, station, startUtc)
%
%   m         struct of equal-length column vectors on a 100 ms grid:
%               Time        window-end time, s since startUtc
%               MicRawRms   100 ms RMS of raw mic volts            -> MIC_RAW_VOLTS
%               MicFiltRms  100 ms RMS after notch + anti-alias    -> MIC_RAW_VOLTS
%               SplZ, SplA  100 ms level, flat dB / dBA            -> SPL_DBA_100MS
%               LeqZ, LeqA  rolling 1 s Leq, flat dB / dBA         -> LEQ_1S_DBA
%               SirenRatio  eta from the latest STFT frame         -> EVENT_SIREN_FLAG
%               SirenFlag   latched Schmitt output, 0/1            -> EVENT_SIREN_FLAG
%   station   struct with Id, Latitude, Longitude
%   startUtc  datetime (UTC) that Time = 0 refers to
%
%   Per record: raw_value is the unconditioned quantity and filtered_value
%   the conditioned one. For the two level channels raw_value is the flat
%   (unweighted) dB SPL and filtered_value the A-weighted level; unit is
%   "dBA" for both. For EVENT_SIREN_FLAG raw_value is the band-energy
%   ratio eta and filtered_value is the latched 0/1 flag.

channels = {'MIC_RAW_VOLTS', 'SPL_DBA_100MS', 'LEQ_1S_DBA', 'EVENT_SIREN_FLAG'};
units    = {'V', 'dBA', 'dBA', 'flag'};
digits   = [6, 2, 2, 4];

raw  = [m.MicRawRms(:),  m.SplZ(:), m.LeqZ(:), m.SirenRatio(:)];
filt = [m.MicFiltRms(:), m.SplA(:), m.LeqA(:), m.SirenFlag(:)];

dt = 0.1;
flags = strings(size(raw));
flags(:, 1) = songdo.acoustic.quality_flags(filt(:, 1), dt, [0 0.7072], Inf);
flags(:, 2) = songdo.acoustic.quality_flags(filt(:, 2), dt, [30 130], 150);
flags(:, 3) = songdo.acoustic.quality_flags(filt(:, 3), dt, [30 130], 150);
flags(:, 4) = songdo.acoustic.quality_flags(filt(:, 4), dt, [0 1], Inf);

startUtc.Format = 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''';
stamps = cellstr(string(startUtc + milliseconds(round(m.Time(:) * 1000))));

nT  = numel(m.Time);
nCh = numel(channels);
recs = repmat(struct('timestamp', '', 'channel', '', 'raw_value', 0, ...
                     'filtered_value', 0, 'unit', '', 'quality_flag', ''), nT*nCh, 1);
k = 0;
for j = 1:nT
    for c = 1:nCh
        k = k + 1;
        recs(k).timestamp      = stamps{j};
        recs(k).channel        = channels{c};
        recs(k).raw_value      = round(raw(j, c),  digits(c));
        recs(k).filtered_value = round(filt(j, c), digits(c));
        recs(k).unit           = units{c};
        recs(k).quality_flag   = char(flags(j, c));
    end
end

genAt = datetime('now', 'TimeZone', 'UTC');
genAt.Format = 'yyyy-MM-dd''T''HH:mm:ss''Z''';

pkt = struct();
pkt.schema_version = '1.0';
pkt.generated_at   = char(string(genAt));
pkt.station_id     = station.Id;
pkt.latitude       = station.Latitude;
pkt.longitude      = station.Longitude;
pkt.records        = recs;

jsonText = jsonencode(pkt, 'PrettyPrint', true);
end
