library(epipredict)
library(dplyr)
library(tidyr)
library(epiprocess)
library(hubEnsembles)
library(lubridate)

# ---------------------------
# HELPERS
# ---------------------------

create_file_path <- function(base_dir, file_name) {
  file.path(base_dir, file_name)
}

# ---------------------------
# LOAD DATA
# ---------------------------

model_op <- read.csv('auxiliary-data/concatenated_model_output.csv')
colnames(model_op)[colnames(model_op) == "model"] <- "model_id"

# ---------------------------
# MAIN FUNCTION (PER DATE)
# ---------------------------

run_for_ref_date <- function(ref_date) {
  
  print(paste("Running ensemble for:", ref_date))
  
  # Filter model outputs for this reference date
  model_outputs <- model_op |>
    filter(reference_date == ref_date) |>
    filter(model_id != 'AI4Casting_Hub-Ensemble_v1') |>
    filter(model_id != 'AI4Casting_Hub-Weighted_Ensemble') |>
    filter(model_id != 'AI4Casting_Hub-GPT_4o')
  
  # Skip if no data (important safeguard)
  if (nrow(model_outputs) == 0) {
    print(paste("No data for:", ref_date, "- skipping"))
    return(NULL)
  }
  
  # Create ensemble
  ensemble <- simple_ensemble(
    model_outputs,
    agg_fun = mean,
    model_id = 'AI4Casting_Hub-Ensemble_v1'
  )
  
  # Output setup
  ensemble_output_dir <- "model-output/AI4Casting_Hub-Ensemble_v1"
  ensemble_file_name <- paste0(as.character(ref_date), "-AI4Casting_Hub-Ensemble_v1.csv")
  ensemble_file_path <- create_file_path(ensemble_output_dir, ensemble_file_name)
  
  # Clean output
  ensemble <- ensemble |>
    select(-model_id)
  
  # Ensure directory exists
  if (!dir.exists(ensemble_output_dir)) {
    dir.create(ensemble_output_dir, recursive = TRUE)
  }
  
  # Write file
  write.csv(ensemble, ensemble_file_path, row.names = FALSE)
  
  print(paste("Saved:", ensemble_file_path))
}

# ---------------------------
# DATE SEQUENCE
# ---------------------------

ref_dates <- seq(
  from = as.Date("2026-04-04"), #as.Date("2025-09-06"),
  to   = as.Date("2026-05-09"),
  by   = "7 days"
)

# ---------------------------
# RUN FOR ALL DATES
# ---------------------------

lapply(ref_dates, run_for_ref_date)
