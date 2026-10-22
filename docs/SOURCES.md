# Exact acquisition links and direct R calls

Downloaded on **23 October 2026, Europe/Kyiv**. UTC timestamps in `metadata/downloads.csv` can fall on 22 October. That file is the machine-readable acquisition record: requested URL, resolved URL after redirects, UTC time, bytes and SHA-256. `scripts/01_download.R` contains every request. No login or API key was needed. Retained original files are in `data/raw/`. ZIP archives were removed during cleanup; their exact source URLs, archive-member links and checksums remain recorded. The download snippets below show the original requests; use `scripts/01_download.R` to manage the current folder structure.

## INVA — original invasive-species locations

- Catalog: <https://data.gov.lt/datasets/4732/>
- Exact requested download: <https://data.gov.lt/datasets/4732/distribution/18484/download/>
- Resolved publisher file: <https://www.geoportal.lt/download/opendata/VSTT/VSTT-Invazines_rusys.zip>
- Main extracted file: `Invazines_rusys.gpkg`, layer `Invaziniu_rusiu_radavietes`.
- Publisher: Valstybinė saugomų teritorijų tarnyba (VSTT), INVA.

```r
download.file("https://data.gov.lt/datasets/4732/distribution/18484/download/",
              "VSTT-Invazines_rusys.zip", mode = "wb")
# Species filtering is performed after extraction, in scripts/02_prepare_and_plot.R.
```

## GBIF — possible external occurrence check

- Taxon match: <https://api.gbif.org/v1/species/match?name=Heracleum%20sosnowskyi>
- Exact occurrence request: <https://api.gbif.org/v1/occurrence/search?taxon_key=3642949&country=LT&has_coordinate=true&limit=300&offset=0>
- API documentation: <https://techdocs.gbif.org/en/openapi/v1/occurrence>

`scripts/01_download.R` reads the matched accepted species key and requests every page until `endOfRecords = true`. Raw responses are saved unchanged, not converted into a replacement source CSV. This is an API snapshot, not a DOI-registered GBIF download. Record licences and dataset keys remain in the raw JSON and derived audit table; cite contributing datasets when using their records. For formal publication, an official GBIF download with a DOI is preferable.

## Climate — WorldClim 2.1, monthly 1970–2000 normals

The supplied message allows **Climatology Lab OR WorldClim**. WorldClim is used in this attempt. Climatology Lab's [TerraClimate](https://www.climatologylab.org/terraclimate.html) is the global monthly option; gridMET and MACA products listed there are US-focused. No TerraClimate data are claimed or mixed into this attempt.

- WorldClim description: <https://www.worldclim.org/data/worldclim21.html>
- R package documentation: <https://rspatial.github.io/geodata/reference/worldclim.html>
- Exact country files, 30 arc seconds, multiband GeoTIFF:
  - <https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/LTU_wc2.1_30s_tmin.tif>
  - <https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/LTU_wc2.1_30s_tmax.tif>
  - <https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/LTU_wc2.1_30s_tavg.tif>
  - <https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/LTU_wc2.1_30s_prec.tif>
  - <https://geodata.ucdavis.edu/climate/worldclim/2_1/tiles/iso/LTU_wc2.1_30s_bio.tif>

Equivalent package-managed downloads and loading directly in R:

```r
install.packages("geodata") # if needed
tavg <- geodata::worldclim_country("LTU", var = "tavg", path = "geodata_cache")
tmin <- geodata::worldclim_country("LTU", var = "tmin", path = "geodata_cache")
tmax <- geodata::worldclim_country("LTU", var = "tmax", path = "geodata_cache")
prec <- geodata::worldclim_country("LTU", var = "prec", path = "geodata_cache")
bio  <- geodata::worldclim_country("LTU", var = "bio",  path = "geodata_cache")
```

The acquisition script uses exact URLs to put the retained source files in `data/raw/`. ZIP downloads are temporary and are deleted after verified extraction. `geodata` uses its own cache subdirectories; these are alternatives, not extra required steps. Cite Fick & Hijmans (2017), *WorldClim 2: new 1km spatial resolution climate surfaces for global land areas*, International Journal of Climatology 37:4302–4315. Follow the provider's data terms.

## Copernicus / EEA — CORINE 2018 land cover

- Product and metadata: <https://land.copernicus.eu/en/products/corine-land-cover/clc2018>
- Raster DOI: <https://doi.org/10.2909/960998c1-1870-4e82-8051-6485205ebbac>
- National distribution catalog: <https://data.gov.lt/datasets/3790/>
- Exact requested download: <https://data.gov.lt/datasets/3790/distribution/18101/download/>
- Resolved publisher file: <https://www.geoportal.lt/download/opendata/EAA/Corine_latest.zip>
- Main extracted files: `CLC_CHA.gpkg` and `U2018_CLC2018_V2020_20u1_LT.tif` with its supplied sidecars/legend.

```r
download.file("https://data.gov.lt/datasets/3790/distribution/18101/download/",
              "Corine_latest.zip", mode = "wb")
```

This is the national distribution of the Copernicus/EEA product, rather than a map screenshot or a manually clipped derivative. The original package also includes older and change layers. Cite European Union, Copernicus Land Monitoring Service / European Environment Agency and follow the [CLMS data policy](https://land.copernicus.eu/en/data-policy). CORINE's minimum mapping unit is 25 ha; 100 m raster pixels do not imply detection of every 100 m habitat patch.

## Elevation — geodata country data

- Exact ZIP: <https://geodata.ucdavis.edu/geodata/elv/LTU_elv_msk.zip>
- Extracted original: `LTU_elv_msk.tif`.
- Documentation: <https://rspatial.github.io/geodata/reference/elevation.html>

```r
elevation <- geodata::elevation_30s("LTU", path = "geodata_cache")
```

The direct ZIP is the masked Lithuania source used by this function. Elevation is SRTM-derived; preserve the source's attribution and terms.

## Roads, rivers/waterways, settlements — Geofabrik / OpenStreetMap

- Catalog: <https://download.geofabrik.de/europe/lithuania.html>
- Requested file: <https://download.geofabrik.de/europe/lithuania-latest-free.gpkg.zip>
- Resolved snapshot downloaded for this attempt: <https://download.geofabrik.de/europe/lithuania-261021-free.gpkg.zip>
- Extracted original: `lithuania.gpkg`.
- Layers used in R: `gis_osm_roads_free`, `gis_osm_waterways_free`, `gis_osm_places_free`.

```r
download.file("https://download.geofabrik.de/europe/lithuania-261021-free.gpkg.zip",
              "lithuania-latest-free.gpkg.zip", mode = "wb")
roads <- sf::st_read("data/raw/lithuania.gpkg", layer = "gis_osm_roads_free")
```

`latest` changes over time; the resolved snapshot and SHA-256 in `metadata/downloads.csv` identify this run. Attribution: © OpenStreetMap contributors, distributed by Geofabrik, [ODbL 1.0](https://www.openstreetmap.org/copyright).

## Lithuania boundary — GADM 4.1

- Exact file: <https://geodata.ucdavis.edu/gadm/gadm4.1/json/gadm41_LTU_0.json>
- GADM: <https://gadm.org/data.html>

```r
boundary <- geodata::gadm("LTU", level = 0, version = "4.1", path = "geodata_cache")
```

The saved GeoJSON is a directly readable official distribution of the same country/level/version; `geodata::gadm()` uses the provider's RDS distribution instead. GADM's [licence](https://gadm.org/license.html) permits academic/non-commercial use, with restrictions on redistribution and commercial use. Source data are kept locally; this task does not publish them. Each dataset's terms apply independently of the R scripts.
