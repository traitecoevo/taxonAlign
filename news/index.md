# Changelog

## taxonAlign 0.1.0

First release.

- [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md),
  [`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
  and
  [`create_taxonomic_update_lookup()`](https://traitecoevo.github.io/taxonAlign/reference/create_taxonomic_update_lookup.md)
  align raw taxon names to any taxonomic reference, at any rank, and
  update them to their accepted names, after APCalign’s approach for the
  Australian Plant Census.
- [`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
  loads versioned reference lists from taxonAlign’s data releases (the
  National Species List groups and the Catalogue of Life for Australian
  animals);
  [`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md),
  [`data_release_datasets()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_datasets.md)
  and
  [`download_data_release_files()`](https://traitecoevo.github.io/taxonAlign/reference/download_data_release_files.md)
  list and fetch them.
- [`taxonomic_reference_schema()`](https://traitecoevo.github.io/taxonAlign/reference/taxonomic_reference_schema.md),
  [`check_taxonomic_reference()`](https://traitecoevo.github.io/taxonAlign/reference/check_taxonomic_reference.md)
  and
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
  let you use your own reference tables.
- A name that is nothing more than a genus, family or other higher-rank
  name stays as written (`"Banksia"`), where APCalign gives
  `"Banksia sp. [Banksia]"`: the input didn’t say `"sp."`.
  `include_bracketed_info = TRUE` treats it as though it had ended in
  `"sp."`: `"Banksia sp. [<identifier>]"`.
