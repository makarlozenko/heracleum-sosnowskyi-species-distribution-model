# Open this folder as an RStudio project. Run sections with Ctrl+Enter, or:
# source("scripts/02_prepare_and_plot.R", encoding = "UTF-8")
# Every transformation happens HERE. Source files are never overwritten.

# 1. Packages and settings ------------------------------------------------------
if (.Platform$OS.type == "windows") try(Sys.setlocale("LC_CTYPE", "English_United States.utf8"), silent = TRUE)
user_lib <- Sys.getenv("R_LIBS_USER")
if (.Platform$OS.type == "windows") user_lib <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = "."))
profile_lib <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = "."))
.libPaths(c(".R-library", user_lib, profile_lib, .libPaths()))
packages <- c("sf", "terra", "ggplot2", "patchwork", "jsonlite", "DBI", "RSQLite", "openssl")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install missing packages: ", paste(missing, collapse = ", "))
library(sf)
library(terra)
library(ggplot2)
for (folder in c("data/processed", "metadata", "maps")) dir.create(folder, recursive = TRUE, showWarnings = FALSE)
raw_file <- function(f) file.path("data", "raw", f)
Sys.setenv(GDAL_PAM_ENABLED = "NO") # Prevent GDAL writing sidecars beside originals.
set.seed(20261023)
crs_m <- 3346                      # Lithuania LKS-94: all distances in metres.
cell_size <- 1000
background_buffer_m <- 1000
write_table <- function(x, f) {
  audit_files <- c("inva_species_audit.csv", "inva_status_counts.csv", "gbif_check_audit.csv", "original_file_integrity.csv")
  folder <- if (f %in% audit_files) "metadata" else "data/processed"
  write.csv(x, file.path(folder, f), row.names = FALSE, fileEncoding = "UTF-8", na = "")
}
hash_file <- function(f) {
  con <- file(f, "rb")
  on.exit(close(con))
  as.character(openssl::sha256(con))
}
originals <- sort(list.files("data/raw", full.names = TRUE))
hash_before <- vapply(originals, hash_file, character(1))

# 2. Load the original environmental datasets ---------------------------------
boundary <- st_transform(st_read(raw_file("gadm41_LTU_0.json"), quiet = TRUE), crs_m)
bio <- rast(raw_file("LTU_wc2.1_30s_bio.tif"))      # 19 bands, BIO1 ... BIO19.
tavg <- rast(raw_file("LTU_wc2.1_30s_tavg.tif"))    # 12 bands, January ... December; degrees C.
tmin <- rast(raw_file("LTU_wc2.1_30s_tmin.tif"))
tmax <- rast(raw_file("LTU_wc2.1_30s_tmax.tif"))
prec <- rast(raw_file("LTU_wc2.1_30s_prec.tif"))    # Monthly totals, mm.
elevation <- rast(raw_file("LTU_elv_msk.tif"))      # Metres above sea level.
land_cover <- rast(raw_file("U2018_CLC2018_V2020_20u1_LT.tif"))
land_legend <- foreign::read.dbf(raw_file("U2018_CLC2018_V2020_20u1_LT.tif.vat.dbf"), as.is = TRUE)
# Optional original vector alternative to the raster:
# land_polygons <- st_read(raw_file("CLC_CHA.gpkg"), layer = "U2018_CLC2018_V2020_20u1", quiet = TRUE)
write_table(land_legend, "land_cover_legend.csv")
# Older GDAL versions can read signed-byte NoData -128 as +128.
# Make an IN-MEMORY copy; source GeoTIFF and legend remain unchanged.
land_cover <- ifel(land_cover >= 1 & land_cover <= 44, land_cover, NA)
levels(land_cover) <- NULL
coltab(land_cover) <- NULL

# 3. Filter INVA to Heracleum sosnowskyi ---------------------------------------
# Reading the geometry bytes preserves attributes even for malformed records.
# This helper removes the standard GeoPackage header to expose OGC WKB.
con <- DBI::dbConnect(RSQLite::SQLite(), raw_file("Invazines_rusys.gpkg"), flags = RSQLite::SQLITE_RO)
geom_info <- DBI::dbGetQuery(con, "SELECT * FROM gpkg_geometry_columns")
inva_table <- geom_info$table_name[1]
geom_column <- geom_info$column_name[1]
species_column <- "R\u016b\u0161ies_mokslinis_pavadinimas"
sql <- paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, inva_table),
  " WHERE ", DBI::dbQuoteIdentifier(con, species_column), " = 'Heracleum sosnowskyi'")
