library(epipredict)
library(dplyr)
library(tidyr)
library(epiprocess)
library(hubEnsembles)
library(lubridate)

# Function to process predictions for a given disease
process_disease <- function(disease, data) {
  # Subset, clean, and convert data to epi_df
  disease_data <- data[, c("geo_value", "time_value", disease)] |>
    drop_na() |>
    as_epi_df(
      geo_value = "geo_value",
      time_value = "time_value"
    )
  
  # Run the baseline forecaster
  cdc <- cdc_baseline_forecaster(disease_data, outcome = disease)
  
  # Process predictions and keep relevant columns
  preds <- pivot_quantiles_wider(cdc$predictions, .pred_distn) |>
    select(geo_value, ahead, forecast_date, target_date, `0.025`, `0.1`, `0.25`, `0.5`, `0.75`, `0.9`, `0.975`) |>
    mutate(disease = paste("wk inc", disease, "hosp"))
  
  return(preds)
}

# Function to create file paths
create_file_path <- function(base_dir, file_name) {
  file.path(base_dir, file_name)
}

# Read and preprocess the data
data <- read.csv('auxiliary-data/concatenated_hospitalization_data.csv') |>
  mutate(time_value = as.Date(time)) |>
  select(-time, -geo_type, -Season)

# Process predictions for all diseases
all_preds <- bind_rows(lapply(c('covid', 'rsv', 'flu'), process_disease, data = data))

# Reshape predictions and apply rounding logic
all_preds <- all_preds |>
  pivot_longer(
    cols = starts_with("0."),
    names_to = "output_type_id",
    values_to = "value"
  ) |>
  mutate(
    forecast_date = forecast_date + 7,
    ahead = ahead - 1,
    value = case_when(
      output_type_id < "0.5" ~ floor(value),
      output_type_id > "0.5" ~ ceiling(value),
      TRUE ~ round(value)
    )
  )

# Rename columns and add 'output_type'
all_preds <- all_preds %>%
  rename(
    horizon = ahead,
    reference_date = forecast_date,
    target_end_date = target_date,
    location = geo_value,
    target = disease
  ) %>%
  mutate(output_type = "quantile") |>
  filter(horizon != 4)

# Save predictions
output_dir <- "model-output/AI4Casting_Hub-Quantile_Baseline"
file_name <- paste0(unique(all_preds$reference_date), "-AI4Casting_Hub-Quantile_Baseline.csv")
file_path <- create_file_path(output_dir, file_name)

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
write.csv(all_preds, file_path, row.names = FALSE)




# Read model output
model_op <- read.csv('auxiliary-data/concatenated_model_output.csv')
colnames(model_op)[colnames(model_op) == "model"] <- "model_id"

# Filter and create ensemble
ref_date <- lubridate::ceiling_date(Sys.Date(), "week") - days(1) - weeks(1)
model_outputs <- model_op |>
  filter(reference_date == ref_date) |>
  filter(model_id != 'AI4Casting_Hub-Quantile_Baseline') |>
  filter(model_id != 'AI4Casting_Hub-Ensemble_v1')

ensemble <- simple_ensemble(model_outputs, agg_fun = mean, model_id = 'AI4Casting_Hub-Ensemble_v1')

# Save ensemble
ensemble_output_dir <- "model-output/AI4Casting_Hub-Ensemble_v1"
ensemble_file_name <- paste0(as.character(ref_date), "-AI4Casting_Hub-Ensemble_v1.csv")
ensemble_file_path <- create_file_path(ensemble_output_dir, ensemble_file_name)

ensemble <- ensemble |>
  select(-model_id)

if (!dir.exists(ensemble_output_dir)) dir.create(ensemble_output_dir, recursive = TRUE)
write.csv(ensemble, ensemble_file_path, row.names = FALSE)
