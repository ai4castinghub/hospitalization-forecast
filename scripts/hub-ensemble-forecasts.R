# Create the hub's simple ensemble from submitted forecasts for one Saturday.
# Run from the repository root after the four hub model files are present.

required_packages <- c("dplyr", "hubEnsembles", "readr")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop("Install these R packages before ensembling: ",
       paste(missing_packages, collapse = ", "))
}

quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
diseases <- c("covid", "rsv", "flu")
locations <- c("Central", "East", "North East", "North West", "Ontario", "Toronto", "West")
horizons <- 0:3
hub_model_ids <- c(
  "AI4Casting_Hub-Flatline", "AI4Casting_Hub-Quantile_AR",
  "AI4Casting_Hub-RF_Quantile_AR", "AI4Casting_Hub-Quantile_Baseline"
)
ensemble_id <- "AI4Casting_Hub-Ensemble_v1"
excluded_model_ids <- c(
  ensemble_id, "AI4Casting_Hub-Weighted_Ensemble", "AI4Casting_Hub-GPT_4o"
)
hub_columns <- c(
  "location", "reference_date", "target_end_date", "target", "horizon",
  "output_type", "output_type_id", "value"
)

output_path <- function(model_id, reference_date) {
  file.path("model-output", model_id,
            sprintf("%s-%s.csv", reference_date, model_id))
}

latest_complete_reference_date <- function() {
  dates_by_model <- lapply(hub_model_ids, function(model_id) {
    directory <- file.path("model-output", model_id)
    if (!dir.exists(directory)) return(character())
    paths <- list.files(directory, pattern = "\\.csv$", full.names = TRUE)
    dates <- substr(basename(paths), 1L, 10L)
    dates[basename(paths) == paste0(dates, "-", model_id, ".csv")]
  })
  common <- Reduce(intersect, dates_by_model)
  if (length(common) == 0L) {
    stop("No reference date has all four hub model forecast files.")
  }
  as.Date(max(common))
}

parse_reference_date <- function(args) {
  if (length(args) == 0L) return(latest_complete_reference_date())
  if (length(args) != 1L ||
      !grepl("^--date=[0-9]{4}-[0-9]{2}-[0-9]{2}$", args)) {
    stop("Usage: Rscript scripts/hub-ensemble-forecasts.R [--date=YYYY-MM-DD]")
  }
  date <- tryCatch(as.Date(sub("^--date=", "", args)), error = function(e) NA)
  if (is.na(date) || as.POSIXlt(date)$wday != 6L) {
    stop("The ensemble reference date must be a valid Saturday.")
  }
  date
}

read_component <- function(path, reference_date) {
  model_id <- basename(dirname(path))
  piece <- readr::read_csv(path, show_col_types = FALSE)
  if (!all(hub_columns %in% names(piece))) {
    stop("Missing hub columns in ensemble component: ", path)
  }
  piece |>
    dplyr::filter(.data$output_type == "quantile",
                  as.Date(.data$reference_date) == reference_date) |>
    dplyr::select(dplyr::all_of(hub_columns)) |>
    dplyr::mutate(
      reference_date = as.Date(.data$reference_date),
      target_end_date = as.Date(.data$target_end_date),
      output_type_id = as.character(.data$output_type_id),
      value = as.numeric(.data$value),
      model_id = model_id
    ) |>
    dplyr::filter(
      .data$location %in% locations,
      .data$target %in% paste("wk inc", diseases, "hosp"),
      .data$horizon %in% horizons,
      .data$output_type_id %in% as.character(quantile_levels),
      .data$target_end_date == reference_date + 7L * .data$horizon
    )
}

validate_output <- function(data, reference_date) {
  expected_count <- length(locations) * length(diseases) *
    length(horizons) * length(quantile_levels)
  keys <- c("location", "reference_date", "target_end_date", "target",
            "horizon", "output_type", "output_type_id")
  if (nrow(data) != expected_count || anyDuplicated(data[keys]) ||
      !setequal(data$horizon, horizons) ||
      !setequal(data$output_type_id, as.character(quantile_levels)) ||
      any(data$reference_date != reference_date) ||
      anyNA(data) || any(data$value < 0)) {
    stop("Incomplete or invalid hub ensemble for ", reference_date)
  }
  invisible(data)
}

run_for_date <- function(reference_date) {
  own_paths <- vapply(hub_model_ids, output_path, character(1),
                      reference_date = reference_date)
  if (!all(file.exists(own_paths))) {
    stop("Missing hub model files for ", reference_date, ": ",
         paste(hub_model_ids[!file.exists(own_paths)], collapse = ", "))
  }

  paths <- list.files("model-output", pattern = "\\.csv$",
                      recursive = TRUE, full.names = TRUE)
  model_ids <- basename(dirname(paths))
  paths <- paths[
    basename(paths) == paste0(reference_date, "-", model_ids, ".csv") &
      !model_ids %in% excluded_model_ids
  ]
  model_ids <- basename(dirname(paths))
  if (anyDuplicated(model_ids)) {
    stop("Multiple component files exist for a model on ", reference_date)
  }

  components <- dplyr::bind_rows(lapply(paths, read_component,
                                        reference_date = reference_date))
  for (model_id in hub_model_ids) {
    validate_output(components[components$model_id == model_id, hub_columns],
                    reference_date)
  }

  ensemble <- hubEnsembles::simple_ensemble(
    components, agg_fun = mean, model_id = ensemble_id
  ) |>
    dplyr::select(-"model_id") |>
    dplyr::select(dplyr::all_of(hub_columns)) |>
    dplyr::mutate(
      output_type_id = as.character(.data$output_type_id),
      value = pmax(0, dplyr::case_when(
        as.numeric(.data$output_type_id) < 0.5 ~ floor(.data$value),
        as.numeric(.data$output_type_id) > 0.5 ~ ceiling(.data$value),
        TRUE ~ round(.data$value)
      ))
    )
  validate_output(ensemble, reference_date)

  path <- output_path(ensemble_id, reference_date)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_csv(ensemble, path)
  message("Wrote ", path, " (", nrow(ensemble), " rows from ",
          length(paths), " models)")
  invisible(ensemble)
}

run_for_date(parse_reference_date(commandArgs(trailingOnly = TRUE)))
