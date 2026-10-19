# Generate the four epipredict hub models and the simple hub ensemble.
# Run from the repository root. By default, forecast the Saturday after the
# newest observed target week. The scheduled run uses the preceding Saturday
# and requires the previous week's PHO observations to be present.

required_packages <- c(
  "dplyr", "epipredict", "epiprocess", "hubEnsembles", "parsnip",
  "ranger", "readr", "tidyr"
)
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0) {
  stop("Install these R packages before forecasting: ",
       paste(missing_packages, collapse = ", "))
}

quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
diseases <- c("covid", "rsv", "flu")
locations <- c("Central", "East", "North East", "North West", "Ontario", "Toronto", "West")
horizons <- 0:3
model_ids <- c(
  flatline = "AI4Casting_Hub-Flatline",
  arx = "AI4Casting_Hub-Quantile_AR",
  rf_arx = "AI4Casting_Hub-RF_Quantile_AR",
  cdc = "AI4Casting_Hub-Quantile_Baseline"
)
ensemble_id <- "AI4Casting_Hub-Ensemble_v1"
excluded_from_ensemble <- c(
  ensemble_id, "AI4Casting_Hub-Weighted_Ensemble", "AI4Casting_Hub-GPT_4o"
)
hub_columns <- c(
  "location", "reference_date", "target_end_date", "target", "horizon",
  "output_type", "output_type_id", "value"
)

parse_options <- function(args) {
  if (length(args) == 0) return(list())
  if (identical(args, "--scheduled")) return(list(scheduled = TRUE))
  if (any(!grepl("^--(date|from|to)=\\d{4}-\\d{2}-\\d{2}$", args))) {
    stop("Usage: Rscript scripts/hub-model-forecasts.R [--scheduled | --date=YYYY-MM-DD | --from=YYYY-MM-DD --to=YYYY-MM-DD]")
  }
  names <- sub("^--([^=]+)=.*$", "\\1", args)
  if (anyDuplicated(names)) stop("Each date option may be supplied only once.")
  if ("date" %in% names && length(args) != 1L) {
    stop("Use --date alone or use --from with --to.")
  }
  if (xor("from" %in% names, "to" %in% names)) {
    stop("--from and --to must be supplied together.")
  }
  values <- as.Date(sub("^--[^=]+=", "", args), format = "%Y-%m-%d")
  if (anyNA(values)) stop("Invalid forecast date. Use YYYY-MM-DD.")
  result <- as.list(values)
  names(result) <- names
  result
}

scheduled_reference_date <- function(today = as.Date(Sys.time(), tz = "America/Toronto")) {
  today - ((as.POSIXlt(today)$wday - 6L) %% 7L)
}

read_target_history <- function() {
  roots <- c("auxiliary-data/target-data-archive", "target-data")
  paths <- unlist(lapply(roots, function(root) {
    if (!dir.exists(root)) return(character())
    list.files(root, pattern = "^hospitalization-data\\.csv$",
               recursive = TRUE, full.names = TRUE)
  }), use.names = FALSE)
  paths <- paths[grepl("[/\\\\]season_[0-9]{4}_[0-9]{4}[/\\\\]hospitalization-data\\.csv$", paths)]
  if (length(paths) == 0) stop("No target-data season files found.")

  data <- dplyr::bind_rows(lapply(paths, function(path) {
    piece <- readr::read_csv(path, show_col_types = FALSE)
    needed <- c("time", "geo_value")
    if (!all(needed %in% names(piece))) {
      stop("Missing target columns in ", path, ": ",
           paste(setdiff(needed, names(piece)), collapse = ", "))
    }
    for (disease in setdiff(diseases, names(piece))) piece[[disease]] <- NA_real_
    piece |>
      dplyr::transmute(
        time_value = as.Date(.data$time),
        geo_value = as.character(.data$geo_value),
        covid = as.numeric(.data$covid),
        rsv = as.numeric(.data$rsv),
        flu = as.numeric(.data$flu)
      )
  }))
  if (anyNA(data$time_value)) stop("Target history contains invalid dates.")
  if (anyDuplicated(data[c("time_value", "geo_value")])) {
    stop("Target history contains duplicate date/location rows.")
  }
  data
}

