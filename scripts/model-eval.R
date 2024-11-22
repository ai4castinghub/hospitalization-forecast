library(lubridate)
library(dplyr)
library(readr)
library(MMWRweek)

# Load and process dataset
cat("Loading hospitalization data...\n")
df_hhs <- read_csv('hospitalization/target-data/season_2024_2025/hospitalization-data.csv') %>%
  mutate(date = as_date(time, format = "%d-%m-%Y"),
         mmwr_week = MMWRweek(date)$MMWRweek) %>%
  arrange(date)
write_csv(df_hhs, "hospitalization-output/hospitalization-data.csv")

print(head(df_hhs))  # Check first few rows to ensure data is loaded correctly

# Define parameters
model_output_dir <- "hospitalization/model-output"
model_names <- list.dirs(model_output_dir, full.names = FALSE, recursive = FALSE)
print(model_names)  # Print model directories to verify

current_reference_date <- floor_date(Sys.Date(), unit = "week") + days(6)
start_reference_date <- as_date("2024-10-19")
all_ref_dates <- seq(start_reference_date, current_reference_date, by = "7 days")
print(all_ref_dates)  # Check the date sequence

region_vector <- c("Ontario","North East", "West", "East","Central","North West","Toronto")
target_vector <- c('wk inc covid hosp','wk inc flu hosp','wk inc rsv hosp')

# Initialize results container
WIS_all <- list()

# Define WIS function
WIS <- function(single_forecast, model, date, forecast_date, region, tid, j) {
  quantiles_vector <- c(0.025, 0.1, 0.25)
  
  single_true <- df_hhs %>%
    filter(time == as_date(forecast_date), geo_value == region) %>%
    pull(covid)
  
  if (length(single_true) == 0) {
    cat("No true value for region:", region, "on date:", forecast_date, "\n")
    return(NULL)
  }
  
  median_forecast <- single_forecast %>%
    filter(output_type_id == 0.5) %>%
    pull(value)
  
  if (length(median_forecast) == 0) {
    cat("No median forecast for region:", region, "on date:", forecast_date, "\n")
    return(NULL)
  }
  
  AE <- abs(single_true - median_forecast)
  MSE <- (single_true - median_forecast)^2
  WIS <- AE / 2
  
  for (quantile in quantiles_vector) {
    lower <- single_forecast %>% filter(output_type_id == quantile) %>% pull(value)
    upper <- single_forecast %>% filter(output_type_id == 1 - quantile) %>% pull(value)
    
    if (length(lower) == 0 || length(upper) == 0) {
      cat("Missing quantile data for region:", region, "quantile:", quantile, "\n")
      next
    }
    
    WIS <- WIS + (quantile * (upper - lower) + 
                  (single_true < lower) * (lower - single_true) + 
                  (single_true > upper) * (single_true - upper))
  }
  
  WIS <- WIS / (length(quantiles_vector) + 0.5)
  
  data.frame(
    reference_date = date,
    target_end_date = forecast_date,
    model = model,
    WIS = WIS,
    AE = AE,
    MSE = MSE,
    region = region,
    target = tid,
    horizon = j
  )
}

