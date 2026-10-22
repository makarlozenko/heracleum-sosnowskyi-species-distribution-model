# Run from the project root: source("scripts/01_download.R", encoding = "UTF-8")
# Originals stay unchanged. Verified extracted files are reused; ZIPs are temporary.
user_lib <- Sys.getenv("R_LIBS_USER")
if (.Platform$OS.type == "windows") user_lib <- file.path(Sys.getenv("LOCALAPPDATA"), "R", "win-library", paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = "."))
profile_lib <- file.path(Sys.getenv("USERPROFILE"), "AppData", "Local", "R", "win-library", paste(R.version$major, strsplit(R.version$minor, "\\.")[[1]][1], sep = "."))
.libPaths(c(".R-library", user_lib, profile_lib, .libPaths()))
needed <- c("curl", "jsonlite", "openssl")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("First run install.packages(c(", paste(sprintf('"%s"', missing), collapse = ", "), "))")
options(timeout = 1200)
dir.create("data/raw", recursive = TRUE, showWarnings = FALSE)
dir.create("metadata", showWarnings = FALSE)
raw_file <- function(f) file.path("data", "raw", f)
download_path <- function(f) if (grepl("\\.zip$", f)) file.path("data", "downloads", f) else raw_file(f)
hash_file <- function(f) {
  con <- file(f, "rb")
  on.exit(close(con))
  as.character(openssl::sha256(con))
}

# Exact source URLs, also saved with final redirect URLs in downloads.csv.
urls <- c(
  "VSTT-Invazines_rusys.zip" = "https://data.gov.lt/datasets/4732/distribution/18484/download/",
  "Corine_latest.zip" = "https://data.gov.lt/datasets/3790/distribution/18101/download/",
  "lithuania-latest-free.gpkg.zip" = "https://download.geofabrik.de/europe/lithuania-latest-free.gpkg.zip",
  "LTU_elv_msk.zip" = "https://geodata.ucdavis.edu/geodata/elv/LTU_elv_msk.zip",
  "gadm41_LTU_0.json" = "https://geodata.ucdavis.edu/gadm/gadm4.1/json/gadm41_LTU_0.json"
)
for (v in c("tmin", "tmax", "tavg", "prec", "bio")) {
  f <- paste0("LTU_wc2.1_30s_", v, ".tif")
  urls[f] <- paste0("https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/", f)
}

receipts <- if (file.exists("metadata/downloads.csv")) read.csv("metadata/downloads.csv", stringsAsFactors = FALSE) else data.frame(
  file = character(), requested_url = character(), resolved_url = character(),
  downloaded_utc = character(), bytes = numeric(), sha256 = character())
