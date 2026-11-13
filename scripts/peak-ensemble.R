peak_ensemble_rows <- function(paths, reference_date, locations, quantile_levels, excluded_model_ids) {
  weeks <- seq(as.Date('2026-10-17'), as.Date('2027-05-29'), by = '7 days')
  if (reference_date < as.Date('2026-10-24') || reference_date > max(weeks)) return(tibble::tibble())
  targets <- c('peak week inc flu hosp', 'peak inc flu hosp')
  hub_peak_models <- c('AI4Casting_Hub-PeakBaseline', 'AI4Casting_Hub-PeakAR', 'AI4Casting_Hub-PeakRF')
  status_file <- file.path('target-data', 'season_2026_2027', 'influenza-admissions-status.csv')
  admissions_available <- tryCatch({
    status <- readr::read_csv(status_file, show_col_types = FALSE,
                              col_types = readr::cols(.default = readr::col_character()))
    'status' %in% names(status) && nrow(status) == 1L &&
      !is.na(status$status[[1]]) && status$status[[1]] == 'available'
  }, error = function(e) FALSE)
  groups <- list()
  for (path in paths) {
    model <- basename(dirname(path))
    if (model %in% hub_peak_models && !admissions_available) {
      message('Skipping hub peak forecast because influenza admissions are unavailable: ', model)
      next
    }
    metadata_files <- file.path('model-metadata', paste0(model, c('.yml', '.yaml')))
    metadata_files <- metadata_files[file.exists(metadata_files)]
    if (model %in% excluded_model_ids || length(metadata_files) != 1L) next
    metadata_file <- metadata_files[[1]]
    metadata <- tryCatch(yaml::read_yaml(metadata_file), error = function(e) NULL)
    if (is.null(metadata) || isTRUE(metadata$ensemble_of_hub_models) ||
        !(isTRUE(metadata$designated_model) || model %in% hub_peak_models)) next
    data <- tryCatch(readr::read_csv(path, show_col_types = FALSE,
                                    col_types = readr::cols(.default = readr::col_character())),
                     error = function(e) NULL)
    required <- c('reference_date', 'location', 'target', 'target_end_date', 'horizon', 'output_type', 'output_type_id', 'value')
    if (is.null(data) || !all(required %in% names(data))) next
    data <- data |> dplyr::filter(.data$target %in% targets, .data$location %in% locations,
                                  .data$reference_date == as.character(reference_date))
    if (!nrow(data)) next
    for (location in unique(data$location)) for (target in targets) {
      x <- data[data$location == location & data$target == target, , drop = FALSE]
      if (!nrow(x)) next
      ids <- x$output_type_id
      value <- suppressWarnings(as.numeric(x$value))
      blank <- function(v) all(is.na(v) | trimws(v) == '')
      valid <- blank(x$target_end_date) && blank(x$horizon) && !anyDuplicated(ids) &&
        all(is.finite(value) & value >= 0)
      if (target == targets[1]) {
        valid <- valid && all(x$output_type == 'pmf') && length(ids) == length(weeks) &&
          setequal(ids, as.character(weeks)) && all(value <= 1) && abs(sum(value) - 1) <= 1e-6
        expected <- as.character(weeks)
      } else {
        numeric_ids <- suppressWarnings(as.numeric(ids))
        valid <- valid && all(x$output_type == 'quantile') && length(ids) == length(quantile_levels) &&
          !anyNA(numeric_ids) && setequal(numeric_ids, quantile_levels) &&
          all(value == floor(value)) && !is.unsorted(value[order(numeric_ids)])
        expected <- as.character(quantile_levels)
        ids <- as.character(numeric_ids)
      }
      if (!isTRUE(valid)) { message('Skipping invalid peak forecast: ', model, ' / ', location, ' / ', target); next }
      key <- paste(location, target, sep = '|')
      groups[[key]] <- c(groups[[key]], list(data.frame(location = location, target = target,
                                                        output_type_id = expected,
                                                        value = value[match(expected, ids)])))
    }
  }
  if (!length(groups)) return(tibble::tibble())
  dplyr::bind_rows(lapply(groups, function(members) {
    x <- dplyr::bind_rows(members)
    x |>
      dplyr::group_by(.data$location, .data$target, .data$output_type_id) |>
      dplyr::summarise(value = if (dplyr::first(.data$target) == targets[1]) mean(.data$value) else round(median(.data$value)), .groups = 'drop') |>
      dplyr::mutate(reference_date = reference_date, target_end_date = as.Date(NA),
                    horizon = NA_integer_, output_type = ifelse(.data$target == targets[1], 'pmf', 'quantile')) |>
      dplyr::select(location, reference_date, target_end_date, target, horizon, output_type, output_type_id, value)
  }))
}
