script_file <- NULL
for (frame in sys.frames()) if (!is.null(frame$ofile)) script_file <- frame$ofile
if (is.null(script_file)) {
  script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
}
if (is.na(script_file)) stop("Run the complete script using Source in RStudio or Rscript.")
setwd(dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE)))

#Builds the 1 km modelling tables and the maps from the files in "data"
library(sf)
library(terra)
library(ggplot2)
library(patchwork)

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("maps", showWarnings = FALSE)

set.seed(123)
crs_m <- 3346               #LKS-94, units are metres
cell_size <- 1000           #grid cell size, m
background_buffer_m <- 1000 #background cells must be farther than this from any INVA polygon

data_file <- function(f) file.path("data", f)
write_processed <- function(x, f) {
  output_dir <- file.path("data", "processed")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)
  output_path <- file.path(output_dir, f)

  # Write a complete CSV before attempting to replace an existing, possibly locked file.
  new_path <- tempfile(paste0(tools::file_path_sans_ext(f), "_"),
                       tmpdir = output_dir, fileext = ".csv")
  write.csv(x, new_path, row.names = FALSE, fileEncoding = "UTF-8", na = "")
  if (suppressWarnings(file.copy(new_path, output_path, overwrite = TRUE))) {
    unlink(new_path)
    invisible(output_path)
  } else {
    warning("Could not replace ", output_path,
            ". Close the CSV in Excel or another application and check write permissions. ",
            "This run's table was saved as ",
            new_path, ".", call. = FALSE)
    invisible(new_path)
  }
}


#Environmental source data
boundary  <- st_transform(st_read(data_file("gadm41_LTU_0.json"), quiet = TRUE), crs_m)
bio       <- rast(data_file("LTU_wc2.1_30s_bio.tif"))
elevation <- rast(data_file("LTU_elv_msk.tif"))

land_cover  <- rast(data_file("U2018_CLC2018_V2020_20u1_LT.tif"))
land_legend <- foreign::read.dbf(data_file("U2018_CLC2018_V2020_20u1_LT.tif.vat.dbf"), as.is = TRUE)
write_processed(land_legend, "land_cover_legend.csv")

#Keeping valid CORINE classes only
land_cover <- ifel(land_cover >= 1 & land_cover <= 44, land_cover, NA)
levels(land_cover) <- NULL
coltab(land_cover) <- NULL


#INVA records of Heracleum sosnowskyi
#Reading the GeoPackage directly so records with malformed geometry keep their attributes
con <- DBI::dbConnect(RSQLite::SQLite(), data_file("Invazines_rusys.gpkg"), flags = RSQLite::SQLITE_RO)
geom_info <- DBI::dbGetQuery(con, "SELECT * FROM gpkg_geometry_columns")
inva_table <- geom_info$table_name[1]
geom_column <- geom_info$column_name[1]
species_column <- "R\u016b\u0161ies_mokslinis_pavadinimas"
inva_attributes <- DBI::dbGetQuery(con, paste0(
  "SELECT * FROM ", DBI::dbQuoteIdentifier(con, inva_table),
  " WHERE ", DBI::dbQuoteIdentifier(con, species_column), " = 'Heracleum sosnowskyi'"))
DBI::dbDisconnect(con)

#Stripping the GeoPackage header from a geometry blob to get standard WKB
read_wkb <- function(b) {
  if (!length(b)) return(st_as_binary(st_sfc(st_geometrycollection()))[[1]])
  envelope <- bitwAnd(bitwShiftR(as.integer(b[4]), 1), 7)
  header <- 8 + c(0, 32, 48, 48, 64)[envelope + 1]
  b[-seq_len(header)]
}

blobs <- inva_attributes[[geom_column]]
inva_attributes[[geom_column]] <- NULL
geometry <- st_as_sfc(structure(lapply(blobs, read_wkb), class = "WKB"), crs = crs_m)
unreadable <- is.na(st_is_valid(geometry, NA_on_exception = TRUE))
geometry[unreadable] <- st_sfc(st_geometrycollection(), crs = crs_m)
inva <- st_sf(inva_attributes, geometry = geometry)

