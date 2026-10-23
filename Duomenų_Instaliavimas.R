script_file <- NULL
for (frame in sys.frames()) if (!is.null(frame$ofile)) script_file <- frame$ofile
if (is.null(script_file)) {
  script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
}
if (is.na(script_file)) stop("Run the complete script using Source in RStudio or Rscript.")
setwd(dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE)))

#Downloading the datasets
dir.create("data", showWarnings = FALSE)

data_file <- function(f) file.path("data", f)

download <- function(url, file) {
  message("Downloading ", file)
  curl::curl_download(url, data_file(file))
}

download("https://geodata.ucdavis.edu/gadm/gadm4.1/json/gadm41_LTU_0.json", "gadm41_LTU_0.json")

for (v in c("tmin", "tmax", "tavg", "prec", "bio")) {
  f <- paste0("LTU_wc2.1_30s_", v, ".tif")
  download(paste0("https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/", f), f)
}

zip_sources <- list(
  "VSTT-Invazines_rusys.zip" = list(
    url     = "https://data.gov.lt/datasets/4732/distribution/18484/download/",
    extract = "Invazines_rusys\\.gpkg$"),
  "Corine_latest.zip" = list(
    url     = "https://data.gov.lt/datasets/3790/distribution/18101/download/",
    extract = "CLC_2018/U2018_CLC2018_V2020_20u1_LT\\.tif(\\.vat\\.dbf)?$"),
  "lithuania-latest-free.gpkg.zip" = list(
    url     = "https://download.geofabrik.de/europe/lithuania-latest-free.gpkg.zip",
    extract = "lithuania\\.gpkg$"),
  "LTU_elv_msk.zip" = list(
    url     = "https://geodata.ucdavis.edu/geodata/elv/LTU_elv_msk.zip",
    extract = "LTU_elv_msk\\.tif$")
)

for (zip in names(zip_sources)) {
  download(zip_sources[[zip]]$url, zip)
  members <- unzip(data_file(zip), list = TRUE)$Name
  members <- members[grepl(zip_sources[[zip]]$extract, members, ignore.case = TRUE)]
  stopifnot(length(members) > 0)
  unzip(data_file(zip), files = members, exdir = "data", junkpaths = TRUE)
  file.remove(data_file(zip))
}

download("https://api.gbif.org/v1/species/match?name=Heracleum%20sosnowskyi", "gbif_taxon_match.json")
taxon <- jsonlite::fromJSON(data_file("gbif_taxon_match.json"))
taxon_key <- if (!is.null(taxon$acceptedUsageKey)) taxon$acceptedUsageKey else taxon$usageKey

offset <- 0
repeat {
  page_file <- sprintf("gbif_occurrences_%06d.json", offset)
  download(paste0("https://api.gbif.org/v1/occurrence/search?taxon_key=", taxon_key,
                  "&country=LT&has_coordinate=true&limit=300&offset=", offset), page_file)
  page <- jsonlite::fromJSON(data_file(page_file), simplifyVector = FALSE)
  if (isTRUE(page$endOfRecords) || length(page$results) == 0) break
  offset <- offset + length(page$results)
}