inva_attributes <- DBI::dbGetQuery(con, sql)
DBI::dbDisconnect(con)
blobs <- inva_attributes[[geom_column]]
read_wkb <- function(b) {
  if (!length(b)) return(st_as_binary(st_sfc(st_geometrycollection()))[[1]])
  envelope <- bitwAnd(bitwShiftR(as.integer(b[4]), 1), 7)
  header <- 8 + c(0, 32, 48, 48, 64)[envelope + 1]
  b[-seq_len(header)]
}
inva_attributes[[geom_column]] <- NULL
geometry <- st_as_sfc(structure(lapply(blobs, read_wkb), class = "WKB"), crs = crs_m)
validity <- st_is_valid(geometry, NA_on_exception = TRUE)
unreadable <- is.na(validity)
geometry[unreadable] <- st_sfc(st_geometrycollection(), crs = crs_m)
inva <- st_sf(inva_attributes, geometry = geometry)
stopifnot(nrow(inva) > 0)
inva$record_id <- as.character(inva[["Radaviet\u0117s_ID"]])
inva$status <- inva[["Radaviet\u0117s_statusas"]]
inva$unreadable_geometry <- st_is_empty(inva)
inva$original_valid <- st_is_valid(inva)
inva$original_valid[inva$unreadable_geometry] <- NA
inva$presence_status <- inva$status %in% c("INITIAL", "INCREASED", "STABLE", "DECREASED")
write_table(st_drop_geometry(inva), "inva_species_audit.csv")
write_table(as.data.frame(table(inva$status)), "inva_status_counts.csv")
message("INVA read: ", nrow(inva), " species records; ", sum(inva$unreadable_geometry), " unreadable geometries.")
# Geometry repairs are explicit, reproducible, and applied only to a derived copy.
inva_readable <- st_make_valid(inva[!inva$unreadable_geometry, ])
inva_readable <- st_collection_extract(inva_readable, "POLYGON", warn = FALSE)
inside <- lengths(st_intersects(inva_readable, boundary)) > 0
inva_readable <- inva_readable[inside, ]
presence_polygons <- inva_readable[inva_readable$presence_status, ]
presence_points <- suppressWarnings(st_point_on_surface(presence_polygons))
st_write(presence_polygons, "data/processed/occurrences.gpkg", layer = "inva_presence_polygons", delete_layer = TRUE, quiet = TRUE)
st_write(presence_points, "data/processed/occurrences.gpkg", layer = "inva_representative_points", delete_layer = TRUE, quiet = TRUE)

# 4. GBIF: keep for a possible external check, outside training ----------------
pages <- lapply(sort(list.files("data/raw", full.names = TRUE, pattern = "^gbif_occurrences_[0-9]+\\.json$")), jsonlite::fromJSON)
gbif_rows <- do.call(rbind, lapply(pages, function(x) {
  d <- x$results
  # Common columns, retaining provenance and licences; originals retain ALL fields.
  columns <- c("key", "species", "speciesKey", "acceptedTaxonKey", "decimalLongitude", "decimalLatitude",
    "occurrenceStatus", "countryCode", "coordinateUncertaintyInMeters", "eventDate", "occurrenceID", "datasetKey", "license", "basisOfRecord")
  for (n in setdiff(columns, names(d))) d[[n]] <- NA
  d[columns]
}))
gbif_rows <- gbif_rows[!duplicated(gbif_rows$key), ]
taxon_key <- jsonlite::fromJSON(raw_file("gbif_taxon_match.json"))$usageKey
gbif_rows <- gbif_rows[gbif_rows$speciesKey == taxon_key & gbif_rows$countryCode == "LT" &
  !is.na(gbif_rows$decimalLongitude) & !is.na(gbif_rows$decimalLatitude) &
  (is.na(gbif_rows$occurrenceStatus) | gbif_rows$occurrenceStatus != "ABSENT"), ]
