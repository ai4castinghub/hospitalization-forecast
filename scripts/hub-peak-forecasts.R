suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(lubridate)
})

peak_weeks <- seq(as.Date('2026-10-17'), as.Date('2027-05-29'), by = '7 days')
peak_quantiles <- c(.025, .1, .25, .5, .75, .9, .975)
peak_locations <- c('Ontario', 'Central', 'East', 'North East', 'North West', 'Toronto', 'West')
peak_models <- c(baseline = 'AI4Casting_Hub-PeakBaseline',
                 ar = 'AI4Casting_Hub-PeakAR',
                 rf = 'AI4Casting_Hub-PeakRF')
peak_columns <- c('location', 'reference_date', 'target_end_date', 'target', 'horizon',
                  'output_type', 'output_type_id', 'value')

read_admissions_history <- function(workbook = 'auxiliary-data/data.xlsx',
                                    mapping_file = 'auxiliary-data/phu_region_mapping.csv',
                                    current_file = 'target-data/season_2026_2027/influenza-admissions.csv') {
  status_file <- file.path(dirname(current_file), 'influenza-admissions-status.csv')
  if (!file.exists(status_file)) {
    stop('Current influenza admissions status is missing; peak forecasts will be skipped')
  }
  status <- read_csv(status_file, show_col_types = FALSE, col_types = cols(.default = col_character()))
  if (!'status' %in% names(status) || nrow(status) != 1L ||
      is.na(status$status[[1]]) || status$status[[1]] != 'available') {
    stop('Current influenza admissions are unavailable; peak forecasts will be skipped')
  }
  mapping <- read_csv(mapping_file, show_col_types = FALSE, col_types = cols(.default = col_character())) |>
    filter(!is.na(NAME_ENG), !is.na(OH_Name)) |>
    transmute(phu = NAME_ENG, location = OH_Name)
  if (anyDuplicated(mapping$phu)) stop('Duplicate PHUs in region mapping')
  raw <- readxl::read_excel(workbook) |>
    filter(Outcome == 'Influenza hospital admissions', !is.na(`Public health unit`)) |>
    transmute(phu = trimws(`Public health unit`), time = as.Date(`Week end date`),
              value = suppressWarnings(as.numeric(Number)))
  if (anyNA(raw$time)) stop('Invalid historical admissions dates')
  if (anyDuplicated(raw[c('phu', 'time')])) stop('Duplicate historical admissions PHU/week')
  if (nrow(anti_join(raw, mapping, by = 'phu'))) stop('Historical admissions contain unmapped PHUs')
  expected <- mapping |> count(location, name = 'expected')
  history <- raw |>
    left_join(mapping, by = 'phu') |>
    group_by(time, location) |>
    summarise(n = n(), valid = all(is.finite(value) & value >= 0 & value == floor(value)),
              admissions = sum(value), .groups = 'drop') |>
    left_join(expected, by = 'location') |>
    filter(n == expected, valid) |>
    select(time, location, admissions)
  if (file.exists(current_file)) {
    current <- read_csv(current_file, show_col_types = FALSE,
                        col_types = cols(time = col_date(), geo_value = col_character(),
                                         geo_type = col_character(), admissions = col_double())) |>
      transmute(time, location = geo_value, admissions)
    if (anyNA(current) || anyDuplicated(current[c('time', 'location')]) ||
        any(!is.finite(current$admissions) | current$admissions < 0 |
            current$admissions != floor(current$admissions))) stop('Invalid current admissions')
    if (nrow(inner_join(history, current, by = c('time', 'location')))) stop('Admissions history overlaps current season')
    history <- bind_rows(history, current)
  }
  arrange(history, location, time)
}

complete_peak_seasons <- function(history, location, cutoff) {
  data <- history |> filter(.data$location == !!location, time < as.Date('2026-10-17'), time <= cutoff)
  seasons <- sort(unique(year(data$time) - ifelse(month(data$time) < 7, 1L, 0L)))
  reference_epi <- epiweek(peak_weeks)
  result <- lapply(seasons, function(y) {
    x <- data |> filter((year(time) == y & month(time) >= 7) |
                        (year(time) == y + 1L & month(time) < 7)) |>
      mutate(epi_week = epiweek(time)) |> filter(epi_week %in% reference_epi)
    if (nrow(x) != length(peak_weeks) || anyDuplicated(x$epi_week) ||
        !setequal(x$epi_week, reference_epi)) return(NULL)
    x <- x[match(reference_epi, x$epi_week), ]
    data.frame(season = y, week = which.max(x$admissions), peak = max(x$admissions))
  })
  bind_rows(result)
}

season_observations <- function(history, location, origin) {
  required <- peak_weeks[peak_weeks <= origin]
  x <- history |> filter(.data$location == !!location, time %in% required)
  if (nrow(x) != length(required) || anyDuplicated(x$time) || !setequal(x$time, required)) {
    stop('Incomplete current-season admissions')
  }
  x <- x[match(required, x$time), ]
  x$admissions
}

make_peak_output <- function(location, reference_date, week_index, peak_value) {
  probs <- tabulate(week_index, nbins = length(peak_weeks)) / length(week_index)
  qs <- as.numeric(quantile(peak_value, probs = peak_quantiles, names = FALSE, type = 1))
  bind_rows(
    tibble(location, reference_date, target_end_date = as.Date(NA), target = 'peak week inc flu hosp',
           horizon = NA_integer_, output_type = 'pmf', output_type_id = as.character(peak_weeks), value = probs),
    tibble(location, reference_date, target_end_date = as.Date(NA), target = 'peak inc flu hosp',
           horizon = NA_integer_, output_type = 'quantile', output_type_id = as.character(peak_quantiles), value = qs)
  ) |> select(all_of(peak_columns))
}