fetch <- function(url, file) {
  old <- receipts[receipts$file == file, , drop = FALSE]
  path <- download_path(file)
  if (file.exists(path)) {
    if (nrow(old) != 1 || hash_file(path) != old$sha256) stop("Existing source failed verification: ", path)
    return(invisible(path))
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  request <- if (nrow(old) == 1) old$resolved_url else url
  message("Downloading ", file)
  result <- curl::curl_fetch_disk(request, paste0(path, ".part"), handle = curl::new_handle(
    followlocation = TRUE, connecttimeout = 40, timeout = 1200,
    useragent = "Lithuania-hogweed-research/2.0"))
  if (result$status_code != 200) stop("HTTP ", result$status_code, ": ", url)
  if (grepl("\\.zip$", file) && nrow(unzip(paste0(path, ".part"), list = TRUE)) == 0) stop("Invalid ZIP")
  if (nrow(old) == 1 && hash_file(paste0(path, ".part")) != old$sha256) stop("Download differs from the recorded snapshot: ", file)
  if (!file.rename(paste0(path, ".part"), path)) stop("Could not save ", path)
  row <- data.frame(file = file, requested_url = url, resolved_url = result$url,
    downloaded_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    bytes = file.info(path)$size, sha256 = hash_file(path))
  receipts <<- rbind(receipts[receipts$file != file, , drop = FALSE], row)
  write.csv(receipts, "metadata/downloads.csv", row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}
known_extractions <- if (file.exists("metadata/extracted_files.csv")) read.csv("metadata/extracted_files.csv", stringsAsFactors = FALSE) else data.frame()
archive_ready <- function(zip) {
  if (!nrow(known_extractions)) return(FALSE)
  x <- known_extractions[known_extractions$archive == zip, , drop = FALSE]
  nrow(x) > 0 && all(vapply(seq_len(nrow(x)), function(i) {
    f <- raw_file(x$file[i])
    file.exists(f) && hash_file(f) == x$sha256[i]
  }, logical(1)))
}
for (f in names(urls)) {
  if (grepl("\\.zip$", f) && archive_ready(f)) next
  fetch(urls[[f]], f)
}

# Keep GBIF HTTP responses exactly as returned, including all metadata/fields.
fetch("https://api.gbif.org/v1/species/match?name=Heracleum%20sosnowskyi", "gbif_taxon_match.json")
taxon <- jsonlite::fromJSON(raw_file("gbif_taxon_match.json"))
stopifnot(taxon$canonicalName == "Heracleum sosnowskyi", taxon$matchType == "EXACT")
key <- if (!is.null(taxon$acceptedUsageKey)) taxon$acceptedUsageKey else taxon$usageKey
offset <- 0
repeat {
  url <- paste0("https://api.gbif.org/v1/occurrence/search?taxon_key=", key,
    "&country=LT&has_coordinate=true&limit=300&offset=", offset)
  f <- sprintf("gbif_occurrences_%06d.json", offset)
  fetch(url, f)
  page <- jsonlite::fromJSON(raw_file(f), simplifyVector = FALSE)
  if (isTRUE(page$endOfRecords)) break
  offset <- offset + length(page$results)
  if (length(page$results) == 0 || offset >= 100000) stop("GBIF pagination incomplete; use an official GBIF download")
}

# Extract only main analysis formats, unchanged, into data/raw.
# Archive-member links and checksums are kept even after deleting the temporary ZIP.
extract_main <- function(zip, pattern) {
  if (archive_ready(zip)) return(known_extractions[known_extractions$archive == zip, c("archive", "member", "file")])
  entries <- unzip(download_path(zip), list = TRUE)
  entries <- entries[grepl(pattern, entries$Name, ignore.case = TRUE), ]
  if (!nrow(entries)) stop("Expected dataset missing in ", zip)
  for (i in seq_len(nrow(entries))) {
    dest <- raw_file(basename(entries$Name[i]))
    if (!file.exists(dest)) unzip(download_path(zip), files = entries$Name[i], exdir = "data/raw", junkpaths = TRUE)
    stopifnot(file.info(dest)$size == entries$Length[i])
  }
  data.frame(archive = zip, member = entries$Name, file = basename(entries$Name))
}
extracted <- rbind(
  extract_main("VSTT-Invazines_rusys.zip", "\\.gpkg$"),
  extract_main("Corine_latest.zip", "\\.gpkg$|CLC_2018/[^/]+$"),
  extract_main("lithuania-latest-free.gpkg.zip", "\\.gpkg$"),
  extract_main("LTU_elv_msk.zip", "\\.tif$")
)
extracted$sha256 <- vapply(extracted$file, function(f) hash_file(raw_file(f)), character(1))
if (nrow(known_extractions)) stopifnot(all(known_extractions$sha256 == extracted$sha256[match(known_extractions$file, extracted$file)]))
write.csv(extracted, "metadata/extracted_files.csv", row.names = FALSE)
for (zip in unique(extracted$archive)) {
  path <- download_path(zip)
  if (file.exists(path) && !file.remove(path)) stop("Could not remove temporary ZIP: ", path)
}
message("Source files verified in data/raw. Run scripts/02_prepare_and_plot.R next.")

# Equivalent direct R interfaces (optional alternatives; do not run both):
# install.packages("geodata")
# geodata::worldclim_country("LTU", var = "tavg", path = "data/geodata_cache")
# geodata::worldclim_country("LTU", var = "prec", path = "data/geodata_cache")
# geodata::worldclim_country("LTU", var = "bio", path = "data/geodata_cache")
# geodata::elevation_30s("LTU", path = "data/geodata_cache")
# geodata::gadm("LTU", level = 0, version = "4.1", path = "data/geodata_cache")
# These use the same provider datasets but geodata manages its own subfolders.
