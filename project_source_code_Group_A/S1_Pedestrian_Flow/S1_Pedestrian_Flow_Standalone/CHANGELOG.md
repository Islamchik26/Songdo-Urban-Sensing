# Plot/logic revision notes

This revision addresses the readability failures in the first improved ZIP:

1. S1-1 is plotted on a 0–6 s axis, with physical response timing marked.
2. The S1-2 filter starts from a pre-warmed steady state; the main comparison is limited to 0–3 s, and ADC error is shown separately over 250 ms.
3. S1-3 now has a 10-minute cumulative-event overview and a separate 8-second pulse detail; totals match the full-run panel.
4. The synthetic S1-3 event schedule has varied inflow/outflow periods instead of a near-constant linear ramp.
5. S1-4 calculates the rate from a causal 2-second-smoothed density trace, shows the full density/rate/alarm timeline, and explicitly reports when the assigned 0.30 people/(m²·s) rate threshold is not reached. The threshold itself was not changed.
6. README and tests now describe/check the revised behavior.

Validation note: the source was reviewed and the signal logic was numerically prototyped in Python for plot review. MATLAB/Octave is not installed in the authoring environment, so the MATLAB runner and test suite still need to be executed in MATLAB before submission.