baseline_draws <- function(history, location, origin, observed, n = 2000L) {
  seasons <- complete_peak_seasons(history, location, origin)
  if (nrow(seasons) < 2L) stop('Fewer than two complete historical seasons')
  if (nrow(seasons) == 2L) message('  ', location, ': baseline uses only two complete seasons')
  picked <- sample(seq_len(nrow(seasons)), n, replace = TRUE)
  weeks <- pmax(1L, pmin(length(peak_weeks), as.integer(round(rnorm(n, seasons$week[picked], 1)))))
  bandwidth <- max(1, sd(seasons$peak) * nrow(seasons)^(-1/5), na.rm = TRUE)
  values <- pmax(0, round(rnorm(n, seasons$peak[picked], bandwidth)))
  observed_peak <- max(observed)
  observed_week <- which.max(observed)
  replace <- weeks <= length(observed) | values <= observed_peak
  weeks[replace] <- observed_week
  values[replace] <- observed_peak
  list(week = weeks, value = values)
}

training_rows <- function(series, origin) {
  series <- series |> filter(time <= origin) |> arrange(time)
  dates <- series$time
  y <- series$admissions
  one <- match(dates - 7, dates); two <- match(dates - 14, dates); three <- match(dates - 21, dates)
  data.frame(time = dates, y = log1p(y), lag1 = log1p(y[one]), lag2 = log1p(y[two]),
             lag3 = log1p(y[three]), sin_week = sin(2*pi*epiweek(dates)/52.18),
             cos_week = cos(2*pi*epiweek(dates)/52.18)) |>
    filter(if_all(everything(), ~ !is.na(.x)))
}

simulate_ar <- function(history, location, origin, observed, method, n = 2000L) {
  series <- history |> filter(.data$location == !!location, time <= origin) |> arrange(time)
  last_dates <- origin - 7L * 0:2
  last_values <- series$admissions[match(last_dates, series$time)]
  if (length(last_values) != 3 || anyNA(last_values)) stop('Missing recent lagged admissions')
  train <- training_rows(series, origin)
  if (nrow(train) < 26L) stop('Fewer than 26 usable training observations')
  features <- c('lag1', 'lag2', 'lag3', 'sin_week', 'cos_week')
  if (method == 'ar') {
    fit <- lm(y ~ lag1 + lag2 + lag3 + sin_week + cos_week, data = train)
    fitted <- predict(fit, train)
    predictor <- function(x) as.numeric(predict(fit, newdata = x))
  } else {
    if (!requireNamespace('ranger', quietly = TRUE)) stop('The ranger package is required')
    fit <- ranger::ranger(y ~ lag1 + lag2 + lag3 + sin_week + cos_week, data = train,
                          num.trees = 500, seed = 2026, num.threads = 1, keep.inbag = TRUE)
    fitted <- fit$predictions
    predictor <- function(x) predict(fit, data = x, num.threads = 1)$predictions
  }
  residuals <- train$y - fitted
  if (any(!is.finite(residuals))) stop('Invalid training residuals')
  lags <- matrix(rep(log1p(last_values), each = n), nrow = n)
  best <- rep(max(observed), n); best_week <- rep(which.max(observed), n)
  for (index in which(peak_weeks > origin)) {
    date <- peak_weeks[index]
    x <- data.frame(lag1 = lags[,1], lag2 = lags[,2], lag3 = lags[,3],
                    sin_week = sin(2*pi*epiweek(date)/52.18), cos_week = cos(2*pi*epiweek(date)/52.18))
    mu <- predictor(x)
    if (any(!is.finite(mu))) stop('Invalid simulated prediction')
    next_y <- pmax(0, round(expm1(pmin(20, pmax(0, mu + sample(residuals, n, replace = TRUE))))))
    higher <- next_y > best
    best[higher] <- next_y[higher]; best_week[higher] <- index
    lags <- cbind(log1p(next_y), lags[,1:2, drop = FALSE])
  }
  list(week = best_week, value = best)
}

run_peak_models <- function(reference_date, history = read_admissions_history()) {
  reference_date <- as.Date(reference_date)
  if (is.na(reference_date) || !reference_date %in% peak_weeks || reference_date < as.Date('2026-10-24')) {
    stop('Reference date is outside the 2026-27 peak forecast rounds')
  }
  origin <- reference_date - 7L
  generated <- setNames(vector('list', length(peak_models)), peak_models)
  for (method in names(peak_models)) {
    model_id <- peak_models[[method]]
    for (location in peak_locations) {
      result <- tryCatch({
        observed <- season_observations(history, location, origin)
        set.seed(2026L + as.integer(reference_date) + match(location, peak_locations) * 100L + match(method, names(peak_models)))
        draws <- if (method == 'baseline') baseline_draws(history, location, origin, observed) else
          simulate_ar(history, location, origin, observed, method)
        make_peak_output(location, reference_date, draws$week, draws$value)
      }, error = function(e) { message('Skipping ', model_id, ' / ', location, ': ', conditionMessage(e)); NULL })
      generated[[model_id]] <- bind_rows(generated[[model_id]], result)
    }
  }
  for (model_id in names(generated)) {
    path <- file.path('model-output', model_id, sprintf('%s-%s.csv', reference_date, model_id))
    if (nrow(generated[[model_id]]) == 0L) {
      if (file.exists(path)) stop('No forecasts produced; existing file needs review: ', path)
      message('No forecasts available for ', model_id)
      next
    }
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    write_csv(generated[[model_id]], path, na = '')
    message('Wrote ', path)
  }
  invisible(generated)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 1L || !grepl('^--date=[0-9]{4}-[0-9]{2}-[0-9]{2}$', args)) stop('Use --date=YYYY-MM-DD')
  run_peak_models(sub('^--date=', '', args))
}
