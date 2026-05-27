# test epipredict models
library(epipredict)
library(dplyr)
library(tidyr)
library(lubridate)
library(parsnip)
library(hubValidations)

# fixed forecast date used for all models
#forecast_date <- lubridate::ceiling_date(Sys.Date(), "week") - days(1)
forecast_date <- as.Date("2026-02-07")

print(forecast_date)

# shared quantiles and ahead values for all forecasters
quantile_levels <- c(0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975)
ahead_seq <- seq(0, 21, by = 7)
print(ahead_seq)

disease_data <- read.csv("auxiliary-data/concatenated_hospitalization_data.csv") |>
  mutate(time_value = as.Date(time)) |>
  select(-time, -geo_type, -Season)

process_disease_flatline_forecaster <- function(disease, data) {
  # subset by disease and convert to epi_df
  data <- data[, c("geo_value", "time_value", disease), drop = FALSE] |>
    drop_na() |>
    as_epi_df(
      geo_value  = "geo_value",
      time_value = "time_value"
    )
  
  # restrict data to information available at forecast date
  data_hist <- data |>
    filter(time_value <= forecast_date)
  
  weekly_canned_results <- lapply(
    ahead_seq,
    function(days_ahead) {
      flatline_forecaster(
        data_hist,
        outcome   = disease,
        args_list = flatline_args_list(
          ahead           = days_ahead,
          quantile_levels = quantile_levels,
          forecast_date = forecast_date
        )
      )
    }
  )
  
  disease_label  <- paste("wk inc", disease, "hosp")
  shifted_f_date <- forecast_date 
  
  pred_list <- lapply(seq_along(weekly_canned_results), function(i) {
    weekly_canned_results[[i]]$predictions |>
      pivot_quantiles_wider(.pred_distn) |>
      pivot_longer(
        cols      = starts_with("0."),
        names_to  = "output_type_id",
        values_to = "value"
      ) |>
      mutate(
        reference_date = shifted_f_date,
        disease       = disease_label,
        horizon       = i - 1,
        value         = case_when(
          as.numeric(output_type_id) < 0.5 ~ floor(value),
          as.numeric(output_type_id) > 0.5 ~ ceiling(value),
          TRUE                             ~ round(value)
        )
      ) |>
      select(-.pred, -forecast_date)
  })
  
  bind_rows(pred_list)
}

process_disease_arx_forecaster <- function(disease, data) {
  # subset by disease and convert to epi_df
  data <- data[, c("geo_value", "time_value", disease), drop = FALSE] |>
    drop_na() |>
    as_epi_df(
      geo_value  = "geo_value",
      time_value = "time_value"
    )
  
  # restrict data to information available at forecast date
  data_hist <- data |>
    filter(time_value <= forecast_date)
  
  weekly_canned_results <- lapply(
    ahead_seq,
    function(days_ahead) {
      arx_forecaster(
        epi_data  = data_hist,
        outcome   = disease,
        args_list = arx_args_list(
          ahead           = days_ahead,
          quantile_levels = quantile_levels,
          forecast_date = forecast_date
        )
      )
    }
  )
  
  disease_label  <- paste("wk inc", disease, "hosp")
  shifted_f_date <- forecast_date 
  
  pred_list <- lapply(seq_along(weekly_canned_results), function(i) {
    weekly_canned_results[[i]]$predictions |>
      pivot_quantiles_wider(.pred_distn) |>
      pivot_longer(
        cols      = starts_with("0."),
        names_to  = "output_type_id",
        values_to = "value"
      ) |>
      mutate(
        reference_date = shifted_f_date,
        disease       = disease_label,
        horizon       = i - 1,
        value         = case_when(
          as.numeric(output_type_id) < 0.5 ~ floor(value),
          as.numeric(output_type_id) > 0.5 ~ ceiling(value),
          TRUE                             ~ round(value)
        )
      ) |>
      select(-.pred, -forecast_date)
  })
  
  bind_rows(pred_list)
}

process_disease_rf_arx_forecaster <- function(disease, data) {
  # subset by disease and convert to epi_df
  data <- data[, c("geo_value", "time_value", disease), drop = FALSE] |>
    drop_na() |>
    as_epi_df(
      geo_value  = "geo_value",
      time_value = "time_value"
    )
  
  # restrict data to information available at forecast date
  data_hist <- data |>
    filter(time_value <= forecast_date)
  
  weekly_canned_results <- lapply(
    ahead_seq,
    function(days_ahead) {
      arx_forecaster(
        epi_data  = data_hist,
        outcome   = disease,
        trainer   = rand_forest(mode = "regression") |>
          set_engine("ranger"),
        args_list = arx_args_list(
          ahead           = days_ahead,
          quantile_levels = quantile_levels,
          forecast_date = forecast_date
        )
      )
    }
  )
  
  disease_label  <- paste("wk inc", disease, "hosp")
  shifted_f_date <- forecast_date 
  
  pred_list <- lapply(seq_along(weekly_canned_results), function(i) {
    weekly_canned_results[[i]]$predictions |>
      pivot_quantiles_wider(.pred_distn) |>
      pivot_longer(
        cols      = starts_with("0."),
        names_to  = "output_type_id",
        values_to = "value"
      ) |>
      mutate(
        reference_date = shifted_f_date,
        disease       = disease_label,
        horizon       = i - 1,
        value         = case_when(
          as.numeric(output_type_id) < 0.5 ~ floor(value),
          as.numeric(output_type_id) > 0.5 ~ ceiling(value),
          TRUE                             ~ round(value)
        )
      ) |>
      select(-.pred, -forecast_date)
  })
  
  bind_rows(pred_list)
}

