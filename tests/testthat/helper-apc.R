# A live APC snapshot, flattened into taxonAlign's format the way taxonAlign.dataprep's load_APC() does
# (repeated here so these tests don't depend on dataprep), and APCalign's own resources for the same
# data. Loaded once per test session. Used by test-apc_equivalence.R, which is
# skipped unless APCalign is installed and the network is available.
apc_test_cache <- new.env(parent = emptyenv())

load_apc_resources_for_test <- function() {
  if (!is.null(apc_test_cache$loaded)) return(apc_test_cache$loaded)
  suppressMessages(APC <- APCalign::load_taxonomic_resources())
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
