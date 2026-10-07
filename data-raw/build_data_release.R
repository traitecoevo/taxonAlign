# Builds the files for a taxonAlign data release (issue #24): one parquet file per National Species
# List export, stored verbatim, plus the GBIF Australia (extant animals) list, a manifest and release
# notes. Publishing is a separate step (see the end of this file).
#
# Run from the package root:
#   Rscript data-raw/build_data_release.R <release_date> <out_dir> <animals_dir> <gbif_au_rds>...
# e.g.
#   Rscript data-raw/build_data_release.R 2026-10-08 ~/taxonAlign_release_2026-10-08 \
#     data/AFD_NSL_export_20260929 \
#     ignore/gbif_au_animals_with_extinct.rds
#
# - algae, bryophytes, fungi, lichens: downloaded fresh from their public NSL export URLs
# - animals: the AFD's NSL-format export, supplied directly by the AFD (not yet public on NSL)
# - GBIF: the August 2026 GBIF Australia lists (all taxa, with GBIF's `extinct` flag as a column;
#   load_GBIF_AU_resources() returns extant taxa unless asked otherwise)

suppressMessages(library(dplyr))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("usage: build_data_release.R <release_date> <out_dir> <animals_dir> <gbif_au_rds>...")
release <- args[1]
out_dir <- path.expand(args[2])
animals_dir <- args[3]
gbif_files <- args[-(1:3)]
stopifnot(grepl("^\\d{4}-\\d{2}-\\d{2}$", release))
raw_dir <- file.path(out_dir, "source_files")
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

nsl_groups <- tibble::tribble(
  ~group, ~host, ~taxon_code, ~names_code, ~title,
  "algae", "algae", "AAL", "AANI", "Australian Algae",
  "bryophytes", "moss", "CAB", "ABNI", "Australian Mosses, Hornworts and Liverworts",
  "fungi", "fungi", "AFL", "AFNI", "Australian Fungi",
  "lichens", "lichen", "ALC", "ALNI", "Australian Lichens"
)

# Reads an export exactly as supplied: every column as text, only empty fields treated as missing.
read_verbatim <- function(file) {
  header <- readLines(file, n = 1, warn = FALSE)
  delim <- if (grepl("|", header, fixed = TRUE)) "|" else ","
  readr::read_delim(file, delim = delim, col_types = readr::cols(.default = readr::col_character()),
                    na = "", progress = FALSE)
}

manifest <- list()
add_asset <- function(asset, data, source, source_file, retrieved, licence, citation) {
  arrow::write_parquet(data, file.path(out_dir, asset))
  manifest[[length(manifest) + 1]] <<- tibble::tibble(
    asset = asset, source = source, source_file = source_file, retrieved = retrieved,
    rows = nrow(data), columns = ncol(data),
    source_md5 = if (file.exists(source_file)) unname(tools::md5sum(source_file)) else NA_character_,
    licence = licence, citation = citation
  )
  message(asset, ": ", nrow(data), " rows")
}

# ---- the four public NSL groups, downloaded now -------------------------------------------------------
today <- format(Sys.Date())
for (i in seq_len(nrow(nsl_groups))) {
  g <- nsl_groups[i, ]
  for (kind in c("taxon", "names")) {
    url <- sprintf("https://%s.biodiversity.org.au/nsl/services/export/%sCsv", g$host, kind)
    code <- if (kind == "taxon") g$taxon_code else g$names_code
    file <- file.path(raw_dir, sprintf("%s-%s-%s.csv", code, kind, today))
    utils::download.file(url, file, mode = "wb", quiet = TRUE)
    add_asset(
      sprintf("nsl_%s_%s.parquet", g$group, kind), read_verbatim(file),
      source = url, source_file = file, retrieved = today,
      licence = "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)",
      citation = sprintf("National Species List: %s (%s) %s export, %s, retrieved %s.",
                         g$title, code, if (kind == "taxon") "taxa" else "names", url, today)
    )
  }
}

# ---- animals: the AFD's NSL-format export, supplied directly ------------------------------------------
for (kind in c("taxon", "names")) {
  marker <- if (kind == "taxon") "[-_]taxon[-_]" else "[-_]names?[-_]"
  file <- list.files(animals_dir, pattern = marker, full.names = TRUE)
  stopifnot(length(file) == 1)
  add_asset(
    sprintf("nsl_animals_%s.parquet", kind), read_verbatim(file),
    source = "Australian Faunal Directory, NSL-format export supplied by the AFD (not yet public on NSL)",
    source_file = file, retrieved = format(as.Date(file.info(file)$mtime)),
    licence = "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)",
    citation = sprintf("Australian Faunal Directory (ABRS), NSL-format %s export (%s), released with permission of the AFD.",
                       if (kind == "taxon") "taxa" else "names", basename(file))
  )
}

# ---- GBIF Australia, animals --------------------------------------------------------------------------
gbif <- bind_rows(lapply(gbif_files, readRDS))
stopifnot("extinct" %in% names(gbif))
add_asset(
  "gbif_au_animals.parquet", gbif,
  source = paste("GBIF Backbone Taxonomy, taxa with occurrence records in Australia plus their synonyms,",
                 "with GBIF's extinct flag (load_GBIF_AU_resources() returns extant taxa by default). Built",
                 "with taxonAlign's generate_GBIF_taxonomic_reference_list(country = \"AU\")."),
  source_file = paste(basename(gbif_files), collapse = "; "),
  retrieved = "2026-08 (GBIF backbone and occurrence records accessed via the GBIF API, August 2026)",
  licence = "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
  citation = "GBIF Secretariat. GBIF Backbone Taxonomy. Checklist dataset https://doi.org/10.15468/39omei accessed via GBIF.org, August 2026."
)

manifest <- bind_rows(manifest)
readr::write_csv(manifest, file.path(out_dir, "manifest.csv"))

notes <- c(
  sprintf("taxonAlign data release %s.", release), "",
  "Reference data for `load_NSL_resources()` and `load_GBIF_AU_resources()`. NSL exports are stored verbatim (every column as text) as parquet; taxonAlign reshapes them on load. `manifest.csv` records each file's source, retrieval date, row count, source-file checksum, licence and citation.", "",
  "| File | Rows | Source | Retrieved |", "|---|---|---|---|",
  sprintf("| `%s` | %s | %s | %s |", manifest$asset, format(manifest$rows, big.mark = ","), manifest$source, manifest$retrieved)
)
writeLines(notes, file.path(out_dir, "release_notes.md"))
message("Built ", nrow(manifest), " files in ", out_dir)

# ---- publishing (run by hand, after checking the files) ------------------------------------------------
# Create the release as a draft first; publish it as a separate step:
#   gh release create <release_date> --draft --title "Data release <release_date>" \
#     --notes-file <out_dir>/release_notes.md <out_dir>/*.parquet <out_dir>/manifest.csv
#   gh release edit <release_date> --draft=false
