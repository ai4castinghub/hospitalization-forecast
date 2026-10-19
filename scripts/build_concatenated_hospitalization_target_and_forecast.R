library(dplyr)
library(readr)
library(tidyr)
library(lubridate)
library(purrr)
withr::local_options(list(readr.show_col_types = FALSE))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L || (length(args) == 1L && args[[1]] != "--models-only")) {
  stop("Usage: Rscript scripts/build_concatenated_hospitalization_target_and_forecast.R [--models-only]")
}
models_only <- length(args) == 1L

if (!models_only) {
  # Include every archived season and the current target-data season.
  target_roots <- c("auxiliary-data/target-data-archive", "target-data")
  target_files <- unlist(lapply(target_roots, function(root) {
    if (!dir.exists(root)) return(character())
    list.files(root, pattern = "^hospitalization-data\\.csv$",
               recursive = TRUE, full.names = TRUE)
  }), use.names = FALSE)
  target_files <- target_files[
    grepl("[/\\\\]season_[0-9]{4}_[0-9]{4}[/\\\\]hospitalization-data\\.csv$",
          target_files)
  ]
  if (length(target_files) == 0L) stop("No season target data files found.")

  season_dirs <- basename(dirname(target_files))
  season_labels <- sub("^season_([0-9]{4})_([0-9]{4})$", "\\1-\\2", season_dirs)
  if (anyDuplicated(season_labels)) {
    stop("A target season is present in both the archive and target-data.")
  }

  final_data <- purrr::map2_dfr(target_files, season_labels, function(file, season) {
    readr::read_csv(file, col_types = readr::cols(.default = readr::col_guess(),
                                                 time = readr::col_date())) %>%
      dplyr::mutate(Season = season)
  }) %>%
    dplyr::mutate(time = lubridate::as_date(time)) %>%
    dplyr::arrange(dplyr::desc(time))

  readr::write_csv(final_data, "auxiliary-data/concatenated_hospitalization_data.csv")
  message("Wrote: auxiliary-data/concatenated_hospitalization_data.csv")
}

# concatenate model outputs (robust date parsing, filename-date filter)

model_output_dir <- "model-output"

parse_maybe_date <- function(x) {
  suppressWarnings({
    num <- as.numeric(x)
    out <- as_date(num, origin = "1970-01-01")          
    need <- is.na(out)
    if (any(need)) {
      out[need] <- as_date(parse_date_time(
        x[need],
        orders = c("Ymd", "Y-m-d", "dmY", "d-m-Y", "Ymd HMS", "Y-m-d H:M:S"),
        tz = "UTC"
      ))
    }
    out
  })
}

process_model_file <- function(file) {
  model_name <- basename(dirname(file))
  df <- read_csv(file, progress = FALSE)
  
  df %>%
    mutate(
      model = model_name,
      reference_date  = if ("reference_date"  %in% names(.)) parse_maybe_date(reference_date)  else as_date(NA),
      target_end_date = if ("target_end_date" %in% names(.)) parse_maybe_date(target_end_date) else as_date(NA),
      value = pmax(0, ceiling(suppressWarnings(as.numeric(replace_na(value, 0)))))
    ) %>%
    filter(!is.na(reference_date), !is.na(target_end_date))
}

# keep only files whose basename starts with a date >= 2025-08-30 ---
extract_leading_date <- function(paths) {
  bases <- basename(paths)
  m <- regexpr("^\\d{4}-\\d{2}-\\d{2}", bases)
  # Pull the matched date string, or NA if no match
  ds <- ifelse(m == -1, NA_character_, regmatches(bases, m))
  ymd(ds)
}

cutoff_date <- as_date("2025-08-30")
all_csvs <- list.files(model_output_dir, pattern = "\\.csv$", full.names = TRUE, recursive = TRUE)

if (length(all_csvs) == 0) {
  message("No model CSV files found under: ", model_output_dir)
  all_model_data <- tibble()
} else {
  file_dates <- extract_leading_date(all_csvs)
  keep <- !is.na(file_dates) & file_dates >= cutoff_date
  model_files <- all_csvs[keep]
  
  all_model_data <- if (length(model_files) == 0) {
    message("No model CSV files on or after ", cutoff_date, " with a leading YYYY-MM-DD in the filename.")
    tibble()
  } else {
    map_dfr(model_files, process_model_file) %>%
      arrange(model, desc(reference_date), desc(target_end_date))
  }
}

readr::write_csv(all_model_data, "auxiliary-data/concatenated_model_output.csv")
message("Wrote: auxiliary-data/concatenated_model_output.csv")