gbif <- st_transform(st_as_sf(gbif_rows, coords = c("decimalLongitude", "decimalLatitude"), crs = 4326, remove = FALSE), crs_m)
gbif$inside_lithuania <- lengths(st_intersects(gbif, boundary)) > 0
nearest <- st_nearest_feature(gbif, inva_readable)
gbif$nearest_inva_m <- as.numeric(st_distance(gbif, inva_readable[nearest, ], by_element = TRUE))
gbif$overlaps_inva <- gbif$nearest_inva_m == 0
# This conservative distance/uncertainty screen does NOT establish independence.
gbif$possible_check <- gbif$inside_lithuania & gbif$nearest_inva_m > 1000 &
  (is.na(gbif$coordinateUncertaintyInMeters) | gbif$coordinateUncertaintyInMeters <= 1000)
write_table(st_drop_geometry(gbif), "gbif_check_audit.csv")
st_write(gbif, "data/processed/occurrences.gpkg", layer = "gbif_check", delete_layer = TRUE, quiet = TRUE)

# 5. Load original OSM layers. SQL selects themes without editing the GeoPackage.
roads <- st_transform(st_read(raw_file("lithuania.gpkg"), query = paste0(
  "SELECT osm_id, fclass, geom FROM gis_osm_roads_free WHERE fclass NOT IN ",
  "('bridleway','cycleway','footway','path','pedestrian','steps')"), quiet = TRUE), crs_m)
waterways <- st_transform(st_read(raw_file("lithuania.gpkg"), query =
  "SELECT osm_id, fclass, geom FROM gis_osm_waterways_free", quiet = TRUE), crs_m)
settlements <- st_transform(st_read(raw_file("lithuania.gpkg"), query = paste0(
  "SELECT osm_id, fclass, name, geom FROM gis_osm_places_free WHERE fclass IN ",
  "('national_capital','city','town','village','hamlet','farm')"), quiet = TRUE), crs_m)

# 6. One row per 1 km cell; environmental features at cell centres --------------
template <- rast(ext(vect(boundary)), resolution = cell_size, crs = paste0("EPSG:", crs_m))
xy <- xyFromCell(template, seq_len(ncell(template)))
centres <- st_as_sf(data.frame(cell_id = seq_len(ncell(template)), x_m = xy[, 1], y_m = xy[, 2]), coords = c("x_m", "y_m"), crs = crs_m, remove = FALSE)
centres <- centres[lengths(st_intersects(centres, boundary)) > 0, ]
# Rasterise polygon footprints: all touched grid cells count as occupied.
occupied <- rasterize(vect(presence_polygons), template, field = 1, background = 0, touches = TRUE)
table_all <- st_drop_geometry(centres)
table_all$y <- as.integer(values(occupied)[table_all$cell_id, 1] > 0)
table_all$label_type <- ifelse(table_all$y == 1, "presence", "background_not_confirmed_absence")
# A cell-to-record crosswalk lets you keep cells of the same polygon together.
# Full record links are computed on cell polygons, not only one representative ID.
cell_boxes <- st_as_sf(as.polygons(occupied, aggregate = FALSE, values = TRUE))
cell_boxes$cell_id <- cellFromXY(template, st_coordinates(st_centroid(st_geometry(cell_boxes))))
cell_boxes <- cell_boxes[cell_boxes$cell_id %in% table_all$cell_id[table_all$y == 1], ]
links <- st_intersects(cell_boxes, presence_polygons)
record_links <- data.frame(cell_id = rep(cell_boxes$cell_id, lengths(links)), record_id = presence_polygons$record_id[unlist(links)])
write_table(record_links, "cell_occurrence_links.csv")

# Original geographic rasters are sampled at transformed cell centres.
at_centres <- function(r) extract(r, project(vect(centres), crs(r)), ID = FALSE)
bioclim <- bio[[c(1, 4, 8, 12, 13, 15)]]
names(bioclim) <- c("bio1_temp_mean_c", "bio4_temp_sd_x100", "bio8_temp_wettest_quarter_c",
  "bio12_precip_annual_mm", "bio13_precip_wettest_month_mm", "bio15_precip_cv_pct")
