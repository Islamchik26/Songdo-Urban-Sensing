function s1_post_json(jsonPath,url)
% Optional HTTP POST; start integration/mock_receiver.py first.
if nargin<1||isempty(jsonPath), jsonPath=fullfile(pwd,'output','S1_telemetry.json'); end
if nargin<2||isempty(url), url='http://localhost:8080/api/v1/telemetry'; end
assert(isfile(jsonPath),'JSON file not found: %s',jsonPath);
payload=jsondecode(fileread(jsonPath));
opts=weboptions('MediaType','application/json','Timeout',5);
response=webwrite(url,payload,opts); disp(response);
fprintf('POST succeeded. Check the receiver log for the accepted packet.\n');
end
