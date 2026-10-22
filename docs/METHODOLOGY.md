# Методика подготовки данных

Подробное описание исходников, признаков, обработки геометрий и ограничений. Все команды выполняются из корня репозитория; проект RStudio — `hogweed.Rproj`. Инструкция по клонированию с Git LFS находится в [README](../README.md).

```r
# Install once if needed:
install.packages(c("sf", "terra", "ggplot2", "patchwork", "jsonlite",
                   "DBI", "RSQLite", "curl", "openssl"))

# Downloads are already present. Run this to reproduce acquisition or extraction:
source("scripts/01_download.R", encoding = "UTF-8")

# Load originals, filter the species, build tables, and plot all maps:
source("scripts/02_prepare_and_plot.R", encoding = "UTF-8")

# Inspect the resulting model inputs:
d <- read.csv("data/processed/model_table.csv")
d$land_cover_clc <- factor(d$land_cover_clc)
X <- d[readLines("data/processed/predictor_columns.txt")]
y <- d$y
View(d)
```

You can run the numbered sections of `scripts/02_prepare_and_plot.R` one at a time with **Ctrl+Enter**. It leaves `inva`, `presence_polygons`, `gbif`, `roads`, `waterways`, `settlements`, `table_all` and `model_table` available for inspection. It fits no model. Runtime is several minutes, mostly spatial distances and maps.

## Original datasets

| Original file | What R reads from it |
|---|---|
| `Invazines_rusys.gpkg` | All invasive-species polygons. R selects exactly `Heracleum sosnowskyi` and checks record status and geometry. |
| `gbif_taxon_match.json`, `gbif_occurrences_000000.json` | Unmodified GBIF API responses, all returned fields retained. R selects the accepted species and Lithuania, then checks coordinates and INVA proximity. More page files are downloaded automatically if necessary. |
| `LTU_wc2.1_30s_tavg.tif` | Twelve monthly mean temperatures, January–December, degrees C. |
| `LTU_wc2.1_30s_tmin.tif`, `LTU_wc2.1_30s_tmax.tif` | Twelve monthly mean minimum/maximum temperatures each, degrees C. |
| `LTU_wc2.1_30s_prec.tif` | Twelve long-term mean monthly precipitation totals, mm. |
| `LTU_wc2.1_30s_bio.tif` | All 19 WorldClim bioclimatic variables; R selects six starting predictors. |
| `LTU_elv_msk.tif` | Elevation, metres, 30 arc seconds. |
| `U2018_CLC2018_V2020_20u1_LT.tif` and supplied sidecars | CORINE 2018 land cover, 100 m. The `.tif.vat.dbf` maps raster indices to true three-digit CORINE codes and names. |
| `CLC_CHA.gpkg` | Original national CORINE vector package, retained for polygon analysis. The main script uses the supplied raster for efficient extraction. |
| `lithuania.gpkg` | Complete original Geofabrik extract. R reads roads, waterways and settlement points from its thematic layers. |
| `gadm41_LTU_0.json` | GADM 4.1 national boundary. |

Original files live in `data/raw/`. All retained source files and generated data tables are versioned through Git LFS. ZIP archives were removed after the extracted files passed SHA-256 verification. `metadata/extracted_files.csv` retains their original archive-member names and hashes; `metadata/downloads.csv` retains the exact archive URLs and download hashes. The R downloader recreates missing sources from the recorded snapshot when needed and removes temporary ZIPs after extraction. Additional archive formats and historical layers are not retained outside the source vector package. All transformations happen in R; tables go to `data/processed/`, maps to `maps/`, and audits to `metadata/`. Original file contents are never overwritten.

## The modelling table

`data/processed/grid_predictors.csv` has one row per **1 × 1 km LKS-94 cell whose centre is inside the GADM boundary**. It contains predictors for mapping the modelling domain. `data/processed/model_table.csv` is a concrete starting presence/background sample: all eligible presence cells plus up to three background cells per presence cell, using a fixed random seed.

