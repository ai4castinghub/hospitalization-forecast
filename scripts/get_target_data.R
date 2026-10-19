library(dplyr)
library(lubridate)
library(readr)
library(tidyr)

# The Power BI export is deliberately retained as the raw source artifact.
pho_outcomes_file <- "./auxiliary-data/pho-outcomes.csv"
phu_region_mapping_file <- "./auxiliary-data/phu_region_mapping.csv"
target_dir <- "./target-data"
archive_dir <- "./auxiliary-data/target-data-archive"

required_outcomes <- c(
  covid = "COVID-19 hospital bed occupancy (total)",
  flu = "Influenza hospital bed occupancy (total)",
  rsv = "RSV hospital bed occupancy (total)"
)
required_headers <- c(
  "Public health unit", "Outcome", "Respiratory season",
  "Surveillance week", "Week end date", "Number"
)

stopifnot(
  file.exists(pho_outcomes_file),
  file.exists(phu_region_mapping_file)
)

# ---- Read and validate the raw Power BI export ----
hospital_bed_occupancy_raw <- read_csv(
  pho_outcomes_file,
  show_col_types = FALSE,
  na = c("", "NA")
)

# Power BI occasionally adds a UTF-8 BOM or whitespace to exported headers.
names(hospital_bed_occupancy_raw) <- trimws(
  sub("^\\ufeff", "", names(hospital_bed_occupancy_raw))
)

missing_headers <- setdiff(required_headers, names(hospital_bed_occupancy_raw))
if (length(missing_headers) > 0) {
  stop(
    "PHO export is missing required headers: ",
    paste(missing_headers, collapse = ", ")
  )
}

phu_region_mapping <- read_csv(
  phu_region_mapping_file,
  show_col_types = FALSE,
  col_types = cols(.default = col_character())
)

season_values <- hospital_bed_occupancy_raw |>
  transmute(season = trimws(as.character(`Respiratory season`))) |>
  filter(grepl("^[0-9]{4}-[0-9]{2}$", season)) |>
  distinct() |>
  pull(season)

if (length(season_values) != 1) {
  stop(
    "Expected exactly one respiratory season in the PHO export; found: ",
    paste(season_values, collapse = ", ")
  )
}

current_season <- season_values[[1]]
current_start_year <- as.integer(substr(current_season, 1, 4))
current_end_year <- current_start_year + 1L
current_season_dir_name <- sprintf(
  "season_%d_%d", current_start_year, current_end_year
)

target_rows <- hospital_bed_occupancy_raw |>
  transmute(
    `Public health unit` = trimws(as.character(`Public health unit`)),
    Outcome = trimws(as.character(Outcome)),
    time = as.Date(parse_date_time(
      as.character(`Week end date`),
      orders = c("ymd HMS", "ymd"),
      quiet = TRUE
    )),
    Number = suppressWarnings(as.numeric(Number))
  ) |>
  filter(
    !is.na(`Public health unit`),
    `Public health unit` != "",
    Outcome %in% unname(required_outcomes)
  )

if (nrow(target_rows) == 0) {
  stop("The PHO export contains no usable bed-occupancy target rows.")
}
if (any(is.na(target_rows$time))) {
  stop("One or more PHO 'Week end date' values could not be parsed.")
}

missing_outcomes <- setdiff(unname(required_outcomes), unique(target_rows$Outcome))
if (length(missing_outcomes) > 0) {
  stop(
    "PHO export is missing required outcomes: ",
    paste(missing_outcomes, collapse = ", ")
  )
}

unmapped_phus <- target_rows |>
  anti_join(phu_region_mapping, by = c("Public health unit" = "NAME_ENG")) |>
  distinct(`Public health unit`) |>
  pull(`Public health unit`)
if (length(unmapped_phus) > 0) {
  stop(
    "PHO export contains public health units absent from the mapping: ",
    paste(unmapped_phus, collapse = ", ")
  )
}

# Preserve a missing aggregate if every contributing PHU is missing; otherwise
# add the reported PHU values for the Ontario Health Region.
sum_or_na <- function(values) {
  if (all(is.na(values))) NA_real_ else sum(values, na.rm = TRUE)
}

hospital_bed_occupancy <- target_rows |>
  left_join(
    phu_region_mapping,
    by = c("Public health unit" = "NAME_ENG")
  ) |>
  select(time, OH_Name, Outcome, Number) |>
  group_by(time, OH_Name, Outcome) |>
  summarise(Number = sum_or_na(Number), .groups = "drop") |>
  pivot_wider(names_from = Outcome, values_from = Number) |>
  rename(
    geo_value = OH_Name,
    covid = all_of(required_outcomes[["covid"]]),
    flu = all_of(required_outcomes[["flu"]]),
    rsv = all_of(required_outcomes[["rsv"]])
  ) |>
  mutate(
    geo_type = if_else(geo_value == "Ontario", "Province", "OH Region"),
    across(c(covid, flu, rsv), ~ as.integer(ceiling(.x)))
  ) |>
  select(time, geo_value, geo_type, covid, flu, rsv) |>
  arrange(desc(time), geo_value)

expected_geographies <- sort(unique(phu_region_mapping$OH_Name))
actual_geographies <- sort(unique(hospital_bed_occupancy$geo_value))
if (!identical(expected_geographies, actual_geographies)) {
  stop(
    "Processed target geographies do not match the PHU mapping. Expected: ",
    paste(expected_geographies, collapse = ", "),
    "; found: ",
    paste(actual_geographies, collapse = ", ")
  )
}

duplicate_keys <- hospital_bed_occupancy |>
  count(time, geo_value) |>
  filter(n != 1)
if (nrow(duplicate_keys) > 0) {
  stop("Processed target data contains duplicate time/geography keys.")
}

# ---- Rotate the previous current season into the archive ----
dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)

current_target_dir <- file.path(target_dir, current_season_dir_name)
other_target_seasons <- list.dirs(target_dir, recursive = FALSE, full.names = TRUE)
other_target_seasons <- other_target_seasons[
  grepl("^season_[0-9]{4}_[0-9]{4}$", basename(other_target_seasons)) &
    basename(other_target_seasons) != current_season_dir_name
]

for (old_dir in other_target_seasons) {
  archive_destination <- file.path(archive_dir, basename(old_dir))
  if (dir.exists(archive_destination)) {
    stop("Cannot archive target season because it already exists: ", archive_destination)
  }
  if (!file.rename(old_dir, archive_destination)) {
    stop("Failed to archive old target season: ", old_dir)
  }
  message("Archived previous target season: ", archive_destination)
}

dir.create(current_target_dir, recursive = TRUE, showWarnings = FALSE)
target_file <- file.path(current_target_dir, "hospitalization-data.csv")
write_csv(hospital_bed_occupancy, target_file, na = "NA")

message(sprintf(
  "Processed %d PHO rows into %d target rows for %s (%s through %s): %s",
  nrow(target_rows),
  nrow(hospital_bed_occupancy),
  current_season,
  min(hospital_bed_occupancy$time),
  max(hospital_bed_occupancy$time),
  target_file
))
