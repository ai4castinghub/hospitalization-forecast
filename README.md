# [AI4Casting Hub – Hospital Bed Occupancy Data for Ontario Respiratory Virus Activity (2024-2025)](https://sites.uoguelph.ca/4castinghub/hospitalization/)
Welcome to the AI4Casting Hub's repository for the 2024-2025 Hospital Bed Occupancy Forecasting Challenge, focused on respiratory virus activity in Ontario, including COVID-19, Influenza, and RSV. This repository is dedicated to collecting weekly forecast data for hospital bed occupancy across the Ontario province, aiding in real-time decision-making and resource allocation.

[**Link to AI4Casting Hub's Ontario Hospital Bed Occupancy Forecasting Official Page**](https://4castinghub.uoguelph.ca/hospitalization/)

### Challenge Overview
AI4Casting Hub is organizing a collaborative nowcasting and forecasting challenge for confirmed hospital bed occupancy during the 2024-2025 influenza season, starting on November 25, 2024. The challenge will run until May 31, 2025. During this period, participating teams are asked to provide weekly probabilistic interval hindcasts, nowcasts and forecasts for hospital bed occupancy at both the provincial level (Ontario) and for each of the 6 Public Health Regions.

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
* Challenge Start Date: November 25, 2024
* Challenge End Date: May 31, 2025
* Weekly Submission Deadline: Fridays at 11 PM Eastern Standard Time (referred to as the "Forecast Due Date"). Submissions should cover the reference week ending on the Saturday following the Forecast Due Date.

The reference week is defined by the epidemiological week (EW) running from Sunday to Saturday. Submissions are expected to provide forecasts for the end of the reference week and the subsequent three weeks. Teams are encouraged to submit predictions for all forecast horizons, but it is not mandatory to cover every time period or location. Similarly, while teams are encouraged to forecast for all three targets, submitting predictions for all of them is not required. Predictions for the previous week's hospital bed occupancy (horizon -1) are optional and will not be scored in summary evaluations but may assist with calibration.

### Important Notes
Data for hospital bed occupancy from the preceding week will be available by the Friday deadline.
Forecasts for the previous week (horizon -1) will not be included in official evaluations but are encouraged.

If you have any questions regarding this challenge or the development of prediction targets, please contact Siddhesh S. Kadam at 4castinghub@uoguelph.ca.

### Acknowledgments
This repository follows the guidelines and standards outlined by the hubverse, which provides a set of data formats and open source tools for modeling hubs.
