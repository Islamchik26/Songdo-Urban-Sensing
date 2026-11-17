function r = s4_1_sensor(doPlot, outDir)
% S4-1  Sensor transduction: optical PM2.5 and NDIR CO2 as first-order systems.
%   Continuous model  tau*dy/dt + y = K*u + V0  ->  exact ZOH discretization
%   y[n] = a*y[n-1] + (1-a)*(K*u[n-1] + V0),  a = exp(-Ts/tau).
%   Measures t63, t10-90, 2 % settling and identifies tau back from a noisy step.
if nargin < 1, doPlot = true; end
if nargin < 2, outDir = pwd; end
rng(42);

Ts = 0.1;                      % [s] analog front-end simulation step
t  = (0:Ts:300)';  N = numel(t);
t0 = 20;                       % step instant [s]

% name, K [V per unit], V0 [V], tau [s], u0, u1, unit
S(1) = struct('name','PM25_UG_M3', 'K',0.0033,   'V0',0.0, 'tau',8,  'u0',15,  'u1',80,   'unit','ug/m3');
S(2) = struct('name','CO2_NDIR_PPM','K',1.6/2000, 'V0',0.4, 'tau',25, 'u0',420, 'u1',1000, 'unit','ppm');

for k = 1:2
    s = S(k);
    u = s.u0 + (s.u1 - s.u0)*(t >= t0);
    % continuous-time analytic response
    yc = s.V0 + s.K*s.u0 + s.K*(s.u1-s.u0)*(1 - exp(-max(t-t0,0)/s.tau));
    % exact ZOH difference equation (state initialised in steady state)
    a  = exp(-Ts/s.tau);
    yd = zeros(N,1);  yd(1) = s.V0 + s.K*s.u0;
    for n = 2:N
        yd(n) = a*yd(n-1) + (1-a)*(s.K*u(n-1) + s.V0);
    end
    zohErr = max(abs(yd - yc));

    % step metrics on normalised response
    yn  = (yd - yd(1)) / (s.K*(s.u1-s.u0));
    t10 = crossTime(t, yn, 0.10) - t0;
    t63 = crossTime(t, yn, 1-exp(-1)) - t0;
    t90 = crossTime(t, yn, 0.90) - t0;
    i2  = find(abs(yn - 1) > 0.02, 1, 'last');  ts2 = t(i2+1) - t0;

    % identification of tau from a noisy reading (log-linear least squares)
    noisy = yd + 0.002*randn(N,1);
    ynn   = (noisy - mean(noisy(t < t0))) / (mean(noisy(t > t0+10*s.tau)) - mean(noisy(t < t0)));
    m     = t > t0 & ynn > 0.05 & ynn < 0.90;
    p     = polyfit(t(m) - t0, log(1 - ynn(m)), 1);
    tauHat = -1/p(1);

    r.(lower(strtok(s.name,'_'))) = struct('tau',s.tau, 'K',s.K, 'zoh_err',zohErr, ...
        't63',t63, 't1090',t90-t10, 'ts2',ts2, 'tau_hat',tauHat, ...
        't',t, 'u',u, 'yc',yc, 'yd',yd, 'noisy',noisy, 'unit',s.unit, 'name',s.name);
end

fprintf('\n--- S4-1 Sensor transduction (first-order, exact ZOH) ---\n');
for f = {'pm25','co2'}
    q = r.(f{1});
    fprintf('%-13s tau=%5.1f s | t63=%5.2f s | t10-90=%5.2f s (theory %5.2f) | ts2%%=%5.2f s (theory %5.2f) | tau_hat=%5.2f s | ZOH err=%.1e V\n', ...
        q.name, q.tau, q.t63, q.t1090, q.tau*log(9), q.ts2, q.tau*log(50), q.tau_hat, q.zoh_err);
end

if doPlot
    fig = figure('Name','S4-1 Sensor step response','Position',[100 100 1100 420]);
    for k = 1:2
        q = r.(ifelse(k==1,'pm25','co2'));
        subplot(1,2,k); hold on; grid on;
        plot(q.t, q.noisy, 'Color',[0.75 0.75 0.75]);
        plot(q.t, q.yc, 'b', 'LineWidth',1.6);
        plot(q.t(1:50:end), q.yd(1:50:end), 'ro', 'MarkerSize',4);
        yl = ylim;  plot([20+q.t63 20+q.t63], yl, 'k--');
        xlim([0 20+8*q.tau]);
        xlabel('Time [s]'); ylabel('Sensor output [V]');
        title(sprintf('%s: \\tau = %g s, t_{63} = %.1f s', strrep(q.name,'_','\_'), q.tau, q.t63));
        legend('noisy reading','continuous y(t)','ZOH y[n]','t_{63}','Location','southeast');
    end
    print(fig, fullfile(outDir,'S4_1_sensor_step.png'), '-dpng', '-r150');
end
end

function tc = crossTime(t, y, lvl)
i = find(y >= lvl, 1);
tc = t(i-1) + (lvl - y(i-1)) * (t(i) - t(i-1)) / (y(i) - y(i-1));
end

function out = ifelse(c, a, b)
if c, out = a; else, out = b; end
end
