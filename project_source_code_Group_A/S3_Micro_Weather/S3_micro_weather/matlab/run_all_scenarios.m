function report = run_all_scenarios(varargin)
%RUN_ALL_SCENARIOS S3-only package compatibility entrypoint, not all five teams.
warning('songdo:S3Only','This package implements S3 only; S1/S2/S4/S5 are not implemented.');
report=run_S3(varargin{:});
end
