import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from datetime import datetime, timedelta
import matplotlib.image as mpimg
import os
import warnings
warnings.filterwarnings("ignore")

# ---------------------------
# LOAD DATA (once)
# ---------------------------

model_data_all = pd.read_csv('auxiliary-data/concatenated_model_output.csv')

truth_data = pd.read_csv('target-data/season_2025_2026/hospitalization-data.csv')
truth_data['time'] = pd.to_datetime(truth_data['time'])

# Format columns
model_data_all['reference_date'] = pd.to_datetime(model_data_all['reference_date']).dt.date
model_data_all['target_end_date'] = pd.to_datetime(model_data_all['target_end_date'])
model_data_all['output_type_id'] = pd.to_numeric(model_data_all['output_type_id'], errors='coerce')

# ---------------------------
# LOAD LOGO
# ---------------------------

logo_path = "scripts\logo.png"  # <-- change this to your file path
logo_img = mpimg.imread(logo_path)

# ---------------------------
# HELPER: ADD LOGO
# ---------------------------

def add_logo(fig):
    # position: [left, bottom, width, height]
    ax_logo = fig.add_axes([0.82, 0.12, 0.1, 0.1], anchor='SE', zorder=10)
    ax_logo.imshow(logo_img, alpha=0.3)
    ax_logo.axis('off')

# ---------------------------
# DATE SEQUENCE
# ---------------------------

ref_dates = pd.date_range(
    start="2026-03-07",
    end="2026-04-04",
    freq="7D"
).date

# ---------------------------
# MAIN LOOP
# ---------------------------

for ref_date in ref_dates:
    
    print(f"Running for {ref_date}")
    
    # Filter model data for this date
    model_data = model_data_all[model_data_all['reference_date'] == ref_date]
    
    if model_data.empty:
        print(f"No data for {ref_date}, skipping...")
        continue

    targets = model_data['target'].unique()

    file_name = f'weekly-forecast-reports/{ref_date}-Forecast_Report.pdf'
    os.makedirs("weekly-forecast-reports", exist_ok=True)

    with PdfPages(file_name) as pdf:
        
        for target in targets:
            target_data = model_data[model_data['target'] == target]
            regions = target_data['location'].unique()

            # Ontario first
            regions = sorted([r for r in regions if r != "Ontario"])
            if "Ontario" in target_data['location'].unique():
                regions = ["Ontario"] + regions

            # Match truth column
            truth_column = (
                "covid" if "covid hosp" in target.lower() else
                "flu" if "flu hosp" in target.lower() else
                "rsv" if "rsv hosp" in target.lower() else
                None
            )

            if truth_column is None:
                print(f"Skipping target '{target}'")
                continue

            for region in regions:
                region_data = target_data[target_data['location'] == region]

                if region_data.empty:
                    continue

                fig, axes = plt.subplots(1, 2, figsize=(13, 5), sharey=True)

                ref_yaxis = region_data[region_data['output_type_id'] == 0.5]

                def calculate_intervals(data):
                    return data.groupby('target_end_date').apply(
                        lambda x: pd.Series({
                            'median': x.loc[x['output_type_id'] == 0.5, 'value'].mean(),
                            'lower_95': x.loc[x['output_type_id'] == 0.025, 'value'].mean(),
                            'upper_95': x.loc[x['output_type_id'] == 0.975, 'value'].mean(),
                            'lower_50': x.loc[x['output_type_id'] == 0.25, 'value'].mean(),
                            'upper_50': x.loc[x['output_type_id'] == 0.75, 'value'].mean(),
                        })
                    ).reset_index()

                # ---------------------------
                # LEFT: All models
                # ---------------------------
                ax = axes[0]
                ax.set_ylim([0, ref_yaxis['value'].max() * 1.9])

                non_ensemble = region_data[region_data['model'] != 'AI4Casting_Hub-Ensemble_v1']

                for model in non_ensemble['model'].unique():
                    model_df = non_ensemble[non_ensemble['model'] == model]
                    grouped = calculate_intervals(model_df)

                    if not grouped.empty:
                        line, = ax.plot(grouped['target_end_date'], grouped['median'], label=model)
                        ax.fill_between(grouped['target_end_date'],
                                        grouped['lower_95'],
                                        grouped['upper_95'],
                                        alpha=0.2,
                                        color=line.get_color())
                        ax.scatter(grouped['target_end_date'],
                                   grouped['median'],
                                   color=line.get_color(),
                                   s=30)

                # Truth
                region_truth = truth_data[truth_data['geo_value'] == region]
                if not region_truth.empty:
                    ax.plot(region_truth['time'],
                            region_truth[truth_column],
                            color="black",
                            linestyle="--",
                            linewidth=2,
                            label="Truth")

                ax.set_title(f"Models - {region} - {target}")
                ax.legend(fontsize="small")
                ax.grid()

                # ---------------------------
                # RIGHT: Ensemble
                # ---------------------------
                ax = axes[1]
                ensemble_data = region_data[region_data['model'] == 'AI4Casting_Hub-Ensemble_v1']

                if not ensemble_data.empty:
                    grouped = calculate_intervals(ensemble_data)

                    if not grouped.empty:
                        line, = ax.plot(grouped['target_end_date'], grouped['median'], label="Ensemble")
                        ax.fill_between(grouped['target_end_date'],
                                        grouped['lower_95'],
                                        grouped['upper_95'],
                                        alpha=0.1,
                                        color=line.get_color())
                        ax.fill_between(grouped['target_end_date'],
                                        grouped['lower_50'],
                                        grouped['upper_50'],
                                        alpha=0.2,
                                        color=line.get_color())

                if not region_truth.empty:
                    ax.plot(region_truth['time'],
                            region_truth[truth_column],
                            color="black",
                            linestyle="--",
                            linewidth=2,
                            label="Truth")

                ax.set_title(f"Ensemble - {region} - {target}")
                ax.legend(fontsize="small")
                ax.grid()

                # ---------------------------
                # ADD LOGO
                # ---------------------------
                add_logo(fig)

                plt.tight_layout()
                pdf.savefig(fig)
                plt.close()

    print(f"Saved: {file_name}")

print("All reports generated!")