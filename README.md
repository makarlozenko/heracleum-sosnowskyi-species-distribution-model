# Heracleum sosnowskyi: exploratory data analysis

Compare environmental conditions in cells with recorded Heracleum presence (`y = 1`) and sampled background cells (`y = 0`). Background cells are not confirmed absences. The 3:1 background-to-presence ratio is a sampling choice, not an estimate of species prevalence.

## Run the analysis

Clone or download this repository, then open `hogweed.Rproj` in RStudio. Install the required packages once:

```r
install.packages(c("ggplot2", "patchwork"))
```

Run the complete script using **Source**, or execute:

```r
source("Data_analysis.R")
```

Alternatively, from a terminal:

```sh
Rscript /path/to/repository/Data_analysis.R
```

The script locates the repository from its own file path, independently of the current working directory. No local absolute paths need editing.

The input table is included at `data/processed/model_table.csv`. Each run creates `plots/data_analysis/YYYY-MM-DD_HH-MM-SS/` beside the code and saves eight PNG figures at 300 dpi. No PDFs are created by the analysis script. Committed example figures are in `plots/`.

Figures cover climate and elevation, climate densities, Spearman correlations, sample sizes, standardized mean differences, landscape distances, land cover fractions, and monthly standardized differences. Monthly differences use the pooled standard deviation so temperature and precipitation can be compared on one scale. Neighbouring cells are spatially dependent; these plots are descriptive comparisons, not causal estimates.

## Optional: rebuild the input data

The original geospatial datasets are not included. To download them and rebuild the modelling table and maps, install:

```r
install.packages(c("sf", "terra", "curl", "jsonlite", "DBI", "RSQLite", "foreign"))
```

Run `Duomenų_Instaliavimas.R` first and `Filtravimai_ir_grafikai.R` second. These scripts require network access and download large geospatial datasets. Raw data, intermediate tables, generated maps, and dated analysis runs are excluded from Git.