check_reference_date <- function(reference_date, history) {
  if (as.POSIXlt(reference_date)$wday != 6L) {
    stop("Reference dates must be Saturdays: ", reference_date)
  }
  origin <- reference_date - 7L
  current <- history[history$time_value == origin, , drop = FALSE]
  if (!setequal(current$geo_value, locations) || nrow(current) != length(locations)) {
    stop("Expected all seven target locations on ", origin,
         " before forecasting ", reference_date)
  }
  if (anyNA(current[diseases])) {
    stop("Target observations are missing for the week ending ", origin)
  }
  origin
}

format_predictions <- function(predictions, reference_date, disease, expected_dates) {
  wide <- epipredict::pivot_quantiles_wider(predictions, .pred_distn)
  quantile_names <- as.character(quantile_levels)
  needed <- c("geo_value", "target_date", quantile_names)
  if (!all(needed %in% names(wide))) {
    stop("epipredict returned unexpected prediction columns: ",
         paste(setdiff(needed, names(wide)), collapse = ", "))
  }
  result <- wide |>
    dplyr::select(dplyr::all_of(needed)) |>
    tidyr::pivot_longer(
      cols = dplyr::all_of(quantile_names),
      names_to = "output_type_id", values_to = "value"
    ) |>
    dplyr::mutate(
      target_end_date = as.Date(.data$target_date),
      reference_date = reference_date,
      horizon = as.integer((.data$target_end_date - reference_date) / 7),
      location = as.character(.data$geo_value),
      target = paste("wk inc", disease, "hosp"),
      output_type = "quantile",
      value = pmax(0, dplyr::case_when(
        as.numeric(.data$output_type_id) < 0.5 ~ floor(.data$value),
        as.numeric(.data$output_type_id) > 0.5 ~ ceiling(.data$value),
        TRUE ~ round(.data$value)
      ))
    ) |>
    dplyr::select(dplyr::all_of(hub_columns))

  if (anyNA(result$value) || any(!is.finite(result$value)) ||
      !setequal(result$target_end_date, expected_dates) ||
      !setequal(result$location, locations)) {
    stop("Incomplete or invalid ", disease, " predictions for ", reference_date)
  }
  result
}

forecast_one_disease <- function(history, reference_date, disease, method) {
  origin <- check_reference_date(reference_date, history)
  epi_data <- history |>
    dplyr::filter(.data$time_value <= origin, !is.na(.data[[disease]])) |>
    dplyr::select(dplyr::all_of(c("geo_value", "time_value", disease))) |>
    epiprocess::as_epi_df(
      geo_value = "geo_value", time_value = "time_value", as_of = reference_date
    )
  expected_dates <- reference_date + 7L * horizons

  if (method == "cdc") {
    predictions <- epipredict::cdc_baseline_forecaster(
      epi_data, outcome = disease,
      args_list = epipredict::cdc_baseline_args_list(
        data_frequency = "1 week", aheads = 1:4,
        forecast_date = origin, quantile_levels = quantile_levels
      )
    )$predictions
    return(format_predictions(predictions, reference_date, disease, expected_dates))
  }

  dplyr::bind_rows(lapply(seq_along(horizons), function(i) {
    ahead <- 7L * i
    if (method == "flatline") {
      fit <- epipredict::flatline_forecaster(
        epi_data, outcome = disease,
        args_list = epipredict::flatline_args_list(
          ahead = ahead, forecast_date = origin,
          quantile_levels = quantile_levels
        )
      )
    } else {
      args <- epipredict::arx_args_list(
        ahead = ahead, forecast_date = origin,
        quantile_levels = quantile_levels
      )
      if (method == "rf_arx") {
        set.seed(2026L + i)
        trainer <- parsnip::rand_forest(mode = "regression") |>
          parsnip::set_engine("ranger", seed = 2026L + i, num.threads = 1L)
        fit <- epipredict::arx_forecaster(
          epi_data, outcome = disease, trainer = trainer, args_list = args
        )
      } else {
        fit <- epipredict::arx_forecaster(
          epi_data, outcome = disease, args_list = args
        )
      }
    }
    format_predictions(fit$predictions, reference_date, disease,
                       expected_dates[i])
  }))
}

