function D = haversineKm(lat, lon)
%HAVERSINEKM  Pairwise great-circle distances (km) between WGS84 points.
%   D = songdoui.haversineKm(latDeg, lonDeg) -> N x N matrix.
Re = 6371.0088;   % mean Earth radius, km
lat = deg2rad(lat(:)); lon = deg2rad(lon(:));
dLat = lat - lat.'; dLon = lon - lon.';
h = sin(dLat/2).^2 + cos(lat).*cos(lat.').*sin(dLon/2).^2;
D = 2*Re*asin(sqrt(min(1, h)));
end