process_disease_cdc_baseline_forecaster <- function(disease, data) {
  # subset by disease and convert to epi_df
  data <- data[, c("geo_value", "time_value", disease), drop = FALSE] |>
    drop_na() |>
    as_epi_df(
      geo_value  = "geo_value",
      time_value = "time_value"
    )
  
  # restrict data to information available at forecast date
  data_hist <- data |>
    filter(time_value <= forecast_date)
  
  # cdc baseline forecaster with multiple aheads on daily data
  cdc_results <- cdc_baseline_forecaster(
    epi_data = data_hist,
    outcome  = disease
  )
  
  disease_label  <- paste("wk inc", disease, "hosp")
  shifted_f_date <- forecast_date 
  
  cdc_results$predictions |>
    pivot_quantiles_wider(.pred_distn) |>
    select(geo_value, ahead, forecast_date, target_date, `0.025`, `0.1`, `0.25`, `0.5`, `0.75`, `0.9`, `0.975`) |>
    pivot_longer(
      cols      = starts_with("0."),
      names_to  = "output_type_id",
      values_to = "value"
    ) |>
    mutate(
      reference_date = shifted_f_date,
      disease       = disease_label,
      horizon       = ahead - 1,
      value         = case_when(
        as.numeric(output_type_id) < 0.5 ~ floor(value),
        as.numeric(output_type_id) > 0.5 ~ ceiling(value),
        TRUE ~ round(value)
      )
    ) |>
    select(-ahead, -forecast_date)|>
    filter(horizon != 4)
}

all_preds <- bind_rows(
  lapply(
    c("covid", "rsv", "flu"),
    process_disease_flatline_forecaster,
    data = disease_data
  )
) |>
  rename(
    target_end_date = target_date,
    location        = geo_value,
    target          = disease
  ) |>
  mutate(output_type = "quantile")

all_preds_arx <- bind_rows(
  lapply(
    c("covid", "rsv", "flu"),
    process_disease_arx_forecaster,
    data = disease_data
  )
) |>
  rename(
    target_end_date = target_date,
    location        = geo_value,
    target          = disease
  ) |>
  mutate(output_type = "quantile")

rf_preds <- bind_rows(
  lapply(
    c("covid", "rsv", "flu"),
    process_disease_rf_arx_forecaster,
    data = disease_data
  )
) |>
  rename(
    target_end_date = target_date,
    location        = geo_value,
    target          = disease
  ) |>
  mutate(output_type = "quantile")

cdc_baseline_preds <- bind_rows(
  lapply(
    c("covid", "rsv", "flu"),
    process_disease_cdc_baseline_forecaster,
    data = disease_data
  )
) |>
  rename(
    target_end_date = target_date,
    location        = geo_value,
    target          = disease
  ) |>
  mutate(output_type = "quantile")


all_preds_dir          <- paste0('AI4Casting_Hub-Flatline/', forecast_date, "-AI4Casting_Hub-Flatline.csv")
all_preds_arx_dir      <- paste0('AI4Casting_Hub-Quantile_AR/',forecast_date, "-AI4Casting_Hub-Quantile_AR.csv")
rf_preds_dir           <- paste0('AI4Casting_Hub-RF_Quantile_AR/',forecast_date, "-AI4Casting_Hub-RF_Quantile_AR.csv")
cdc_baseline_preds_dir <- paste0('AI4Casting_Hub-Quantile_Baseline/',forecast_date, "-AI4Casting_Hub-Quantile_Baseline.csv")


all_preds_path = paste0("model-output/",all_preds_dir)
all_preds_arx_path <- paste0('model-output/', all_preds_arx_dir)
rf_preds_path = paste0('model-output/', rf_preds_dir)
cdc_baseline_preds_path <- paste0('model-output/', cdc_baseline_preds_dir)


write.csv(all_preds, all_preds_path  , row.names = FALSE)
write.csv(all_preds_arx, all_preds_arx_path , row.names = FALSE)
write.csv(rf_preds, rf_preds_path  , row.names = FALSE)
write.csv(cdc_baseline_preds, cdc_baseline_preds_path , row.names = FALSE)


files = list(all_preds_dir, all_preds_arx_dir, rf_preds_dir, cdc_baseline_preds_dir)

validate_one <- function(file_path) {
  tryCatch({
    v <- hubValidations::validate_submission(
      hub_path = "C:/Users/Siddhesh/Desktop/ai4castinghub/hospitalization-forecast",
      file_path = file_path
    )
    
    # Check for any validation errors
    err_msg <- tryCatch({
      hubValidations::check_for_errors(v, verbose = TRUE)
      NULL  # passed
    }, error = function(e) {
      e$message
    })
    
    list(
      status  = if (is.null(err_msg)) "pass" else "fail",
      message = err_msg
    )
    
  }, error = function(e) {
    list(status = "error", message = e$message)
  })
}

#validation for all files
results <- lapply(files, validate_one)

# Print results
print(results)

