# A live APC snapshot, flattened into taxonAlign's format the way taxonAlign.dataprep's load_APC() does
# (repeated here so these tests don't depend on dataprep), and APCalign's own resources for the same
# data. Loaded once per test session. Used by test-apc_equivalence.R, which is
# skipped unless APCalign is installed and the network is available.
apc_test_cache <- new.env(parent = emptyenv())

# A named APC release, so loading it never asks the GitHub API for the latest one: that call is limited
# to 60 an hour per IP address without authentication, and on shared CI runners it failed, leaving
# APCalign's resources NULL (macOS, PR #30). Both packages are compared on the same data, so any release
# will do; move it forward now and then.
apc_test_version <- "2026-11-15"

load_apc_resources_for_test <- function() {
  if (!is.null(apc_test_cache$loaded)) return(apc_test_cache$loaded)
  # APCalign's messages are kept, to say why if loading fails
  messages <- character(0)
  APC <- withCallingHandlers(
    APCalign::load_taxonomic_resources(version = apc_test_version),
    message = function(m) {
      messages <<- c(messages, trimws(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  # Nothing loaded: offline on a developer's machine, skip; on CI, where the release download is
  # reliable once no API call is made, fail -- a mistyped `apc_test_version` or an unreadable file
  # would otherwise switch these tests off unnoticed.
  if (is.null(APC)) {
    why <- paste0("couldn't load APC release ", apc_test_version, " with APCalign: ",
                  paste(messages, collapse = " "))
    if (nzchar(Sys.getenv("CI"))) stop(why, call. = FALSE)
    testthat::skip(why)
  }
  # Loaded but incomplete is a change in APCalign, never the network's fault
  needed <- c("APC", "APC_accepted", "APC_synonyms", "genera_accepted", "genera_synonym",
              "family_accepted", "family_synonym")
  missing <- setdiff(needed, names(APC))
  if (length(missing) > 0) {
    stop("APCalign's resources no longer include: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  flat <- dplyr::bind_rows(
    APC$APC_accepted, APC$APC_synonyms,
    APC$genera_accepted, APC$genera_synonym,
    APC$family_accepted |> dplyr::mutate(taxonomic_dataset = "APC"),
    APC$family_synonym
  )
  # as in load_APC(): the records synonyms lead to that APCalign's split tables leave out (excluded
  # taxa -- "Achneria brevifolia" -> excluded "Eriachne brevifolia"), from its full APC table
  missing_targets <- setdiff(flat$accepted_name_usage_ID, flat$taxon_ID)
  flat <- dplyr::bind_rows(flat, APC$APC[APC$APC$taxon_ID %in% missing_targets, ] |> dplyr::mutate(taxonomic_dataset = "APC"))
  # as in load_APC(): subclass/taxon_distribution are only in the full APC table, and APC's other
  # metadata columns would be read as ranks
  extra <- APC$APC[, c("taxon_ID", "subclass", "taxon_distribution")]
  flat <- flat |>
    dplyr::select(-dplyr::any_of(c("subclass", "taxon_distribution"))) |>
    dplyr::left_join(extra[!duplicated(extra$taxon_ID), ], by = "taxon_ID") |>
    dplyr::select(dplyr::any_of(c(taxonomic_reference_schema()$column, "kingdom", "class", "subclass", "family")))
  apc_test_cache$loaded <- list(APC = APC, resources = prepare_taxonomic_resources(flat))
  apc_test_cache$loaded
}

# APCalign's form for a bare higher-rank name, "Banksia sp. [Banksia; id]" (or "Banksia sp. [Banksia]"
# without an identifier), as taxonAlign gives it with include_bracketed_info = TRUE: as though the name
# had ended in "sp." -- "Banksia sp. [id]", "Banksia sp." (user, 2026-11-22: an approved difference).
# Bare: one word, or a "Genus (Subgenus)" that aligned to that subgenus ("Asystasia (voucher)" aligns
# to the genus, and keeps "(voucher)" in brackets), as match_taxa()'s bare_one_word() counts it.
apcalign_bare_form <- function(name, original_name) {
  cleaned <- trimws(APCalign::standardise_names(original_name))
  bare <- !is.na(name) & grepl(" sp\\. \\[[^]]*\\]$", name) &
    (grepl("^\\S+$", cleaned) | (grepl("^\\S+ \\([^ )]+\\)$", cleaned) & grepl("^\\S+ \\(", name)))
  name[bare] <- sub(" \\[[^];]*\\]$", "", name[bare])
  name[bare] <- sub(" \\[[^];]*; ", " [", name[bare])
  name
}
