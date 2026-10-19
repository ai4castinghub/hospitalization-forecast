# [AI4Casting Hub – Hospital Bed Occupancy Data for Ontario Respiratory Virus Activity (2025-2026)](https://sites.uoguelph.ca/4castinghub/hospitalization/)
Welcome to the AI4Casting Hub's repository for the 2025-2026 Hospital Bed Occupancy Forecasting Challenge, focused on respiratory virus activity in Ontario, including COVID-19, Influenza, and RSV. This repository is dedicated to collecting weekly forecast data for hospital bed occupancy across the Ontario province, aiding in real-time decision-making and resource allocation.

[**Link to AI4Casting Hub's Ontario Hospital Bed Occupancy Forecasting Official Page**](https://4castinghub.uoguelph.ca/hospitalization/)

### Challenge Overview
AI4Casting Hub is organizing a collaborative nowcasting and forecasting challenge for confirmed hospital bed occupancy during the 2025-2026 influenza season, starting on November 20, 2025. The challenge will run until May 16, 2026. During this period, participating teams are asked to provide weekly probabilistic interval hindcasts, nowcasts and forecasts for hospital bed occupancy at both the provincial level (Ontario) and for each of the 6 Public Health Regions.

These predictions will cover three major respiratory viruses:
* COVID-19 Hospital Bed Occupancy Count (wk inc covid hosp)
* Influenza Hospital Bed Occupancy Count (wk inc flu hosp)
* RSV Hospital Bed Occupancy Count (wk inc rsv hosp)

Teams will submit predictions for the number of hospital beds occupied during:
* The preceding week (horizon -1)
* The current week (horizon 0)
* The following three weeks (horizon 1,2,3)

Predictions will be compared against confirmed hospital bed occupancy data released by Public Health Ontario's Ontario Respiratory Virus Tool. For detailed information regarding the forecasting targets refer [model-output/README.md](https://github.com/ai4castinghub/hospitalization-forecast/blob/main/model-output/README.md) file.

### Key Dates
* Challenge Start Date: November 20, 2025
* Challenge End Date: May 16, 2026
* Weekly Submission Deadline: Saturdays at 11 PM Eastern Standard Time (referred to as the "Forecast Due Date"). Submissions should cover the reference week ending on the Saturday i.e. the Forecast Due Date.

The reference week is defined by the epidemiological week (EW) running from Sunday to Saturday. Submissions are expected to provide forecasts for the end of the reference week and the subsequent three weeks. Teams are encouraged to submit predictions for all forecast horizons, but it is not mandatory to cover every time period or location. Similarly, while teams are encouraged to forecast for all three targets, submitting predictions for all of them is not required. Predictions for the previous week's hospital bed occupancy (horizon -1) are optional and will not be scored in summary evaluations but may assist with calibration.

### Important Notes
Data for hospital bed occupancy from the preceding week will be available by the Friday deadline.
Forecasts for the previous week (horizon -1) will not be included in official evaluations but are encouraged.

If you have any questions regarding this challenge or the development of prediction targets, please contact Siddhesh S. Kadam at 4castinghub@uoguelph.ca.

### Hub model forecasts

Run `Rscript scripts/hub-model-forecasts.R` from the repository root to create
the Flatline, Quantile AR, Random Forest Quantile AR, and CDC Quantile Baseline
files for the Saturday after the newest observed target week.
Use `--date=YYYY-MM-DD` for one Saturday or `--from=YYYY-MM-DD
--to=YYYY-MM-DD` for a weekly backfill. The manual **Hub model forecasts**
GitHub Action accepts an optional single date.

The model script reads the season files under `target-data/` and
`auxiliary-data/target-data-archive/`. After its workflow commits the four model
files, a separate **Hub ensemble forecasts** workflow runs
`scripts/hub-ensemble-forecasts.R` for the same Saturday. It combines those
four files with any other eligible same-date model outputs, and commits only
the Ensemble v1 file. The ensemble workflow can also be run manually with an
optional Saturday date; without one it uses the newest date with all four hub
model files. Both jobs install and cache their own R dependencies on
GitHub-hosted runners. The cache-warming workflow runs on Sundays at 9:30 AM
Toronto time and can also be started manually. The task dates in
`hub-config/tasks.json` must include a date before its output can pass Hubverse
submission validation. The scheduled action runs every Monday at 10:30 AM
Toronto time for the preceding Saturday, and stops if PHO target data for the
Saturday before that have not been updated.

### Acknowledgments
This repository follows the guidelines and standards outlined by the hubverse, which provides a set of data formats and open source tools for modeling hubs.
