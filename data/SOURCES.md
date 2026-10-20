# Working data sources

Downloaded on 2026-10-20. Dataset licences apply independently of the R code.
The full original download is retained locally in `archive/`; that directory is not published.

| Working files | Source / attribution | Conditions |
|---|---|---|
| `model/presence.csv`, `model/inva_polygons.gpkg` | Valstybine saugomu teritoriju tarnyba, INVA; [Lithuanian open data portal](https://data.gov.lt/datasets/4732/) | No explicit licence was listed on the dataset page at download time; consult the publisher's terms before redistribution or other reuse. |
| `model/gbif_check.csv` | [GBIF species 3642949](https://www.gbif.org/species/3642949), Lithuania, 180 records | Record licences are retained in the CSV; sources include CC BY, CC BY-NC and CC0. Source dataset citations are listed below. This is an API snapshot, not a separately DOI-registered GBIF download. |
| `model/climate.tif` | [WorldClim 2.1](https://www.worldclim.org/data/worldclim21.html), 1970-2000, 30 arc seconds; BIO1, BIO4, BIO12, BIO15, BIO8, BIO13 | Follow WorldClim's source terms and cite Fick & Hijmans (2017), *WorldClim 2: new 1km spatial resolution climate surfaces for global land areas*, International Journal of Climatology 37, 4302-4315. |
| `model/elevation.tif` | [geodata elevation_30s](https://rspatial.github.io/geodata/reference/elevation.html), Lithuania; SRTM/CGIAR-SRTM-based elevation | Source attribution and conditions apply; resolution is 30 arc seconds, values in metres. |
| `model/land_cover.tif`, `model/land_cover_classes.csv` | European Environment Agency / Copernicus Land Monitoring Service, CORINE 2018; [national distribution](https://data.gov.lt/datasets/3790/), [product page](https://land.copernicus.eu/en/products/corine-land-cover/clc2018) | Follow the product's access and attribution terms. Raster values are category indices; use the included legend. |
| `model/infrastructure.gpkg` | Copyright OpenStreetMap contributors, [Geofabrik Lithuania](https://download.geofabrik.de/europe/lithuania.html), snapshot `lithuania-261019` | [Open Database Licence 1.0](https://www.openstreetmap.org/copyright). This is a selected and reprojected extract with roads, waterways and settlements. |
| `model/boundary.geojson` | [GADM 4.1](https://gadm.org/data.html), Lithuania, national boundary | [GADM licence](https://gadm.org/license.html): academic and non-commercial use; redistribution and commercial use require permission. |

GBIF source datasets, accessed through GBIF on 2026-10-20:

- iNaturalist contributors, iNaturalist (2026). *iNaturalist Research-grade Observations*. [DOI: 10.15468/ab3s5x](https://doi.org/10.15468/ab3s5x).
- Bijmoer R, Arias Guerrero S, Creuwels J (2026). *Naturalis Biodiversity Center (NL) - Botany*. [DOI: 10.15468/ib5ypt](https://doi.org/10.15468/ib5ypt).
- Trillo A, Castro-Diez P, Espinar J L, Vila M (2024). *Database of field studies on environmental impacts of invasive plant species in Europe*. [DOI: 10.15470/wanfdf](https://doi.org/10.15470/wanfdf).
- Senckenberg. *Herbarium Senckenbergianum (FR)*. [DOI: 10.15468/ucmdjy](https://doi.org/10.15468/ucmdjy).

INVA points are derived representative points of polygons. Three unreadable source
geometries remain empty in the polygon layer; other geometry problems are flagged.
The viewing script maps valid presence candidates and retains GBIF separately.
