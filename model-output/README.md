# Model Outputs Folder Overview

This folder contains subdirectories for each model, which hold the submitted model output files. The structure and contents of these directories follow the [model output guidelines in our documentation]([https://hubdocs.readthedocs.io/en/latest/format/model-output.html](https://hubverse.io/en/latest/user-guide/model-output.html)). Below, we outline instructions specifically for AI4Casting Hub submissions.

# Data Submission Instructions

Submit all forecasts directly to the [model-output/](./) folder by creating a pull request after forking the repository and adding submissions. This process ensures that automatic data validation checks are performed.

These instructions cover details on [data formatting](#Data-formatting) and [forecast validation](#Forecast-validation), which you can perform before submitting the pull request. Additionally, [metadata](https://github.com/ai4castinghub/hospitalization-forecast/blob/main/model-metadata/README.md) required for each model should be provided in the model-metadata folder prior to or with any forecast submissions.

**Table of Contents**:
- [What is a forecast](#What-is-a-forecast)
- [Target data](#Target-data)
- [Data formatting](#Data-formatting)
- [Forecast file format](#Forecast-file-format)
- [Forecast data validation](#Forecast-validation)
- [Policy on late submissions](#policy-on-late-or-updated-submissions)

## What is a Forecast?

Forecasts are quantitative predictions about data to be observed in the future. These are considered "unconditional" predictions, meaning they should represent uncertainty across all possible future scenarios, not just specific ones (like increased vaccination rates or new social-distancing policies). Forecasts submitted here will be evaluated against actual observed data.

## Target Data

This project focuses on hospital bed occupancy data for COVID-19, Influenza, and RSV, as reported in the [Ontario Respiratory Virus Tool](https://www.publichealthontario.ca/en/Data-and-Analysis/Infectious-Disease/Respiratory-Virus-Tool). Further details regarding the target-data can be found in the [target-data folder README](../target-data/README.md).

Teams are encouraged to submit predictions for all forecast horizons, but it is not mandatory to cover every time period or location. Similarly, while teams are encouraged to forecast for all three targets, submitting predictions for all of them is not required. Predictions for the previous week's hospital admissions (horizon -1) are optional and will not be scored in summary evaluations.

## Data Formatting

Automatic checks validate the filename and contents of forecast files to ensure compatibility with visualization and ensemble forecasting.

### Subdirectory

Each model submitting forecasts will have a unique subdirectory in the [model-output/](model-output/) directory. The subdirectory should be named as follows:

    team-model

Where:
- `team` is the team name
- `model` is the model name

Both `team` and `model` should be under 15 characters and not contain special characters, except for underscores (`_`). Each team-model combination must be unique.

### Metadata

The metadata file for each model must follow this naming convention and be placed in the model-metadata directory:

    team-model.yml

For more details, see the [model-metadata README](https://github.com/ai4castinghub/hospitalization-forecast/blob/main/model-metadata/README.md).

### Forecasts

Each forecast file should be named as follows:

    YYYY-MM-DD-team-model.csv

Where:
- `YYYY` is the 4-digit year
- `MM` is the 2-digit month
- `DD` is the 2-digit day
- `team` is the team name
- `model` is the model name

The `YYYY-MM-DD` date should be the Saturday following the submission date and match the `reference_date` inside the file. The `team` and `model` in the filename must match the subdirectory names.

## Forecast File Format

The forecast file should be a CSV with the following columns:

- `reference_date`
- `target`
- `horizon`
- `target_end_date`
- `location`
- `output_type`
- `output_type_id`
- `value`

No additional columns are allowed.

Each row in the file represents a quantile prediction for a specific location, date, and horizon.

### `reference_date`

This date (in `YYYY-MM-DD` format) indicates when the forecast is made. It should always be the Saturday following the submission date.

### `target`

This column must contain one of the following target strings:
- `wk inc flu hosp` (Influenza Hospital Bed Occupancy Count)
- `wk inc rsv hosp` (RSV Hospital Bed Occupancy Count)
- `wk inc covid hosp` (COVID-19 Hospital Bed Occupancy Count)

### `horizon`

Indicates the number of weeks between the `reference_date` and the `target_end_date`. A horizon of `0` represents a nowcast, while a horizon of `1` represents a forecast for the following week. Submissions are expected to provide forecasts for the end of the reference week (horizon `0`) and the subsequent three weeks (horizon `1`,`2` and `3`) and may also choose to submit a hindcast for a week before (horizon `-1`).

### `target_end_date`

The last date of the forecast target’s week, formatted as `YYYY-MM-DD`. It is the Saturday at the end of the forecasted week.

### `location`

This should match one of the "OH_Name" in the [location information file](../auxiliary-data/phu_region_mapping.csv). 
The regions of interests are: 
* Province: `Ontario`
* Public Health Regions: `North East`, `West`, `East`, `Central`, `North West` and `Toronto`

### `output_type`

This column should be set to `quantile`, representing probabilistic quantile forecasts for hospital bed occupancy.

    0.###

### `output_type_id`

For quantile forecasts, this column specifies the quantile probability level, formatted as `0.###`. This value indicates the quantile probability level for for the
`value` in this row.

Teams must provide the following 7 quantiles:

`0.025`, `0.1`, `0.25`, `0.5`, `0.75`, `0.9` and `0.975`


### `value`

Values in the `value` column are non-negative integer numbers indicating the "quantile" prediction for this row. For a "quantile" prediction, `value` is the inverse of the cumulative distribution function (CDF) for the target, location, and quantile associated with that row. For example, the 2.5 and 97.5 quantiles for a given target and location should capture 95% of the predicted values and correspond to the central 95% Prediction Interval.

For predicted hospital bed occupancy (count), forecast `value` for quantiles less than 0.5 should be rounded down, `value` for quantiles greater than 0.5 should be rounded up, and `value` for the 0.5 quantile should be rounded normally. This rounding procedure will ensure that teams are not penalized for missing the prediction interval by less than one hospital bed occupancy. 


### Example tables

**Table 1:** This table represents a forecast for the week ending on 2024-10-12 for flu hospitalizations in the Central region. The forecast includes quantile predictions ranging from the 2.5th to the 97.5th percentiles. The horizon of -1 indicates this is a hindcast for the previous week relative to the reference_date of 2024-10-19.

| reference_date | target          | horizon | location | target_end_date | output_type | output_type_id | value |
|----------------|-----------------|---------|----------|-----------------|-------------|----------------|-------|
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.025          | 30    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.1            | 32    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.25           | 33    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.5            | 35    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.75           | 37    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.9            | 38    |
| 2024-10-19     | wk inc flu hosp | -1      | Central  | 2024-10-12      | quantile    | 0.975          | 40    |



## Forecast validation 

To ensure proper data formatting, pull requests for new data in
`model-output/` will be automatically run. Optionally, you may also run these validations locally.

### Pull request forecast validation

When a pull request is submitted, the data are validated through [Github
Actions](https://docs.github.com/en/actions) which runs the tests to validate the requirements above. Please
[let us know](https://github.com/ai4castinghub/hospitalization-forecast/issues) if you are facing issues while running the tests.

### Local forecast validation

Optionally, you may validate a forecast file locally before submitting it to the hub in a pull request. Note that this is not required, since the validations will also run on the pull request. To run the validations locally, follow these steps:

1. Create a fork of the `hospitalization-forecast` repository and then clone the fork to your computer.
2. Create a draft of the model submission file for your model and place it in the `model-output/<your model id>` folder of this clone.
3. Install the hubValidations package for R by running the following command from within an R session:
``` r
install.packages("hubValidations", repos = c("https://hubverse-org.r-universe.dev", "https://cloud.r-project.org"))
```
4. Validate your draft forecast submission file by running the following command in an R session:
``` r
library(hubValidations)
hubValidations::validate_submission(
    hub_path="<path to your clone of the hub repository>",
    file_path="<path to your file, relative to the model-output folder>")
```

For example, if your working directory is the root of the hub repository, you can use a command similar to the following:
``` r
library(hubValidations)
hubValidations::validate_submission(
    hub_path=".",
    file_path="F-trends/2024-11-12-F-trends.csv")
```
The function returns the output of each validation check.

If all is well, all checks should either be prefixed with a `✔` indicating success or `ℹ` indicating a check was skipped, e.g.:
```
✔ 2024-11-12-F-trends.csv: File exists at path model-output/F-trends/2024-11-12-F-trends.csv.
✔ 2024-11-12-F-trends.csv: File name "2022-10-22-team1-goodmodel.csv" is valid.
✔ 2024-11-12-F-trends.csv: File directory name matches `model_id` metadata in file name.
✔ 2024-11-12-F-trends.csv: `round_id` is valid.
✔ 2024-11-12-F-trends.csv: File is accepted hub format.
...
```

If there are any failed checks or execution errors, the check's output will be prefixed with a `✖` or `!` and include a message describing the problem.

To get an overall assessment of whether the file has passed validation checks, you can pass the output of `validate_submission()` to `check_for_errors()`
```r
library(hubValidations)

validations <- validate_submission(
    hub_path = ".",
    file_path = "F-trends/2024-11-12-F-trends.csv")

check_for_errors(validations)
```
If the file passes all validation checks, the function will return the following output:

```r
✔ All validation checks have been successful.
```
If test failures or execution errors are detected, the function throws an error and prints the messages of checks affected. For example, the following output is returned when all other checks have passed but the file is being validated outside the submission time window for the round:

```r
! 2024-11-12-F-trends.csv: Submission time must be within accepted submission window for round.  Current time
  2024-11-12 10:00:08 is outside window 2024-11-01 EDT--2024-11-07 23:59:59 EDT.
Error in `check_for_errors()`:
! 
The validation checks produced some failures/errors reported above.
```


## Policy on late or updated submissions 

In order to ensure that forecasting is done in real-time, all forecasts are required to be submitted to this repository by 11PM America/Toronto on Fridays each week. We do not accept late forecasts.

## Evaluation criteria
Forecasts will be evaluated using `Weighted Interval Score (WIS)`, `Absolute Error (AE)` and `Mean Squared Error (MSE)`. The CMU [Delphi group's Forecast Evaluation Dashboard](https://delphi.cmu.edu/forecast-eval/) and the COVID-19 Forecast Hub periodic [Forecast Evaluation Reports](https://covid19forecasthub.org/eval-reports/) provide examples of evaluations using these criteria.
