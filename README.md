# [AI4Casting Hub – Hospital Bed Occupancy Data for Ontario Respiratory Virus Activity (2026-2027)](https://sites.uoguelph.ca/4castinghub/hospitalization/)
Welcome to the AI4Casting Hub's repository for the 2026-2027 Hospital Bed Occupancy Forecasting Challenge, focused on respiratory virus activity in Ontario, including COVID-19, Influenza, and RSV. This repository collects weekly forecasts of hospital bed occupancy across Ontario to support real-time decision-making and resource allocation.

[**Link to AI4Casting Hub's Ontario Hospital Bed Occupancy Forecasting Official Page**](https://4castinghub.uoguelph.ca/hospitalization/)

### Challenge Overview
AI4Casting Hub is organizing a collaborative nowcasting and forecasting challenge for confirmed hospital bed occupancy during the 2026-2027 respiratory virus season. The challenge starts on Friday, November 20, 2026. PHO data updates run from Friday, October 23, 2026 through Friday, May 28, 2027. Participating teams are asked to provide weekly probabilistic interval hindcasts, nowcasts and forecasts for hospital bed occupancy at both the provincial level (Ontario) and for each of the 6 Public Health Regions.

These predictions will cover three major respiratory viruses:
* COVID-19 Hospital Bed Occupancy Count (wk inc covid hosp)
* Influenza Hospital Bed Occupancy Count (wk inc flu hosp)
* RSV Hospital Bed Occupancy Count (wk inc rsv hosp)

Teams will submit predictions for the number of hospital beds occupied during:
* The preceding week (horizon -1)
* The current week (horizon 0)
* The following three weeks (horizon 1,2,3)

Predictions will be compared against confirmed hospital bed occupancy data released by Public Health Ontario's Ontario Respiratory Virus Tool. For detailed information regarding the forecasting targets refer [model-output/README.md](https://github.com/ai4castinghub/hospitalization-forecast/blob/main/model-output/README.md) file.

Two additional, independently optional 2026–27 targets forecast the peak week and peak weekly count of **influenza hospital admissions**. These use admissions rather than the weekly occupancy outcome. Forecasts can cover any of the six regions or Ontario. See [submission instructions](model-output/README.md#optional-influenza-admission-peak-targets).

The Monday hub pipeline also generates seasonal baseline, autoregressive, and random-forest peak forecasts where complete admissions history is available. The peak ensemble is included alongside the weekly ensemble forecasts. Seasonal forecasts are not currently evaluated.

### Key Dates
* Challenge start and first PHO update of the challenge: Friday, November 20, 2026
* Last PHO update of the challenge: Saturday, May 29, 2027
* Forecast rounds: Saturdays from November 21, 2026 through May 29, 2027 (28 rounds).

* Weekly submission deadline: Saturday at 11:30 p.m. America/Toronto time. Use that Saturday as the forecast `reference_date` and in the file name.

The reference week is defined by the epidemiological week (EW) running from Sunday to Saturday. Submissions are expected to provide forecasts for the end of the reference week and the subsequent three weeks. Teams are encouraged to submit predictions for all forecast horizons, but it is not mandatory to cover every time period or location. Similarly, while teams are encouraged to forecast for all three targets, submitting predictions for all of them is not required. Predictions for the previous week's hospital bed occupancy (horizon -1) are optional and will not be scored in summary evaluations but may assist with calibration.

### Important Notes
PHO updates its dashboard on Friday morning. The hub retrieves the updated data on Friday, and teams may submit forecasts from Friday through Saturday at 11:30 p.m. America/Toronto time. The Friday data describe the preceding week, ending on the previous Saturday.
Forecasts for the previous week (horizon -1) will not be included in official evaluations but are encouraged.

The Monday pipeline runs at 10:00 a.m. America/Toronto time, generating hub models
and ensembles and refreshing concatenated data before and after generation.

Beginning with the November 14, 2026 reference date, the hub ensemble is saved as
`AI4Casting_Hub-Simple_Ens`. Its weekly mean ensemble excludes
`AI4Casting_Hub-Quantile_Baseline` and `AI4Casting_Hub-Flatline`; these models
continue to be generated as individual forecasts. Influenza peak ensemble
methods and component eligibility are unchanged. `AI4Casting_Hub-Ensemble_v1`
is discontinued, with its historical forecasts and metadata retained.

From November 14, 2026, the same run generates `AI4Casting_Hub-Team_Ens` for weekly
horizons 0-3 using external models with `designated_model: true`, including team
ensembles. It uses Simple_Ens's quantile mean and rounding with equal model
weights. One eligible submission suffices; none means no output. Team_Ens is
excluded from Simple_Ens inputs and reports; reports retain Simple_Ens and the
historical Ensemble_v1 fallback.

If you have any questions regarding this challenge or the development of prediction targets, please contact Siddhesh S. Kadam at 4castinghub@uoguelph.ca.

### Acknowledgments
This repository follows the guidelines and standards outlined by the hubverse, which provides a set of data formats and open source tools for modeling hubs.