names(elevation) <- "elevation_m"
table_all <- cbind(table_all, at_centres(bioclim), at_centres(elevation))
for (v in c("tavg", "tmin", "tmax", "prec")) {
  r <- get(v)
  names(r) <- sprintf("%s_%02d", v, 1:12)
  table_all <- cbind(table_all, at_centres(r))
}
lc_index <- at_centres(land_cover)[[1]]
table_all$land_cover_clc <- as.character(land_legend$CODE_18[match(lc_index, land_legend$Value)])
# CORINE class is categorical: convert to factor again after reading CSV.
table_all$land_cover_clc <- factor(table_all$land_cover_clc)
# Sub-kilometre land-cover composition is represented by fractions of 100 m pixels.
group_raster <- classify(land_cover, cbind(land_legend$Value, as.integer(as.character(land_legend$CODE_18)) %/% 100))
group_names <- c("artificial", "agriculture", "forest_seminatural", "wetland", "water")
for (i in 1:5) {
  fraction <- project(group_raster == i, template, method = "average")
  table_all[[paste0("lc_fraction_", group_names[i])]] <- values(fraction)[table_all$cell_id, 1]
}
distance_m <- function(features) {
  j <- st_nearest_feature(centres, features)
  as.numeric(st_distance(centres, features[j, ], by_element = TRUE))
}
message("Calculating distances to roads, waterways, settlements and INVA footprints...")
table_all$distance_road_m <- distance_m(roads)
table_all$distance_waterway_m <- distance_m(waterways)
table_all$distance_settlement_m <- distance_m(settlements)
table_all$distance_any_inva_m <- distance_m(inva_readable) # Sampling/audit ONLY, never an X predictor!
table_all$edge_distance_m <- as.numeric(st_distance(st_geometry(centres), st_boundary(st_geometry(boundary))))
table_all$near_country_edge <- table_all$edge_distance_m < 5000
table_all$block_id <- paste(floor(table_all$x_m / 20000), floor(table_all$y_m / 20000), sep = "_")
predictor_columns <- c(names(bioclim), "elevation_m", sprintf("%s_%02d", rep(c("tavg", "tmin", "tmax", "prec"), each = 12), rep(1:12, 4)),
  "land_cover_clc", paste0("lc_fraction_", group_names), "distance_road_m", "distance_waterway_m", "distance_settlement_m")
table_all$predictors_complete <- complete.cases(table_all[predictor_columns])
write_table(table_all, "grid_predictors.csv")
writeLines(predictor_columns, "data/processed/predictor_columns.txt")

# A concrete starting table: presence + 3 background cells per presence cell.
# Restrict background to cells >1 km from ALL readable species polygons (any status).
present <- which(table_all$y == 1 & table_all$predictors_complete)
pool <- which(table_all$y == 0 & table_all$predictors_complete & table_all$distance_any_inva_m > background_buffer_m)
background <- sample(pool, min(length(pool), 3 * length(present)))
model_table <- table_all[c(present, background), ]
model_table <- model_table[order(model_table$cell_id), ]
write_table(model_table, "model_table.csv")
# Example for your future model:
# d <- read.csv("data/processed/model_table.csv")
# d$land_cover_clc <- factor(d$land_cover_clc)
# X <- d[readLines("data/processed/predictor_columns.txt")]; y <- d$y
# Build spatial folds using block_id AND cell_occurrence_links.csv. Keep connected
# blocks sharing a record together; use separation buffers before any evaluation.

# 7. Maps: one design, projected kilometre axes, shared colours -----------------
ink <- "#183C3B"; paper <- "#F6F4ED"; muted <- "#657B78"
map_theme <- theme_minimal(base_size = 11, base_family = "sans") + theme(
  plot.background = element_rect(fill = paper, colour = NA),
  panel.background = element_rect(fill = "#E6EEEB", colour = NA),
  panel.grid.major = element_line(colour = "white", linewidth = 0.25),
  plot.title = element_text(face = "bold", colour = ink, size = 16),
  plot.subtitle = element_text(colour = muted, size = 10),
  plot.caption = element_text(colour = muted, size = 8, hjust = 0),
  axis.text = element_text(colour = muted, size = 8),
  axis.title = element_text(colour = ink, size = 9),
  legend.position = "bottom", legend.title = element_text(colour = ink, size = 9),
  legend.text = element_text(size = 8), plot.margin = margin(13, 16, 12, 13))
