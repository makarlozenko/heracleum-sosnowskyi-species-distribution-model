# Open hogweed.Rproj. Run each block with Ctrl+Enter in RStudio.
# Required packages: install.packages(c("sf", "terra"))
library(sf)
library(terra)

# 1. Read species records and environmental data.
presence <- read.csv("data/model/presence.csv")
inva_polygons <- st_read("data/model/inva_polygons.gpkg", layer = "inva_polygons", quiet = TRUE)
gbif <- read.csv("data/model/gbif_check.csv")
boundary <- st_read("data/model/boundary.geojson", quiet = TRUE)
climate <- rast("data/model/climate.tif")  # Six climate predictors
elevation <- rast("data/model/elevation.tif")
land_cover <- rast("data/model/land_cover.tif")
classes <- read.csv("data/model/land_cover_classes.csv")
roads <- st_read("data/model/infrastructure.gpkg", layer = "roads", quiet = TRUE)
waterways <- st_read("data/model/infrastructure.gpkg", layer = "waterways", quiet = TRUE)
settlements <- st_read("data/model/infrastructure.gpkg", layer = "settlements", quiet = TRUE)

# 2. Inspect tables. Use View(presence) or View(gbif) to see all rows in RStudio.
print(head(presence))
print(head(st_drop_geometry(inva_polygons)))
print(table(presence$status))
print(head(gbif))
print(head(classes))
print(head(st_drop_geometry(roads)))
print(head(st_drop_geometry(waterways)))
print(head(st_drop_geometry(settlements)))

# 3. Map records: INVA in red, GBIF in blue.
points <- st_as_sf(presence, coords = c("longitude", "latitude"), crs = 4326)
gbif_points <- st_as_sf(gbif, coords = c("longitude", "latitude"), crs = 4326)
plot(st_geometry(boundary), main = "Heracleum sosnowskyi: occurrence records")
plot(st_geometry(points), add = TRUE, col = "red", pch = 16, cex = 0.3)
plot(st_geometry(gbif_points), add = TRUE, col = "blue", pch = 16, cex = 0.5)
legend("bottomleft", c("INVA", "GBIF"), col = c("red", "blue"), pch = 16, bty = "n")

# Show polygon footprints separately; the CSV points are derived representatives.
# The file keeps every record; map only candidates with valid geometries.
polygons_for_map <- inva_polygons[inva_polygons$presence_candidate & inva_polygons$polygon_valid, ]
boundary_m <- st_transform(boundary, 3346)
plot(st_geometry(boundary_m), main = "Valid INVA presence polygons")
plot(st_geometry(polygons_for_map), col = "tomato", border = "firebrick", add = TRUE)

# 4. Map predictors. Use the arrows in the Plots tab to see earlier maps.
# temp_mean: BIO1, degrees C; temp_seasonality: BIO4, temperature SD * 100.
# precip_year: BIO12, mm/year; precip_seasonality: BIO15, precipitation CV, %.
# temp_wettest_quarter: BIO8, mean temperature of the wettest 3-month period, degrees C.
# precip_wettest_month: BIO13, precipitation of the wettest month, mm.
plot(mask(climate, vect(boundary)), maxcell = 100000)
plot(elevation, main = "Elevation, m", maxcell = 100000)

# Group CORINE classes for display; the original raster remains unchanged.
land_groups <- classify(land_cover, cbind(classes$value, classes$clc_code %/% 100))
levels(land_groups) <- data.frame(id = 1:5, class = c("Artificial surfaces", "Agricultural land",
  "Forest / semi-natural areas", "Wetlands", "Water"))
plot(land_groups, col = c("red", "gold", "forestgreen", "purple", "skyblue"),
     maxcell = 100000, plg = list(x = "bottomleft", cex = 0.8))

# Roads and waterways are lines; settlements are points. Use them for distances.
# Show major roads on the map; roads still contains the full selected road layer.
major_roads <- roads[roads$fclass %in% c("motorway", "trunk", "primary", "secondary"), ]
par(mfrow = c(1, 3))
plot(st_geometry(major_roads), col = "grey50", lwd = 0.2, main = "Major roads")
plot(st_geometry(waterways), col = "steelblue", lwd = 0.4, main = "Waterways")
plot(st_geometry(settlements), pch = 16, cex = 0.15, main = "Settlements")
par(mfrow = c(1, 1))

# 5. Example: turn occurrence coordinates into ML predictors (X).
# Extract the raster values at each representative point.
ml_example <- data.frame(
  record_id = presence$record_id,
  y = 1,
  extract(climate, vect(points), ID = FALSE),
  extract(elevation, vect(points), ID = FALSE)
)
print(head(ml_example))
# This is an extraction example, not a finished training dataset: all y values are 1.
# Next: a common grid, land-cover/distance features, background or pseudoabsences,
# and a spatial train/test split; see README. Use polygons to assess occupied cells.
# Review polygon_valid before using polygon areas; do not treat missing geometry as absence.
# Keep cells from the same record_id together in validation; IDs are not predictors.
# Keep GBIF separate from this table for a potential independent check.
