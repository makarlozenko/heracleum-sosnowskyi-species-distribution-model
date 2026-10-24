# Heracleum sosnowskyi in Lithuania

R scripts for preparing spatial data and exploring the environmental conditions associated with recorded Sosnowsky's hogweed presence in Lithuania.

## Files

- `Duomenų_Instaliavimas.R` downloads occurrence records and environmental datasets into `data/`.
- `Filtravimai_ir_grafikai.R` builds the 1 km modelling table at `data/processed/model_table.csv` and saves maps to `maps/`.
- `Data_analysis.R` produces the eight final analysis figures in `plot/` as 300 dpi PNG files. Re-running it replaces these files.
- `hogweed.Rproj` opens the project in RStudio.

Downloaded data and generated outputs are not included in the repository.

## Run

Open `hogweed.Rproj` in RStudio and install the required packages once:

```r
install.packages(c("sf", "terra", "ggplot2", "patchwork", "scales", "curl",
                   "jsonlite", "DBI", "RSQLite", "foreign"))
```

Run the scripts in this order from the project folder:

```r
source("Duomenų_Instaliavimas.R")
source("Filtravimai_ir_grafikai.R")
source("Data_analysis.R")
```

The download step requires internet access and retrieves large geospatial datasets. If `data/processed/model_table.csv` is already available, run only `Data_analysis.R` (requires `ggplot2` and `scales`).

The analysis compares recorded presence with sampled background cells. Background cells are not confirmed absences; the 3:1 sampling ratio does not estimate species prevalence.
