# taxonAlign 0.1.0

First release.

* `align_taxa()`, `update_taxa()` and `create_taxonomic_update_lookup()` align raw taxon names to any
  taxonomic reference, at any rank, and update them to their accepted names, after APCalign's
  approach for the Australian Plant Census.
* `load_taxonomic_resources()` loads versioned reference lists from taxonAlign's data releases
  (the National Species List groups and the Catalogue of Life for Australian animals);
  `data_release_versions()`, `data_release_datasets()` and `download_data_release_files()` list and
  fetch them.
* `taxonomic_reference_schema()`, `check_taxonomic_reference()` and `prepare_taxonomic_resources()`
  let you use your own reference tables.
* A name that is nothing more than a genus, family or other higher-rank name stays as written
  (`"Banksia"`), where APCalign gives `"Banksia sp. [Banksia]"`: the input didn't say `"sp."`.
  `include_bracketed_info = TRUE` treats it as though it had ended in `"sp."`: `"Banksia sp. [<identifier>]"`.
