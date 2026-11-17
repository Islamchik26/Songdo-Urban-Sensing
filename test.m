
clc;
clear;
close all;

a = 10;
b = 20;

result = a + b;

fprintf('Result = %d\n', result);

x = 0:0.1:10;
y = sin(x);

figure;
plot(x, y);
grid on;
title('My First MATLAB Graph');
xlabel('X');
ylabel('sin(X)');