inva$record_id <- as.character(inva[["Radaviet\u0117s_ID"]])
inva$status <- inva[["Radaviet\u0117s_statusas"]]
inva$unreadable_geometry <- st_is_empty(inva)
inva$original_valid <- st_is_valid(inva)
inva$original_valid[inva$unreadable_geometry] <- NA
inva$presence_status <- inva$status %in% c("INITIAL", "INCREASED", "STABLE", "DECREASED")

#Repair readable geometries, keep polygons inside Lithuania
inva_readable <- st_make_valid(inva[!inva$unreadable_geometry, ])
inva_readable <- st_collection_extract(inva_readable, "POLYGON", warn = FALSE)
inva_readable <- inva_readable[lengths(st_intersects(inva_readable, boundary)) > 0, ]

presence_polygons <- inva_readable[inva_readable$presence_status, ]
presence_points <- suppressWarnings(st_point_on_surface(presence_polygons))

st_write(presence_polygons, "data/processed/occurrences.gpkg", layer = "inva_presence_polygons",
         delete_layer = TRUE, quiet = TRUE)
st_write(presence_points, "data/processed/occurrences.gpkg", layer = "inva_representative_points",
         delete_layer = TRUE, quiet = TRUE)


#GBIF records
gbif_columns <- c("key", "species", "speciesKey", "acceptedTaxonKey", "decimalLongitude", "decimalLatitude",
                  "occurrenceStatus", "countryCode", "coordinateUncertaintyInMeters", "eventDate",
                  "occurrenceID", "datasetKey", "license", "basisOfRecord")

read_gbif_page <- function(file) {
  d <- jsonlite::fromJSON(file)$results
  for (n in setdiff(gbif_columns, names(d))) d[[n]] <- NA
  d[gbif_columns]
}

gbif_pages <- sort(list.files("data", pattern = "^gbif_occurrences_[0-9]+\\.json$", full.names = TRUE))
gbif_rows <- do.call(rbind, lapply(gbif_pages, read_gbif_page))
gbif_rows <- gbif_rows[!duplicated(gbif_rows$key), ]

taxon_key <- jsonlite::fromJSON(data_file("gbif_taxon_match.json"))$usageKey
gbif_rows <- gbif_rows[gbif_rows$speciesKey == taxon_key & gbif_rows$countryCode == "LT" &
                         !is.na(gbif_rows$decimalLongitude) & !is.na(gbif_rows$decimalLatitude) &
                         (is.na(gbif_rows$occurrenceStatus) | gbif_rows$occurrenceStatus != "ABSENT"), ]

gbif <- st_transform(st_as_sf(gbif_rows, coords = c("decimalLongitude", "decimalLatitude"),
                              crs = 4326, remove = FALSE), crs_m)
gbif$inside_lithuania <- lengths(st_intersects(gbif, boundary)) > 0

nearest <- st_nearest_feature(gbif, inva_readable)
gbif$nearest_inva_m <- as.numeric(st_distance(gbif, inva_readable[nearest, ], by_element = TRUE))
gbif$overlaps_inva <- gbif$nearest_inva_m == 0
gbif$possible_check <- gbif$inside_lithuania & gbif$nearest_inva_m > 1000 &
  (is.na(gbif$coordinateUncertaintyInMeters) | gbif$coordinateUncertaintyInMeters <= 1000)

st_write(gbif, "data/processed/occurrences.gpkg", layer = "gbif_check", delete_layer = TRUE, quiet = TRUE)


#OpenStreetMap layers
read_osm <- function(query) {
  st_transform(st_read(data_file("lithuania.gpkg"), query = query, quiet = TRUE), crs_m)
}

roads <- read_osm(paste0(
  "SELECT fclass, geom FROM gis_osm_roads_free WHERE fclass NOT IN ",
  "('bridleway','cycleway','footway','path','pedestrian','steps')"))
waterways <- read_osm("SELECT fclass, geom FROM gis_osm_waterways_free")
settlements <- read_osm(paste0(
  "SELECT fclass, geom FROM gis_osm_places_free WHERE fclass IN ",
  "('national_capital','city','town','village','hamlet','farm')"))


