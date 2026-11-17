function txt = runScriptIsolated(scriptFile)
%RUNSCRIPTISOLATED  Run a member SCRIPT in a throw-away function workspace.
%   Member scripts start with CLEAR; CLC; CLOSE ALL. Running them here means
%   CLEAR only wipes this function's workspace (never the app or the base
%   workspace) and CLOSE ALL cannot reach the app (uifigure handles are
%   hidden). RUN changes into the script folder, so outputs land exactly
%   where the member's own instructions put them.
txt = evalc('run(scriptFile)');
end