| Column group | Meaning |
|---|---|
| `cell_id`, `x_m`, `y_m` | Grid identity and cell centre, EPSG:3346, metres; not included in X. |
| `y`, `label_type` | `1`: cell touched by a usable current INVA presence polygon. `0`: background with no usable presence mapped there; **not a surveyed absence**. |
| `bio1_*`, `bio4_*`, `bio8_*`, `bio12_*`, `bio13_*`, `bio15_*` | Annual temperature, temperature seasonality, wettest-quarter temperature, annual precipitation, wettest-month precipitation, precipitation seasonality. BIO4 is temperature SD × 100, as supplied. |
| `tavg_01` … `tavg_12`, `tmin_*`, `tmax_*`, `prec_*` | Monthly climate values sampled at cell centres. Temperature in degrees C; precipitation in mm. |
| `elevation_m` | Elevation sampled at cell centre. |
| `land_cover_clc` | Three-digit CORINE class at the centre. Use as a **factor**, not a continuous number. |
| `lc_fraction_*` | Fractions of valid 100 m source pixels in each of five broad land-cover groups within the cell. |
| `distance_road_m`, `distance_waterway_m`, `distance_settlement_m` | Straight-line distance from the cell centre to the nearest selected OSM feature. |
| `distance_any_inva_m` | Distance to any readable species polygon, including rejected/historical statuses, used only to keep background >1 km away. **Exclude from X: it reveals the response.** |
| `block_id` | 20 km spatial block for designing validation; not a predictor or a ready-made train/test split. |
| `edge_distance_m`, `near_country_edge`, `predictors_complete` | Audit flags. All complete presence cells are kept; cells missing any proposed predictor are excluded from the starting model table. |

The exact proposed X columns are in `data/processed/predictor_columns.txt`. They are candidates, not a claim that all should enter one model: monthly temperatures and BIO variables are strongly correlated. Select variables, encode factors, scale and impute within training folds. Model selection and training are outside this data-preparation attempt.

`data/processed/cell_occurrence_links.csv` links every occupied cell to source `record_id` values. For validation, group spatial blocks connected by the same polygon/record, and add a separation buffer so one occurrence cannot leak across training and testing. Random row splitting is inappropriate.

## Interpretation and checks

- INVA polygons with `INITIAL`, `INCREASED`, `STABLE` or `DECREASED` statuses are presence candidates. `MISTAKEN`, `DESTROYED`, `DISAPPEARED` and unknown statuses are excluded. These are status-based candidates, not a verified current field survey. Creation/update dates are not assumed to be observation dates.
- Unreadable geometries retain all attributes in `metadata/inva_species_audit.csv` and are excluded from spatial operations. Readable invalid geometries are repaired by `sf::st_make_valid()` in R, on a derived copy only. No source features are edited.
- Polygons that do not intersect the GADM Lithuania boundary are excluded from the spatial sample. Unknown/unreadable footprints cannot be used to screen nearby background; review their source records before final modelling.
- GBIF remains outside the training sample. `metadata/gbif_check_audit.csv` retains record IDs, source dataset IDs, licences, uncertainty and INVA proximity. `possible_check` is only a conservative preliminary screen; it does not prove source or spatial independence. Unknown uncertainty is retained and requires review. A presence-only external sample cannot measure specificity against true absences.
- Climate uses **WorldClim 2.1, 1970–2000**, an option in the supplied message. It is not recent weather. CORINE is from 2018; INVA and OSM are current download snapshots. This temporal mismatch matters when interpreting habitat associations.
- The 1 km grid is an analysis unit, not a claim of 1 km precision. Original climate/elevation are 30 arc seconds. Climate and terrain use centre samples; land-cover fractions use area averaging of valid pixels; presence uses all touched polygon cells.
- The Geofabrik national extract has limited coverage outside Lithuania. `near_country_edge` flags cells within 5 km of the border, where distances could miss nearer foreign features. Use neighbouring-country OSM extracts before interpreting border distances. Waterways include the supplied rivers, streams, drains and canals; settlements are OSM place points, not urban-footprint boundaries.
- Occurrence reporting and OSM coverage can be biased toward accessible/populated places. Road and settlement associations may reflect observation effort as well as habitat. Review alternative background sampling and spatial validation before drawing ecological conclusions.

## Figures

All maps use one cream/teal design, LKS-94 projected kilometre axes, source captions and consistent typography. PNGs are suitable for viewing; PDFs are vector exports where layers support it.

- `maps/00_map_atlas.png` and `.pdf`: four-map overview.
- `maps/01_occurrences.*`: INVA and GBIF.
- `maps/02_temperature.*`, `03_precipitation.*`, `04_elevation.*`.
- `maps/05_land_cover.*`, `06_infrastructure.*`, `07_modelling_sample.*`.

`metadata/run_summary.txt` gives actual record/cell counts; `metadata/original_file_integrity.csv` verifies byte preservation; `metadata/r_session.txt` records package versions. Exact acquisition links and equivalent direct R calls are in `docs/SOURCES.md` and `metadata/downloads.csv`.
