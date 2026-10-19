# PHO hospital bed occupancy target data

The current respiratory season's processed target data is stored in a
`season_YYYY_YYYY/hospitalization-data.csv` directory. Earlier seasons are
stored under `auxiliary-data/target-data-archive/`.

The weekly `Update PHO target data` GitHub Actions workflow retrieves the
public Outcomes data table from Public Health Ontario's
[Ontario Respiratory Virus Tool](https://www.publichealthontario.ca/en/Data-and-Analysis/Infectious-Disease/Respiratory-Virus-Tool).
PHO updates the dashboard on Friday morning. The hub's scheduled retrieval runs
Friday at 12:30 p.m. America/Toronto time, providing the preceding week's
observations for the Saturday forecast round. For the 2026-2027 season, the
Friday updates run from October 23, 2026 through May 28, 2027.
It saves the unmodified Power BI CSV export as
`auxiliary-data/pho-outcomes.csv` before running
`scripts/get_target_data.R`.
To retrieve the PHO data locally, change to `scripts/`, run `npm ci`, then run
`npm run fetch:pho-outcomes`. The CSV is still written to `auxiliary-data/`.

The processing script:

- verifies the required PHO column headers and three total bed-occupancy outcomes;
- maps public health units to Ontario Health Regions using
  `auxiliary-data/phu_region_mapping.csv`;
- aggregates PHU counts into the six regions while retaining the published
  Ontario total;
- writes `time`, `geo_value`, `geo_type`, `covid`, `flu`, and `rsv` columns;
- validates dates, locations, and unique time/location keys; and
- automatically archives the previous target season when PHO starts a new one.

The raw `Number` values represent beds occupied by people with COVID-19,
influenza, or RSV, irrespective of whether the infection was the primary reason
for admission.