# Main Loop for Forecast Calculation
for (reference_date in all_ref_dates) {
  reference_date <- as_date(reference_date)
  for (model in model_names) {
    filename <- paste0("hospitalization/model-output/", model, "/", reference_date, "-", model, ".csv")
    cat("Processing file:", filename, "\n")
    
    if (!file.exists(filename)) {
      cat("File does not exist:", filename, "\n")
      next
    }
    
    forecast <- read_csv(filename, show_col_types = FALSE)
    if (!is.data.frame(forecast)) {
      cat("Error: forecast is not a data frame for file:", filename, "\n")
      next
    }
    
    for (region in region_vector) {
      for (tid in target_vector) {
        filtered_forecast <- forecast %>%
          filter(location == region, target == tid)
        
        if (nrow(filtered_forecast) == 0) {
          cat("No data for region:", region, "and target:", tid, "\n")
          next
        }
        
        for (j in 0:3) {
          target_date <- as.Date(reference_date) + (j * 7)
          horizon_forecast <- filtered_forecast %>% filter(horizon == j)
          
          if (nrow(horizon_forecast) == 0) {
            cat("No forecast data for horizon:", j, "on target date:", target_date, "\n")
            next
          }
          
          WIS_current <- WIS(
            single_forecast = horizon_forecast, 
            model = model, 
            date = as.character(reference_date), 
            forecast_date = as.character(target_date), 
            region = region, 
            tid = tid,
            j = j
          )
          
          if (!is.null(WIS_current)) {
            WIS_all <- bind_rows(WIS_all, WIS_current)
          } else {
            cat("WIS calculation returned NULL for model:", model, 
                "| Region:", region, "| Target:", tid, "| Horizon:", j, "\n")
          }
        }
      }
    }
  }
}

# Check if WIS_all has any data before proceeding
if (length(WIS_all) == 0 || is.null(WIS_all) || nrow(WIS_all) == 0) {
  cat("No forecast data available for any model. Skipping WIS average calculation.\n")
} else {
  cat("Calculating WIS averages...\n")
  WIS_average <- expand.grid(Horizon = 0:3, Model = model_names) %>%
    mutate(Average_WIS = NA, Average_MAE = NA, Average_MSE = NA)

  for (model_name in model_names) {
    for (h in 0:3) {
      WIS_horizon <- WIS_all %>% filter(model == model_name, target_end_date == (as_date(reference_date) + (h * 7)))
      WIS_average$Average_WIS[WIS_average$Model == model_name & WIS_average$Horizon == h] <- mean(WIS_horizon$WIS, na.rm = TRUE)
      WIS_average$Average_MAE[WIS_average$Model == model_name & WIS_average$Horizon == h] <- mean(WIS_horizon$AE, na.rm = TRUE)
      WIS_average$Average_MSE[WIS_average$Model == model_name & WIS_average$Horizon == h] <- mean(WIS_horizon$MSE, na.rm = TRUE)
    }
  }
  
  # Write results to CSV
  write_csv(WIS_average, "hospitalization-output/WIS_average.csv")
  write_csv(WIS_all, "hospitalization-output/all_scores.csv")
}

# Aggregate model output with additional checks
cat("Aggregating model output...\n")
all_model_data <- lapply(list.dirs(model_output_dir, full.names = TRUE, recursive = FALSE), function(model_dir) {
  model_name <- basename(model_dir)
  model_files <- list.files(model_dir, pattern = "\\.csv$", full.names = TRUE)
  
  if (length(model_files) == 0) {
    cat("No CSV files found in model directory:", model_dir, "\n")
    return(NULL)
  }
  
  do.call(rbind, lapply(model_files, function(file) {
    if (file.exists(file)) {
      read_csv(file, show_col_types = FALSE) %>%
        mutate(model = model_name,
              reference_date = if_else(is.na(as_date(dmy(reference_date))),
                                  as_date(as.numeric(reference_date)),
                                  as_date(dmy(reference_date))),
         target_end_date = if_else(is.na(as_date(dmy(target_end_date))),
                                   as_date(as.numeric(target_end_date)),
                                   as_date(dmy(target_end_date)))) %>%
  # Drop rows where either reference_date or target_end_date is NA
  filter(!is.na(reference_date), !is.na(target_end_date))
    } else {
      cat("File does not exist:", file, "\n")
      return(NULL)
    }
  }))
})

# Combine and clean data
cat("Combining model data...\n")
concatenated_data <- bind_rows(all_model_data) %>%
  filter(!is.na(reference_date), !is.na(target_end_date))

write_csv(concatenated_data, "hospitalization-output/concatenated_model_output.csv")

cat("Script completed successfully.\n")