bb <- st_bbox(boundary)
map_coord <- function() coord_sf(crs = st_crs(crs_m), default_crs = st_crs(crs_m), datum = st_crs(crs_m),
  xlim = bb[c("xmin", "xmax")], ylim = bb[c("ymin", "ymax")], expand = FALSE)
map_base <- function(title, subtitle, caption) {
  ggplot() + geom_sf(data = boundary, fill = "#EDF0E8", colour = NA) +
    scale_x_continuous(labels = function(x) format(x / 1000, trim = TRUE)) +
    scale_y_continuous(labels = function(y) format(y / 1000, trim = TRUE)) +
    labs(title = title, subtitle = paste(strwrap(subtitle, width = 85), collapse = "\n"),
      x = "Easting (km, LKS-94 / EPSG:3346)", y = "Northing (km, LKS-94 / EPSG:3346)",
      caption = paste(strwrap(caption, width = 100), collapse = "\n")) + map_theme
}
outline <- function() geom_sf(data = boundary, fill = NA, colour = ink, linewidth = 0.3)
save_map <- function(p, file, width = 9, height = 6.6) {
  if (interactive()) print(p)
  ggsave(file.path("maps", paste0(file, ".png")), p, width = width, height = height, dpi = 220, bg = paper)
  ggsave(file.path("maps", paste0(file, ".pdf")), p, width = width, height = height, device = cairo_pdf, bg = paper)
}
occurrence_map <- map_base("Sosnowsky's hogweed in Lithuania", "INVA polygon representatives and GBIF records for a possible external check",
  "Sources: VSTT / INVA; GBIF contributors; GADM 4.1. Points do not show polygon extent.") +
  geom_sf(data = presence_points, aes(colour = "INVA"), size = 0.55, alpha = 0.5) +
  geom_sf(data = gbif[gbif$inside_lithuania, ], aes(colour = "GBIF"), size = 1.35, shape = 17) +
  outline() + scale_colour_manual(NULL, values = c(INVA = "#BE6945", GBIF = "#226DAD")) + map_coord()
save_map(occurrence_map, "01_occurrences")

grid_map <- function(column, title, subtitle, unit, palette = "viridis") {
  map_base(title, subtitle, "Sources: WorldClim 2.1 / geodata; GADM 4.1. Values sampled at 1 km cell centres.") +
    geom_raster(data = table_all, aes(x = x_m, y = y_m, fill = .data[[column]])) +
    outline() + scale_fill_viridis_c(name = unit, option = palette, na.value = "#DADCD5") + map_coord()
}
temp_map <- grid_map("bio1_temp_mean_c", "Long-term mean temperature", "WorldClim 2.1 | 1970-2000 climate normal", "Temperature (degrees C)", "magma")
rain_map <- grid_map("bio12_precip_annual_mm", "Annual precipitation", "WorldClim 2.1 | 1970-2000 climate normal", "Precipitation (mm/year)")
elevation_map <- grid_map("elevation_m", "Lithuania's terrain", "Elevation | original 30 arc-second source", "Elevation (m)", "cividis")
save_map(temp_map, "02_temperature")
save_map(rain_map, "03_precipitation")
save_map(elevation_map, "04_elevation")

lc_plot <- project(group_raster, template, method = "near")
lc_df <- as.data.frame(lc_plot, xy = TRUE, na.rm = TRUE)
names(lc_df) <- c("x_m", "y_m", "group")
lc_df$group <- factor(lc_df$group, levels = 1:5, labels = c("Artificial", "Agriculture", "Forest / semi-natural", "Wetland", "Water"))
land_map <- map_base("Land cover", "CORINE 2018 | five broad groups for display; full class codes retained for models",
  "Source: European Union, Copernicus Land Monitoring Service / EEA, national Geoportal distribution; GADM 4.1.") +
  geom_raster(data = lc_df, aes(x = x_m, y = y_m, fill = group)) + outline() +
  scale_fill_manual(NULL, values = c("#BA705A", "#D9BD64", "#477C5C", "#9B85A7", "#69A4B8"), drop = FALSE) + map_coord()