validate_model_output <- function(data, reference_date, model_id) {
  expected_count <- length(locations) * length(diseases) *
    length(horizons) * length(quantile_levels)
  keys <- c("location", "reference_date", "target_end_date", "target",
            "horizon", "output_type", "output_type_id")
  if (nrow(data) != expected_count || anyDuplicated(data[keys]) ||
      !setequal(data$horizon, horizons) ||
      !setequal(data$output_type_id, as.character(quantile_levels)) ||
      any(data$reference_date != reference_date) ||
      anyNA(data) || any(data$value < 0)) {
    stop("Incomplete or invalid hub output for ", model_id, " on ", reference_date)
  }
  invisible(data)
}

output_path <- function(model_id, reference_date) {
  file.path("model-output", model_id,
            sprintf("%s-%s.csv", reference_date, model_id))
}

read_ensemble_components <- function(reference_date, generated) {
  paths <- list.files("model-output", pattern = "\\.csv$",
                      recursive = TRUE, full.names = TRUE)
  prefix <- paste0(reference_date, "-")
  paths <- paths[startsWith(basename(paths), prefix)]
  model_names <- basename(dirname(paths))
  paths <- paths[!model_names %in% c(excluded_from_ensemble, unname(model_ids))]
  model_names <- basename(dirname(paths))
  if (anyDuplicated(model_names)) {
    stop("Multiple component files exist for a model on ", reference_date)
  }
  other_models <- lapply(seq_along(paths), function(i) {
    piece <- readr::read_csv(paths[[i]], show_col_types = FALSE)
    if (!all(hub_columns %in% names(piece))) {
      stop("Missing hub columns in ensemble component: ", paths[[i]])
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
        model_id = model_names[[i]]
      ) |>
      dplyr::filter(
        .data$location %in% locations,
        .data$target %in% paste("wk inc", diseases, "hosp"),
        .data$horizon %in% horizons,
        .data$output_type_id %in% as.character(quantile_levels),
        .data$target_end_date == reference_date + 7L * .data$horizon
      )
  })
  own_models <- lapply(names(generated), function(model_id) {
    dplyr::mutate(generated[[model_id]], model_id = model_id)
  })
  dplyr::bind_rows(c(own_models, other_models))
}

run_for_date <- function(reference_date, history) {
  check_reference_date(reference_date, history)
  message("Forecasting ", reference_date)
  generated <- lapply(names(model_ids), function(method) {
    model_id <- model_ids[[method]]
    message("  ", model_id)
    data <- dplyr::bind_rows(lapply(diseases, function(disease) {
      forecast_one_disease(history, reference_date, disease, method)
    }))
    validate_model_output(data, reference_date, model_id)
    data
  })
  names(generated) <- unname(model_ids)

  components <- read_ensemble_components(reference_date, generated)
  if (nrow(components) == 0) stop("No ensemble components for ", reference_date)
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
  validate_model_output(ensemble, reference_date, ensemble_id)
  generated[[ensemble_id]] <- ensemble

  for (model_id in names(generated)) {
    path <- output_path(model_id, reference_date)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    readr::write_csv(generated[[model_id]], path)
    message("  Wrote ", path, " (", nrow(generated[[model_id]]), " rows)")
  }
  invisible(generated)
}

options <- parse_options(commandArgs(trailingOnly = TRUE))
history <- read_target_history()
dates <- if ("scheduled" %in% names(options)) {
  reference_date <- scheduled_reference_date()
  expected_observation <- reference_date - 7L
  latest_observation <- max(history$time_value)
  if (latest_observation != expected_observation) {
    stop("Scheduled forecast expects PHO targets through ", expected_observation,
         "; latest available week is ", latest_observation,
         ". Check the Friday PHO data update before rerunning.")
  }
  reference_date
} else if ("date" %in% names(options)) {
  options$date
} else if ("from" %in% names(options)) {
  if (options$from > options$to ||
      as.integer(options$to - options$from) %% 7L != 0L) {
    stop("--from and --to must be ordered Saturdays exactly seven days apart.")
  }
  seq(options$from, options$to, by = "7 days")
} else {
  max(history$time_value) + 7L
}

for (i in seq_along(dates)) run_for_date(dates[i], history)
