function path = export_sensor_grid_json(grid,path)
%EXPORT_SENSOR_GRID_JSON Compatibility-named local exporter from README.
issues=songdo.io.validateTelemetry(grid);
if ~isempty(issues), error('songdo:Schema','%s',strjoin(issues,newline)); end
for k=1:numel(grid.records)
    for name={'raw_value','filtered_value'}
        if isempty(grid.records(k).(name{1})), grid.records(k).(name{1})=NaN; end
    end
end
fid=fopen(path,'w'); if fid<0, error('songdo:ExportFile','Cannot open %s.',path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(grid,'PrettyPrint',true,'ConvertInfAndNaN',true));
end