save_map(land_map, "05_land_cover")

major_roads <- roads[roads$fclass %in% c("motorway", "trunk", "primary", "secondary"), ]
rivers <- waterways[waterways$fclass == "river", ]
towns <- settlements[settlements$fclass %in% c("national_capital", "city", "town"), ]
infrastructure_map <- map_base("Movement corridors and settlements", "Major roads, rivers and towns | full selected layers used for distances",
  "Sources: OpenStreetMap contributors / Geofabrik (ODbL); GADM 4.1.") +
  geom_sf(data = major_roads, aes(colour = "Major roads"), linewidth = 0.14, alpha = 0.7) +
  geom_sf(data = rivers, aes(colour = "Rivers"), linewidth = 0.2, alpha = 0.8) +
  geom_sf(data = towns, aes(colour = "Towns / cities"), size = 0.8) + outline() +
  scale_colour_manual(NULL, values = c("Major roads" = "#BA705A", "Rivers" = "#4994AE", "Towns / cities" = ink)) + map_coord()
save_map(infrastructure_map, "06_infrastructure")

sampling <- model_table
sampling$sample <- ifelse(sampling$y == 1, "Presence", "Background")
sample_map <- map_base("A starting table for habitat modelling", "One row per 1 km cell | background is not confirmed absence",
  "Background is sampled >1 km from INVA polygons. Apply spatial validation and sampling-bias review before modelling.") +
  geom_point(data = sampling, aes(x = x_m, y = y_m, colour = sample), size = 0.4, alpha = 0.55) + outline() +
  scale_colour_manual(NULL, values = c(Presence = "#BE6945", Background = "#608A81")) + map_coord()
save_map(sample_map, "07_modelling_sample")
atlas <- (occurrence_map + temp_map) / (land_map + infrastructure_map) +
  patchwork::plot_annotation(title = "H E R A C L E U M   /   L I T H U A N I A", theme = theme(
    plot.title = element_text(colour = ink, face = "bold", size = 22),
    plot.background = element_rect(fill = paper, colour = NA)))
save_map(atlas, "00_map_atlas", 17, 12.8)

# 8. Verify originals and save a concise run report -----------------------------
hash_after <- vapply(originals, hash_file, character(1))
stopifnot(identical(hash_before, hash_after), !anyDuplicated(table_all$cell_id),
  all(table_all$y %in% 0:1), all(model_table$predictors_complete),
  all(model_table$distance_any_inva_m[model_table$y == 0] > background_buffer_m),
  all(model_table$cell_id[model_table$y == 1] %in% record_links$cell_id),
  max(abs(rowSums(model_table[paste0("lc_fraction_", group_names)]) - 1)) < 1e-6)
write_table(data.frame(file = originals, sha256_before = hash_before, sha256_after = hash_after,
  unchanged = hash_before == hash_after), "original_file_integrity.csv")
report <- c(
  paste("INVA species records:", nrow(inva)),
  paste("Unreadable INVA geometries excluded:", sum(inva$unreadable_geometry)),
  paste("Invalid original INVA geometries (readable ones repaired in R):", sum(!inva$original_valid, na.rm = TRUE)),
  paste("INVA presence polygons:", nrow(presence_polygons)),
  paste("GBIF records:", nrow(gbif)), paste("GBIF records overlapping INVA:", sum(gbif$overlaps_inva)),
  paste("GBIF records passing preliminary check screen:", sum(gbif$possible_check)),
  paste("Grid cells:", nrow(table_all)), paste("Complete predictor cells:", sum(table_all$predictors_complete)),
  paste("Model table presence cells:", length(present)), paste("Model table background cells:", length(background)),
  paste("Predictors:", length(predictor_columns)), "All original files passed before/after SHA-256 verification.",
  "No habitat model has been fitted. Background labels are not confirmed absences.",
  "Distance to INVA, IDs, coordinates, block IDs, labels and audit flags are not predictors.")
writeLines(report, "metadata/run_summary.txt")
writeLines(trimws(capture.output(sessionInfo()), which = "right"), "metadata/r_session.txt")
cat(paste(report, collapse = "\n"), "\n")
