function distanceM = haversine(latitude1,longitude1,latitude2,longitude2)
%HAVERSINE Great-circle distance on a sphere of mean radius 6371008.8 m.
% Inputs are degrees; output meters. Compatible scalar expansion is allowed.
% This is a spherical approximation, not a WGS84 geodesic calculation.
for x = {latitude1,longitude1,latitude2,longitude2}
    validateattributes(x{1},{'numeric'},{'real','finite'});
end
if any(abs(latitude1(:)) > 90) || any(abs(latitude2(:)) > 90) || ...
        any(abs(longitude1(:)) > 180) || any(abs(longitude2(:)) > 180)
    error('songdo:InvalidCoordinates','Latitude/longitude are outside geographic bounds.');
end
latitude1 = double(latitude1); longitude1 = double(longitude1);
latitude2 = double(latitude2); longitude2 = double(longitude2);
lat1 = deg2rad(latitude1); lat2 = deg2rad(latitude2);
dlat = lat2-lat1; dlon = deg2rad(longitude2-longitude1);
a = sin(dlat/2).^2+cos(lat1).*cos(lat2).*sin(dlon/2).^2;
a = max(0,min(1,a));
distanceM = 2*6371008.8*atan2(sqrt(a),sqrt(1-a));
end