#Grid table: one row per 1 km cell
#Cell centres inside Lithuania
template <- rast(ext(vect(boundary)), resolution = cell_size, crs = paste0("EPSG:", crs_m))
xy <- xyFromCell(template, seq_len(ncell(template)))
centres <- st_as_sf(data.frame(cell_id = seq_len(ncell(template)), x_m = xy[, 1], y_m = xy[, 2]),
                    coords = c("x_m", "y_m"), crs = crs_m, remove = FALSE)
centres <- centres[lengths(st_intersects(centres, boundary)) > 0, ]

#Presence label: every cell touched by a presence polygon
occupied <- rasterize(vect(presence_polygons), template, field = 1, background = 0, touches = TRUE)
table_all <- st_drop_geometry(centres)
table_all$y <- as.integer(values(occupied)[table_all$cell_id, 1] > 0)
table_all$label_type <- ifelse(table_all$y == 1, "presence", "background_not_confirmed_absence")

#Cell-to-record links, so cells of the same polygon can be kept together
cell_boxes <- st_as_sf(as.polygons(occupied, aggregate = FALSE, values = TRUE))
cell_boxes$cell_id <- cellFromXY(template, st_coordinates(st_centroid(st_geometry(cell_boxes))))
cell_boxes <- cell_boxes[cell_boxes$cell_id %in% table_all$cell_id[table_all$y == 1], ]
links <- st_intersects(cell_boxes, presence_polygons)
record_links <- data.frame(cell_id = rep(cell_boxes$cell_id, lengths(links)),
                           record_id = presence_polygons$record_id[unlist(links)])
write_processed(record_links, "cell_occurrence_links.csv")

#Climate and elevation sampled at cell centres
at_centres <- function(r) extract(r, project(vect(centres), crs(r)), ID = FALSE)

bioclim <- bio[[c(1, 4, 8, 12, 13, 15)]]
names(bioclim) <- c("bio1_temp_mean_c", "bio4_temp_sd_x100", "bio8_temp_wettest_quarter_c",
                    "bio12_precip_annual_mm", "bio13_precip_wettest_month_mm", "bio15_precip_cv_pct")
names(elevation) <- "elevation_m"
table_all <- cbind(table_all, at_centres(bioclim), at_centres(elevation))

for (v in c("tavg", "tmin", "tmax", "prec")) {
  r <- rast(data_file(paste0("LTU_wc2.1_30s_", v, ".tif")))
  names(r) <- sprintf("%s_%02d", v, 1:12)
  table_all <- cbind(table_all, at_centres(r))
}

#Land cover: CORINE class at the cell centre, plus fractions of 5 broad groups per cell
lc_index <- at_centres(land_cover)[[1]]
table_all$land_cover_clc <- factor(as.character(land_legend$CODE_18[match(lc_index, land_legend$Value)]))

group_raster <- classify(land_cover, cbind(land_legend$Value, as.integer(as.character(land_legend$CODE_18)) %/% 100))
group_names <- c("artificial", "agriculture", "forest_seminatural", "wetland", "water")
for (i in 1:5) {
  fraction <- project(group_raster == i, template, method = "average")
  table_all[[paste0("lc_fraction_", group_names[i])]] <- values(fraction)[table_all$cell_id, 1]
}

#Distances (m) and spatial blocks
distance_m <- function(features) {
  j <- st_nearest_feature(centres, features)
  as.numeric(st_distance(centres, features[j, ], by_element = TRUE))
}

message("Calculating distances to roads, waterways, settlements and INVA footprints")
table_all$distance_road_m <- distance_m(roads)
table_all$distance_waterway_m <- distance_m(waterways)
table_all$distance_settlement_m <- distance_m(settlements)
table_all$distance_any_inva_m <- distance_m(inva_readable) #for background sampling only, this is not a predictor
table_all$edge_distance_m <- as.numeric(st_distance(st_geometry(centres), st_boundary(st_geometry(boundary))))
table_all$near_country_edge <- table_all$edge_distance_m < 5000
table_all$block_id <- paste(floor(table_all$x_m / 20000), floor(table_all$y_m / 20000), sep = "_")

predictor_columns <- c(
  names(bioclim), "elevation_m",
  sprintf("%s_%02d", rep(c("tavg", "tmin", "tmax", "prec"), each = 12), rep(1:12, 4)),
  "land_cover_clc", paste0("lc_fraction_", group_names),
  "distance_road_m", "distance_waterway_m", "distance_settlement_m")
