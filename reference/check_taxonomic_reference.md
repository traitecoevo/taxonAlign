# Check a table is in taxonAlign's taxonomic reference format

Checks a reference table against
[`taxonomic_reference_schema()`](https://traitecoevo.github.io/taxonAlign/reference/taxonomic_reference_schema.md):
every required column is present, every record has a name, rank, status,
dataset and ID, `taxon_ID` is unique, and every record leads somewhere
in the table – an accepted record to itself, any other to another
record's `taxon_ID`. Every data release
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
downloads passes this check.

## Usage

``` r
check_taxonomic_reference(x, name = deparse(substitute(x)))
```

## Arguments

- x:

  A data frame.

- name:

  What to call `x` in the error message. Defaults to the expression
  passed as `x`.

## Value

`x`, invisibly, if it passes. Otherwise an error listing every problem
found.

## Details

[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
is more forgiving than this: it renames Darwin Core columns, and drops
(with a warning) a record with no `canonical_name`. Use this check on a
reference you're going to share or release, so that other people get the
same results from it that you do.

## Examples

``` r
reference <- data.frame(
  canonical_name = c("Boronia serrulata", "Boronia oldname"),
  scientific_name = c("Boronia serrulata Sm.", "Boronia oldname Sm."),
  taxon_rank = "species", taxonomic_status = c("accepted", "synonym"),
  taxonomic_dataset = "MY_LIST", genus = "Boronia",
  taxon_ID = c("1", "2"), accepted_name_usage_ID = c("1", "1")
)
check_taxonomic_reference(reference)
```