table_all$predictors_complete <- complete.cases(table_all[predictor_columns])

write_processed(table_all, "grid_predictors.csv")
writeLines(predictor_columns, "data/processed/predictor_columns.txt")


#Model table
present <- which(table_all$y == 1 & table_all$predictors_complete)
pool <- which(table_all$y == 0 & table_all$predictors_complete &
                table_all$distance_any_inva_m > background_buffer_m)
background <- sample(pool, min(length(pool), 3 * length(present)))

model_table <- table_all[c(present, background), ]
model_table <- model_table[order(model_table$cell_id), ]
write_processed(model_table, "model_table.csv")


#Maps
ink <- "#183C3B"
paper <- "white"
muted <- "#657B78"

map_theme <- theme_minimal(base_size = 11, base_family = "sans") + theme(
  plot.background = element_rect(fill = paper, colour = NA),
  panel.background = element_rect(fill = paper, colour = NA),
  panel.grid.major = element_line(colour = "white", linewidth = 0.25),
  plot.title = element_text(face = "bold", colour = ink, size = 16, hjust = 0.5),
  plot.subtitle = element_text(colour = muted, size = 10, hjust = 0.5),
  plot.caption = element_text(colour = muted, size = 8, hjust = 0),
  axis.text = element_text(colour = muted, size = 8),
  axis.title = element_text(colour = ink, size = 9),
  legend.position = "bottom", legend.title = element_text(colour = ink, size = 9),
  legend.text = element_text(size = 8), plot.margin = margin(13, 16, 12, 13))

bb <- st_bbox(boundary)

map_coord <- function() {
  coord_sf(crs = st_crs(crs_m), default_crs = st_crs(crs_m), datum = st_crs(crs_m),
           xlim = bb[c("xmin", "xmax")], ylim = bb[c("ymin", "ymax")], expand = FALSE)
}

map_base <- function(title, subtitle, caption) {
  ggplot() + geom_sf(data = boundary, fill = paper, colour = NA) +
    scale_x_continuous(labels = function(x) format(x / 1000, trim = TRUE)) +
    scale_y_continuous(labels = function(y) format(y / 1000, trim = TRUE)) +
    labs(title = title, subtitle = paste(strwrap(subtitle, width = 85), collapse = "\n"),
         x = "Easting (km, LKS-94 / EPSG:3346)", y = "Northing (km, LKS-94 / EPSG:3346)",
         caption = paste(strwrap(caption, width = 100), collapse = "\n")) + map_theme
}

outline <- function() geom_sf(data = boundary, fill = NA, colour = ink, linewidth = 0.3)

save_map <- function(p, file, width = 9, height = 6.6) {
  dir.create("maps", recursive = TRUE, showWarnings = FALSE)
  if (interactive()) print(p)
  ggsave(file.path("maps", paste0(file, ".png")), p, width = width, height = height, dpi = 220, bg = paper)

  # Render to a new file first; an open PDF viewer may lock the previous PDF.
  pdf_path <- file.path("maps", paste0(file, ".pdf"))
  pdf_new <- tempfile(paste0(file, "_"), tmpdir = "maps", fileext = ".pdf")
  ggsave(pdf_new, p, width = width, height = height, device = grDevices::pdf, bg = paper)
  if (suppressWarnings(file.copy(pdf_new, pdf_path, overwrite = TRUE))) {
    unlink(pdf_new)
  } else {
    warning("Could not replace ", pdf_path,
            ". Close it in the PDF viewer. The new PDF was saved as ",
            normalizePath(pdf_new, winslash = "/"), call. = FALSE)
  }
}

#Occurrences
occurrence_map <- map_base(
  "Sosnowsky's hogweed in Lithuania",
  "INVA polygon representatives and GBIF records for a possible external check",
  "Sources: VSTT / INVA; GBIF contributors; GADM 4.1.") +
  geom_sf(data = presence_points, aes(colour = "INVA"), size = 0.55, alpha = 0.5) +
  geom_sf(data = gbif[gbif$inside_lithuania, ], aes(colour = "GBIF"), size = 1.35, shape = 17) +
  outline() + scale_colour_manual(NULL, values = c(GBIF = "#226DAD", INVA = "#BE6945")) + map_coord()
save_map(occurrence_map, "01_occurrences")

#Climate and elevation
grid_map <- function(column, title, subtitle, unit, palette = "viridis") {
  map_base(title, subtitle, "Sources: WorldClim 2.1 / geodata; GADM 4.1.") +
    geom_raster(data = table_all, aes(x = x_m, y = y_m, fill = .data[[column]])) +
    outline() + scale_fill_viridis_c(name = unit, option = palette, na.value = "#DADCD5") + map_coord()
}

temp_map <- grid_map("bio1_temp_mean_c", "Long-term mean temperature",
                     "WorldClim 2.1 | 1970-2000 climate", "Temperature (degrees C)", "magma")
rain_map <- grid_map("bio12_precip_annual_mm", "Annual precipitation",
                     "WorldClim 2.1 | 1970-2000 climate", "Precipitation (mm/year)")
elevation_map <- grid_map("elevation_m", "Lithuania's terrain",
                          "Elevation | original 30 arc-second source", "Elevation (m)", "cividis")
save_map(temp_map, "02_temperature")
save_map(rain_map, "03_precipitation")
save_map(elevation_map, "04_elevation")

#Land cover
lc_df <- as.data.frame(project(group_raster, template, method = "near"), xy = TRUE, na.rm = TRUE)
names(lc_df) <- c("x_m", "y_m", "group")
lc_df$group <- factor(lc_df$group, levels = 1:5,
                      labels = c("Artificial", "Agriculture", "Forest / semi-natural", "Wetland", "Water"))

land_map <- map_base(
  "Land cover",
  "CORINE 2018 | five broad groups for display",
  "Source: European Union, Copernicus Land Monitoring Service / EEA, national Geoportal distribution; GADM 4.1.") +
  geom_raster(data = lc_df, aes(x = x_m, y = y_m, fill = group)) + outline() +
  scale_fill_manual(NULL, values = c("#BA705A", "#D9BD64", "#477C5C", "#9B85A7", "#69A4B8"), drop = FALSE) +
  map_coord()
save_map(land_map, "05_land_cover")

#Roads, rivers and towns
major_roads <- roads[roads$fclass %in% c("motorway", "trunk", "primary", "secondary"), ]
rivers <- waterways[waterways$fclass == "river", ]
towns <- settlements[settlements$fclass %in% c("national_capital", "city", "town"), ]

infrastructure_map <- map_base(
  "Movement corridors",
  "Major roads, rivers and towns | full selected layers used for distances",
  "Sources: OpenStreetMap contributors / Geofabrik (ODbL); GADM 4.1.") +
  geom_sf(data = major_roads, aes(colour = "Major roads"), linewidth = 0.14, alpha = 0.7) +
  geom_sf(data = rivers, aes(colour = "Rivers"), linewidth = 0.2, alpha = 0.8) +
  geom_sf(data = towns, aes(colour = "Towns / cities"), size = 0.8) + outline() +
  scale_colour_manual(NULL, values = c("Major roads" = "#BA705A", "Rivers" = "#4994AE", "Towns / cities" = ink)) +
  map_coord()
save_map(infrastructure_map, "06_infrastructure")

#Modelling sample
sampling <- model_table
sampling$sample <- ifelse(sampling$y == 1, "Presence", "Background")

sample_map <- map_base(
  "A starting table for habitat modelling",
  "One row per 1 km cell | background is not confirmed absence",
  "Background is sampled >1 km from INVA polygons.") +
  geom_point(data = sampling, aes(x = x_m, y = y_m, colour = sample), size = 0.4, alpha = 0.55) + outline() +
  scale_colour_manual(NULL, values = c(Presence = "#BE6945", Background = "#608A81")) + map_coord()
save_map(sample_map, "07_modelling_sample")

#All maps in one atlas
atlas <- (occurrence_map + sample_map) /
  (land_map + infrastructure_map) /
  (temp_map + rain_map) /
  (elevation_map + plot_spacer()) +
  plot_annotation(
    title = "HERACLEUM / LITHUANIA",
    theme = theme(
      plot.title = element_text(colour = ink, face = "bold", size = 22, hjust = 0.5),
      plot.background = element_rect(fill = paper, colour = NA)
    )
  )
save_map(atlas, "00_map_atlas", 17, 24)
